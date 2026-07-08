import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:super_native_extensions/raw_clipboard.dart';

import '../../../../shared/constants/app_string.dart';
import '../../models/file_node.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_session.dart';
import '../../models/transfer_task.dart';
import '../../transfer/mobile/android_transfer_foreground_bridge.dart';
import '../../transfer/facade/transfer_facade.dart';
import '../../transfer/engine/upload_download_flow_engine.dart';
import '../../transfer/control/cancellation_token.dart';
import '../../transfer/transport/native/native_transfer_bridge.dart';
import '../../transfer/transport/transport_factory.dart';
import '../diagnostics/path_error_diagnostics.dart';
import '../terminal_app_state.dart';
import '../terminal_app_state_models.dart';

part 'terminal_app_state_transfers_runtime.dart';
part 'terminal_app_state_transfers_adaptive.dart';

final Expando<Map<String, _SessionTransferRuntimeSet>> _transferRuntimeByState =
    Expando<Map<String, _SessionTransferRuntimeSet>>('transfer-runtime');
final Expando<Map<String, Map<String, CancellationToken>>>
_transferTaskTokensByState =
    Expando<Map<String, Map<String, CancellationToken>>>('transfer-tokens');
final Expando<Map<String, Map<String, Future<void> Function()>>>
_transferTaskCancelCleanupsByState =
    Expando<Map<String, Map<String, Future<void> Function()>>>(
      'transfer-cancel-cleanups',
    );
final Expando<Map<String, Map<String, _StoredTransferTaskRunner>>>
_transferTaskRunnersByState =
    Expando<Map<String, Map<String, _StoredTransferTaskRunner>>>(
      'transfer-task-runners',
    );
final Expando<_TransferAdaptiveState> _transferAdaptiveByState =
    Expando<_TransferAdaptiveState>('transfer-adaptive');
final Expando<_TransferForegroundServiceState>
_transferForegroundServiceByState = Expando<_TransferForegroundServiceState>(
  'transfer-foreground-service',
);
final Expando<Map<String, Set<String>>> _transferLoggedStartByState =
    Expando<Map<String, Set<String>>>('transfer-logged-start');
final Expando<Map<String, int>> _transferErrorReportCountByState =
    Expando<Map<String, int>>('transfer-error-report-count');
final Expando<Map<String, Map<String, _TransferRetrySummary>>>
_transferRetrySummaryByState =
    Expando<Map<String, Map<String, _TransferRetrySummary>>>(
      'transfer-retry-summary',
    );
final Expando<Map<String, Set<String>>> _transferPendingResumeByState =
    Expando<Map<String, Set<String>>>('transfer-pending-resume');
const int _transferSafetyQueueHardCap = 6;
const int _transferSafetyNativeHardCap = 12;
const int _transferSafetyFailureThreshold = 2;
const Duration _transferSafetyFailureWindow = Duration(seconds: 45);
const Duration _transferSafetyFallbackDuration = Duration(seconds: 90);
const Duration _transferAdaptiveProfileHold = Duration(seconds: 12);
const int _transferSafetyFallbackQueueParallel = 1;
const int _transferSafetyFallbackNativeConcurrency = 2;
const int _transferSafetyFallbackChunkSizeKb = 256;
const int _maxDuplicateTransferErrorReports = 3;
const int _maxTransferErrorKeyCache = 256;
const _AdaptiveTransferProfile _mobileProfileBalanced =
    _AdaptiveTransferProfile(
      name: 'mobile-balanced',
      queueParallelJobs: 2,
      nativeConcurrency: 4,
      chunkSizeKb: 512,
    );
const _AdaptiveTransferProfile _mobileProfileThroughput =
    _AdaptiveTransferProfile(
      name: 'mobile-throughput',
      queueParallelJobs: 2,
      nativeConcurrency: 6,
      chunkSizeKb: 768,
    );
const _AdaptiveTransferProfile _desktopProfileBalanced =
    _AdaptiveTransferProfile(
      name: 'desktop-balanced',
      queueParallelJobs: 2,
      nativeConcurrency: 6,
      chunkSizeKb: 768,
    );
const _AdaptiveTransferProfile _desktopProfileThroughput =
    _AdaptiveTransferProfile(
      name: 'desktop-throughput',
      queueParallelJobs: 3,
      nativeConcurrency: 8,
      chunkSizeKb: 1024,
    );
const _AdaptiveTransferProfile _desktopProfileHighThroughput =
    _AdaptiveTransferProfile(
      name: 'desktop-high-throughput',
      queueParallelJobs: 4,
      nativeConcurrency: 10,
      chunkSizeKb: 1024,
    );
const TransferTransportFactory _transferTransportFactory =
    TransferTransportFactory();

extension TerminalAppStateTransfers on TerminalAppState {
  void syncTransferForegroundGuardNow() {
    _syncTransferForegroundService();
  }

  String _nextTransferId(String prefix) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    if (stamp == lastTransferTimestamp) {
      transferIdSeed += 1;
    } else {
      lastTransferTimestamp = stamp;
      transferIdSeed = 0;
    }
    return '$prefix-$stamp-$transferIdSeed';
  }

  Map<String, _SessionTransferRuntimeSet> _runtimeMap() {
    return _transferRuntimeByState[this] ??=
        <String, _SessionTransferRuntimeSet>{};
  }

  Map<String, Map<String, CancellationToken>> _tokenMapBySession() {
    return _transferTaskTokensByState[this] ??=
        <String, Map<String, CancellationToken>>{};
  }

  Map<String, Map<String, Future<void> Function()>>
  _cancelCleanupMapBySession() {
    return _transferTaskCancelCleanupsByState[this] ??=
        <String, Map<String, Future<void> Function()>>{};
  }

  Map<String, Map<String, _StoredTransferTaskRunner>>
  _taskRunnerMapBySession() {
    return _transferTaskRunnersByState[this] ??=
        <String, Map<String, _StoredTransferTaskRunner>>{};
  }

  Map<String, _StoredTransferTaskRunner> _taskRunnerMapForSession(
    TerminalSession session,
  ) {
    final bySession = _taskRunnerMapBySession();
    return bySession.putIfAbsent(
      session.id,
      () => <String, _StoredTransferTaskRunner>{},
    );
  }

  void _registerTaskRunner(
    TerminalSession session,
    TransferTask task,
    Future<void> Function() execute, {
    required bool priority,
  }) {
    _taskRunnerMapForSession(session)[task.id] = _StoredTransferTaskRunner(
      taskTemplate: task,
      execute: execute,
      priority: priority,
    );
  }

  _StoredTransferTaskRunner? _taskRunnerForTask(
    TerminalSession session,
    String taskId,
  ) {
    return _taskRunnerMapForSession(session)[taskId];
  }

  void _clearTaskRunner(TerminalSession session, String taskId) {
    _taskRunnerMapForSession(session).remove(taskId);
  }

  void _clearAllTaskRunners(TerminalSession session) {
    _taskRunnerMapBySession().remove(session.id);
  }

  Map<String, Set<String>> _loggedStartMapBySession() {
    return _transferLoggedStartByState[this] ??= <String, Set<String>>{};
  }

  Set<String> _loggedStartSetForSession(TerminalSession session) {
    return _loggedStartMapBySession().putIfAbsent(session.id, () => <String>{});
  }

  Map<String, int> _transferErrorReportCounts() {
    return _transferErrorReportCountByState[this] ??= <String, int>{};
  }

  Map<String, Map<String, _TransferRetrySummary>> _retrySummaryMapBySession() {
    return _transferRetrySummaryByState[this] ??=
        <String, Map<String, _TransferRetrySummary>>{};
  }

  Map<String, Set<String>> _pendingResumeMapBySession() {
    return _transferPendingResumeByState[this] ??= <String, Set<String>>{};
  }

  Set<String> _pendingResumeSetForSession(TerminalSession session) {
    return _pendingResumeMapBySession().putIfAbsent(
      session.id,
      () => <String>{},
    );
  }

  bool _hasPendingResumeRequest(TerminalSession session, String taskId) {
    return _pendingResumeSetForSession(session).contains(taskId);
  }

  void _setPendingResumeRequest(
    TerminalSession session,
    String taskId,
    bool pending,
  ) {
    final set = _pendingResumeSetForSession(session);
    if (pending) {
      set.add(taskId);
      return;
    }
    set.remove(taskId);
    if (set.isEmpty) {
      _pendingResumeMapBySession().remove(session.id);
    }
  }

  void _clearAllPendingResumeRequests(TerminalSession session) {
    _pendingResumeMapBySession().remove(session.id);
  }

  Map<String, _TransferRetrySummary> _retrySummaryForSession(
    TerminalSession session,
  ) {
    return _retrySummaryMapBySession().putIfAbsent(
      session.id,
      () => <String, _TransferRetrySummary>{},
    );
  }

  void _clearTransferRetrySummary(TerminalSession session, String taskId) {
    _retrySummaryForSession(session).remove(taskId);
  }

  void _clearAllTransferRetrySummaries(TerminalSession session) {
    _retrySummaryMapBySession().remove(session.id);
  }

  String _transferErrorReportKey(String message) {
    return message.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  bool _tryReportTransferError(String normalizedError) {
    final key = _transferErrorReportKey(normalizedError);
    if (key.isEmpty) {
      return true;
    }
    final counts = _transferErrorReportCounts();
    final current = counts[key] ?? 0;
    if (current >= _maxDuplicateTransferErrorReports) {
      return false;
    }
    counts[key] = current + 1;
    if (counts.length > _maxTransferErrorKeyCache) {
      counts.removeWhere(
        (_, value) => value >= _maxDuplicateTransferErrorReports,
      );
      if (counts.length > _maxTransferErrorKeyCache) {
        counts.clear();
      }
    }
    return true;
  }

  Map<String, CancellationToken> _tokenMapForSession(TerminalSession session) {
    final map = _tokenMapBySession();
    return map.putIfAbsent(session.id, () => <String, CancellationToken>{});
  }

  CancellationToken _cancellationTokenForTask(
    TerminalSession session,
    String taskId,
  ) {
    final map = _tokenMapForSession(session);
    return map.putIfAbsent(taskId, CancellationToken.new);
  }

  void _cancelTaskToken(TerminalSession session, String taskId) {
    final token = _tokenMapForSession(session)[taskId];
    token?.cancel();
  }

  void _clearTaskToken(TerminalSession session, String taskId) {
    _tokenMapForSession(session).remove(taskId);
  }

  void _cancelAllTaskTokens(TerminalSession session) {
    final map = _tokenMapForSession(session);
    for (final token in map.values) {
      token.cancel();
    }
  }

  void _clearAllTaskTokens(TerminalSession session) {
    _tokenMapBySession().remove(session.id);
  }

  bool _tryMarkTransferStartLogged(TerminalSession session, String taskId) {
    return _loggedStartSetForSession(session).add(taskId);
  }

  void _clearTransferStartLogged(TerminalSession session, String taskId) {
    _loggedStartSetForSession(session).remove(taskId);
  }

  void _clearAllTransferStartLogged(TerminalSession session) {
    _loggedStartMapBySession().remove(session.id);
  }

  void _registerTaskCancelCleanup(
    TerminalSession session,
    String taskId,
    Future<void> Function() cleanup,
  ) {
    final bySession = _cancelCleanupMapBySession();
    final taskMap = bySession.putIfAbsent(
      session.id,
      () => <String, Future<void> Function()>{},
    );
    taskMap[taskId] = cleanup;
  }

  void _clearTaskCancelCleanup(TerminalSession session, String taskId) {
    final bySession = _cancelCleanupMapBySession();
    bySession[session.id]?.remove(taskId);
  }

  void _runTaskCancelCleanup(TerminalSession session, String taskId) {
    final bySession = _cancelCleanupMapBySession();
    final cleanup = bySession[session.id]?.remove(taskId);
    if (cleanup == null) {
      return;
    }
    unawaited(cleanup());
  }

  void _runAllTaskCancelCleanups(TerminalSession session) {
    final bySession = _cancelCleanupMapBySession();
    final taskMap = bySession.remove(session.id);
    if (taskMap == null) {
      return;
    }
    for (final cleanup in taskMap.values) {
      unawaited(cleanup());
    }
  }

  _SessionTransferRuntimeSet _runtimeSetFor(TerminalSession session) {
    final map = _runtimeMap();
    return map.putIfAbsent(
      session.id,
      () => _SessionTransferRuntimeSet(
        uploadRuntime: _SessionTransferRuntime(),
        downloadRuntime: _SessionTransferRuntime(),
      ),
    );
  }

  _SessionTransferRuntime _runtimeFor(
    TerminalSession session,
    TransferDirection direction,
  ) {
    final set = _runtimeSetFor(session);
    return direction == TransferDirection.upload
        ? set.uploadRuntime
        : set.downloadRuntime;
  }

  TransferFacade _transferFacadeFor(
    TerminalSession session, {
    TransferDirection? direction,
  }) {
    if (session.profile.isLocal) {
      throw StateError(
        AppStrings.values.sftpNotReady.resolve(locale.languageCode),
      );
    }
    final transferDirection = direction ?? TransferDirection.download;
    final options = _effectiveTransferRuntimeOptions();
    return TransferFacade(
      _transferTransportFactory.create(
        profile: session.profile,
        options: options,
      ),
      direction: transferDirection,
    );
  }

  _SessionTransferRuntimeSet? _runtimeMaybeFor(TerminalSession session) {
    return _runtimeMap()[session.id];
  }

  void _disposeRuntimeFor(TerminalSession session) {
    _runtimeMap().remove(session.id);
    _clearAllTransferStartLogged(session);
    _clearAllTransferRetrySummaries(session);
    _clearAllTaskRunners(session);
    _clearAllPendingResumeRequests(session);
  }

  Future<void> _queueTransferTask(
    TerminalSession session, {
    required String batchId,
    required String name,
    required TransferDirection direction,
    String? sourcePath,
    String? destinationPath,
    int size = 0,
    bool priority = false,
    void Function(String taskId)? onTaskCreated,
    required Future<void> Function(String taskId) run,
  }) {
    final taskId = _nextTransferId(
      direction == TransferDirection.upload ? 'up' : 'down',
    );
    onTaskCreated?.call(taskId);
    final task = TransferTask(
      id: taskId,
      batchId: batchId,
      name: name,
      size: size,
      progress: 0,
      status: TransferStatus.queued,
      direction: direction,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      attempt: 1,
      maxAttempts: transferAutoRetryEnabled
          ? transferRetryMaxAttempts.clamp(1, 12).toInt()
          : 1,
    );
    return _enqueueTransfer(session, task, () async {
      await run(taskId);
    }, priority: priority);
  }

  UploadDownloadFlowEngine _uploadDownloadEngine() {
    return UploadDownloadFlowEngine(
      languageCode: locale.languageCode,
      createTransferFacade: (session, {required direction}) =>
          _transferFacadeFor(session, direction: direction),
      cancellationTokenForTask: _cancellationTokenForTask,
      registerTaskCancelCleanup: _registerTaskCancelCleanup,
      queueTransferTask: _queueTransferTask,
      startTransferBatch: _startTransferBatch,
      updateTransfer: _updateTransfer,
      findTransferTask: _findTransferTask,
      finishTransfer: _finishTransfer,
      markCancelledIfNeeded: _markCancelledIfNeeded,
      ensureNotCancelled: _ensureNotCancelled,
      nextTransferId: _nextTransferId,
      resolveDesktopDirectory: resolveDesktopDirectory,
    );
  }

  Future<void> uploadFiles(
    TerminalSession session,
    List<String> localPaths,
    String remoteDir,
  ) {
    return _runTransferAction(
      () => _uploadDownloadEngine().uploadFiles(session, localPaths, remoteDir),
    );
  }

  Future<void> downloadFiles(
    TerminalSession session,
    List<String> remotePaths,
    String localDir,
  ) {
    return _runTransferAction(
      () =>
          _uploadDownloadEngine().downloadFiles(session, remotePaths, localDir),
    );
  }

  Future<void> streamRemoteForDrag({
    required TerminalSession session,
    required FileNode node,
    required VirtualFileEventSinkProvider sinkProvider,
    required WriteProgress progress,
  }) {
    return _runTransferAction(
      () => _uploadDownloadEngine().streamRemoteForDrag(
        session: session,
        node: node,
        sinkProvider: sinkProvider,
        progress: progress,
      ),
    );
  }

  Future<String> prepareFolderDragDirectory(String folderName) {
    return _uploadDownloadEngine().prepareFolderDragDirectory(folderName);
  }

  Future<String> prepareDesktopDropFolder(String folderName) {
    return _uploadDownloadEngine().prepareDesktopDropFolder(folderName);
  }

  Future<String> prepareDesktopDropFile(String fileName) {
    return _uploadDownloadEngine().prepareDesktopDropFile(fileName);
  }

  Future<String> prepareDesktopDropDirectoryBundle(String folderName) {
    return _uploadDownloadEngine().prepareDesktopDropDirectoryBundle(
      folderName,
    );
  }

  Future<void> cleanupDragFolder(String folderPath) {
    return _uploadDownloadEngine().cleanupDragFolder(folderPath);
  }

  Future<void> cleanupDragFile(String filePath) {
    return _uploadDownloadEngine().cleanupDragFile(filePath);
  }

  Future<void> downloadSelectionToLocal(
    TerminalSession session,
    List<FileNode> nodes,
    String localDir,
  ) {
    return _runTransferAction(
      () => _uploadDownloadEngine().downloadSelectionToLocal(
        session,
        nodes,
        localDir,
      ),
    );
  }

  Future<void> downloadFileToLocal(
    TerminalSession session,
    String remotePath,
    String localPath, {
    String? displayName,
  }) {
    return _runTransferAction(
      () => _uploadDownloadEngine().downloadFileToLocal(
        session,
        remotePath,
        localPath,
        displayName: displayName,
      ),
    );
  }

  Future<void> downloadDirectoryToLocal(
    TerminalSession session,
    String remotePath,
    String localDir,
  ) {
    return _runTransferAction(
      () => _uploadDownloadEngine().downloadDirectoryToLocal(
        session,
        remotePath,
        localDir,
      ),
    );
  }

  Future<void> _runTransferAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (error is TransferCancelledException) {
        return;
      }
      final normalized = _normalizeTransferError(error);
      setError(
        AppStrings.values.transferFailedVar.resolve(
          locale.languageCode,
          params: {'error': normalized},
        ),
      );
    }
  }

  String _normalizeTransferError(Object error) {
    if (error is StateError) {
      return error.message;
    }
    final diagnostic = diagnosePathError(error);
    if (diagnostic.kind != PathErrorKind.unknown) {
      final operation = AppStrings.values.transferLabel.resolve(locale.languageCode);
      return formatPathError(
        diagnostic,
        languageCode: locale.languageCode,
        operation: operation,
      );
    }
    final message = '$error';
    const prefix = 'Bad state: ';
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length);
    }
    return message;
  }

  String _transferDirectionLabel(TransferDirection direction) {
    return (direction == TransferDirection.upload
            ? AppStrings.values.upload
            : AppStrings.values.download)
        .resolve(locale.languageCode);
  }

  String _transferPathDisplay(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return AppStrings.values.unknown.resolve(locale.languageCode);
    }
    if (value == '<drag-stream>') {
      return AppStrings.values.dragStream.resolve(locale.languageCode);
    }
    return value;
  }

  void _logTransferStarted(TerminalSession session, TransferTask task) {
    _tryMarkTransferStartLogged(session, task.id);
  }

  void _logTransferCompleted(TerminalSession session, TransferTask task) {
    _flushTransferRetrySummary(
      session,
      task,
      outcome: _retryOutcomeCompleted(),
    );
    _clearTransferStartLogged(session, task.id);
  }

  void _logTransferCancelled(
    TerminalSession session,
    TransferTask task, {
    String? reason,
  }) {
    _flushTransferRetrySummary(session, task, outcome: _retryOutcomeCanceled());
    _clearTransferStartLogged(session, task.id);
    addStructuredLog(
      category: TerminalLogCategory.transfer,
      level: TerminalLogLevel.warn,
      message: AppStrings.values.transferCancelledVarVarVarVarVarVar.resolve(
        locale.languageCode,
        params: {
          'direction': _transferDirectionLabel(task.direction),
          'name': task.name,
          'source': _transferPathDisplay(task.sourcePath),
          'destination': _transferPathDisplay(task.destinationPath),
          'reason':
              reason ??
              AppStrings.values.transferCancelled.resolve(locale.languageCode),
          'host': session.profile.host,
        },
      ),
      notifyListeners: false,
    );
  }

  void _logTransferFailed(
    TerminalSession session,
    TransferTask task,
    String reason,
  ) {
    _flushTransferRetrySummary(session, task, outcome: _retryOutcomeFailed());
    _clearTransferStartLogged(session, task.id);
    addStructuredLog(
      category: TerminalLogCategory.transfer,
      level: TerminalLogLevel.error,
      message: AppStrings.values.transferFailedDetailVarVarVarVarVarVar.resolve(
        locale.languageCode,
        params: {
          'direction': _transferDirectionLabel(task.direction),
          'name': task.name,
          'source': _transferPathDisplay(task.sourcePath),
          'destination': _transferPathDisplay(task.destinationPath),
          'reason': reason,
          'host': session.profile.host,
        },
      ),
      notifyListeners: false,
    );
  }

  void _logTransferRetrying(
    TerminalSession session,
    TransferTask task,
    Object error,
    Duration delay,
    int nextAttempt,
  ) {
    final reason = _normalizeTransferError(error);
    final retries = _retrySummaryForSession(session);
    final previous = retries[task.id];
    final currentCount = (previous?.count ?? 0) + 1;
    retries[task.id] = _TransferRetrySummary(
      count: currentCount,
      lastAttempt: nextAttempt,
      maxAttempts: task.maxAttempts,
      lastDelayMs: delay.inMilliseconds,
      lastReason: reason,
    );

    if (currentCount == 1) {
      final hint = locale.languageCode == 'zh'
          ? '（后续重试已聚合显示）'
          : ' (subsequent retries are aggregated)';
      addStructuredLog(
        category: TerminalLogCategory.transfer,
        level: TerminalLogLevel.warn,
        message:
            '[Retry] ${_transferDirectionLabel(task.direction)} ${task.name} '
            'attempt $nextAttempt/${task.maxAttempts} in ${delay.inMilliseconds}ms: $reason$hint',
        notifyListeners: false,
      );
    }
  }

  void _flushTransferRetrySummary(
    TerminalSession session,
    TransferTask task, {
    required String outcome,
    bool emitLog = true,
  }) {
    final summary = _retrySummaryForSession(session).remove(task.id);
    if (summary == null || summary.count <= 0 || !emitLog) {
      return;
    }
    final compactReason = _compactLogMessage(summary.lastReason, max: 220);
    addStructuredLog(
      category: TerminalLogCategory.transfer,
      level: TerminalLogLevel.warn,
      message:
          '[RetrySummary] ${_transferDirectionLabel(task.direction)} ${task.name} '
          'retries=${summary.count} outcome=$outcome '
          'lastAttempt=${summary.lastAttempt}/${summary.maxAttempts} '
          'lastDelay=${summary.lastDelayMs}ms lastError=$compactReason',
      notifyListeners: false,
    );
  }

  String _retryOutcomeCompleted() {
    return AppStrings.values.completedLabel.resolve(locale.languageCode);
  }

  String _retryOutcomeCanceled() {
    return AppStrings.values.canceledLabel.resolve(locale.languageCode);
  }

  String _retryOutcomeFailed() {
    return AppStrings.values.failedLabel.resolve(locale.languageCode);
  }

  String _compactLogMessage(String input, {int max = 220}) {
    final compact = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= max) {
      return compact;
    }
    return '${compact.substring(0, max)}...';
  }

  Duration _transferRetryDelayForAttempt(int attempt) {
    final normalizedAttempt = attempt.clamp(1, 24);
    final baseMs = transferRetryBaseDelayMs.clamp(100, 120000).toInt();
    final maxMs = transferRetryMaxDelayMs.clamp(baseMs, 300000).toInt();
    final exp = 1 << (normalizedAttempt - 1).clamp(0, 12);
    final raw = baseMs * exp;
    final clamped = raw > maxMs ? maxMs : raw;
    return Duration(milliseconds: clamped);
  }

  Future<void> _enqueueTransfer(
    TerminalSession session,
    TransferTask task,
    Future<void> Function() run, {
    bool priority = false,
  }) {
    final runtime = _runtimeFor(session, task.direction);
    final completer = Completer<void>();
    final taskIndex = session.transferQueue.length;
    session.transferQueue.add(task);
    session.transferTaskIndex[task.id] = taskIndex;
    _registerTaskRunner(session, task, run, priority: priority);
    _bumpTransferVersion(session);
    runtime.enqueue(
      _QueuedTransferJob(
        task: task,
        execute: run,
        completer: completer,
        priority: priority,
      ),
    );
    _processTransferQueue(session, direction: task.direction);
    _syncTransferForegroundService();
    notifyState();
    return completer.future.catchError((_) {});
  }

  void _processTransferQueue(
    TerminalSession session, {
    TransferDirection? direction,
  }) {
    if (direction != null) {
      _processTransferQueueForDirection(session, direction);
      return;
    }
    _processTransferQueueForDirection(session, TransferDirection.upload);
    _processTransferQueueForDirection(session, TransferDirection.download);
  }

  void refreshTransferSchedulers() {
    for (final session in sessions) {
      _processTransferQueue(session);
    }
  }

  bool isTransferDirectionPaused(
    TerminalSession session,
    TransferDirection direction,
  ) {
    return session.pausedTransferDirections.contains(direction);
  }

  void setTransferDirectionPaused(
    TerminalSession session,
    TransferDirection direction,
    bool paused,
  ) {
    final changed = paused
        ? session.pausedTransferDirections.add(direction)
        : session.pausedTransferDirections.remove(direction);
    if (!changed) {
      return;
    }
    if (paused) {
      final activeTasks = session.transferQueue
          .where(
            (task) =>
                task.direction == direction &&
                (task.status == TransferStatus.running ||
                    task.status == TransferStatus.queued),
          )
          .map((task) => task.id)
          .toList(growable: false);
      for (final taskId in activeTasks) {
        pauseTransfer(session, taskId);
      }
    } else {
      final pausedTasks = session.transferQueue
          .where(
            (task) =>
                task.direction == direction &&
                task.status == TransferStatus.paused,
          )
          .map((task) => task.id)
          .toList(growable: false);
      for (final taskId in pausedTasks) {
        resumeTransfer(session, taskId);
      }
      _processTransferQueue(session, direction: direction);
    }
    _bumpTransferVersion(session);
    notifyState();
  }

  void pauseTransferQueue(TerminalSession session, String batchId) {
    final taskIds = session.transferQueue
        .where(
          (task) =>
              task.batchId == batchId &&
              (task.status == TransferStatus.running ||
                  task.status == TransferStatus.queued),
        )
        .map((task) => task.id)
        .toList(growable: false);
    for (final taskId in taskIds) {
      pauseTransfer(session, taskId);
    }
    _bumpTransferVersion(session);
    notifyState();
  }

  void resumeTransferQueue(TerminalSession session, String batchId) {
    final taskIds = session.transferQueue
        .where(
          (task) =>
              task.batchId == batchId && task.status == TransferStatus.paused,
        )
        .map((task) => task.id)
        .toList(growable: false);
    for (final taskId in taskIds) {
      resumeTransfer(session, taskId);
    }
    _bumpTransferVersion(session);
    notifyState();
  }

  void pauseTransfer(TerminalSession session, String taskId) {
    final index = _indexOfTransferTask(session, taskId);
    if (index == -1) {
      return;
    }
    final current = session.transferQueue[index];
    if (current.status == TransferStatus.completed ||
        current.status == TransferStatus.failed ||
        current.status == TransferStatus.canceled ||
        current.status == TransferStatus.paused) {
      return;
    }
    _setPendingResumeRequest(session, taskId, false);
    session.pausedTransferTaskIds.add(taskId);
    session.canceledTransferIds.remove(taskId);
    _cancelTaskToken(session, taskId);
    if (current.status == TransferStatus.queued) {
      _runtimeFor(session, current.direction).removeQueuedWhere((job) {
        if (job.task.id != taskId) {
          return false;
        }
        if (!job.completer.isCompleted) {
          job.completer.complete();
        }
        return true;
      });
      _markTransferPaused(session, taskId);
      _syncTransferForegroundService();
      _processTransferQueue(session, direction: current.direction);
    } else if (current.status == TransferStatus.running) {
      _updateTransfer(
        session,
        taskId,
        current.progress,
        status: TransferStatus.paused,
        clearLastError: true,
      );
    }
    _bumpTransferVersion(session);
    notifyState();
  }

  void resumeTransfer(TerminalSession session, String taskId) {
    final index = _indexOfTransferTask(session, taskId);
    if (index == -1) {
      return;
    }
    final current = session.transferQueue[index];
    if (current.status != TransferStatus.paused) {
      return;
    }
    final runner = _taskRunnerForTask(session, taskId);
    if (runner == null) {
      setError(
        AppStrings.values.transferFailedVar.resolve(
          locale.languageCode,
          params: {'error': 'task runner missing'},
        ),
      );
      return;
    }
    if (session.transferRunningTaskIds.contains(taskId)) {
      _setPendingResumeRequest(session, taskId, true);
      _bumpTransferVersion(session);
      notifyState();
      return;
    }
    final direction = current.direction;
    _setPendingResumeRequest(session, taskId, false);
    session.pausedTransferTaskIds.remove(taskId);
    final queuedTask = current.copyWith(
      status: TransferStatus.queued,
      clearLastError: true,
    );
    session.transferQueue[index] = queuedTask;
    final completer = Completer<void>();
    _runtimeFor(session, direction).enqueue(
      _QueuedTransferJob(
        task: queuedTask,
        execute: runner.execute,
        completer: completer,
        priority: runner.priority,
      ),
    );
    _processTransferQueue(session, direction: direction);
    _syncTransferForegroundService();
    _bumpTransferVersion(session);
    notifyState();
  }

  void _processTransferQueueForDirection(
    TerminalSession session,
    TransferDirection direction,
  ) {
    if (isTransferDirectionPaused(session, direction)) {
      return;
    }
    final runtime = _runtimeFor(session, direction);
    runtime.processQueue(
      maxParallelJobs: () => _effectiveQueueParallelJobs(session, direction),
      shouldStop: () => session.transferCancelRequested,
      isTaskCanceled: (taskId) =>
          session.canceledTransferIds.contains(taskId) ||
          session.pausedTransferTaskIds.contains(taskId),
      onTaskStart: (taskId) {
        session.transferRunningTaskIds.add(taskId);
        session.activeTransfers = _totalRunningJobs(session);
        final task = _findTransferTask(session, taskId);
        final currentProgress = (task?.progress ?? 0)
            .clamp(0.0, 1.0)
            .toDouble();
        if (task != null) {
          _logTransferStarted(session, task);
        }
        _updateTransfer(
          session,
          taskId,
          currentProgress,
          status: TransferStatus.running,
          clearLastError: true,
        );
      },
      onTaskCanceled: (taskId) {
        session.transferRunningTaskIds.remove(taskId);
        final paused =
            session.pausedTransferTaskIds.contains(taskId) ||
            _findTransferTask(session, taskId)?.status == TransferStatus.paused;
        if (paused) {
          _markTransferPaused(session, taskId);
          if (_hasPendingResumeRequest(session, taskId)) {
            _setPendingResumeRequest(session, taskId, false);
            resumeTransfer(session, taskId);
          }
        } else {
          _setPendingResumeRequest(session, taskId, false);
          _markTransferCanceled(session, taskId);
        }
      },
      maxRetryAttempts: (taskId) {
        final task = _findTransferTask(session, taskId);
        return task?.maxAttempts ?? 1;
      },
      retryDelay: (taskId, nextAttempt, _) =>
          _transferRetryDelayForAttempt(nextAttempt),
      onTaskRetrying: (taskId, nextAttempt, delay, error) {
        session.transferRunningTaskIds.remove(taskId);
        _markTransferRetrying(
          session,
          taskId,
          nextAttempt: nextAttempt,
          delay: delay,
          error: error,
        );
      },
      onTaskSucceeded: (_) {},
      onTaskFailed: (taskId, error) {
        _failTransfer(session, taskId, error);
      },
      onStateChanged: () {
        session.activeTransfers = _totalRunningJobs(session);
        _syncTransferForegroundService();
        notifyState();
      },
    );
  }

  int _totalRunningJobs(TerminalSession session) {
    final runtimeSet = _runtimeSetFor(session);
    return runtimeSet.uploadRuntime.runningJobs +
        runtimeSet.downloadRuntime.runningJobs;
  }

  void _updateTransfer(
    TerminalSession session,
    String id,
    double progress, {
    TransferStatus? status,
    int? size,
    int? attempt,
    int? maxAttempts,
    String? lastError,
    bool clearLastError = false,
  }) {
    final index = _indexOfTransferTask(session, id);
    if (index == -1) return;
    final current = session.transferQueue[index];
    final nextProgress = progress.clamp(0.0, 1.0);
    final nextStatus = status ?? current.status;
    final nextSize = size ?? current.size;
    final stableProgress = max(current.progress, nextProgress);
    final now = DateTime.now();
    final lastNotify = session.transferLastNotifyAt[id];
    final progressDelta = (stableProgress - current.progress).abs();
    final timeElapsedMs = lastNotify == null
        ? 999999
        : now.difference(lastNotify).inMilliseconds;
    final shouldNotify =
        nextStatus != current.status ||
        nextSize != current.size ||
        (progressDelta > 0 &&
            (progressDelta >= 0.002 || timeElapsedMs >= 500)) ||
        stableProgress >= 1;
    session.transferQueue[index] = current.copyWith(
      progress: stableProgress,
      status: nextStatus,
      size: nextSize,
      attempt: attempt,
      maxAttempts: maxAttempts,
      lastError: lastError,
      clearLastError: clearLastError,
    );
    if (shouldNotify) {
      session.transferLastNotifyAt[id] = now;
      if (nextStatus == TransferStatus.running || progressDelta > 0) {
        session.lastTransferId = id;
      }
      _bumpTransferVersion(session);
      _syncTransferForegroundService();
      notifyState();
    }
  }

  void _finishTransfer(TerminalSession session, String id) {
    final index = _indexOfTransferTask(session, id);
    if (index == -1) return;
    final finishedTask = session.transferQueue[index];
    _clearTaskToken(session, id);
    _clearTaskCancelCleanup(session, id);
    _clearTaskRunner(session, id);
    _setPendingResumeRequest(session, id, false);
    session.transferRunningTaskIds.remove(id);
    session.pausedTransferTaskIds.remove(id);
    if (session.transferCancelRequested ||
        session.canceledTransferIds.contains(id) ||
        session.transferQueue[index].status == TransferStatus.canceled) {
      _markTransferCanceled(session, id);
      return;
    }
    _logTransferCompleted(session, finishedTask.copyWith(progress: 1));
    session.transferQueue[index] = session.transferQueue[index].copyWith(
      progress: 1,
      status: TransferStatus.completed,
      clearLastError: true,
    );
    session.transferLastNotifyAt.remove(id);
    if (session.lastTransferId == id) {
      session.lastTransferId = null;
    }
    _incrementBatchDone(session);
    _recordTransferSuccessForSafety();
    _scheduleTransferCleanup(session);
    _syncTransferForegroundService();
    notifyState();
  }

  void _failTransfer(TerminalSession session, String id, Object error) {
    final index = _indexOfTransferTask(session, id);
    if (index == -1) return;
    final failedTask = session.transferQueue[index];
    final normalizedError = _normalizeTransferError(error);
    _clearTaskToken(session, id);
    _clearTaskCancelCleanup(session, id);
    _clearTaskRunner(session, id);
    _setPendingResumeRequest(session, id, false);
    session.transferRunningTaskIds.remove(id);
    session.pausedTransferTaskIds.remove(id);
    if (error is TransferCancelledException ||
        session.transferCancelRequested ||
        session.canceledTransferIds.contains(id) ||
        session.pausedTransferTaskIds.contains(id) ||
        session.transferQueue[index].status == TransferStatus.canceled) {
      if (session.pausedTransferTaskIds.contains(id)) {
        _markTransferPaused(session, id);
      } else {
        _markTransferCanceled(session, id);
      }
      return;
    }
    final shouldReportError = _tryReportTransferError(normalizedError);
    if (shouldReportError) {
      _logTransferFailed(session, failedTask, normalizedError);
    } else {
      _flushTransferRetrySummary(
        session,
        failedTask,
        outcome: _retryOutcomeFailed(),
        emitLog: false,
      );
    }
    session.transferQueue[index] = session.transferQueue[index].copyWith(
      status: TransferStatus.failed,
      lastError: normalizedError,
    );
    session.transferLastNotifyAt.remove(id);
    if (session.lastTransferId == id) {
      session.lastTransferId = null;
    }
    _incrementBatchDone(session);
    _applyTransferSafetyFallbackIfNeeded(error);
    _scheduleTransferCleanup(session);
    _syncTransferForegroundService();
    if (shouldReportError) {
      setError(
        AppStrings.values.transferFailedVar.resolve(
          locale.languageCode,
          params: {'error': normalizedError},
        ),
      );
    } else {
      notifyState();
    }
  }

  void _startTransferBatch(
    TerminalSession session,
    int total, {
    required String batchId,
  }) {
    session.transferCleanupTimer?.cancel();
    session.currentTransferBatchId = batchId;
    session.transferBatchTotal = total;
    session.transferBatchDone = 0;
    session.transferBatchCreatedAt.putIfAbsent(batchId, DateTime.now);
    session.transferBatchPreparing[batchId] = false;
    session.transferBatchPreparingLabel[batchId] = null;
    session.transferBatchScanningScanned[batchId] = 0;
    session.transferBatchScanningFiles[batchId] = 0;
    _bumpTransferVersion(session);
    notifyState();
  }

  void _incrementBatchDone(TerminalSession session) {
    if (session.transferBatchTotal > 0) {
      session.transferBatchDone = min(
        session.transferBatchDone + 1,
        session.transferBatchTotal,
      );
    } else {
      session.transferBatchDone += 1;
    }
    _scheduleTransferCleanup(session);
    _bumpTransferVersion(session);
    notifyState();
  }

  void _markTransferCanceled(
    TerminalSession session,
    String id, {
    String? reason,
  }) {
    final index = _indexOfTransferTask(session, id);
    if (index == -1) return;
    final cancelledTask = session.transferQueue[index];
    _clearTaskToken(session, id);
    _runTaskCancelCleanup(session, id);
    _clearTaskRunner(session, id);
    _setPendingResumeRequest(session, id, false);
    session.transferRunningTaskIds.remove(id);
    session.pausedTransferTaskIds.remove(id);
    if (session.transferQueue[index].status == TransferStatus.canceled) {
      _clearTransferRetrySummary(session, id);
      return;
    }
    _logTransferCancelled(session, cancelledTask, reason: reason);
    session.transferQueue[index] = session.transferQueue[index].copyWith(
      status: TransferStatus.canceled,
    );
    session.transferLastNotifyAt.remove(id);
    if (session.lastTransferId == id) {
      session.lastTransferId = null;
    }
    _incrementBatchDone(session);
    _scheduleTransferCleanup(session);
    _syncTransferForegroundService();
  }

  void _markTransferPaused(TerminalSession session, String id) {
    final index = _indexOfTransferTask(session, id);
    if (index == -1) {
      return;
    }
    final current = session.transferQueue[index];
    _clearTaskToken(session, id);
    session.transferRunningTaskIds.remove(id);
    session.transferQueue[index] = current.copyWith(
      status: TransferStatus.paused,
      clearLastError: true,
    );
    session.transferLastNotifyAt.remove(id);
    if (session.lastTransferId == id) {
      session.lastTransferId = null;
    }
    _syncTransferForegroundService();
    _bumpTransferVersion(session);
    notifyState();
  }

  void _markTransferRetrying(
    TerminalSession session,
    String id, {
    required int nextAttempt,
    required Duration delay,
    required Object error,
  }) {
    final index = _indexOfTransferTask(session, id);
    if (index == -1) return;
    final current = session.transferQueue[index];
    _logTransferRetrying(session, current, error, delay, nextAttempt);
    session.transferQueue[index] = current.copyWith(
      status: TransferStatus.queued,
      attempt: nextAttempt,
      lastError: _normalizeTransferError(error),
    );
    session.transferLastNotifyAt[id] = DateTime.now();
    _bumpTransferVersion(session);
    notifyState();
  }

  void _scheduleTransferCleanup(TerminalSession session) {
    session.transferCleanupTimer?.cancel();
    session.transferCleanupTimer = Timer(const Duration(milliseconds: 120), () {
      final remaining = session.transferQueue
          .where(
            (task) =>
                task.status == TransferStatus.running ||
                task.status == TransferStatus.queued ||
                task.status == TransferStatus.paused,
          )
          .map((task) => task.id)
          .toSet();
      session.transferLastNotifyAt.removeWhere(
        (key, value) => !remaining.contains(key),
      );
      if (session.lastTransferId != null &&
          !remaining.contains(session.lastTransferId)) {
        session.lastTransferId = null;
      }
      final activeBatchIds = session.transferQueue
          .where(
            (task) =>
                task.status == TransferStatus.running ||
                task.status == TransferStatus.queued ||
                task.status == TransferStatus.paused,
          )
          .map((task) => task.batchId)
          .toSet();
      for (final entry in session.transferBatchPreparing.entries) {
        if (entry.value) {
          activeBatchIds.add(entry.key);
        }
      }
      session.transferQueue.removeWhere(
        (task) =>
            task.status != TransferStatus.running &&
            task.status != TransferStatus.queued &&
            task.status != TransferStatus.paused,
      );
      _reindexTransferTasks(session);

      final allBatchIds = {
        ...session.transferBatchCreatedAt.keys,
        ...session.transferQueue.map((task) => task.batchId),
      };
      final staleBatchIds = allBatchIds.where(
        (id) => !activeBatchIds.contains(id),
      );
      for (final id in staleBatchIds) {
        session.transferBatchCreatedAt.remove(id);
        session.transferBatchPreparing.remove(id);
        session.transferBatchPreparingLabel.remove(id);
        session.transferBatchScanningScanned.remove(id);
        session.transferBatchScanningFiles.remove(id);
      }

      final remainingIds = session.transferQueue.map((task) => task.id).toSet();
      session.canceledTransferIds.removeWhere(
        (taskId) => !remainingIds.contains(taskId),
      );
      session.pausedTransferTaskIds.removeWhere(
        (taskId) => !remainingIds.contains(taskId),
      );
      if (session.transferQueue.isEmpty) {
        session.transferBatchDone = 0;
        session.transferBatchTotal = 0;
        session.currentTransferBatchId = null;
        session.transferPreparing = false;
        session.transferPreparingLabel = null;
        session.transferScanningScanned = 0;
        session.transferScanningFiles = 0;
      }
      _bumpTransferVersion(session);
      _syncTransferForegroundService();
      notifyState();
    });
  }

  TransferDirectionSummary _directionSummary(
    TerminalSession session,
    TransferDirection direction,
  ) {
    final tasks = session.transferQueue
        .where(
          (task) =>
              task.direction == direction &&
              (task.status == TransferStatus.running ||
                  task.status == TransferStatus.queued ||
                  task.status == TransferStatus.paused),
        )
        .toList(growable: false);
    if (tasks.isEmpty) {
      return const TransferDirectionSummary(total: 0, done: 0, progress: 0);
    }
    const done = 0;
    final progress =
        tasks.fold<double>(
          0,
          (sum, task) => sum + task.progress.clamp(0.0, 1.0),
        ) /
        tasks.length;
    return TransferDirectionSummary(
      total: tasks.length,
      done: done,
      progress: progress.clamp(0.0, 1.0),
    );
  }

  SessionTransferSummary transferSummaryForSession(TerminalSession session) {
    final runtimeSet = _runtimeMaybeFor(session);
    final runningUploadJobs = runtimeSet?.uploadRuntime.runningJobs ?? 0;
    final runningDownloadJobs = runtimeSet?.downloadRuntime.runningJobs ?? 0;
    final runningTotalJobs = runningUploadJobs + runningDownloadJobs;
    final nativePoolStats = NativeTransferBridge.instance
        .poolStatsForSessionConfig(_nativeSessionConfigForSession(session));
    final activeTasks = session.transferQueue
        .where((task) {
          return task.status == TransferStatus.running ||
              task.status == TransferStatus.queued ||
              task.status == TransferStatus.paused;
        })
        .toList(growable: false);
    final tasksByBatch = <String, List<TransferTask>>{};
    for (final task in activeTasks) {
      tasksByBatch.putIfAbsent(task.batchId, () => []).add(task);
    }

    final preparingOnlyBatchIds = session.transferBatchPreparing.entries
        .where((entry) => entry.value && !tasksByBatch.containsKey(entry.key))
        .map((entry) => entry.key)
        .toList(growable: false);

    final queueSummaries =
        tasksByBatch.entries
            .map((entry) {
              final batchId = entry.key;
              final tasks = entry.value;
              final first = tasks.first;
              const done = 0;
              final progress =
                  tasks.fold<double>(
                    0,
                    (sum, task) => sum + task.progress.clamp(0.0, 1.0),
                  ) /
                  max(1, tasks.length);
              final canCancel = tasks.any(
                (task) =>
                    task.status == TransferStatus.running ||
                    task.status == TransferStatus.queued ||
                    task.status == TransferStatus.paused,
              );
              final hasRunningOrQueued = tasks.any(
                (task) =>
                    task.status == TransferStatus.running ||
                    task.status == TransferStatus.queued,
              );
              final batchPaused =
                  !hasRunningOrQueued &&
                  tasks.any((task) => task.status == TransferStatus.paused);
              return TransferQueueSummary(
                id: batchId,
                name: _queueNameForTasks(tasks, direction: first.direction),
                direction: first.direction,
                paused:
                    isTransferDirectionPaused(session, first.direction) ||
                    batchPaused,
                total: tasks.length,
                done: done,
                progress: progress.clamp(0.0, 1.0),
                preparing: session.transferBatchPreparing[batchId] ?? false,
                preparingLabel: session.transferBatchPreparingLabel[batchId],
                canCancel: canCancel,
                createdAt:
                    session.transferBatchCreatedAt[batchId] ??
                    DateTime.fromMillisecondsSinceEpoch(0),
                etaSeconds: _estimateQueueEtaSeconds(
                  createdAt:
                      session.transferBatchCreatedAt[batchId] ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                  progress: progress.clamp(0.0, 1.0),
                  preparing: session.transferBatchPreparing[batchId] ?? false,
                  canCancel: canCancel,
                  paused:
                      isTransferDirectionPaused(session, first.direction) ||
                      batchPaused,
                ),
              );
            })
            .toList(growable: true)
          ..addAll(
            preparingOnlyBatchIds.map(
              (batchId) => TransferQueueSummary(
                id: batchId,
                name: _queueNameForPreparingBatch(
                  session,
                  batchId,
                  direction: _directionForBatchId(
                    batchId,
                    tasks: session.transferQueue,
                  ),
                ),
                direction: _directionForBatchId(
                  batchId,
                  tasks: session.transferQueue,
                ),
                paused: isTransferDirectionPaused(
                  session,
                  _directionForBatchId(batchId, tasks: session.transferQueue),
                ),
                total: session.transferBatchScanningFiles[batchId] ?? 0,
                done: 0,
                progress: 0,
                preparing: true,
                preparingLabel: session.transferBatchPreparingLabel[batchId],
                canCancel: true,
                createdAt:
                    session.transferBatchCreatedAt[batchId] ??
                    DateTime.fromMillisecondsSinceEpoch(0),
                etaSeconds: null,
              ),
            ),
          )
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final uploadQueues = queueSummaries
        .where((queue) => queue.direction == TransferDirection.upload)
        .toList(growable: false);
    final downloadQueues = queueSummaries
        .where((queue) => queue.direction == TransferDirection.download)
        .toList(growable: false);

    final summary = SessionTransferSummary(
      preparing: session.transferPreparing,
      preparingLabel: session.transferPreparingLabel,
      scanningScanned: session.transferScanningScanned,
      scanningFiles: session.transferScanningFiles,
      uploadQueues: uploadQueues,
      downloadQueues: downloadQueues,
      upload: _directionSummary(session, TransferDirection.upload),
      download: _directionSummary(session, TransferDirection.download),
      runningUploadJobs: runningUploadJobs,
      runningDownloadJobs: runningDownloadJobs,
      runningTotalJobs: runningTotalJobs,
      nativeBusySessions: nativePoolStats.busySessions,
      nativeTotalSessions: nativePoolStats.totalSessions,
    );
    session.transferSummary = summary;
    return summary;
  }

  int? _estimateQueueEtaSeconds({
    required DateTime createdAt,
    required double progress,
    required bool preparing,
    required bool canCancel,
    required bool paused,
  }) {
    if (preparing || !canCancel || paused) {
      return null;
    }
    if (createdAt.millisecondsSinceEpoch <= 0) {
      return null;
    }
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.01 || p >= 0.999) {
      return null;
    }
    final elapsed = DateTime.now().difference(createdAt).inSeconds;
    if (elapsed < 3) {
      return null;
    }
    final remaining = (elapsed * (1 - p) / p).round();
    if (remaining < 0 || remaining > 7 * 24 * 60 * 60) {
      return null;
    }
    return remaining;
  }

  void _bumpTransferVersion(TerminalSession session) {
    session.transferVersion += 1;
  }

  bool hasOngoingTransfers(TerminalSession session, {String? batchId}) {
    if (batchId == null) {
      final runtimeSet = _runtimeMaybeFor(session);
      if (runtimeSet != null &&
          (runtimeSet.uploadRuntime.hasWorkInFlight ||
              runtimeSet.downloadRuntime.hasWorkInFlight)) {
        return true;
      }
    }
    return session.transferQueue.any(
      (task) =>
          (batchId == null || task.batchId == batchId) &&
          (task.status == TransferStatus.running ||
              task.status == TransferStatus.queued),
    );
  }

  void cancelTransfers(TerminalSession session) {
    session.transferCancelRequested = true;
    _cancelAllTaskTokens(session);
    _runAllTaskCancelCleanups(session);
    final cancelReason = AppStrings.values.transferCancelReasonUser.resolve(
      locale.languageCode,
    );
    for (final task in session.transferQueue) {
      if (task.status == TransferStatus.running ||
          task.status == TransferStatus.queued ||
          task.status == TransferStatus.paused) {
        _logTransferCancelled(session, task, reason: cancelReason);
      }
    }
    final runtimeSet = _runtimeMaybeFor(session);
    runtimeSet?.uploadRuntime.cancelQueued();
    runtimeSet?.downloadRuntime.cancelQueued();
    session.transferQueue.clear();
    session.transferTaskIndex.clear();
    session.transferBatchCreatedAt.clear();
    session.transferBatchPreparing.clear();
    session.transferBatchPreparingLabel.clear();
    session.transferBatchScanningScanned.clear();
    session.transferBatchScanningFiles.clear();
    session.currentTransferBatchId = null;
    session.transferBatchDone = 0;
    session.transferBatchTotal = 0;
    session.transferPreparing = false;
    session.transferPreparingLabel = null;
    session.transferScanningScanned = 0;
    session.transferScanningFiles = 0;
    session.pausedTransferDirections.clear();
    session.transferLastNotifyAt.clear();
    session.lastTransferId = null;
    session.activeTransfers = 0;
    session.transferRunningTaskIds.clear();
    session.transferCleanupTimer?.cancel();
    session.canceledTransferIds.clear();
    session.pausedTransferTaskIds.clear();
    _clearAllPendingResumeRequests(session);
    _clearAllTaskTokens(session);
    _clearAllTaskRunners(session);
    _clearAllTransferStartLogged(session);
    _clearAllTransferRetrySummaries(session);
    _syncTransferForegroundService();
    _bumpTransferVersion(session);
    notifyState();
    Timer(const Duration(seconds: 1), () {
      if (!sessions.contains(session)) return;
      session.transferCancelRequested = false;
    });
  }

  void cleanupTransfersForSession(TerminalSession session) {
    session.transferCancelRequested = true;
    _cancelAllTaskTokens(session);
    _runAllTaskCancelCleanups(session);
    final cancelReason = AppStrings.values.transferCancelReasonSessionClosed
        .resolve(locale.languageCode);
    final runtimeSet = _runtimeMaybeFor(session);
    final pending = <_QueuedTransferJob>[
      ...?runtimeSet?.uploadRuntime.cancelQueued(),
      ...?runtimeSet?.downloadRuntime.cancelQueued(),
    ];
    for (final job in pending) {
      _markTransferCanceled(session, job.task.id, reason: cancelReason);
    }
    for (var i = 0; i < session.transferQueue.length; i++) {
      final task = session.transferQueue[i];
      if (task.status == TransferStatus.running ||
          task.status == TransferStatus.queued ||
          task.status == TransferStatus.paused) {
        _logTransferCancelled(session, task, reason: cancelReason);
        session.transferQueue[i] = task.copyWith(
          status: TransferStatus.canceled,
        );
      }
    }
    _reindexTransferTasks(session);
    session.transferLastNotifyAt.clear();
    session.lastTransferId = null;
    session.transferRunningTaskIds.clear();
    session.canceledTransferIds.clear();
    session.pausedTransferTaskIds.clear();
    _clearAllPendingResumeRequests(session);
    session.transferTaskIndex.clear();
    session.transferBatchCreatedAt.clear();
    session.transferBatchPreparing.clear();
    session.transferBatchPreparingLabel.clear();
    session.transferBatchScanningScanned.clear();
    session.transferBatchScanningFiles.clear();
    session.currentTransferBatchId = null;
    session.transferBatchDone = 0;
    session.transferBatchTotal = 0;
    session.transferPreparing = false;
    session.transferPreparingLabel = null;
    session.transferScanningScanned = 0;
    session.transferScanningFiles = 0;
    session.pausedTransferDirections.clear();
    _clearAllTaskTokens(session);
    _clearAllTaskRunners(session);
    _clearAllTransferStartLogged(session);
    _clearAllTransferRetrySummaries(session);
    _disposeRuntimeFor(session);
    _syncTransferForegroundService();
    _bumpTransferVersion(session);
    notifyState();
  }

  TransferDirection _directionForBatchId(
    String batchId, {
    required List<TransferTask> tasks,
  }) {
    for (final task in tasks) {
      if (task.batchId == batchId) {
        return task.direction;
      }
    }
    if (batchId.contains('batch-up')) {
      return TransferDirection.upload;
    }
    return TransferDirection.download;
  }

  String _queueNameForTasks(
    List<TransferTask> tasks, {
    required TransferDirection direction,
  }) {
    final names = tasks
        .map((task) => task.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) {
      return _defaultQueueName(direction);
    }
    final first = names.first;
    final extra = names.length - 1;
    if (extra <= 0) {
      return first;
    }
    if (locale.languageCode == 'en') {
      return '$first (+$extra)';
    }
    return '$first（+$extra）';
  }

  String _queueNameForPreparingBatch(
    TerminalSession session,
    String batchId, {
    required TransferDirection direction,
  }) {
    final label = (session.transferBatchPreparingLabel[batchId] ?? '').trim();
    if (label.isNotEmpty) {
      return label;
    }
    return _defaultQueueName(direction);
  }

  String _defaultQueueName(TransferDirection direction) {
    return (direction == TransferDirection.upload
            ? AppStrings.values.uploads
            : AppStrings.values.downloads)
        .resolve(locale.languageCode);
  }

  TransferTask? _findTransferTask(TerminalSession session, String id) {
    final index = _indexOfTransferTask(session, id);
    if (index == -1) return null;
    return session.transferQueue[index];
  }

  int _indexOfTransferTask(TerminalSession session, String id) {
    final cached = session.transferTaskIndex[id];
    if (cached != null &&
        cached >= 0 &&
        cached < session.transferQueue.length &&
        session.transferQueue[cached].id == id) {
      return cached;
    }
    final index = session.transferQueue.indexWhere((t) => t.id == id);
    if (index != -1) {
      session.transferTaskIndex[id] = index;
    }
    return index;
  }

  void _reindexTransferTasks(TerminalSession session) {
    session.transferTaskIndex
      ..clear()
      ..addEntries(
        session.transferQueue.asMap().entries.map(
          (entry) => MapEntry(entry.value.id, entry.key),
        ),
      );
  }

  void _ensureNotCancelled(TerminalSession session, String taskId) {
    if (session.transferCancelRequested ||
        session.canceledTransferIds.contains(taskId)) {
      throw const TransferCancelledException();
    }
  }

  void _markCancelledIfNeeded(TerminalSession session, String taskId) {
    if (session.transferCancelRequested ||
        session.canceledTransferIds.contains(taskId)) {
      _markTransferCanceled(session, taskId);
    }
  }

  int _effectiveQueueParallelJobs(
    TerminalSession session,
    TransferDirection direction,
  ) {
    final profile = _effectiveAdaptiveProfile();
    final runtimeSet = _runtimeSetFor(session);
    final uploadRunning = runtimeSet.uploadRuntime.runningJobs;
    final downloadRunning = runtimeSet.downloadRuntime.runningJobs;
    final otherDirectionRunning = direction == TransferDirection.upload
        ? downloadRunning
        : uploadRunning;
    final thisDirectionRunning = direction == TransferDirection.upload
        ? uploadRunning
        : downloadRunning;
    final totalCap = profile.queueParallelJobs
        .clamp(1, _transferSafetyQueueHardCap)
        .toInt();
    final availableForThisDirection = max(
      1,
      min(totalCap, totalCap - otherDirectionRunning + thisDirectionRunning),
    );
    return availableForThisDirection;
  }

  TransferRuntimeOptions _effectiveTransferRuntimeOptions() {
    final profile = _effectiveAdaptiveProfile();
    final nativeConcurrency = profile.nativeConcurrency
        .clamp(1, _transferSafetyNativeHardCap)
        .toInt();
    final chunkKb = profile.chunkSizeKb.clamp(64, 1024).toInt();
    final retryEnabled = transferAutoRetryEnabled;
    return TransferRuntimeOptions(
      nativeMaxConcurrency: nativeConcurrency,
      defaultChunkSizeBytes: chunkKb * 1024,
      enableResume: transferResumeEnabled,
      retryMaxAttempts: retryEnabled
          ? transferRetryMaxAttempts.clamp(1, 12).toInt()
          : 1,
      retryBaseBackoffMs: transferRetryBaseDelayMs.clamp(100, 120000).toInt(),
      retryMaxBackoffMs: transferRetryMaxDelayMs.clamp(100, 300000).toInt(),
    );
  }

  NativeTransferSessionConfig _nativeSessionConfigForSession(
    TerminalSession session,
  ) {
    final options = _effectiveTransferRuntimeOptions();
    return NativeTransferSessionConfig(
      host: session.profile.host,
      port: session.profile.port,
      username: session.profile.username,
      password: session.profile.authType == AuthType.password
          ? session.profile.password
          : null,
      privateKeyPath: session.profile.authType == AuthType.key
          ? session.profile.privateKeyPath
          : null,
      privateKeyPassphrase: session.profile.authType == AuthType.key
          ? (session.profile.privateKeyPassphrase ?? session.profile.password)
          : null,
      connectTimeoutMs:
          session.profile.connectTimeoutSeconds.clamp(3, 120) * 1000,
      maxConcurrency: options.nativeMaxConcurrency,
      defaultChunkSize: options.defaultChunkSizeBytes,
      enableResume: options.enableResume,
      retryMaxAttempts: options.retryMaxAttempts,
      retryBaseBackoffMs: options.retryBaseBackoffMs,
      retryMaxBackoffMs: options.retryMaxBackoffMs,
    );
  }
}

class _TransferRetrySummary {
  const _TransferRetrySummary({
    required this.count,
    required this.lastAttempt,
    required this.maxAttempts,
    required this.lastDelayMs,
    required this.lastReason,
  });

  final int count;
  final int lastAttempt;
  final int maxAttempts;
  final int lastDelayMs;
  final String lastReason;
}
