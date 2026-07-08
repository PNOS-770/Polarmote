import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/design_system/design_system.dart';
import '../state/terminal_app_state.dart';
import 'common/terminal_localization.dart';
import 'dialogs/terminal_dialogs.dart';
import 'panels/terminal_main_panel.dart';

class TerminalHomePage extends StatefulWidget {
  const TerminalHomePage({super.key});

  @override
  State<TerminalHomePage> createState() => _TerminalHomePageState();
}

class _TerminalHomePageState extends State<TerminalHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.terminalBackground,
      body: Consumer<TerminalAppState>(
        builder: (context, state, child) {
          if (state.lastError != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showErrorIfNeeded(context, state);
            });
          }
          if (state.hostKeyPromptToken > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showHostKeyPromptIfNeeded(context, state);
            });
          }

          return const MainPanel();
        },
      ),
    );
  }
}

