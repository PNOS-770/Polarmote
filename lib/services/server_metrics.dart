class ServerMetricsSnapshot {
  final DateTime timestamp;
  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final int uptimeSeconds;

  const ServerMetricsSnapshot({
    required this.timestamp,
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.diskUsage = 0,
    this.uptimeSeconds = 0,
  });
}

