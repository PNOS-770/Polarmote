import 'dart:async';

import 'package:flutter/foundation.dart';

import '../events/event_bus.dart';
import '../features/terminal/models/host_entry.dart';
import '../features/terminal/models/terminal_session.dart';
import '../features/terminal/state/terminal_app_state.dart';

class SessionProvider extends ChangeNotifier {
  final TerminalAppState _appState;
  final EventBus _eventBus;
  final List<StreamSubscription<AppEvent>> _subscriptions = [];

  SessionProvider({
    required TerminalAppState appState,
    required EventBus eventBus,
  }) : _appState = appState,
       _eventBus = eventBus {
    _subscriptions.addAll([
      _eventBus.listen<SessionConnectedEvent>(_onSessionConnected),
      _eventBus.listen<SessionDisconnectedEvent>(_onSessionDisconnected),
    ]);
  }

  List<TerminalSession> get sessions => _appState.sessions;
  int get activeSessionIndex => _appState.activeSessionIndex;
  TerminalSession? get activeSession => _appState.activeSession;
  bool get hasActiveSession => activeSession != null;

  TerminalSession? sessionById(String id) => _appState.terminalSessionById(id);
  TerminalSession? sessionForHost(HostEntry host) => _appState.terminalSessionForHost(host);

  void connectToHost(HostEntry host, {bool remember = true, bool background = false}) {
    unawaited(_appState.connectToHost(host, remember: remember, background: background));
  }

  void closeSession(String sessionId) {
    unawaited(_appState.closeSession(sessionId));
  }

  void reconnectSession(TerminalSession session, {bool background = false}) {
    unawaited(_appState.reconnectSession(session, background: background));
  }

  void setActiveSession(String sessionId) {
    _appState.setActiveTerminalSession(sessionId);
    notifyListeners();
  }

  void renameSessionTab(TerminalSession session, String title) {
    _appState.renameSessionTab(session, title);
    notifyListeners();
  }

  void _onSessionConnected(SessionConnectedEvent event) {
    notifyListeners();
  }

  void _onSessionDisconnected(SessionDisconnectedEvent event) {
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}

