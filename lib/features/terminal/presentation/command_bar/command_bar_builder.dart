import 'package:flutter/material.dart';
import '../../state/terminal_app_state.dart';
import 'command_bar_models.dart';
import '../dialogs/terminal_dialogs.dart';
import '../modal_panels/transfer_modal_panel.dart';
import '../panels/terminal_home_panels.dart';
import '../modal_panels/file_tree_modal_panel.dart';
import '../common/terminal_localization.dart';
import '../../../../shared/constants/app_string.dart';

/// 构建命令栏的所有分组
List<CommandBarSection> buildCommandBarSections(
  BuildContext context,
  TerminalAppState appState,
) {
  return [
    _buildSessionsSection(context, appState),
    _buildScriptsSection(context, appState),
    _buildTransferSection(context, appState),
    _buildToolsSection(context, appState),
    _buildSettingsSection(context, appState),
  ];
}

/// Sessions 分组
CommandBarSection _buildSessionsSection(
  BuildContext context,
  TerminalAppState appState,
) {
  return CommandBarSection(
    id: 'sessions',
    title: l(appState, AppStrings.values.commandBarSessions),
    icon: Icons.terminal,
    items: [
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarNewSession),
        icon: Icons.add,
        shortcut: 'Ctrl+T',
        onTap: () => showHostDialog(context, appState),
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarQuickConnect),
        icon: Icons.flash_on,
        shortcut: 'Ctrl+Shift+K',
        onTap: () => showQuickConnectDialog(context, appState),
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarDuplicateSession),
        icon: Icons.content_copy,
        shortcut: 'Ctrl+Shift+T',
        onTap: () {
          // TODO: Implement duplicate session
          final session = appState.activeSession;
          if (session != null) {
            // Duplicate not implemented yet
          }
        },
        enabled: false,  // Disabled for now
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarCloseSession),
        icon: Icons.close,
        shortcut: 'Ctrl+W',
        onTap: () {
          final session = appState.activeSession;
          if (session != null) {
            appState.closeSession(session.id);
          }
        },
        enabled: appState.activeSession != null,
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarCloseAllSessions),
        icon: Icons.clear_all,
        onTap: () {
          // Close all sessions
          final sessionIds = appState.sessions.map((s) => s.id).toList();
          for (final id in sessionIds) {
            appState.closeSession(id);
          }
        },
        enabled: appState.sessions.isNotEmpty,
      ),
    ],
  );
}

/// Scripts 分组
CommandBarSection _buildScriptsSection(
  BuildContext context,
  TerminalAppState appState,
) {
  return CommandBarSection(
    id: 'scripts',
    title: l(appState, AppStrings.values.commandBarScripts),
    icon: Icons.code,
    items: [
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarRunScript),
        icon: Icons.play_arrow,
        shortcut: 'Ctrl+Shift+R',
        onTap: () => showScriptsPanelDialog(context, appState),
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarNewScript),
        icon: Icons.add,
        onTap: () => showScriptsPanelDialog(context, appState),
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarManageScripts),
        icon: Icons.folder,
        onTap: () => showScriptsPanelDialog(context, appState),
      ),
    ],
  );
}

/// Transfer 分组
CommandBarSection _buildTransferSection(
  BuildContext context,
  TerminalAppState appState,
) {
  return CommandBarSection(
    id: 'transfer',
    title: l(appState, AppStrings.values.commandBarTransfer),
    icon: Icons.swap_vert,
    items: [
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarUploadFile),
        icon: Icons.upload,
        onTap: () {
          // TODO: Direct upload action
          TransferModalPanel.show(context);
        },
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarDownloadFile),
        icon: Icons.download,
        onTap: () {
          // TODO: Direct download action
          TransferModalPanel.show(context);
        },
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarSftpBrowser),
        icon: Icons.folder_open,
        shortcut: 'Ctrl+Shift+F',
        onTap: () => FileTreeModalPanel.show(context),
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarTransferManager),
        icon: Icons.sync,
        onTap: () => TransferModalPanel.show(context),
      ),
    ],
  );
}

/// Tools 分组
CommandBarSection _buildToolsSection(
  BuildContext context,
  TerminalAppState appState,
) {
  return CommandBarSection(
    id: 'tools',
    title: l(appState, AppStrings.values.commandBarTools),
    icon: Icons.build,
    items: [
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarPortForward),
        icon: Icons.network_check,
        onTap: () {
          // TODO: Open port forward dialog
        },
      ),
      CommandBarItem(
        label: l(appState, AppStrings.values.commandBarSearchLogs),
        icon: Icons.search,
        onTap: () {
          // TODO: Open log search
        },
      ),
    ],
  );
}

/// Settings 分组
CommandBarSection _buildSettingsSection(
  BuildContext context,
  TerminalAppState appState,
) {
  return CommandBarSection(
    id: 'settings',
    title: t(context, AppStrings.values.commandBarSettings),
    icon: Icons.settings,
    items: [
      CommandBarItem(
        label: t(context, AppStrings.values.commandBarPreferences),
        icon: Icons.tune,
        shortcut: 'Ctrl+,',
        onTap: () => showSettingsDialog(context, appState),
      ),
      CommandBarItem(
        label: t(context, AppStrings.values.commandBarKeyboardShortcuts),
        icon: Icons.keyboard,
        onTap: () {
          showSettingsDialog(context, appState);
        },
      ),
      CommandBarItem(
        label: t(context, AppStrings.values.commandBarAppearance),
        icon: Icons.palette,
        onTap: () {
          showSettingsDialog(context, appState);
        },
      ),
    ],
  );
}

