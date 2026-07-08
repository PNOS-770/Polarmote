import 'dart:async';

import 'package:flutter/foundation.dart';

import '../events/event_bus.dart';
import '../features/terminal/models/terminal_session.dart';
import '../features/terminal/state/terminal_app_state.dart';

class TransferProvider extends ChangeNotifier {
  final TerminalAppState _appState;
  final EventBus _eventBus;
  final List<StreamSubscription<AppEvent>> _subscriptions = [];

  TransferProvider({
    required TerminalAppState appState,
    required EventBus eventBus,
  }) : _appState = appState,
       _eventBus = eventBus {
    _subscriptions.addAll([
      _eventBus.listen<TransferCompletedEvent>((_) => notifyListeners()),
      _eventBus.listen<TransferErrorEvent>((_) => notifyListeners()),
    ]);
  }

  bool get hasActiveTransfers =>
      _appState.sessions.any((s) => s.transferQueue.isNotEmpty);

  int get totalActiveJobs =>
      _appState.sessions.fold(0, (sum, s) => sum + s.activeTransfers);

  bool sessionHasTransfers(TerminalSession session) =>
      session.transferQueue.isNotEmpty;

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}

