import '../models/transfer_task.dart';

class SpeedSample {
  const SpeedSample({
    required this.timestamp,
    required this.bytesPerSec,
  });

  final DateTime timestamp;
  final double bytesPerSec;
}

class SharedSessionDiscoveryView {
  const SharedSessionDiscoveryView({
    required this.deviceName,
    required this.hostAddress,
    required this.port,
    required this.sharedCount,
    this.sessionTitle,
  });

  final String deviceName;
  final String hostAddress;
  final int port;
  final int sharedCount;
  final String? sessionTitle;
}

class ExternalEditEntry {
  ExternalEditEntry({
    required this.sessionId,
    required this.remotePath,
    required this.localPath,
  });

  final String sessionId;
  final String remotePath;
  final String localPath;
  DateTime? suppressUntil;
  DateTime? lastModified;
  int? lastSize;
  bool uploading = false;
}

class TransferQueueSummary {
  const TransferQueueSummary({
    required this.id,
    required this.name,
    required this.direction,
    required this.paused,
    required this.total,
    required this.done,
    required this.progress,
    required this.preparing,
    required this.preparingLabel,
    required this.canCancel,
    required this.createdAt,
    required this.etaSeconds,
  });

  final String id;
  final String name;
  final TransferDirection direction;
  final bool paused;
  final int total;
  final int done;
  final double progress;
  final bool preparing;
  final String? preparingLabel;
  final bool canCancel;
  final DateTime createdAt;
  final int? etaSeconds;

  bool get isTerminal => !preparing && total > 0 && done >= total;
}

class TransferDirectionSummary {
  const TransferDirectionSummary({
    required this.total,
    required this.done,
    required this.progress,
  });

  final int total;
  final int done;
  final double progress;

  bool get hasTasks => total > 0;
}

class SessionTransferSummary {
  const SessionTransferSummary({
    required this.preparing,
    required this.preparingLabel,
    required this.scanningScanned,
    required this.scanningFiles,
    required this.uploadQueues,
    required this.downloadQueues,
    required this.upload,
    required this.download,
    required this.runningUploadJobs,
    required this.runningDownloadJobs,
    required this.runningTotalJobs,
    required this.nativeBusySessions,
    required this.nativeTotalSessions,
    this.uploadSpeedHistory = const [],
    this.downloadSpeedHistory = const [],
  });

  final bool preparing;
  final String? preparingLabel;
  final int scanningScanned;
  final int scanningFiles;
  final List<TransferQueueSummary> uploadQueues;
  final List<TransferQueueSummary> downloadQueues;
  final TransferDirectionSummary upload;
  final TransferDirectionSummary download;
  final int runningUploadJobs;
  final int runningDownloadJobs;
  final int runningTotalJobs;
  final int nativeBusySessions;
  final int nativeTotalSessions;
  final List<SpeedSample> uploadSpeedHistory;
  final List<SpeedSample> downloadSpeedHistory;

  bool get hasTransferTasks =>
      uploadQueues.isNotEmpty || downloadQueues.isNotEmpty;
  bool get showPreparing => preparing && !hasTransferTasks;
  bool get showEmpty => !preparing && !hasTransferTasks;
  bool get canCancel =>
      uploadQueues.any((queue) => queue.canCancel) ||
      downloadQueues.any((queue) => queue.canCancel);
}

class InternalViewerPreparationResult {
  const InternalViewerPreparationResult({
    required this.localPath,
    required this.truncated,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final String localPath;
  final bool truncated;
  final int downloadedBytes;
  final int? totalBytes;
}

class InternalViewerDownloadProgress {
  const InternalViewerDownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.done,
    required this.truncated,
    this.error,
  });

  final int downloadedBytes;
  final int? totalBytes;
  final bool done;
  final bool truncated;
  final String? error;
}

class InternalViewerStreamPreparationResult {
  const InternalViewerStreamPreparationResult({
    required this.localPath,
    required this.progressStream,
    required this.completion,
    required this.cancel,
  });

  final String localPath;
  final Stream<InternalViewerDownloadProgress> progressStream;
  final Future<InternalViewerPreparationResult?> completion;
  final void Function() cancel;
}

/// 终端性能设置
class TerminalPerformanceSettings {
  const TerminalPerformanceSettings({
    this.adaptiveThrottleEnabled = true,
  });

  /// 是否启用自适应限流
  final bool adaptiveThrottleEnabled;

  TerminalPerformanceSettings copyWith({
    bool? adaptiveThrottleEnabled,
  }) {
    return TerminalPerformanceSettings(
      adaptiveThrottleEnabled: adaptiveThrottleEnabled ?? this.adaptiveThrottleEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'adaptiveThrottleEnabled': adaptiveThrottleEnabled,
    };
  }

  factory TerminalPerformanceSettings.fromJson(Map<String, dynamic> json) {
    return TerminalPerformanceSettings(
      adaptiveThrottleEnabled: json['adaptiveThrottleEnabled'] as bool? ?? true,
    );
  }
}

