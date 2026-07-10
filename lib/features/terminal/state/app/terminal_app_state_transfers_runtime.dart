part of 'terminal_app_state_transfers.dart';

class _SessionTransferRuntimeSet {
  _SessionTransferRuntimeSet({
    required this.uploadRuntime,
    required this.downloadRuntime,
  });

  final _SessionTransferRuntime uploadRuntime;
  final _SessionTransferRuntime downloadRuntime;
}

class _TransferAdaptiveState {
  int consecutiveTransportFailures = 0;
  DateTime lastFailureAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime conservativeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime profileLockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  _AdaptiveTransferProfile? activeProfile;
}

class _AdaptiveTransferProfile {
  const _AdaptiveTransferProfile({
    required this.name,
    required this.queueParallelJobs,
    required this.nativeConcurrency,
    required this.chunkSizeKb,
  });

  final String name;
  final int queueParallelJobs;
  final int nativeConcurrency;
  final int chunkSizeKb;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _AdaptiveTransferProfile &&
        other.name == name &&
        other.queueParallelJobs == queueParallelJobs &&
        other.nativeConcurrency == nativeConcurrency &&
        other.chunkSizeKb == chunkSizeKb;
  }

  @override
  int get hashCode =>
      Object.hash(name, queueParallelJobs, nativeConcurrency, chunkSizeKb);
}

class _TransferPressure {
  const _TransferPressure({
    required this.runningJobs,
    required this.queuedJobs,
  });

  final int runningJobs;
  final int queuedJobs;
}

class _TransferForegroundServiceState {
  bool targetActive = false;
  bool appliedActive = false;
  _TransferForegroundProgress targetProgress =
      const _TransferForegroundProgress(
        title: '',
        progressPercent: 0,
        progressPermille: 0,
        indeterminate: true,
        activeCount: 0,
      );
  String? appliedProgressSignature;
  bool syncing = false;
  bool needsResync = false;
}

class _TransferForegroundProgress {
  const _TransferForegroundProgress({
    required this.title,
    required this.progressPercent,
    required this.progressPermille,
    required this.indeterminate,
    required this.activeCount,
  });

  final String title;
  final int progressPercent;
  final int progressPermille;
  final bool indeterminate;
  final int activeCount;

  String get signature =>
      '$title|$progressPercent|$progressPermille|$indeterminate|$activeCount';
}

class _QueuedTransferJob {
  _QueuedTransferJob({
    required this.task,
    required this.execute,
    required this.completer,
    required this.priority,
  });

  final TransferTask task;
  final Future<void> Function() execute;
  final Completer<void> completer;
  final bool priority;
}

class _StoredTransferTaskRunner {
  _StoredTransferTaskRunner({
    required this.taskTemplate,
    required this.execute,
    required this.priority,
  });

  final TransferTask taskTemplate;
  final Future<void> Function() execute;
  final bool priority;
}

class _SessionTransferRuntime {
  _SessionTransferRuntime();

  final ListQueue<_QueuedTransferJob> _priorityQueue = ListQueue();
  final ListQueue<_QueuedTransferJob> _queue = ListQueue();

  bool _dispatching = false;
  int _runningJobs = 0;

  int get runningJobs => _runningJobs;
  bool get hasPendingJobs => _priorityQueue.isNotEmpty || _queue.isNotEmpty;
  bool get hasWorkInFlight => hasPendingJobs || _runningJobs > 0;

  void enqueue(_QueuedTransferJob job) {
    if (job.priority) {
      _priorityQueue.add(job);
      return;
    }
    _queue.add(job);
  }

  bool removeQueuedWhere(bool Function(_QueuedTransferJob job) predicate) {
    var removed = false;
    removed = _removeFromQueue(_priorityQueue, predicate) || removed;
    removed = _removeFromQueue(_queue, predicate) || removed;
    return removed;
  }

  List<_QueuedTransferJob>? cancelQueued() {
    if (!hasPendingJobs) return null;
    final canceled = <_QueuedTransferJob>[..._priorityQueue, ..._queue];
    _priorityQueue.clear();
    _queue.clear();
    return canceled;
  }

  void processQueue({
    required int Function() maxParallelJobs,
    required bool Function() shouldStop,
    required bool Function(String taskId) isTaskCanceled,
    required void Function(String taskId) onTaskStart,
    required void Function(String taskId) onTaskCanceled,
    required int Function(String taskId) maxRetryAttempts,
    required Duration Function(String taskId, int nextAttempt, Object error)
    retryDelay,
    required void Function(
      String taskId,
      int nextAttempt,
      Duration delay,
      Object error,
    )
    onTaskRetrying,
    required void Function(String taskId) onTaskSucceeded,
    required void Function(String taskId, Object error) onTaskFailed,
    required void Function() onStateChanged,
  }) {
    if (_dispatching || shouldStop()) return;
    _dispatching = true;
    try {
      while (!shouldStop() &&
          _runningJobs < max(1, maxParallelJobs()) &&
          hasPendingJobs) {
        final job = _dequeue();
        if (job == null) break;
        _runningJobs += 1;
        onTaskStart(job.task.id);
        unawaited(
          _runQueuedJob(
            job,
            maxParallelJobs: maxParallelJobs,
            shouldStop: shouldStop,
            isTaskCanceled: isTaskCanceled,
            onTaskStart: onTaskStart,
            onTaskCanceled: onTaskCanceled,
            maxRetryAttempts: maxRetryAttempts,
            retryDelay: retryDelay,
            onTaskRetrying: onTaskRetrying,
            onTaskSucceeded: onTaskSucceeded,
            onTaskFailed: onTaskFailed,
            onStateChanged: onStateChanged,
          ),
        );
      }
    } finally {
      _dispatching = false;
    }
  }

  Future<void> _runQueuedJob(
    _QueuedTransferJob job, {
    required int Function() maxParallelJobs,
    required bool Function() shouldStop,
    required bool Function(String taskId) isTaskCanceled,
    required void Function(String taskId) onTaskStart,
    required void Function(String taskId) onTaskCanceled,
    required int Function(String taskId) maxRetryAttempts,
    required Duration Function(String taskId, int nextAttempt, Object error)
    retryDelay,
    required void Function(
      String taskId,
      int nextAttempt,
      Duration delay,
      Object error,
    )
    onTaskRetrying,
    required void Function(String taskId) onTaskSucceeded,
    required void Function(String taskId, Object error) onTaskFailed,
    required void Function() onStateChanged,
  }) async {
    try {
      if (shouldStop() || isTaskCanceled(job.task.id)) {
        onTaskCanceled(job.task.id);
        if (!job.completer.isCompleted) {
          job.completer.complete();
        }
        return;
      }
      var attempt = 1;
      final maxAttempts = max(1, maxRetryAttempts(job.task.id));
      while (true) {
        try {
          await job.execute();
          break;
        } catch (error) {
          if (error is TransferCancelledException) {
            rethrow;
          }
          if (shouldStop() || isTaskCanceled(job.task.id)) {
            rethrow;
          }
          if (attempt >= maxAttempts) {
            rethrow;
          }
          final nextAttempt = attempt + 1;
          final delay = retryDelay(job.task.id, nextAttempt, error);
          onTaskRetrying(job.task.id, nextAttempt, delay, error);
          await Future<void>.delayed(delay);
          if (shouldStop() || isTaskCanceled(job.task.id)) {
            throw const TransferCancelledException();
          }
          attempt = nextAttempt;
        }
      }
      onTaskSucceeded(job.task.id);
      if (!job.completer.isCompleted) {
        job.completer.complete();
      }
    } catch (error) {
      if (error is TransferCancelledException) {
        onTaskCanceled(job.task.id);
        if (!job.completer.isCompleted) {
          job.completer.complete();
        }
      } else {
        onTaskFailed(job.task.id, error);
        if (!job.completer.isCompleted) {
          job.completer.completeError(error);
        }
      }
    } finally {
      _runningJobs = max(0, _runningJobs - 1);
      onStateChanged();
      processQueue(
        maxParallelJobs: maxParallelJobs,
        shouldStop: shouldStop,
        isTaskCanceled: isTaskCanceled,
        onTaskStart: onTaskStart,
        onTaskCanceled: onTaskCanceled,
        maxRetryAttempts: maxRetryAttempts,
        retryDelay: retryDelay,
        onTaskRetrying: onTaskRetrying,
        onTaskSucceeded: onTaskSucceeded,
        onTaskFailed: onTaskFailed,
        onStateChanged: onStateChanged,
      );
    }
  }

  _QueuedTransferJob? _dequeue() {
    if (_priorityQueue.isNotEmpty) {
      return _priorityQueue.removeFirst();
    }
    if (_queue.isNotEmpty) {
      return _queue.removeFirst();
    }
    return null;
  }

  bool _removeFromQueue(
    ListQueue<_QueuedTransferJob> queue,
    bool Function(_QueuedTransferJob job) predicate,
  ) {
    if (queue.isEmpty) return false;
    final retained = <_QueuedTransferJob>[];
    var removed = false;
    while (queue.isNotEmpty) {
      final job = queue.removeFirst();
      if (predicate(job)) {
        removed = true;
      } else {
        retained.add(job);
      }
    }
    queue.addAll(retained);
    return removed;
  }
}
