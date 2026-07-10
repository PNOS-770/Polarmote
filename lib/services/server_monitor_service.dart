import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import '../shared/logging/Polarmote_log.dart';

import '../features/terminal/models/host_entry.dart';
import '../features/terminal/models/terminal_tab.dart';
import '../features/terminal/state/terminal_app_state.dart';
import 'server_metrics.dart';

class _ProcStatValues {
  const _ProcStatValues(this.idle, this.total);
  final int idle;
  final int total;
}

class ServerMonitorService {
  static final ServerMonitorService _instance = ServerMonitorService._();
  static ServerMonitorService get instance => _instance;
  ServerMonitorService._();

  bool _running = false;
  Timer? _collectTimer;
  TerminalAppState? _appState;

  int _intervalSeconds = 3;
  int get intervalSeconds => _intervalSeconds;
  set intervalSeconds(int v) {
    _intervalSeconds = v.clamp(2, 300);
    if (_running) {
      _collectTimer?.cancel();
      _collectTimer = Timer.periodic(
        Duration(seconds: _intervalSeconds),
        (_) => _collectAll(),
      );
    }
  }

  static const int maxHistory = 120;

  final Map<String, List<ServerMetricsSnapshot>> _history = {};
  List<ServerMetricsSnapshot> history(String hostId) =>
      _history[hostId] ?? [];

  final Map<String, _ProcStatValues> _previousProcStat = {};

  void start(TerminalAppState appState) {
    if (_running) return;
    _appState = appState;
    _running = true;
    _collectAll();
    _collectTimer = Timer.periodic(
      Duration(seconds: _intervalSeconds),
      (_) => _collectAll(),
    );
  }

  void stop() {
    _running = false;
    _collectTimer?.cancel();
    _collectTimer = null;
    _history.clear();
    _previousProcStat.clear();
  }

  void _collectAll() {
    final appState = _appState;
    if (appState == null) return;
    for (final host in appState.hosts) {
      final status = appState.hostSessionStatus(host.id);
      if (status == TerminalStatus.connected) {
        if (host.isSsh) {
          _collectForSshHost(appState, host);
        } else if (host.isLocal) {
          _collectForLocalHost(host);
        }
      }
    }
  }

  double? _cpuFromProcStat(String output, String hostId) {
    final match = RegExp(
      r'^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)',
    ).firstMatch(output);
    if (match == null) return null;

    final user = int.parse(match.group(1)!);
    final nice = int.parse(match.group(2)!);
    final system = int.parse(match.group(3)!);
    final idle = int.parse(match.group(4)!);
    final iowait = int.parse(match.group(5)!);
    final irq = int.parse(match.group(6)!);
    final softirq = int.parse(match.group(7)!);
    final steal = int.parse(match.group(8)!);

    final total = user + nice + system + idle + iowait + irq + softirq + steal;
    final current = _ProcStatValues(idle + iowait, total);

    final previous = _previousProcStat[hostId];
    _previousProcStat[hostId] = current;
    if (previous == null) return null;

    final deltaIdle = current.idle - previous.idle;
    final deltaTotal = current.total - previous.total;
    if (deltaTotal <= 0) return null;

    return ((deltaTotal - deltaIdle) / deltaTotal * 100).clamp(0, 100);
  }

  Future<void> _collectForSshHost(
      TerminalAppState appState, HostEntry host) async {
    try {
      final client = await appState.connectSshClientForHost(host);
      try {
        double cpu = 0;
        final procStat = await _execSsh(
          client,
          "cat /proc/stat | grep '^cpu ' 2>/dev/null",
        );
        final deltaCpu = _cpuFromProcStat(procStat, host.id);
        if (deltaCpu != null) {
          cpu = deltaCpu;
        } else {
          final fallback = await _execSsh(
            client,
            "top -bn1 2>/dev/null | grep -E '^(%?)Cpu' | awk '{print \$2}' | cut -d'%' -f1",
          );
          cpu = double.tryParse(fallback.trim()) ?? 0;
        }

        final mem = await _execSsh(
          client,
          "free -m | awk '/Mem:/ {printf \"%.1f\", \$3/\$2 * 100}'",
        );
        final disk = await _execSsh(
          client,
          "df -h / 2>/dev/null | awk 'NR==2 {print \$5}' | cut -d'%' -f1",
        );
        final uptimeStr = await _execSsh(
          client,
          'cat /proc/uptime | cut -d. -f1',
        );

        final snapshot = ServerMetricsSnapshot(
          timestamp: DateTime.now(),
          cpuUsage: cpu,
          memoryUsage: double.tryParse(mem.trim()) ?? 0,
          diskUsage: double.tryParse(disk.trim()) ?? 0,
          uptimeSeconds: int.tryParse(uptimeStr.trim()) ?? 0,
        );

        _addSnapshot(host.id, snapshot);
      } finally {
        client.close();
      }
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
  }

  Future<void> _collectForLocalHost(HostEntry host) async {
    try {
      double cpu = 0;
      double mem = 0;
      double disk = 0;

      if (Platform.isWindows) {
        cpu = await _getWindowsCpu();
        mem = await _getWindowsMemory();
        disk = await _getWindowsDisk();
      } else if (Platform.isMacOS) {
        cpu = await _getMacosCpu();
        mem = await _getUnixMemory();
        disk = await _getUnixDisk();
      } else if (Platform.isIOS) {
        cpu = await _getIosCpu();
        mem = await _getIosMemory();
        disk = await _getUnixDisk();
      } else if (Platform.isAndroid) {
        cpu = await _getAndroidCpu(host.id);
        mem = await _getAndroidMemory();
        disk = await _getAndroidDisk();
      } else {
        final procStat = await _readLocalProcStat();
        if (procStat != null) {
          final deltaCpu = _cpuFromProcStat(procStat, host.id);
          cpu = deltaCpu ?? await _getFallbackUnixCpu();
        }
        mem = await _getUnixMemory();
        disk = await _getUnixDisk();
      }

      final snapshot = ServerMetricsSnapshot(
        timestamp: DateTime.now(),
        cpuUsage: cpu,
        memoryUsage: mem,
        diskUsage: disk,
        uptimeSeconds: 0,
      );

      _addSnapshot(host.id, snapshot);
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
  }

  Future<String?> _readLocalProcStat() async {
    try {
      final file = File('/proc/stat');
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.startsWith('cpu ')) return line;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<double> _getWindowsCpu() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          r'$cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | '
          r'Measure-Object -Property LoadPercentage -Average; '
          r'if ($cpu.Average -ne $null) { [math]::Round($cpu.Average, 1) } else { 0 }',
        ],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null && value > 0) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }

    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          r"(Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue",
        ],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null && value > 0) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }

    try {
      final result = await Process.run('wmic', ['cpu', 'get', 'loadpercentage']);
      for (final line in result.stdout.toString().split('\n')) {
        final trimmed = line.trim();
        final value = int.tryParse(trimmed);
        if (value != null && value > 0) return value.toDouble();
      }
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }

    return 0;
  }

  Future<double> _getWindowsMemory() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          r"$os = Get-CimInstance Win32_OperatingSystem; "
          r'[math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1)',
        ],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }

    try {
      final result = await Process.run(
        'wmic',
        ['OS', 'get', 'FreePhysicalMemory,TotalVisibleMemorySize', '/Value'],
      );
      final output = result.stdout.toString();
      final freeMatch = RegExp(r'FreePhysicalMemory=(\d+)').firstMatch(output);
      final totalMatch =
          RegExp(r'TotalVisibleMemorySize=(\d+)').firstMatch(output);
      if (freeMatch != null && totalMatch != null) {
        final free = int.parse(freeMatch.group(1)!);
        final total = int.parse(totalMatch.group(1)!);
        if (total > 0) {
          return ((total - free) / total * 100);
        }
      }
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }

    return 0;
  }

  Future<double> _getWindowsDisk() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          r"$disk = Get-PSDrive C; [math]::Round(($disk.Used / ($disk.Used + $disk.Free)) * 100, 1)",
        ],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }

    try {
      final result = await Process.run(
        'wmic',
        ['logicaldisk', 'where', 'DeviceID="C:"', 'get', 'Size,FreeSpace', '/Value'],
      );
      final output = result.stdout.toString();
      final freeMatch = RegExp(r'FreeSpace=(\d+)').firstMatch(output);
      final sizeMatch = RegExp(r'Size=(\d+)').firstMatch(output);
      if (freeMatch != null && sizeMatch != null) {
        final free = int.parse(freeMatch.group(1)!);
        final size = int.parse(sizeMatch.group(1)!);
        if (size > 0) {
          return ((size - free) / size * 100);
        }
      }
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }

    return 0;
  }

  Future<double> _getMacosCpu() async {
    try {
      final result = await Process.run('top', ['-l', '1', '-n', '0']);
      final output = result.stdout.toString();
      final match =
          RegExp(r'CPU usage: ([\d.]+)% user, ([\d.]+)% sys').firstMatch(output);
      if (match != null) {
        final user = double.tryParse(match.group(1) ?? '0') ?? 0;
        final sys = double.tryParse(match.group(2) ?? '0') ?? 0;
        return user + sys;
      }
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<double> _getFallbackUnixCpu() async {
    try {
      final result = await Process.run(
        'sh',
        ['-c', r"top -bn1 2>/dev/null | grep -E '^(%?)Cpu' | awk '{print $2}' | cut -d'%' -f1"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    try {
      final result = await Process.run(
        'sh',
        ['-c', r"cat /proc/stat | grep '^cpu ' | awk '{total=$2+$3+$4+$5+$6+$7+$8+$9; idle=$5; if (total>0) print (total-idle)*100/total}'"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<double> _getUnixMemory() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('vm_stat', []);
        final output = result.stdout.toString();
        const pageSize = 4096;
        final freeMatch = RegExp(r'Pages free:\s+(\d+)').firstMatch(output);
        final activeMatch =
            RegExp(r'Pages active:\s+(\d+)').firstMatch(output);
        final inactiveMatch =
            RegExp(r'Pages inactive:\s+(\d+)').firstMatch(output);
        final wiredMatch =
            RegExp(r'Pages wired down:\s+(\d+)').firstMatch(output);
        if (freeMatch != null &&
            activeMatch != null &&
            inactiveMatch != null &&
            wiredMatch != null) {
          final free = int.parse(freeMatch.group(1)!) * pageSize;
          final active = int.parse(activeMatch.group(1)!) * pageSize;
          final inactive = int.parse(inactiveMatch.group(1)!) * pageSize;
          final wired = int.parse(wiredMatch.group(1)!) * pageSize;
          final total = free + active + inactive + wired;
          if (total > 0) {
            return ((active + wired) / total * 100);
          }
        }
      } else {
        final result = await Process.run(
          'sh',
          ['-c', "free -m | awk '/Mem:/ {printf \"%.1f\", \$3/\$2 * 100}'"],
        );
        final value = double.tryParse(result.stdout.toString().trim());
        if (value != null) return value;
      }
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<double> _getUnixDisk() async {
    try {
      final result = await Process.run(
        'sh',
        ['-c', "df -h / 2>/dev/null | awk 'NR==2 {print \$5}' | cut -d'%' -f1"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<double> _getAndroidCpu(String hostId) async {
    final procStat = await _readLocalProcStat();
    if (procStat != null) {
      final deltaCpu = _cpuFromProcStat(procStat, hostId);
      if (deltaCpu != null) return deltaCpu;
    }
    try {
      final result = await Process.run(
        'sh',
        ['-c', "cat /proc/stat | grep '^cpu ' | awk '{total=\$2+\$3+\$4+\$5+\$6+\$7+\$8+\$9; idle=\$5; if (total>0) print (total-idle)*100/total}'"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    try {
      final result = await Process.run(
        'sh',
        ['-c', "top -n 1 2>/dev/null | grep 'CPU:' | awk '{print \$2}' | cut -d'%' -f1"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<double> _getAndroidMemory() async {
    try {
      final result = await Process.run(
        'sh',
        ['-c',
         "cat /proc/meminfo | awk '/MemTotal|MemAvailable/ {print \$2}' | awk 'NR==1{t=\$1} NR==2{a=\$1} END{printf \"%.1f\", (t-a)/t*100}'"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    try {
      final result = await Process.run(
        'sh',
        ['-c', "free -m 2>/dev/null | awk '/Mem:/ {printf \"%.1f\", \$3/\$2 * 100}'"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<double> _getAndroidDisk() async {
    try {
      final result = await Process.run(
        'sh',
        ['-c', "df /data 2>/dev/null | awk 'NR==2 {print \$5}' | cut -d'%' -f1"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    try {
      final result = await Process.run(
        'sh',
        ['-c', "df / 2>/dev/null | awk 'NR==2 {print \$5}' | cut -d'%' -f1"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<double> _getIosCpu() async {
    try {
      final result = await Process.run(
        'sh',
        ['-c', "top -l 1 -n 0 | grep 'CPU usage' | awk '{print \$3}' | cut -d'%' -f1"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<double> _getIosMemory() async {
    try {
      final result = await Process.run(
        'sh',
        ['-c',
         "vm_stat | awk '/Pages free|Pages active|Pages inactive|Pages wired/ {sum+=\$NF} END {print (NR>0 ? 100-(\$NF/sum)*100 : 0)}'"],
      );
      final value = double.tryParse(result.stdout.toString().trim());
      if (value != null) return value;
    } catch (e) { PolarmoteLog.error('server_monitor_service', '$e'); }
    return 0;
  }

  Future<String> _execSsh(SSHClient client, String cmd) async {
    final session = await client.execute(cmd);
    final output = await session.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    return output.trim();
  }

  void _addSnapshot(String hostId, ServerMetricsSnapshot snapshot) {
    _history.putIfAbsent(hostId, () => []);
    _history[hostId]!.add(snapshot);
    if (_history[hostId]!.length > maxHistory) {
      _history[hostId]!.removeAt(0);
    }
  }
}




