import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import '../session_tree/session_tree_panel.dart';
import 'modal_panel_base.dart';

/// 会话列表模态面板
class SessionListModalPanel extends StatelessWidget {
  const SessionListModalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context);

    return ModalPanelBase(
      title: l(appState, AppStrings.values.sessions),
      width: 700,
      height: 600,
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          iconSize: 20,
          tooltip: l(appState, AppStrings.values.newSession),
          onPressed: () {
            Navigator.of(context).pop();
            // TODO: Open new session dialog
          },
        ),
      ],
      child: SessionTreePanel(),
    );
  }

  /// 显示会话列表面板
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (context) => const SessionListModalPanel(),
    );
  }
}

