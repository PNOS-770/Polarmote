import 'dart:async';
import 'dart:io';

import '../../transfer/mobile/android_ssh_foreground_bridge.dart';
import '../terminal_app_state.dart';

extension TerminalAppStateSshForeground on TerminalAppState {
  void setAppForegroundForSshGuard(bool value) {
    // Flutter-only mode: do not run SSH foreground service.
  }

  bool isAppForegroundForSshGuard() {
    return true;
  }

  void syncSshForegroundGuardNow() {
    if (!Platform.isAndroid) {
      return;
    }
    // Ensure old versions' SSH foreground notification is removed.
    unawaited(AndroidSshForegroundBridge.stop().catchError((_) {}));
  }

  void disposeSshForegroundGuardRuntime() {
    // No runtime state in Flutter-only mode.
  }
}

