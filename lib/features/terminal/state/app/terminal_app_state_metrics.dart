import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;

import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../transport/native/native_local_metrics_bridge.dart';
import '../terminal_app_state.dart';

extension TerminalAppStateMetrics on TerminalAppState {
  void startMetricsPolling(TerminalSession session) {
    _stopMetricsPolling(session);
    session.metricsTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
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
    if (session.tab.status != TerminalStatus.connected) {
      return;
    }
    // 只对当前活跃会话采集指标，后台会话跳过昂贵的 SSH proc/* 查询
    if (activeSession != session) {
      return;
    }
    if (session.profile.isLocal) {
      await _pollLocalMetrics(session);
      if (session.deviceModel == null) {
        await _pollLocalSystemInfo(session);
      }
    } else {
      await _pollRemoteMetrics(session);
      if (session.deviceModel == null) {
        await _pollSystemInfo(session);
      }
    }
    _shareMetricsWithSiblingSessions(session);
  }

  void _shareMetricsWithSiblingSessions(TerminalSession source) {
    final hostId = source.profile.id;
    for (final s in sessions) {
      if (s.id == source.id || s.profile.id != hostId) continue;
      s.cpuUsage = source.cpuUsage;
      s.cpuHistory
        ..clear()
        ..addAll(source.cpuHistory);
      s.lastCpuTotal = source.lastCpuTotal;
      s.lastCpuIdle = source.lastCpuIdle;
      s.memUsage = source.memUsage;
      s.memUsedBytes = source.memUsedBytes;
      s.memTotalBytes = source.memTotalBytes;
      s.diskUsage = source.diskUsage;
      s.diskReadRate = source.diskReadRate;
      s.diskWriteRate = source.diskWriteRate;
      s.loadAvg = source.loadAvg;
      s.netRxRate = source.netRxRate;
      s.netTxRate = source.netTxRate;
      s.netRxHistory
        ..clear()
        ..addAll(source.netRxHistory);
      s.netTxHistory
        ..clear()
        ..addAll(source.netTxHistory);
      s.metricsUpdatedAt = source.metricsUpdatedAt;
      s.deviceModel ??= source.deviceModel;
      s.cpuCores ??= source.cpuCores;
      s.osInfo ??= source.osInfo;
      s.kernelVersion ??= source.kernelVersion;
      s.totalMem ??= source.totalMem;
      s.hostName ??= source.hostName;
      s.uptime ??= source.uptime;
    }
  }

  // ── Native local metrics collector (singleton) ──

  static LocalMetricsCollector? _nativeCollector;

  static LocalMetricsCollector _getCollector() {
    if (_nativeCollector == null) {
      try {
        _nativeCollector = LocalMetricsCollector();
      } catch (e) {
        
        rethrow;
      }
    }
    return _nativeCollector!;
  }

  // ── CPU delta state ──

  static int? _prevCpuIdle;
  static int? _prevTotal;

  Future<void> _pollLocalMetrics(TerminalSession session) async {
    try {
      final collector = _getCollector();
      final data = collector.collect();
      if (data == null || data.isEmpty) {
        
        return;
      }

      // CPU - compute fraction from idle/total delta
      if (data.cpuIdle != null && data.cpuKernel != null && data.cpuUser != null) {
        final total = data.cpuIdle! + data.cpuKernel! + data.cpuUser!;
        if (_prevCpuIdle != null && _prevTotal != null && total > _prevTotal!) {
          final deltaTotal = total - _prevTotal!;
          final deltaIdle = data.cpuIdle! - _prevCpuIdle!;
          if (deltaTotal > 0) {
            session.cpuUsage = (deltaTotal - deltaIdle) / deltaTotal;
          }
        }
        _prevCpuIdle = data.cpuIdle;
        _prevTotal = total;
      }

      // Memory
      if (data.memTotal != null && data.memAvail != null && data.memTotal! > 0) {
        session.memUsage =
            (data.memTotal! - data.memAvail!) / data.memTotal!;
        session.memUsedBytes = data.memTotal! - data.memAvail!;
        session.memTotalBytes = data.memTotal!;
      }

      // Network - cumulative, need delta for rate
      if (data.netRx != null && data.netTx != null) {
        _updateNetRates(session, data.netRx!, data.netTx!);
        session.netRxHistory.add(session.netRxRate ?? 0);
        if (session.netRxHistory.length > 120) session.netRxHistory.removeAt(0);
        session.netTxHistory.add(session.netTxRate ?? 0);
        if (session.netTxHistory.length > 120) session.netTxHistory.removeAt(0);
      }

      // Disk - cumulative I/O, need delta for rate
      if (data.diskRead != null && data.diskWrite != null) {
        _updateDiskRatesFromNative(session, data.diskRead!, data.diskWrite!);
      }

      // Disk capacity
      if (data.diskTotal != null && data.diskTotal! > 0) {
        session.diskUsage = (data.diskTotal! - (data.diskFree ?? data.diskTotal!)) / data.diskTotal!;
      }

      session.metricsUpdatedAt = DateTime.now();
      _updateMetricHistory(session);
      notifyState();
    } catch (_) {
      // Metrics polling errors are non-fatal
    }
  }

  void _updateDiskRatesFromNative(
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

  // ── Remote (SSH) metrics: parses /proc/* output ──

  Future<void> _pollRemoteMetrics(TerminalSession session) async {
    if (session.client == null) return;
    try {
      if (session.metricsClient == null) {
        final c = await connectSshClientForHost(session.profile).timeout(const Duration(seconds: 10));
        if (session.client == null) { c.close(); return; }
        session.metricsClient = c;
      }
      final output = await session.metricsClient!
          .run(
            "sh -c 'cat /proc/stat; echo __MEM__; cat /proc/meminfo; echo __DF__; df -P /; echo __LOAD__; cat /proc/loadavg; echo __NET__; cat /proc/net/dev; echo __DISK__; cat /proc/diskstats'",
            stdout: true,
            stderr: false,
          )
          .timeout(const Duration(seconds: 5));
      final text = utf8.decode(output, allowMalformed: true);
      _parseMetrics(session, text);
      session.metricsUpdatedAt = DateTime.now();
      _updateMetricHistory(session);
      notifyState();
    } catch (_) {
      // Ignore metrics failures (non-Linux or permission issues).
    }
  }

  Future<void> _pollSystemInfo(TerminalSession session) async {
    if (session.metricsClient == null) return;
    try {
      final output = await session.metricsClient!
          .run(
            "sh -c '"
            "cat /proc/cpuinfo 2>/dev/null | grep -m1 \"model name\" | cut -d: -f2 | xargs; "
            "echo __CPUCORES__; "
            "grep -c ^processor /proc/cpuinfo 2>/dev/null; "
            "echo __OS__; "
            "(cat /etc/os-release 2>/dev/null | grep -m1 PRETTY_NAME | cut -d= -f2 | tr -d \"\\\"\") || uname -s; "
            "echo __KERNEL__; "
            "uname -r; "
            "echo __MEM__; "
            "grep MemTotal /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2; "
            "echo __HOSTNAME__; "
            "uname -n; "
            "echo __UPTIME__; "
            "cat /proc/uptime 2>/dev/null | tr -s ' ' | cut -d' ' -f1"
            "'",
            stdout: true,
            stderr: false,
          )
          .timeout(const Duration(seconds: 5));
      final text = utf8.decode(output, allowMalformed: true);
      final lines = text.split('\n').map((l) => l.trim()).toList();

      if (lines.isNotEmpty && !lines[0].contains('__')) session.deviceModel = lines[0];

      final ccIdx = lines.indexWhere((l) => l.contains('__CPUCORES__'));
      if (ccIdx >= 0 && ccIdx + 1 < lines.length) {
        final c = int.tryParse(lines[ccIdx + 1]);
        if (c != null) session.cpuCores = c > 1 ? '$c cores' : '$c core';
      }

      final osIdx = lines.indexWhere((l) => l.contains('__OS__'));
      if (osIdx >= 0 && osIdx + 1 < lines.length) session.osInfo = lines[osIdx + 1];

      final kernIdx = lines.indexWhere((l) => l.contains('__KERNEL__'));
      if (kernIdx >= 0 && kernIdx + 1 < lines.length) session.kernelVersion = lines[kernIdx + 1];

      final memIdx = lines.indexWhere((l) => l.contains('__MEM__'));
      if (memIdx >= 0 && memIdx + 1 < lines.length) {
        final kb = int.tryParse(lines[memIdx + 1]);
        if (kb != null) {
          final gb = kb / (1024 * 1024);
          session.totalMem = gb >= 1 ? '${gb.toStringAsFixed(0)} GB' : '${(kb / 1024).toStringAsFixed(0)} MB';
        }
      }

      final hnIdx = lines.indexWhere((l) => l.contains('__HOSTNAME__'));
      if (hnIdx >= 0 && hnIdx + 1 < lines.length) session.hostName = lines[hnIdx + 1];

      final upIdx = lines.indexWhere((l) => l.contains('__UPTIME__'));
      if (upIdx >= 0 && upIdx + 1 < lines.length) {
        final secs = double.tryParse(lines[upIdx + 1]);
        if (secs != null) {
          final days = (secs / 86400).floor();
          final hours = ((secs % 86400) / 3600).floor();
          final mins = ((secs % 3600) / 60).floor();
          session.uptime = days > 0
              ? '${days}d ${hours}h ${mins}m'
              : '${hours}h ${mins}m';
        }
      }
    } catch (_) {}
  }

  Future<void> _pollLocalSystemInfo(TerminalSession session) async {
    session.hostName = Platform.localHostname;
    session.deviceModel = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    session.cpuCores = '${Platform.numberOfProcessors} cores';

    try {
      if (Platform.isLinux) {
        final mem = await Process.run('sh', ['-c', 'grep MemTotal /proc/meminfo | tr -s " " | cut -d" " -f2']);
        if (mem.exitCode == 0) {
          final kb = int.tryParse((mem.stdout as String).trim());
          if (kb != null) {
            final gb = kb / (1024 * 1024);
            session.totalMem = gb >= 1 ? '${gb.toStringAsFixed(0)} GB' : '${(kb / 1024).toStringAsFixed(0)} MB';
          }
        }
        final up = await Process.run('sh', ['-c', 'cat /proc/uptime | cut -d" " -f1']);
        if (up.exitCode == 0) {
          final secs = double.tryParse((up.stdout as String).trim());
          if (secs != null) {
            final days = (secs / 86400).floor();
            final hours = ((secs % 86400) / 3600).floor();
            final mins = ((secs % 3600) / 60).floor();
            session.uptime = days > 0 ? '${days}d ${hours}h ${mins}m' : '${hours}h ${mins}m';
          }
        }
        final kern = await Process.run('uname', ['-r']);
        if (kern.exitCode == 0) session.kernelVersion = (kern.stdout as String).trim();
      } else if (Platform.isMacOS) {
        final mem = await Process.run('sysctl', ['-n', 'hw.memsize']);
        if (mem.exitCode == 0) {
          final bytes = int.tryParse((mem.stdout as String).trim());
          if (bytes != null) {
            final gb = bytes / (1024 * 1024 * 1024);
            session.totalMem = '${gb.toStringAsFixed(0)} GB';
          }
        }
        final kern = await Process.run('uname', ['-r']);
        if (kern.exitCode == 0) session.kernelVersion = (kern.stdout as String).trim();
        final up = await Process.run('sh', ['-c', 'sysctl -n kern.boottime | cut -d" " -f4 | tr -d ","']);
        if (up.exitCode == 0) {
          final boot = int.tryParse((up.stdout as String).trim());
          if (boot != null) {
            final secs = DateTime.now().millisecondsSinceEpoch ~/ 1000 - boot;
            final days = (secs / 86400).floor();
            final hours = ((secs % 86400) / 3600).floor();
            final mins = ((secs % 3600) / 60).floor();
            session.uptime = days > 0 ? '${days}d ${hours}h ${mins}m' : '${hours}h ${mins}m';
          }
        }
      } else if (Platform.isWindows) {
        final os = await Process.run('wmic', ['os', 'get', 'Caption,Version', '/format:list']);
        if (os.exitCode == 0) session.osInfo = (os.stdout as String).trim().replaceAll('\r\n', '; ');
        final mem = await Process.run('wmic', ['computersystem', 'get', 'TotalPhysicalMemory', '/format:list']);
        if (mem.exitCode == 0) {
          final val = (mem.stdout as String).trim().split('\n').lastOrNull?.trim();
          final bytes = int.tryParse(val ?? '');
          if (bytes != null) {
            final gb = bytes / (1024 * 1024 * 1024);
            session.totalMem = '${gb.toStringAsFixed(0)} GB';
          }
        }
      }
    } catch (_) {}
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
      session.netRxHistory.add(session.netRxRate ?? 0);
      if (session.netRxHistory.length > 120) session.netRxHistory.removeAt(0);
      session.netTxHistory.add(session.netTxRate ?? 0);
      if (session.netTxHistory.length > 120) session.netTxHistory.removeAt(0);
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

  void _updateMetricHistory(TerminalSession session) {
    if (session.cpuUsage != null) {
      session.cpuHistory.add(session.cpuUsage!);
      if (session.cpuHistory.length > 120) {
        session.cpuHistory.removeAt(0);
      }
    }
    if (session.memUsage != null) {
      session.memHistory.add(session.memUsage!);
      if (session.memHistory.length > 120) {
        session.memHistory.removeAt(0);
      }
    }
  }
}

