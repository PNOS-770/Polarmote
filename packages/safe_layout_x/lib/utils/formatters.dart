String formatBytes(int? bytes) {
  if (bytes == null) return '--';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}
