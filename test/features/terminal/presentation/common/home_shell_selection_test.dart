import 'package:Polarmote/features/terminal/presentation/common/home_shell_selection.dart';
import 'package:Polarmote/features/terminal/state/terminal_app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HomeShellSelection equality includes hostKeyPromptToken', () {
    const base = HomeShellSelection(
      navSection: NavSection.sessions,
      locale: Locale('zh'),
      lastError: null,
      hostKeyPromptToken: 1,
      hasActiveTransfers: false,
      activeTransferCount: 0,
      hasActiveScripts: false,
      activeScriptRunCount: 0,
      shortcutConflictToken: 0,
      showScriptMonitorInline: false,
      homeLayoutMode: HomeLayoutMode.mobile,
      mobileSidebarWidth: TerminalAppState.mobileSidebarWidthDefault,
    );
    const changedToken = HomeShellSelection(
      navSection: NavSection.sessions,
      locale: Locale('zh'),
      lastError: null,
      hostKeyPromptToken: 2,
      hasActiveTransfers: false,
      activeTransferCount: 0,
      hasActiveScripts: false,
      activeScriptRunCount: 0,
      shortcutConflictToken: 0,
      showScriptMonitorInline: false,
      homeLayoutMode: HomeLayoutMode.mobile,
      mobileSidebarWidth: TerminalAppState.mobileSidebarWidthDefault,
    );

    expect(base == changedToken, isFalse);
  });

  test('HomeShellSelection equality and hashCode match when same', () {
    const first = HomeShellSelection(
      navSection: NavSection.transfers,
      locale: Locale('en'),
      lastError: 'network',
      hostKeyPromptToken: 3,
      hasActiveTransfers: true,
      activeTransferCount: 5,
      hasActiveScripts: false,
      activeScriptRunCount: 0,
      shortcutConflictToken: 0,
      showScriptMonitorInline: false,
      homeLayoutMode: HomeLayoutMode.desktop,
      mobileSidebarWidth: 360,
    );
    const second = HomeShellSelection(
      navSection: NavSection.transfers,
      locale: Locale('en'),
      lastError: 'network',
      hostKeyPromptToken: 3,
      hasActiveTransfers: true,
      activeTransferCount: 5,
      hasActiveScripts: false,
      activeScriptRunCount: 0,
      shortcutConflictToken: 0,
      showScriptMonitorInline: false,
      homeLayoutMode: HomeLayoutMode.desktop,
      mobileSidebarWidth: 360,
    );

    expect(first, equals(second));
    expect(first.hashCode, equals(second.hashCode));
  });
}
