import 'package:path/path.dart' as p;

String formatBytes(int? bytes) {
  if (bytes == null) return '--';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}

String parentPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parent = p.posix.dirname(normalized);
  return parent.isEmpty ? '/' : parent;
}

String formatPercent(double? value) {
  if (value == null || value.isNaN) return '--';
  final percent = (value * 100).clamp(0, 100).toStringAsFixed(0);
  return '$percent%';
}

String formatLoad(double? value) {
  if (value == null || value.isNaN) return '--';
  return value.toStringAsFixed(2);
}

String formatRate(double? bytesPerSec) {
  if (bytesPerSec == null || bytesPerSec.isNaN) return '--';
  if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)}B/s';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)}KB/s';
  }
  if (bytesPerSec < 1024 * 1024 * 1024) {
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)}MB/s';
  }
  return '${(bytesPerSec / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB/s';
}
