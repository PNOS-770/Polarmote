import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'Polarmote_log.dart';
import 'log_level.dart';

class LogController extends ChangeNotifier {
  static const int _maxInMemoryLogLines = 500;
  static const Duration _pruneInterval = Duration(hours: 12);
  static const int _retentionDays = 29;

  final List<String> logs = [];
  Directory? logDirectory;
  File? _logFile;
  IOSink? _logSink;
  String _activeLogDateKey = '';
  DateTime lastLogPrune = DateTime.now();
  final List<_PendingLogLine> _pendingLogWrites = [];

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final base = await getApplicationSupportDirectory();
      logDirectory = Directory(p.join(base.path, 'logs'));
      await logDirectory!.create(recursive: true);
      await _switchLogFile(_dateKeyFor(DateTime.now()), reloadInMemory: true);
      if (_pendingLogWrites.isNotEmpty) {
        for (final e in List<_PendingLogLine>.from(_pendingLogWrites)) {
          _appendLogToFile(e.line, timestamp: e.timestamp);
        }
        _pendingLogWrites.clear();
      }
      lastLogPrune = DateTime.now();
      unawaited(_pruneLogs());
    } catch (e) {
      PolarmoteLog.error('log_controller', 'init failed: $e');
    }
  }

  void addLog(String message, {bool notify = true}) {
    final now = DateTime.now();
    final timestamp = _formatLogTimestamp(now);
    final line = '[$timestamp] $message';
    logs.add(line);
    if (logs.length > _maxInMemoryLogLines) {
      logs.removeRange(0, logs.length - _maxInMemoryLogLines);
    }
    _appendLogToFile(line, timestamp: now);
    _maybePruneLogs();
    if (notify) notifyListeners();
  }

  List<String> get todayLogs {
    final now = DateTime.now();
    return logs.where((l) {
      final ts = _parseLogTimestamp(l);
      return ts != null &&
          ts.year == now.year &&
          ts.month == now.month &&
          ts.day == now.day;
    }).toList();
  }

  Future<void> openLogFolder() async {
    try {
      if (logDirectory == null) await initialize();
      if (logDirectory != null) await OpenFilex.open(logDirectory!.path);
    } catch (e) {
      PolarmoteLog.error('log_controller', '$e');
    }
  }

  Future<void> dispose() async {
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    _logFile = null;
    _initialized = false;
  }

  // ---- internal ----

  void _appendLogToFile(String line, {required DateTime timestamp}) {
    final t = _dateKeyFor(timestamp);
    if (_activeLogDateKey != t) _switchLogFileSync(t);
    _logSink?.writeln(line);
    if (_logSink == null) {
      _pendingLogWrites.add(_PendingLogLine(line: line, timestamp: timestamp));
    }
  }

  void _maybePruneLogs() {
    if (DateTime.now().difference(lastLogPrune) < _pruneInterval) return;
    lastLogPrune = DateTime.now();
    unawaited(_pruneLogs());
  }

  Future<void> _pruneLogs() async {
    if (logDirectory == null) return;
    try {
      final cutoff = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
          .subtract(const Duration(days: _retentionDays));
      await for (final e in logDirectory!.list(followLinks: false)) {
        if (e is! File) continue;
        final fn = p.basename(e.path);
        final d = _dateFromLogFilename(fn);
        if ((d != null && d.isBefore(cutoff)) ||
            (fn == 'Polarmote.log' &&
                await e.lastModified().then((m) => m.isBefore(cutoff)))) {
          try { await e.delete(); } catch (_) {}
        }
      }
    } catch (e) {
      PolarmoteLog.error('log_controller', '$e');
    }
  }

  Future<void> _switchLogFile(String dateKey, {required bool reloadInMemory}) async {
    if (logDirectory == null) return;
    try {
      await _logSink?.flush();
      await _logSink?.close();
      _logFile = File(p.join(logDirectory!.path, 'Polarmote-$dateKey.log'));
      _logSink = await _logFile!.openWrite(mode: FileMode.append);
      _activeLogDateKey = dateKey;
      if (reloadInMemory) {
        _recentLogFiles().then((files) {
          if (files.length > 1) _loadRecentInMemory(files);
        });
      }
    } catch (e) {
      PolarmoteLog.error('log_controller', '$e');
    }
  }

  void _switchLogFileSync(String dateKey) {
    if (logDirectory == null) return;
    try {
      _logSink?.flush();
      _logSink?.close();
      _logFile = File(p.join(logDirectory!.path, 'Polarmote-$dateKey.log'));
      _logSink = _logFile!.openWrite(mode: FileMode.append);
      _activeLogDateKey = dateKey;
    } catch (e) {
      PolarmoteLog.error('log_controller', '$e');
    }
  }

  Future<List<File>> _recentLogFiles() async {
    if (logDirectory == null) return const [];
    try {
      final files = <File>[];
      await for (final e in logDirectory!.list(followLinks: false)) {
        if (e is File && _dateFromLogFilename(p.basename(e.path)) != null) {
          files.add(e);
        }
      }
      files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      return files.where((f) {
        final d = _dateFromLogFilename(p.basename(f.path));
        return d != null && d.isAfter(cutoff);
      }).toList();
    } catch (e) {
      PolarmoteLog.error('log_controller', '$e');
      return const [];
    }
  }

  Future<void> _loadRecentInMemory(List<File> files) async {
    if (files.length <= 1) return;
    final loaded = <String>{...logs};
    for (final file in files) {
      if (p.basename(file.path) == 'Polarmote-$_activeLogDateKey.log') continue;
      try {
        final lines = await file.readAsLines();
        for (final line in lines.reversed) {
          if (loaded.contains(line)) continue;
          if (logs.length >= _maxInMemoryLogLines) break;
          logs.insert(0, line);
          loaded.add(line);
        }
      } catch (_) {}
    }
    if (logs.length > _maxInMemoryLogLines) {
      logs.removeRange(0, logs.length - _maxInMemoryLogLines);
    }
  }

  static String _dateKeyFor(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static DateTime? _dateFromLogFilename(String name) {
    final m = RegExp(r'^Polarmote-(\d{4})-(\d{2})-(\d{2})\.log$').firstMatch(name);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    return (y != null && mo != null && d != null) ? DateTime(y, mo, d) : null;
  }

  static String _formatLogTimestamp(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  static DateTime? _parseLogTimestamp(String line) {
    if (line.length < 20) return null;
    return DateTime.tryParse(line.substring(1, 20).replaceAll(' ', 'T'));
  }
}

class _PendingLogLine {
  _PendingLogLine({required this.line, required this.timestamp});
  final String line;
  final DateTime timestamp;
}

