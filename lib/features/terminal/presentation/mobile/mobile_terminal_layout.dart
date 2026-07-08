import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../state/terminal_app_state.dart';
import 'mobile_stage_panel.dart';
import 'mobile_terminal_menu.dart';

class MobileTerminalLayout extends StatelessWidget {
  const MobileTerminalLayout({
    super.key,
    required this.terminalContent,
  });

  final Widget terminalContent;

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context, listen: false);
    return Stack(
      children: [
        terminalContent,
        Positioned(
          right: 12,
          top: 48,
          child: Column(
            children: [
              _MoreButton(appState: appState),
              const SizedBox(height: 12),
              _StageFloatingButton(),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreButton extends StatelessWidget {
  final TerminalAppState appState;
  const _MoreButton({required this.appState});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: AppColors.cardBackground.withValues(alpha: 0.85),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showMobileMoreMenu(context, appState),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            Icons.more_horiz_rounded,
            color: AppColors.terminalForeground,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _StageFloatingButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shape: const CircleBorder(),
      color: AppColors.cardBackground.withValues(alpha: 0.92),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black38,
            builder: (_) => const MobileStagePanel(),
          );
        },
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            Icons.dashboard_rounded,
            color: AppColors.terminalForeground,
            size: 22,
          ),
        ),
      ),
    );
  }
}

