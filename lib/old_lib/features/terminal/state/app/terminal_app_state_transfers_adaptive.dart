part of 'terminal_app_state_transfers.dart';

extension TerminalAppStateTransfersAdaptive on TerminalAppState {
  _TransferAdaptiveState _transferAdaptiveState() {
    return _transferAdaptiveByState[this] ??= _TransferAdaptiveState();
  }

  void _recordTransferSuccessForSafety() {
    final state = _transferAdaptiveState();
    state.consecutiveTransportFailures = 0;
    state.lastFailureAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _applyTransferSafetyFallbackIfNeeded(Object error) {
    final normalized = _normalizeTransferError(error).toLowerCase();
    if (!_isAggressiveConfigRelatedFailure(normalized)) {
      return;
    }
    final state = _transferAdaptiveState();
    final now = DateTime.now();
    if (now.difference(state.lastFailureAt) > _transferSafetyFailureWindow) {
      state.consecutiveTransportFailures = 0;
    }
    state.lastFailureAt = now;
    state.consecutiveTransportFailures += 1;
    if (state.consecutiveTransportFailures < _transferSafetyFailureThreshold) {
      return;
    }
    state.consecutiveTransportFailures = 0;
    final fallback = _conservativeAdaptiveProfile();
    state.conservativeUntil = now.add(_transferSafetyFallbackDuration);
    state.activeProfile = fallback;
    state.profileLockedUntil = state.conservativeUntil;
    refreshTransferSchedulers();
    notifyState();
  }

  _AdaptiveTransferProfile _effectiveAdaptiveProfile() {
    final state = _transferAdaptiveState();
    final now = DateTime.now();
    final previous = state.activeProfile;
    _AdaptiveTransferProfile selected;
    if (now.isBefore(state.conservativeUntil)) {
      selected = _conservativeAdaptiveProfile();
    } else if (previous != null && now.isBefore(state.profileLockedUntil)) {
      selected = previous;
    } else {
      selected = _profileForPressure(_collectTransferPressure());
      state.profileLockedUntil = now.add(_transferAdaptiveProfileHold);
    }

    if (previous != selected) {
      state.activeProfile = selected;
    }
    return selected;
  }

  _TransferPressure _collectTransferPressure() {
    var runningJobs = 0;
    var queuedJobs = 0;
    for (final session in sessions) {
      final runtimeSet = _runtimeMaybeFor(session);
      if (runtimeSet != null) {
        runningJobs += runtimeSet.uploadRuntime.runningJobs;
        runningJobs += runtimeSet.downloadRuntime.runningJobs;
      }
      queuedJobs += session.transferQueue.where((task) {
        return task.status == TransferStatus.queued;
      }).length;
    }
    return _TransferPressure(runningJobs: runningJobs, queuedJobs: queuedJobs);
  }

  _AdaptiveTransferProfile _profileForPressure(_TransferPressure pressure) {
    final score = (pressure.runningJobs * 2) + min(pressure.queuedJobs, 8);
    if (_isMobilePlatform()) {
      if (score >= 8) {
        return _mobileProfileThroughput;
      }
      return _mobileProfileBalanced;
    }
    if (score >= 14) {
      return _desktopProfileHighThroughput;
    }
    if (score >= 6) {
      return _desktopProfileThroughput;
    }
    return _desktopProfileBalanced;
  }

  _AdaptiveTransferProfile _conservativeAdaptiveProfile() {
    return const _AdaptiveTransferProfile(
      name: 'conservative',
      queueParallelJobs: _transferSafetyFallbackQueueParallel,
      nativeConcurrency: _transferSafetyFallbackNativeConcurrency,
      chunkSizeKb: _transferSafetyFallbackChunkSizeKb,
    );
  }

  bool _isMobilePlatform() {
    return Platform.isAndroid || Platform.isIOS;
  }

  bool _isAggressiveConfigRelatedFailure(String message) {
    const hints = <String>[
      'timeout',
      'timed out',
      'connection reset',
      'broken pipe',
      'unexpected eof',
      'channel eof',
      'resource temporarily unavailable',
      'too many open files',
      'ssh error: [session',
      'ssh error: [channel',
      'connection aborted',
      'network is unreachable',
      '超时',
      '连接重置',
      '连接中断',
      '资源暂时不可用',
    ];
    for (final hint in hints) {
      if (message.contains(hint)) {
        return true;
      }
    }
    return false;
  }

  void cancelTransferQueue(TerminalSession session, String batchId) {
    final batchTasks = session.transferQueue
        .where((task) => task.batchId == batchId)
        .toList(growable: false);
    final activeTasks = batchTasks
        .where(
          (task) =>
              task.status == TransferStatus.running ||
              task.status == TransferStatus.queued ||
              task.status == TransferStatus.paused,
        )
        .toList(growable: false);
    if (activeTasks.isEmpty) {
      final isPreparing = session.transferBatchPreparing[batchId] ?? false;
      if (isPreparing) {
        session.transferBatchPreparing[batchId] = false;
        session.transferBatchPreparingLabel[batchId] = null;
        session.transferBatchScanningScanned[batchId] = 0;
        session.transferBatchScanningFiles[batchId] = 0;
        if (session.currentTransferBatchId == batchId) {
          session.currentTransferBatchId = null;
          session.transferPreparing = false;
          session.transferPreparingLabel = null;
          session.transferScanningScanned = 0;
          session.transferScanningFiles = 0;
        }
        _scheduleTransferCleanup(session);
        _bumpTransferVersion(session);
        notifyState();
      }
      return;
    }

    final cancelIds = activeTasks.map((task) => task.id).toSet();
    session.canceledTransferIds.addAll(cancelIds);
    for (final taskId in cancelIds) {
      _cancelTaskToken(session, taskId);
    }
    session.transferRunningTaskIds.removeWhere((id) => cancelIds.contains(id));

    final cancelIdsByDirection = <TransferDirection, Set<String>>{
      TransferDirection.upload: <String>{},
      TransferDirection.download: <String>{},
    };
    for (final task in activeTasks) {
      cancelIdsByDirection[task.direction]!.add(task.id);
    }
    for (final entry in cancelIdsByDirection.entries) {
      final ids = entry.value;
      if (ids.isEmpty) continue;
      _runtimeFor(session, entry.key).removeQueuedWhere((job) {
        if (!ids.contains(job.task.id)) return false;
        if (!job.completer.isCompleted) {
          job.completer.complete();
        }
        return true;
      });
    }

    for (final taskId in cancelIds) {
      _setPendingResumeRequest(session, taskId, false);
      _markTransferCanceled(
        session,
        taskId,
        reason: AppStrings.values.transferCancelReasonQueue.resolve(
          locale.languageCode,
        ),
      );
    }
    session.transferBatchPreparing[batchId] = false;
    session.transferBatchPreparingLabel[batchId] = null;
    session.transferBatchScanningScanned[batchId] = 0;
    session.transferBatchScanningFiles[batchId] = 0;
    if (session.currentTransferBatchId == batchId) {
      session.currentTransferBatchId = null;
      session.transferPreparing = false;
      session.transferPreparingLabel = null;
      session.transferScanningScanned = 0;
      session.transferScanningFiles = 0;
    }
    _processTransferQueue(session);
    _syncTransferForegroundService();
    notifyState();
  }

  void cancelTransfer(TerminalSession session, String taskId) {
    final index = _indexOfTransferTask(session, taskId);
    if (index == -1) return;
    final direction = session.transferQueue[index].direction;
    final status = session.transferQueue[index].status;
    if (status == TransferStatus.completed ||
        status == TransferStatus.failed ||
        status == TransferStatus.canceled) {
      return;
    }
    _setPendingResumeRequest(session, taskId, false);
    session.canceledTransferIds.add(taskId);
    _cancelTaskToken(session, taskId);
    session.transferRunningTaskIds.remove(taskId);
    _runtimeFor(session, direction).removeQueuedWhere((job) {
      if (job.task.id == taskId) {
        if (!job.completer.isCompleted) {
          job.completer.complete();
        }
        return true;
      }
      return false;
    });
    _markTransferCanceled(
      session,
      taskId,
      reason: AppStrings.values.transferCancelReasonUser.resolve(
        locale.languageCode,
      ),
    );
    _processTransferQueue(session, direction: direction);
    _syncTransferForegroundService();
    notifyState();
  }

  _TransferForegroundServiceState _transferForegroundState() {
    return _transferForegroundServiceByState[this] ??=
        _TransferForegroundServiceState();
  }

  bool _hasAnyTransferWorkGlobally() {
    for (final session in sessions) {
      if (hasOngoingTransfers(session)) {
        return true;
      }
    }
    return false;
  }

  _TransferForegroundProgress _buildTransferForegroundProgress() {
    final activeTasks = <TransferTask>[];
    var hasPreparing = false;
    for (final session in sessions) {
      if (session.transferPreparing) {
        hasPreparing = true;
      }
      for (final task in session.transferQueue) {
        if (task.status == TransferStatus.running ||
            task.status == TransferStatus.queued) {
          activeTasks.add(task);
        }
      }
    }

    if (activeTasks.isEmpty) {
      return _TransferForegroundProgress(
        title: AppStrings.values.transferForegroundTitle.resolve(
          locale.languageCode,
        ),
        progressPercent: 0,
        progressPermille: 0,
        indeterminate: true,
        activeCount: 0,
      );
    }

    final progress =
        activeTasks.fold<double>(
          0,
          (sum, task) => sum + task.progress.clamp(0.0, 1.0),
        ) /
        max(1, activeTasks.length);
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final progressPercent = (normalizedProgress * 100).round();
    final progressPermille = (normalizedProgress * 1000).round();
    final activeCount = activeTasks.length;
    final percentLabel = _formatTransferPercentFromPermille(progressPermille);
    final title = AppStrings.values.transferForegroundTitleWithPercentVar
        .resolve(locale.languageCode, params: {'percent': percentLabel});
    return _TransferForegroundProgress(
      title: title,
      progressPercent: progressPercent,
      progressPermille: progressPermille,
      indeterminate: hasPreparing && progressPercent <= 0,
      activeCount: activeCount,
    );
  }

  String _formatTransferPercentFromPermille(int permille) {
    final bounded = permille.clamp(0, 1000).toInt();
    final integerPart = bounded ~/ 10;
    final decimalPart = bounded % 10;
    if (decimalPart == 0) {
      return '$integerPart';
    }
    return '$integerPart.$decimalPart';
  }

  void _syncTransferForegroundService() {
    if (!Platform.isAndroid) return;
    final state = _transferForegroundState();
    state.targetActive = _hasAnyTransferWorkGlobally();
    state.targetProgress = _buildTransferForegroundProgress();
    if (state.syncing) {
      state.needsResync = true;
      return;
    }

    state.syncing = true;
    unawaited(() async {
      try {
        do {
          state.needsResync = false;
          final target = state.targetActive;
          try {
            if (target != state.appliedActive) {
              if (target) {
                await AndroidTransferForegroundBridge.start(
                  title: AppStrings.values.transferForegroundTitle.resolve(
                    locale.languageCode,
                  ),
                );
              } else {
                await AndroidTransferForegroundBridge.stop();
                state.appliedProgressSignature = null;
              }
              state.appliedActive = target;
            }

            if (target) {
              final progress = state.targetProgress;
              final signature = progress.signature;
              if (signature != state.appliedProgressSignature) {
                await AndroidTransferForegroundBridge.updateProgress(
                  title: progress.title,
                  progressPermille: progress.progressPermille,
                  indeterminate: progress.indeterminate,
                  activeCount: progress.activeCount,
                );
                state.appliedProgressSignature = signature;
              }
            }
          } catch (error) {
            addStructuredLog(
              category: TerminalLogCategory.transfer,
              level: TerminalLogLevel.error,
              message: AppStrings.values.transferForegroundGuardFailedVar
                  .resolve(locale.languageCode, params: {'error': '$error'}),
              notifyListeners: false,
            );
            break;
          }
        } while (state.needsResync);
      } finally {
        state.syncing = false;
      }
    }());
  }
}
