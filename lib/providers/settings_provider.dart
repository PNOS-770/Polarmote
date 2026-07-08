import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../features/terminal/state/terminal_app_state.dart';

class SettingsProvider extends ChangeNotifier {
  final TerminalAppState _appState;

  SettingsProvider({required TerminalAppState appState})
    : _appState = appState;

  Locale get locale => _appState.locale;
  bool get autoReconnect => _appState.autoReconnect;
  bool get confirmPaste => _appState.confirmPaste;
  bool get showHiddenFiles => _appState.showHiddenFiles;

  void setLocale(Locale value) {
    _appState.setLocale(value);
    notifyListeners();
  }

  void toggleLocale() {
    _appState.toggleLocale();
    notifyListeners();
  }

  void setAutoReconnect(bool value) {
    _appState.setAutoReconnect(value);
    notifyListeners();
  }

  void setConfirmPaste(bool value) {
    _appState.setConfirmPaste(value);
    notifyListeners();
  }

  void setShowHiddenFiles(bool value) {
    _appState.setShowHiddenFiles(value);
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}

