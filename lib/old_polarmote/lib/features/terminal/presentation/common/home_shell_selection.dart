import 'package:flutter/widgets.dart';

import '../../state/terminal_app_state.dart';

class HomeShellSelection {
  const HomeShellSelection({
    required this.navSection,
    required this.locale,
    required this.lastError,
    required this.hostKeyPromptToken,
    required this.shortcutConflictToken,
    required this.hasActiveTransfers,
    required this.activeTransferCount,
    required this.hasActiveScripts,
    required this.activeScriptRunCount,
    required this.showScriptMonitorInline,
    required this.homeLayoutMode,
    required this.mobileSidebarWidth,
  });

  final NavSection navSection;
  final Locale locale;
  final String? lastError;
  final int hostKeyPromptToken;
  final int shortcutConflictToken;
  final bool hasActiveTransfers;
  final int activeTransferCount;
  final bool hasActiveScripts;
  final int activeScriptRunCount;
  final bool showScriptMonitorInline;
  final HomeLayoutMode homeLayoutMode;
  final double mobileSidebarWidth;

  @override
  bool operator ==(Object other) {
    return other is HomeShellSelection &&
        other.navSection == navSection &&
        other.locale == locale &&
        other.lastError == lastError &&
        other.hostKeyPromptToken == hostKeyPromptToken &&
        other.shortcutConflictToken == shortcutConflictToken &&
        other.hasActiveTransfers == hasActiveTransfers &&
        other.activeTransferCount == activeTransferCount &&
        other.hasActiveScripts == hasActiveScripts &&
        other.activeScriptRunCount == activeScriptRunCount &&
        other.showScriptMonitorInline == showScriptMonitorInline &&
        other.homeLayoutMode == homeLayoutMode &&
        other.mobileSidebarWidth == mobileSidebarWidth;
  }

  @override
  int get hashCode => Object.hash(
    navSection,
    locale,
    lastError,
    hostKeyPromptToken,
    shortcutConflictToken,
    hasActiveTransfers,
    activeTransferCount,
    hasActiveScripts,
    activeScriptRunCount,
    showScriptMonitorInline,
    homeLayoutMode,
    mobileSidebarWidth,
  );
}
