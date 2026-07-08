import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PolarmoteLog {
  static IOSink? _fileSink;
  static File? _logFile;
  static final List<String> _pendingLogs = [];
  static bool _initialized = false;
  static const int _maxPendingLogs = 50; // 限制待写入的日志数量

  /// 初始化日志系统（在应用启动时调用）
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory(p.join(dir.path, 'logs'));
      await logDir.create(recursive: true);
      
      final now = DateTime.now();
      final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _logFile = File(p.join(logDir.path, '$dateKey.log'));
      
      _fileSink = _logFile!.openWrite(mode: FileMode.append);
      _initialized = true;
      
      // 写入待处理的日志
      for (final log in _pendingLogs) {
        _fileSink!.writeln(log);
      }
      _pendingLogs.clear();
    } catch (e) {
      debugPrint('[Polarmote_log] Failed to initialize log file: $e');
    }
  }

  static void debug(String tag, String message) {
    _write(level: 'DEBUG', tag: tag, message: message);
  }

  static void info(String tag, String message) {
    _write(level: 'INFO', tag: tag, message: message);
  }

  static void warn(String tag, String message) {
    _write(level: 'WARN', tag: tag, message: message);
  }

  static void error(String tag, String message) {
    _write(level: 'ERROR', tag: tag, message: message);
  }

  static void _write({
    required String level,
    required String tag,
    required String message,
  }) {
    final normalizedTag = tag.trim().isEmpty ? 'Polarmote' : tag.trim();
    final normalizedMessage = message.trim();
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp][$level][$normalizedTag] $normalizedMessage';
    
    // 总是输出到控制台
    debugPrint(logLine);
    
    // 写入文件
    if (_fileSink != null) {
      try {
        _fileSink!.writeln(logLine);
      } catch (e) {
        debugPrint('[Polarmote_log] Failed to write to log file: $e');
      }
    } else {
      // 如果还未初始化，先缓存（限制数量）
      if (_pendingLogs.length >= _maxPendingLogs) {
        _pendingLogs.removeAt(0); // 移除最旧的日志
      }
      _pendingLogs.add(logLine);
    }
  }

  /// 关闭日志系统（在应用退出时调用）
  static Future<void> close() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
    _logFile = null;
    _initialized = false;
  }
}

