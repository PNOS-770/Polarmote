import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import '../file_tree/terminal_file_tree.dart';
import 'modal_panel_base.dart';

/// 文件树模态面板
class FileTreeModalPanel extends StatelessWidget {
  const FileTreeModalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context);

    return ModalPanelBase(
      title: l(appState, AppStrings.values.fileTree),
      width: 800,
      height: 650,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: FileTree(
          appState: appState,
          session: appState.activeSession,
          showHidden: false,
        ),
      ),
    );
  }

  /// 显示文件树面板
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (context) => const FileTreeModalPanel(),
    );
  }
}

