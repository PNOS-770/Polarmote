import 'dart:async';
import 'dart:convert';

import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../terminal_app_state.dart';

extension TerminalAppStateMetrics on TerminalAppState {
  void startMetricsPolling(TerminalSession session) {
    _stopMetricsPolling(session);
    session.metricsTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollMetrics(session),
    );
    unawaited(_pollMetrics(session));
  }

  void stopMetricsPolling(TerminalSession session) {
    _stopMetricsPolling(session);
  }

  void _stopMetricsPolling(TerminalSession session) {
    session.metricsTimer?.cancel();
    session.metricsTimer = null;
  }

  Future<void> _pollMetrics(TerminalSession session) async {
    final client = session.client;
    if (client == null || session.tab.status != TerminalStatus.connected) {
      return;
    }
    try {
      final output = await client
          .run(
            "sh -c 'cat /proc/stat; echo __MEM__; cat /proc/meminfo; echo __DF__; df -P /; echo __LOAD__; cat /proc/loadavg; echo __NET__; cat /proc/net/dev; echo __DISK__; cat /proc/diskstats'",
            stdout: true,
            stderr: false,
          )
          .timeout(const Duration(seconds: 5));
      final text = utf8.decode(output, allowMalformed: true);
      _parseMetrics(session, text);
      session.metricsUpdatedAt = DateTime.now();
      notifyState();
    } catch (_) {
      // Ignore metrics failures (non-Linux or permission issues).
    }
  }

  void _parseMetrics(TerminalSession session, String text) {
    final lines = text.split('\n');
    final cpuLine = lines.firstWhere(
      (line) => line.startsWith('cpu '),
      orElse: () => '',
    );
    if (cpuLine.isNotEmpty) {
      final parts = cpuLine.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
      final numbers = parts.skip(1).map(int.tryParse).whereType<int>().toList();
      if (numbers.length >= 4) {
        final idle = numbers[3] + (numbers.length > 4 ? numbers[4] : 0);
        final total = numbers.fold<int>(0, (a, b) => a + b);
        final lastTotal = session.lastCpuTotal;
        final lastIdle = session.lastCpuIdle;
        if (lastTotal != null && lastIdle != null && total > lastTotal) {
          final deltaTotal = total - lastTotal;
          final deltaIdle = idle - lastIdle;
          if (deltaTotal > 0) {
            session.cpuUsage = (deltaTotal - deltaIdle) / deltaTotal;
          }
        }
        session.lastCpuTotal = total;
        session.lastCpuIdle = idle;
      }
    }

    int? memTotal;
    int? memAvailable;
    var memSection = false;
    for (final line in lines) {
      if (line.startsWith('__MEM__')) {
        memSection = true;
        continue;
      }
      if (line.startsWith('__DF__')) {
        memSection = false;
      }
      if (!memSection) continue;
      if (line.startsWith('MemTotal:')) {
        memTotal = _parseMemValue(line);
      } else if (line.startsWith('MemAvailable:')) {
        memAvailable = _parseMemValue(line);
      }
    }
    if (memTotal != null && memAvailable != null && memTotal > 0) {
      final used = memTotal - memAvailable;
      session.memUsage = used / memTotal;
      session.memUsedBytes = used * 1024;
      session.memTotalBytes = memTotal * 1024;
    } else {
      session.memUsedBytes = null;
      session.memTotalBytes = null;
    }

    final dfIndex = lines.indexWhere((line) => line.startsWith('__DF__'));
    if (dfIndex != -1 && dfIndex + 2 < lines.length) {
      final dfLine = lines[dfIndex + 2].trim();
      final dfParts = dfLine.split(RegExp(r'\s+'));
      if (dfParts.length >= 3) {
        final total = int.tryParse(dfParts[1]);
        final used = int.tryParse(dfParts[2]);
        if (total != null && used != null && total > 0) {
          session.diskUsage = used / total;
        }
      }
    }

    final loadIndex = lines.indexWhere((line) => line.startsWith('__LOAD__'));
    if (loadIndex != -1 && loadIndex + 1 < lines.length) {
      final loadParts = lines[loadIndex + 1].trim().split(RegExp(r'\s+'));
      if (loadParts.isNotEmpty) {
        session.loadAvg = double.tryParse(loadParts.first);
      }
    }

    final netIndex = lines.indexWhere((line) => line.startsWith('__NET__'));
    if (netIndex != -1) {
      var rxTotal = 0;
      var txTotal = 0;
      for (var i = netIndex + 1; i < lines.length; i++) {
        final line = lines[i];
        if (line.startsWith('__DISK__')) break;
        if (!line.contains(':')) continue;
        final parts = line.split(':');
        final iface = parts[0].trim();
        if (iface.isEmpty || iface == 'lo') continue;
        final fields = parts[1]
            .trim()
            .split(RegExp(r'\s+'))
            .where((e) => e.isNotEmpty);
        final values = fields.map(int.tryParse).whereType<int>().toList();
        if (values.length >= 9) {
          rxTotal += values[0];
          txTotal += values[8];
        }
      }
      _updateNetRates(session, rxTotal, txTotal);
    }

    final diskIndex = lines.indexWhere((line) => line.startsWith('__DISK__'));
    if (diskIndex != -1) {
      var readBytes = 0;
      var writeBytes = 0;
      for (var i = diskIndex + 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 14) continue;
        final name = parts[2];
        if (name.startsWith('loop') ||
            name.startsWith('ram') ||
            name.startsWith('fd')) {
          continue;
        }
        final readSectors = int.tryParse(parts[5]) ?? 0;
        final writeSectors = int.tryParse(parts[9]) ?? 0;
        readBytes += readSectors * 512;
        writeBytes += writeSectors * 512;
      }
      _updateDiskRates(session, readBytes, writeBytes);
    }
  }

  int? _parseMemValue(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    return int.tryParse(parts[1]);
  }

  void _updateNetRates(TerminalSession session, int rxTotal, int txTotal) {
    final now = DateTime.now();
    final lastAt = session.lastNetAt;
    final lastRx = session.lastNetRxBytes;
    final lastTx = session.lastNetTxBytes;
    session.lastNetRxBytes = rxTotal;
    session.lastNetTxBytes = txTotal;
    session.lastNetAt = now;
    if (lastAt == null || lastRx == null || lastTx == null) return;
    final elapsed = now.difference(lastAt).inMilliseconds / 1000;
    if (elapsed <= 0) return;
    session.netRxRate = (rxTotal - lastRx) / elapsed;
    session.netTxRate = (txTotal - lastTx) / elapsed;
  }

  void _updateDiskRates(
    TerminalSession session,
    int readBytes,
    int writeBytes,
  ) {
    final now = DateTime.now();
    final lastAt = session.lastDiskAt;
    final lastRead = session.lastDiskReadBytes;
    final lastWrite = session.lastDiskWriteBytes;
    session.lastDiskReadBytes = readBytes;
    session.lastDiskWriteBytes = writeBytes;
    session.lastDiskAt = now;
    if (lastAt == null || lastRead == null || lastWrite == null) return;
    final elapsed = now.difference(lastAt).inMilliseconds / 1000;
    if (elapsed <= 0) return;
    session.diskReadRate = (readBytes - lastRead) / elapsed;
    session.diskWriteRate = (writeBytes - lastWrite) / elapsed;
  }
}
