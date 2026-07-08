import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import '../../../shared/constants/app_string.dart';
import '../../../shared/design_system/design_system.dart';
import '../models/transfer_task.dart';
import '../state/terminal_app_state.dart';
import 'common/animated_nav_item.dart';
import 'common/home_shell_selection.dart';
import 'common/terminal_button_styles.dart';
import 'common/terminal_localization.dart';
import 'common/terminal_ui_palette.dart';
import 'dialogs/terminal_dialogs.dart';
import 'panels/terminal_home_panels.dart';
import 'panels/terminal_main_panel.dart';

class TerminalHomePage extends StatefulWidget {
  const TerminalHomePage({super.key});

  @override
  State<TerminalHomePage> createState() => _TerminalHomePageState();
}

class _TerminalHomePageState extends State<TerminalHomePage> {
  int _sidePaneRevealToken = 0;
  bool _registeredPaletteHandler = false;

  @override
  void initState() {
    super.initState();
    _registerCommandPaletteHandler();
  }

  @override
  void dispose() {
    _unregisterCommandPaletteHandler();
    super.dispose();
  }

  void _registerCommandPaletteHandler() {
    if (_registeredPaletteHandler) return;
    HardwareKeyboard.instance.addHandler(_handlePaletteShortcut);
    _registeredPaletteHandler = true;
  }

  void _unregisterCommandPaletteHandler() {
    if (!_registeredPaletteHandler) return;
    HardwareKeyboard.instance.removeHandler(_handlePaletteShortcut);
    _registeredPaletteHandler = false;
  }

  bool _handlePaletteShortcut(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyP) return false;
    final kb = HardwareKeyboard.instance;
    if (!kb.isControlPressed && !kb.isMetaPressed) return false;
    if (kb.isAltPressed || kb.isShiftPressed) return false;
    if (CommandPalette.isOpen) {
      CommandPalette.dismiss();
    } else {
      final appState = context.read<TerminalAppState>();
      CommandPalette.show(context, _buildPaletteActions(context, appState));
    }
    return true;
  }

  List<CommandPaletteAction> _buildPaletteActions(
    BuildContext context,
    TerminalAppState appState,
  ) {
    return [
      CommandPaletteAction(
        label: l(appState, AppStrings.values.cmdPaletteNewSession),
        category: l(appState, AppStrings.values.sessions),
        icon: Icons.computer,
        onSelected: () {
          appState.setNavSection(NavSection.sessions);
          unawaited(showHostDialog(context, appState));
        },
      ),
      CommandPaletteAction(
        label: l(appState, AppStrings.values.cmdPaletteQuickConnect),
        category: l(appState, AppStrings.values.sessions),
        icon: Icons.flash_on,
        onSelected: () {
          appState.setNavSection(NavSection.sessions);
          unawaited(showQuickConnectDialog(context, appState));
        },
      ),
      CommandPaletteAction(
        label: l(appState, AppStrings.values.cmdPaletteSftp),
        category: l(appState, AppStrings.values.sftp),
        icon: Icons.folder,
        onSelected: () => appState.setNavSection(NavSection.sftp),
      ),
      CommandPaletteAction(
        label: l(appState, AppStrings.values.cmdPaletteScripts),
        category: l(appState, AppStrings.values.scripts),
        icon: Icons.code,
        onSelected: () => appState.setNavSection(NavSection.scripts),
      ),
      CommandPaletteAction(
        label: l(appState, AppStrings.values.cmdPaletteSettings),
        category: l(appState, AppStrings.values.settings),
        icon: Icons.settings_outlined,
        onSelected: () => appState.setNavSection(NavSection.settings),
      ),
      CommandPaletteAction(
        label: l(appState, AppStrings.values.cmdPaletteToggleMonitor),
        category: l(appState, AppStrings.values.scripts),
        icon: Icons.monitor_heart_outlined,
        onSelected: () => appState.toggleScriptMonitorInline(),
      ),
      CommandPaletteAction(
        label: l(appState, AppStrings.values.cmdPaletteSessions),
        category: l(appState, AppStrings.values.sessions),
        icon: Icons.swap_horiz,
        onSelected: () => appState.setNavSection(NavSection.sessions),
      ),
    ];
  }

  bool _useMobileLayout(HomeLayoutMode mode) {
    return switch (mode) {
      HomeLayoutMode.mobile => true,
      HomeLayoutMode.desktop => false,
    };
  }

  int _activeTransferCount(TerminalAppState state) {
    var total = 0;
    for (final session in state.sessions) {
      var sessionCount = session.transferQueue.where((task) {
        return task.status == TransferStatus.queued ||
            task.status == TransferStatus.running;
      }).length;
      if (sessionCount == 0 && session.transferPreparing) {
        sessionCount = 1;
      }
      total += sessionCount;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Selector<TerminalAppState, HomeShellSelection>(
      selector: (context, state) {
        final activeTransferCount = _activeTransferCount(state);
        final activeScriptRunCount = state.activeScriptRunCount();
        return HomeShellSelection(
          navSection: state.navSection,
          locale: state.locale,
          lastError: state.lastError,
          hostKeyPromptToken: state.hostKeyPromptToken,
          shortcutConflictToken: state.shortcutConflictToken,
          hasActiveTransfers: activeTransferCount > 0,
          activeTransferCount: activeTransferCount,
          hasActiveScripts: activeScriptRunCount > 0,
          activeScriptRunCount: activeScriptRunCount,
          showScriptMonitorInline: state.showScriptMonitorInline,
          homeLayoutMode: state.homeLayoutMode,
          mobileSidebarWidth: state.mobileSidebarWidth,
        );
      },
      shouldRebuild: (prev, next) => prev != next,
      builder: (context, selection, child) {
        final appState = Provider.of<TerminalAppState>(context, listen: false);
        if (selection.lastError != null) {
          showErrorIfNeeded(context, appState);
        }
        if (selection.hostKeyPromptToken > 0) {
          showHostKeyPromptIfNeeded(context, appState);
        }
        if (selection.shortcutConflictToken > 0) {
          showShortcutConflictsIfNeeded(context, appState);
        }

        void selectSection(NavSection section) {
          unfocusPrimary();
          setState(() {
            _sidePaneRevealToken++;
          });
          appState.setNavSection(section);
        }

        final navItems = [
          ShellNavItem(
            icon: Icons.computer,
            label: l(appState, AppStrings.values.sessions),
            selected: selection.navSection == NavSection.sessions,
            onTap: () => selectSection(NavSection.sessions),
          ),
          ShellNavItem(
            icon: Icons.folder,
            label: l(appState, AppStrings.values.sftp),
            selected: selection.navSection == NavSection.sftp,
            onTap: () => selectSection(NavSection.sftp),
          ),
          createAnimatedNavItem(
            icon: Icons.swap_vert,
            label: l(appState, AppStrings.values.transfers),
            selected: selection.navSection == NavSection.transfers,
            hasActiveTask: selection.hasActiveTransfers,
            onTap: () => selectSection(NavSection.transfers),
          ),
          createAnimatedNavItem(
            icon: Icons.code,
            label: l(appState, AppStrings.values.scripts),
            selected: selection.navSection == NavSection.scripts,
            hasActiveTask: selection.hasActiveScripts,
            onTap: () => selectSection(NavSection.scripts),
          ),
          ShellNavItem(
            icon: Icons.settings_outlined,
            label: l(appState, AppStrings.values.settings),
            selected: selection.navSection == NavSection.settings,
            onTap: () => selectSection(NavSection.settings),
          ),
        ];

        final sidePane = SafeSidePane(
          onPointerDown: unfocusPrimary,
          title: panelTitle(appState),
          borderColor: Colors.transparent,
          actions: [
            if (appState.navSection == NavSection.sessions)
              IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: l(appState, AppStrings.values.openFolder),
                onPressed: appState.openStateFolder,
              ),
            if (appState.navSection == NavSection.scripts) ...[
              IconButton(
                icon: Icon(
                  appState.showScriptMonitorInline
                      ? Icons.arrow_back
                      : Icons.monitor_heart_outlined,
                ),
                tooltip: l(appState, AppStrings.values.scriptMonitor),
                onPressed: () => appState.toggleScriptMonitorInline(),
              ),
              IconButton(
                icon: Icon(
                  appState.scriptMultiSelectActive
                      ? Icons.checklist
                      : Icons.checklist_outlined,
                ),
                tooltip: l(appState, AppStrings.values.selectMultiple),
                onPressed: () => appState.triggerScriptMultiSelect(),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: l(appState, AppStrings.values.addScript),
                onPressed: () => showScriptEditorDialog(context, appState),
              ),
            ],
          ],
          body: KeyedSubtree(
            key: ValueKey(selection.navSection),
            child: const LeftPanelList(),
          ),
        );
        final useMobileLayout = _useMobileLayout(selection.homeLayoutMode);
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final mobileDrawerWidth = appState
            .normalizeMobileSidebarWidthForViewport(
              selection.mobileSidebarWidth,
              viewportWidth,
            );

        return Theme(
          data: TerminalButtonStyles.apply(Theme.of(context)),
          child: SafeAdaptiveShell(
            navItems: navItems,
            mobileTitle: l(appState, AppStrings.values.asmoteTerminal),
            mobileActions: const [],
            mobileDrawerBody: KeyedSubtree(
              key: ValueKey('mobile-${selection.navSection.name}'),
              child: const LeftPanelList(isCompact: true),
            ),
            mobileDrawerWidth: mobileDrawerWidth,
            desktopPane: sidePane,
            desktopPaneConfig: SafeDesktopPaneLayoutConfig(
              revealToken: _sidePaneRevealToken,
              paneStyle: SafeResizablePaneStyle(showDividerLine: true),
              dragOverlayColor: TerminalUiPalette.accent,
            ),
            main: const MainPanel(),
            onDesktopRailPointerDown: unfocusPrimary,
            desktopRailStyle: const SafeDesktopRailStyle(
              railBackgroundColor: Colors.white,
              railBorderColor: TerminalUiPalette.border,
              selectedColor: TerminalUiPalette.railSelected,
              unselectedColor: TerminalUiPalette.railUnselected,
              selectedBackgroundColor: TerminalUiPalette.railSelectedBackground,
            ),
            mobileStyle: const SafeMobileShellStyle(
              selectedColor: TerminalUiPalette.railSelected,
              unselectedColor: TerminalUiPalette.railUnselected,
              showDivider: true,
            ),
            compactWidth: useMobileLayout ? double.infinity : 0,
          ),
        );
      },
    );
  }
}

void showShortcutConflictsIfNeeded(
  BuildContext context,
  TerminalAppState appState,
) {
  if (!appState.beginShortcutConflictDialog()) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) {
      appState.endShortcutConflictDialog();
      return;
    }
    final conflicts = List<String>.from(appState.shortcutConflicts);
    appState.shortcutConflicts.clear();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(l(appState, AppStrings.values.shortcutConflictTitle)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l(appState, AppStrings.values.shortcutConflictMessage)),
              const SizedBox(height: 8),
              for (final conflict in conflicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    conflict,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Cascadia Code',
                      color: Colors.grey[800],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(ctx),
            label: l(appState, AppStrings.values.ok),
          ),
        ],
      ),
    );
    appState.endShortcutConflictDialog();
  });
}
