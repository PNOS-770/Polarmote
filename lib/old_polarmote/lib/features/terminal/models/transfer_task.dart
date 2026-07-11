enum TransferStatus { queued, running, paused, failed, completed, canceled }

enum TransferDirection { upload, download }

class TransferTask {
  const TransferTask({
    required this.id,
    required this.batchId,
    required this.name,
    required this.size,
    required this.progress,
    required this.status,
    required this.direction,
    this.sourcePath,
    this.destinationPath,
    this.attempt = 1,
    this.maxAttempts = 1,
    this.lastError,
  });

  final String id;
  final String batchId;
  final String name;
  final int size;
  final double progress;
  final TransferStatus status;
  final TransferDirection direction;
  final String? sourcePath;
  final String? destinationPath;
  final int attempt;
  final int maxAttempts;
  final String? lastError;

  TransferTask copyWith({
    double? progress,
    TransferStatus? status,
    int? size,
    String? sourcePath,
    String? destinationPath,
    int? attempt,
    int? maxAttempts,
    String? lastError,
    bool clearLastError = false,
  }) {
    return TransferTask(
      id: id,
      batchId: batchId,
      name: name,
      size: size ?? this.size,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      direction: direction,
      sourcePath: sourcePath ?? this.sourcePath,
      destinationPath: destinationPath ?? this.destinationPath,
      attempt: attempt ?? this.attempt,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}
