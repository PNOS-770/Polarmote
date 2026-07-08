import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../common/session_thumbnail.dart';
import '../common/stage_background.dart';
import '../common/stage_context_menu.dart';
import '../common/stage_background_picker.dart';
import '../common/terminal_localization.dart';
import '../dialogs/terminal_dialogs.dart';

class MobileStagePanel extends StatefulWidget {
  const MobileStagePanel({super.key});

  @override
  State<MobileStagePanel> createState() => _MobileStagePanelState();
}

class _MobileStagePanelState extends State<MobileStagePanel> {
  TerminalAppState? _appState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appState = Provider.of<TerminalAppState>(context, listen: false);
      _appState!.addListener(_onStateChanged);
    });
  }

  @override
  void dispose() {
    _appState?.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context, listen: false);
    final stages = appState.terminalStages;

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.15,
      maxChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        l(appState, AppStrings.values.workspace),
                        style: AppTextStyles.h5,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${stages.length}',
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 190,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: stages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == stages.length) {
                        return _AddStageCard(appState: appState);
                      }
                      final stage = stages[index];
                      return _StageCard(
                        key: ValueKey('stage_${stage.id}_thumb_v${appState.thumbnailBackgroundVersion}'),
                        stage: stage,
                        isActive: stage.id == appState.activeTerminalStageId,
                        appState: appState,
                        onTap: () {
                          appState.switchTerminalStage(stage.id);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StageCard extends StatelessWidget {
  final TerminalStage stage;
  final bool isActive;
  final TerminalAppState appState;
  final VoidCallback onTap;

  const _StageCard({
    super.key,
    required this.stage,
    required this.isActive,
    required this.appState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final session = stage.sessionIds
        .map((sid) => appState.terminalSessionById(sid))
        .whereType<TerminalSession>()
        .firstOrNull;

    final isConnected =
        session != null && session.tab.status == TerminalStatus.connected;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 170,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: () => _showContextMenu(context),
          child: AnimatedScale(
            scale: isActive ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: AppRadius.radiusXL,
                border: Border.all(
                  color: isActive ? AppColors.grey300 : Colors.transparent,
                  width: isActive ? 2 : 0,
                ),
                boxShadow: [
                  if (isActive)
                    ...AppShadows.customGlow(AppColors.grey300, opacity: 0.4, blur: 10, spread: 2)
                  else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildThumbnailContent(session),
                  ),
                  if (isActive)
                    Positioned(
                      left: 0, top: 0, bottom: 0,
                      child: Container(
                        width: 5,
                        decoration: BoxDecoration(
                          color: AppColors.grey200,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(AppRadius.xl - 2),
                            bottomLeft: Radius.circular(AppRadius.xl - 2),
                          ),
                        ),
                      ),
                    ),
                  if (isActive)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.grey100.withValues(alpha: 0.2),
                          borderRadius: AppRadius.radiusXL,
                        ),
                      ),
                    ),
                  if (!isActive)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: AppRadius.radiusXL,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              stage.name,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.white,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.8),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (session != null)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isConnected
                                    ? AppColors.success
                                    : AppColors.border,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent(TerminalSession? session) {
    final bgPath = appState.showThumbnailBackground
        ? backgroundImagePathForStage(appState, stage)
        : null;

    return Container(
      color: AppColors.terminalTreeBackground,
      child: Stack(
        children: [
          if (bgPath != null) buildStageBackgroundImage(bgPath),
          if (session == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.link_off,
                    color: AppColors.terminalTreeMuted,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l(appState, AppStrings.values.noStageSessions),
                    style: AppTextStyles.captionSmall.copyWith(
                      color: AppColors.terminalTreeMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            SessionThumbnail(
              session: session,
              fontFamily: session.profile.fontFamily ??
                  appState.globalAppearance.fontFamily,
              backgroundOpacity: bgPath != null
                  ? 1 - appState.terminalBackgroundOpacity
                  : 1.0,
            ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final session = stage.sessionIds
        .map((sid) => appState.terminalSessionById(sid))
        .whereType<TerminalSession>()
        .firstOrNull;

    showStageCardContextMenu(
      context: context,
      appState: appState,
      stage: stage,
      position: RelativeRect.fromLTRB(
        position.dx + size.width,
        position.dy,
        position.dx + size.width + 1,
        position.dy + 1,
      ),
      includeBackground: true,
      onBackgroundTap: () => showStageBackgroundPicker(context, appState, stage),
      onEditSession: session != null
          ? () => showHostDialog(context, appState, host: session.profile)
          : null,
      editSessionLabel: l(appState, AppStrings.values.editSession),
      selectBackgroundLabel: l(appState, AppStrings.values.selectBackground),
      renameLabel: l(appState, AppStrings.values.renameStage),
      renameTitle: l(appState, AppStrings.values.renameStageTitle),
      renameConfirm: l(appState, AppStrings.values.rename),
      renameCancel: l(appState, AppStrings.values.cancel),
      closeSessionLabel: l(appState, AppStrings.values.commandBarCloseSession),
      deleteLabel: l(appState, AppStrings.values.deleteStage),
      deleteTitle: l(appState, AppStrings.values.deleteStage),
      deleteMessage: l(appState, AppStrings.values.deleteVar),
      deleteConfirm: l(appState, AppStrings.values.delete),
      deleteCancel: l(appState, AppStrings.values.cancel),
    );
  }
}



class _AddStageCard extends StatelessWidget {
  final TerminalAppState appState;

  const _AddStageCard({required this.appState});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () async {
          Navigator.of(context).pop();
          final name = await showInputDialog(
            context,
            title: l(appState, AppStrings.values.createStageTitle),
            hint: l(appState, AppStrings.values.enterStageName),
            initialValue: 'Stage ${appState.terminalStages.length + 1}',
            confirmText: l(appState, AppStrings.values.create),
            cancelText: l(appState, AppStrings.values.cancel),
          );
          if (name != null && name.trim().isNotEmpty) {
            appState.createTerminalStage(name.trim());
          }
        },
        child: Container(
          width: 100,
          height: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.backgroundGrey,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                color: AppColors.textTertiary,
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                l(appState, AppStrings.values.newStage),
                style: AppTextStyles.secondarySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

