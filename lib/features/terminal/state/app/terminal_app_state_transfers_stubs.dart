part of 'terminal_app_state_transfers.dart';

extension TerminalAppStateTransfersStubs on TerminalAppState {
  void disposeSessionRuntimes() {}
  void syncTransferForegroundGuardNow() {}

  Future<void> uploadFiles(TerminalSession s, List<String> local, String remote) async {}
  Future<void> downloadFiles(TerminalSession s, List<String> remote, String local) async {}
  Future<void> downloadSelectionToLocal(TerminalSession s, List<FileNode> n, String local) async {}
  Future<void> downloadFileToLocal(TerminalSession s, String r, String l, {String? displayName}) async {}
  Future<void> downloadDirectoryToLocal(TerminalSession s, String r, String l) async {}
  Future<void> cleanupDragFolder(String p) async {}
  Future<void> cleanupDragFile(String p) async {}
  Future<String> prepareDesktopDropFolder(String n) async => '';
  Future<String> prepareDesktopDropFile(String n) async => '';
  Future<String> prepareDesktopDropDirectoryBundle(String n) async => '';

  void refreshTransferSchedulers() {}

  bool isTransferDirectionPaused(TerminalSession s, TransferDirection d) {
    return s.pausedTransferTaskIds.isNotEmpty;
  }
  void setTransferDirectionPaused(TerminalSession s, TransferDirection d, bool p) {}
  void pauseTransferQueue(TerminalSession s, String batchId) {}
  void resumeTransferQueue(TerminalSession s, String batchId) {}

  void _processTransferQueue(TerminalSession s, {TransferDirection? direction}) {}
  void _markTransferCanceled(TerminalSession s, String id, {String? reason}) {
    final idx = _indexOfTransferTask(s, id);
    if (idx < 0) return;
    s.transferQueue[idx] = s.transferQueue[idx].copyWith(status: TransferStatus.canceled);
    s.canceledTransferIds.add(id);
    _bumpTransferVersion(s);
  }
  void _scheduleTransferCleanup(TerminalSession s) {
    Future.delayed(const Duration(seconds: 1), () {
      s.transferQueue.removeWhere((t) => t.status == TransferStatus.completed || t.status == TransferStatus.canceled);
      s.canceledTransferIds.clear();
    });
  }
  void _bumpTransferVersion(TerminalSession s) { s.transferVersion++; }

  bool hasOngoingTransfers(TerminalSession s, {String? batchId}) {
    return s.transferQueue.any((t) => t.status == TransferStatus.queued || t.status == TransferStatus.running);
  }

  void cleanupTransfersForSession(TerminalSession s) {
    s.transferQueue.clear();
    s.transferRunningTaskIds.clear();
    s.pausedTransferTaskIds.clear();
    s.canceledTransferIds.clear();
  }

  SessionTransferSummary transferSummaryForSession(TerminalSession s) {
    final tasks = s.transferQueue;
    final uploadTasks = tasks.where((t) => t.direction == TransferDirection.upload).toList();
    final downloadTasks = tasks.where((t) => t.direction == TransferDirection.download).toList();
    return SessionTransferSummary(
      preparing: false, preparingLabel: null, scanningScanned: 0, scanningFiles: 0,
      uploadQueues: [for (final t in uploadTasks) TransferQueueSummary(
        id: t.id, name: t.name, direction: t.direction, paused: t.status == TransferStatus.paused,
        total: 1, done: t.status == TransferStatus.completed ? 1 : 0, progress: t.progress,
        preparing: false, preparingLabel: null, canCancel: true, createdAt: DateTime.now(), etaSeconds: null)],
      downloadQueues: [for (final t in downloadTasks) TransferQueueSummary(
        id: t.id, name: t.name, direction: t.direction, paused: t.status == TransferStatus.paused,
        total: 1, done: t.status == TransferStatus.completed ? 1 : 0, progress: t.progress,
        preparing: false, preparingLabel: null, canCancel: true, createdAt: DateTime.now(), etaSeconds: null)],
      upload: TransferDirectionSummary(total: uploadTasks.length, done: uploadTasks.where((t) => t.status == TransferStatus.completed).length, progress: uploadTasks.isEmpty ? 0 : uploadTasks.map((t) => t.progress).reduce((a, b) => a + b) / uploadTasks.length),
      download: TransferDirectionSummary(total: downloadTasks.length, done: downloadTasks.where((t) => t.status == TransferStatus.completed).length, progress: downloadTasks.isEmpty ? 0 : downloadTasks.map((t) => t.progress).reduce((a, b) => a + b) / downloadTasks.length),
      runningUploadJobs: 0, runningDownloadJobs: 0, runningTotalJobs: 0, nativeBusySessions: 0, nativeTotalSessions: 0);
  }

  int _indexOfTransferTask(TerminalSession s, String id) => s.transferQueue.indexWhere((t) => t.id == id);
  void _setPendingResumeRequest(TerminalSession s, String id, bool p) {}
  void _cancelTaskToken(TerminalSession s, String id) {}
  _SessionTransferRuntimeSet? _runtimeFor(TerminalSession s, [dynamic arg]) => arg == null ? null : _SessionTransferRuntimeSet(uploadRuntime: _SessionTransferRuntime(), downloadRuntime: _SessionTransferRuntime());
}

