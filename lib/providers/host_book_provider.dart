import 'dart:async';

import 'package:flutter/foundation.dart';

import '../events/event_bus.dart';
import '../features/terminal/models/host_entry.dart';
import '../features/terminal/state/terminal_app_state.dart';

class HostBookProvider extends ChangeNotifier {
  final TerminalAppState _appState;
  final EventBus _eventBus;
  final List<StreamSubscription<AppEvent>> _subscriptions = [];

  HostBookProvider({
    required TerminalAppState appState,
    required EventBus eventBus,
  }) : _appState = appState,
       _eventBus = eventBus {
    _subscriptions.addAll([
      _eventBus.listen<HostListChangedEvent>((_) => notifyListeners()),
    ]);
  }

  List<HostEntry> get hosts => _appState.hosts;
  List<HostEntry> get visibleHosts => _appState.visibleHosts();
  List<HostEntry> recentHosts({int limit = 30}) => _appState.recentHosts(limit: limit);
  Set<String> get pinnedHostIds => _appState.pinnedHostIds;
  Set<String> get selectedHostIds => _appState.selectedHostIds;

  bool isPinned(String hostId) => _appState.isHostPinned(hostId);
  bool isSelected(String hostId) => _appState.selectedHostIds.contains(hostId);

  void togglePin(String hostId) {
    _appState.toggleHostPinned(hostId);
    notifyListeners();
  }

  void toggleSelection(String id, {bool multi = false}) {
    _appState.toggleHostSelection(id, multi: multi);
    notifyListeners();
  }

  void clearSelection() {
    _appState.clearHostSelection();
    notifyListeners();
  }

  void add(HostEntry host) {
    _appState.addHost(host);
  }

  void update(HostEntry host) {
    _appState.updateHost(host);
  }

  void remove(String id) {
    _appState.removeHost(id);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}

