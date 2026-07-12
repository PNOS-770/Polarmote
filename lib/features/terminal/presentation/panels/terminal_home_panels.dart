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
import '../common/host_tree_row.dart';
import '../modal_panels/modal_panel_base.dart';

import '../dialogs/script_editor_dialog.dart';
export '../dialogs/script_editor_dialog.dart';

part 'home/terminal_home_panels_scripts_panel.dart';
part 'home/terminal_home_panels_log_panel.dart';
part 'home/terminal_home_panels_scripts_run.dart';
part 'home/terminal_home_panels_scripts_ops.dart';

/// 脚本面板弹窗（脚本列表 + 监控 + 管理）
class _ScriptsModalPanel extends StatefulWidget {
  const _ScriptsModalPanel({required this.appState, this.onRunScripts, this.runMode = false});

  final TerminalAppState appState;
  final void Function(List<String> scriptIds)? onRunScripts;
  final bool runMode;

  @override
  State<_ScriptsModalPanel> createState() => _ScriptsModalPanelState();
}

class _ScriptsModalPanelState extends State<_ScriptsModalPanel> {
  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    return ModalPanelBase(
      title: l(appState, AppStrings.values.scripts),
      width: 800,
      height: 600,
      actions: [
        if (!widget.runMode)
          Consumer<TerminalAppState>(
            builder: (context, state, _) => IconButton(
              icon: Icon(
                state.showScriptMonitorInline
                    ? Icons.arrow_back
                    : Icons.monitor_heart_outlined,
              ),
              iconSize: 20,
              tooltip: l(appState, AppStrings.values.scriptMonitor),
              onPressed: () {
                state.toggleScriptMonitorInline();
              },
            ),
          ),
        Consumer<TerminalAppState>(
          builder: (context, state, _) => IconButton(
            icon: Icon(
              state.scriptMultiSelectActive
                  ? Icons.checklist
                  : Icons.checklist_outlined,
            ),
            iconSize: 20,
            tooltip: l(appState, AppStrings.values.selectMultiple),
            onPressed: () => state.triggerScriptMultiSelect(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          iconSize: 20,
          tooltip: l(appState, AppStrings.values.addScript),
          onPressed: () => showScriptEditorDialog(context, appState),
        ),
      ],
      child: _ScriptsPanel(appState: appState, isCompact: false, onRunScripts: widget.onRunScripts, runMode: widget.runMode),
    );
  }
}

/// 显示脚本面板弹窗
Future<void> showScriptsPanelDialog(BuildContext context, TerminalAppState appState, {void Function(List<String> scriptIds)? onRunScripts, bool runMode = false}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: AppColors.overlay,
    builder: (context) => _ScriptsModalPanel(appState: appState, onRunScripts: onRunScripts, runMode: runMode),
  );
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: AppTextStyles.h5),
            const SizedBox(height: 8),
            Text(description, style: AppTextStyles.secondary),
            const SizedBox(height: 16),
            PrimaryButton(onPressed: onAction, label: actionLabel),
          ],
        ),
      ),
    );
  }
}

