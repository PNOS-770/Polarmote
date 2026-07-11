import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import '../../../../shared/constants/app_string.dart';
import '../../models/host_entry.dart';
import '../../models/script_entry.dart';
import '../../models/script_folder_entry.dart';
import '../../models/script_run_session.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../state/terminal_app_state.dart';
import '../common/compact_more_menu_button.dart';
import '../common/terminal_localization.dart';
import '../../../../shared/design_system/design_system.dart';
import '../common/terminal_ui_palette.dart';
import '../dialogs/terminal_dialogs.dart';
import '../file_tree/terminal_file_tree.dart';
import '../session_tree/server_dashboard_panel.dart';
import '../transfers/terminal_transfer_panel.dart';

part 'home/terminal_home_panels_scripts_panel.dart';
part 'home/terminal_home_panels_log_panel.dart';
part 'home/terminal_home_panels_scripts_run.dart';
part 'home/terminal_home_panels_scripts_ops.dart';

class LeftPanelList extends StatelessWidget {
  const LeftPanelList({super.key, this.isCompact = false});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final section = context.select<TerminalAppState, NavSection>(
      (state) => state.navSection,
    );
    return switch (section) {
      NavSection.sessions => const ServerDashboardPanel(),
      NavSection.sftp => Selector<TerminalAppState, FileTreeSelection>(
        selector: (context, state) {
          final session = state.activeSession;
          return FileTreeSelection(
            session: session,
            sessionId: session?.id ?? '',
            status: session?.tab.status,
            fileVersion: session?.fileState.version ?? 0,
            rootPath: session?.fileState.rootPath ?? '',
            showHidden: state.showHiddenFiles,
          );
        },
        shouldRebuild: (prev, next) => prev != next,
        builder: (context, selection, child) {
          final state = Provider.of<TerminalAppState>(context, listen: false);
          return FileTree(
            appState: state,
            session: selection.session,
            showHidden: selection.showHidden,
          );
        },
      ),
      NavSection.transfers => Consumer<TerminalAppState>(
        builder: (context, state, child) {
          return TransferPanel(appState: state, isCompact: isCompact);
        },
      ),
      NavSection.scripts => Consumer<TerminalAppState>(
        builder: (context, state, child) {
          return _ScriptsPanel(appState: state, isCompact: isCompact);
        },
      ),
      NavSection.settings => Consumer<TerminalAppState>(
        builder: (context, state, child) {
          return TerminalSettingsPanel(appState: state, embedded: true);
        },
      ),
    };
  }
}

String panelTitle(TerminalAppState appState) {
  if (appState.navSection == NavSection.sessions) {
    return l(appState, AppStrings.values.sessions);
  }
  if (appState.navSection == NavSection.sftp) {
    return l(appState, AppStrings.values.fileTree);
  }
  return switch (appState.navSection) {
    NavSection.transfers => l(appState, AppStrings.values.transfers),
    NavSection.scripts => l(appState, AppStrings.values.scripts),
    NavSection.settings => l(appState, AppStrings.values.settings),
    _ => l(appState, AppStrings.values.panel),
  };
}

class FileTreeSelection {
  const FileTreeSelection({
    required this.session,
    required this.sessionId,
    required this.status,
    required this.fileVersion,
    required this.rootPath,
    required this.showHidden,
  });

  final TerminalSession? session;
  final String sessionId;
  final TerminalStatus? status;
  final int fileVersion;
  final String rootPath;
  final bool showHidden;

  @override
  bool operator ==(Object other) {
    return other is FileTreeSelection &&
        other.sessionId == sessionId &&
        other.status == status &&
        other.fileVersion == fileVersion &&
        other.rootPath == rootPath &&
        other.showHidden == showHidden;
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, status, fileVersion, rootPath, showHidden);
}

class PlaceholderPanel extends StatelessWidget {
  const PlaceholderPanel({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(description, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          PrimaryButton(onPressed: onAction, label: actionLabel),
        ],
      ),
    );
  }
}
