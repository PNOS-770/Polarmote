part of 'terminal_app_state_sessions.dart';

extension TerminalAppStateSessionsReconnect on TerminalAppState {
  void _handleSessionClosed(TerminalSession session) {
    if (session.closedByUser) return;
    if (!sessions.contains(session)) return;
    if (session.tab.status == TerminalStatus.disconnected) return;
    session.closeConnection();
    session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
    eventBus.fire(SessionDisconnectedEvent(sessionId: session.id));
    session.fileTreeRefreshTimer?.cancel();
    session.fileTreeRefreshTimer = null;
    stopMetricsPolling(session);
    _connectedLogSessionIds.remove(session.id);
    notifyState();
    syncSshForegroundGuardNow();
    if (autoReconnect && session.profile.isSsh) {
      _startAutoReconnectLoop(session);
    }
  }

  void _startAutoReconnectLoop(TerminalSession session) {
    if (!autoReconnect) return;
    if (!sessions.contains(session)) return;
    if (_autoReconnectTimers.containsKey(session.id)) return;
    unawaited(_runAutoReconnectAttempt(session));
    _autoReconnectTimers[session.id] = Timer.periodic(
      _autoReconnectInterval,
      (_) => unawaited(_runAutoReconnectAttempt(session)),
    );
  }

  void _stopAutoReconnectLoop(String sessionId) {
    _autoReconnectTimers.remove(sessionId)?.cancel();
    _reconnectingSessionIds.remove(sessionId);
  }

  Future<void> _runAutoReconnectAttempt(TerminalSession session) async {
    if (!sessions.contains(session)) { _stopAutoReconnectLoop(session.id); return; }
    if (!autoReconnect) { _stopAutoReconnectLoop(session.id); return; }
    if (session.tab.status == TerminalStatus.connected ||
        session.tab.status == TerminalStatus.connecting ||
        session.tab.status == TerminalStatus.reconnecting) {
      return;
    }
    try { await reconnectSession(session); } catch (_) {}
  }

  void resumeAutoReconnectOnForeground() {
    if (!autoReconnect) return;
    var reconnectCount = 0;
    for (final session in sessions) {
      if (session.closedByUser) continue;
      if (!session.profile.isSsh) continue;
      if (session.tab.status == TerminalStatus.disconnected) {
        reconnectCount += 1;
        unawaited(reconnectSession(session));
      }
    }
    if (reconnectCount > 0) {
      addStructuredLog(
        category: TerminalLogCategory.session,
        message: AppStrings.values.sshResumeReconnectCountVar.resolve(locale.languageCode, params: {'count': '$reconnectCount'}),
        notifyListeners: false,
      );
    }
  }

  Future<void> restoreStageSessions() async {
    if (!stageManagerEnabled) return;
    addStructuredLog(category: TerminalLogCategory.session, message: 'Restoring stage sessions...', notifyListeners: false);
    if (terminalStages.isEmpty) return;
    restorationInProgress = true;
    var count = 0;
    for (final stage in terminalStages) {
      if (stage.connectedHostIds.isEmpty) continue;
      for (final hostId in stage.connectedHostIds) {
        final host = hosts.where((h) => h.id == hostId).firstOrNull;
        if (host == null) {
          addStructuredLog(category: TerminalLogCategory.session, message: 'restore: host not found id=$hostId', notifyListeners: false);
          continue;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        final capturedStageId = stage.id;
        await connectToHost(host, background: true);
        // Manually assign session to the correct stage (silent, no notifyState).
        // Guards (onAppStateChanged, statusBar) check restorationInProgress to
        // suppress rebuilds; next external timer tick will expose final state.
        if (sessions.isNotEmpty) {
          final newSession = sessions.last;
          final idx = terminalStages.indexWhere((s) => s.id == capturedStageId);
          if (idx >= 0) {
            terminalStages[idx] = terminalStages[idx].copyWith(
              sessionIds: [...terminalStages[idx].sessionIds, newSession.id],
              connectedHostIds: [
                ...terminalStages[idx].connectedHostIds.where((id) => id != host.id),
                host.id,
              ],
            );
          }
        }
        count++;
      }
    }
    if (count > 0) {
      addStructuredLog(category: TerminalLogCategory.session, message: 'Restored $count stage sessions silently', notifyListeners: false);
    }
    restorationInProgress = false;
  }
}



