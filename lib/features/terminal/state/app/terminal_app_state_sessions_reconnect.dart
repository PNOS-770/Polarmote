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
        session.tab.status == TerminalStatus.reconnecting) return;
    try { await reconnectSession(session); } catch (e) { PolarmoteLog.error('terminal_app_state_sessions_reconnect', '$e'); }
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

  void restoreStageSessions() {
    if (!stageManagerEnabled) return;
    addStructuredLog(category: TerminalLogCategory.session, message: 'Restoring stage sessions...', notifyListeners: false);
    var delay = 0;
    for (final stage in terminalStages) {
      if (stage.connectedHostIds.isEmpty) continue;
      for (final hostId in stage.connectedHostIds) {
        final host = hosts.where((h) => h.id == hostId).firstOrNull;
        if (host == null) {
          addStructuredLog(category: TerminalLogCategory.session, message: 'restore: host not found id=$hostId', notifyListeners: false);
          continue;
        }
        delay += 500;
        final capturedStageId = stage.id;
        unawaited(Future.delayed(Duration(milliseconds: delay), () {
          activeTerminalStageId = capturedStageId;
          unawaited(connectToHost(host));
        }));
      }
    }
    if (delay > 0) {
      final count = delay ~/ 500;
      addStructuredLog(category: TerminalLogCategory.session, message: 'Restored $count stage sessions with staggered delays', notifyListeners: false);
    }
  }
}



