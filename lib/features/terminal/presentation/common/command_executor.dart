import 'package:flutter/material.dart';
import '../../state/terminal_app_state.dart';
import '../dialogs/terminal_dialogs.dart';
import '../modal_panels/file_tree_modal_panel.dart';
import '../modal_panels/port_forward_modal_panel.dart';
import '../modal_panels/transfer_modal_panel.dart';
import '../modal_panels/lan_scan_modal_panel.dart';
import '../panels/terminal_home_panels.dart';

void executeTerminalCommand(
    BuildContext context, TerminalAppState appState, String command) {
  switch (command) {
    case 'new_session':
      showHostDialog(context, appState);
    case 'quick_connect':
      showQuickConnectDialog(context, appState);
    case 'close_workspace':
      if (appState.activeSession != null) {
        appState.closeSession(appState.activeSession!.id);
      }
    case 'close_all':
      for (final s in appState.sessions.toList()) {
        appState.closeSession(s.id);
      }
    case 'new_script':
      showScriptEditorDialog(context, appState);
    case 'run_script':
    case 'script_list':
      appState.showScriptMonitorInline = false;
      showScriptsPanelDialog(context, appState);
    case 'script_monitor':
      appState.showScriptMonitorInline = true;
      showScriptsPanelDialog(context, appState);
    case 'sftp_browser':
      FileTreeModalPanel.show(context);
    case 'transfer_manager':
      TransferModalPanel.show(context);
    case 'open_settings':
      showSettingsDialog(context, appState);
    case 'port_forwarding':
      PortForwardModalPanel.show(context);
    case 'lan_scan':
      LanScanPanel.show(context);
  }
}

