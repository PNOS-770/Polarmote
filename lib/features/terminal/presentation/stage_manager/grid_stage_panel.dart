import 'package:flutter/material.dart';

import '../../state/terminal_app_state.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../../../shared/design_system/design_system.dart';
import '../common/session_thumbnail.dart';
import '../common/stage_background.dart';

class GridStagePanel extends StatelessWidget {
  final TerminalAppState appState;
  final void Function(String stageId) onStageTap;
  final void Function(String stageId, TapDownDetails details)
      onStageSecondaryTap;

  const GridStagePanel({
    super.key,
    required this.appState,
    required this.onStageTap,
    required this.onStageSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final stages = appState.terminalStages;

    if (stages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize,
                size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              '暂无 Stage，新建连接后将自动创建',
              style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            (constraints.maxWidth / 240).floor().clamp(1, 5);

        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.6,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
          ),
          itemCount: stages.length,
          itemBuilder: (context, index) {
            final stage = stages[index];
            return _StageCard(
              key: ValueKey('grid_stage_${stage.id}'),
              stage: stage,
              appState: appState,
              onTap: () => onStageTap(stage.id),
              onSecondaryTap: (details) =>
                  onStageSecondaryTap(stage.id, details),
            );
          },
        );
      },
    );
  }
}

class _StageCard extends StatefulWidget {
  final TerminalStage stage;
  final TerminalAppState appState;
  final VoidCallback onTap;
  final void Function(TapDownDetails details) onSecondaryTap;

  const _StageCard({
    super.key,
    required this.stage,
    required this.appState,
    required this.onTap,
    required this.onSecondaryTap,
  });

  @override
  State<_StageCard> createState() => _StageCardState();
}

class _StageCardState extends State<_StageCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.stage.id == widget.appState.activeTerminalStageId;

    TerminalSession? session;
    for (final sid in widget.stage.sessionIds) {
      final idx = widget.appState.sessions.indexWhere((s) => s.id == sid);
      if (idx >= 0) {
        session = widget.appState.sessions[idx];
        break;
      }
    }

    final bgPath = widget.appState.showThumbnailBackground
        ? backgroundImagePathForStage(widget.appState, widget.stage)
        : null;

    final borderRadius = BorderRadius.circular(AppRadius.lg);
    final showGlow = _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: showGlow
                ? AppColors.grey300
                : AppColors.border.withValues(alpha: 0.3),
            width: showGlow ? 2 : 1,
          ),
          boxShadow: showGlow
              ? AppShadows.customGlow(AppColors.grey300,
                  opacity: 0.3, blur: 8, spread: 1)
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(AppRadius.lg - (showGlow ? 2 : 0)),
          child: Material(
            color: AppColors.cardBackground,
            child: InkWell(
              onTap: widget.onTap,
              onSecondaryTapDown: widget.onSecondaryTap,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: AppColors.terminalTreeBackground,
                      child: Stack(
                        children: [
                          if (bgPath != null)
                            buildStageBackgroundImage(bgPath),
                          if (session == null)
                            _buildEmptyThumbnail()
                          else
                            _buildSessionThumbnail(session, bgPath: bgPath),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.05),
                            Colors.white.withValues(alpha: 0.02),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!showGlow)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(
                              AppRadius.lg - (showGlow ? 2 : 0)),
                        ),
                      ),
                    ),
                  _buildStageInfo(session, isActive),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyThumbnail() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_circle_outline,
              color: AppColors.textTertiary, size: 28),
          const SizedBox(height: 6),
          Text(
            '点击连接',
            style: AppTextStyles.captionSmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionThumbnail(TerminalSession session, {String? bgPath}) {
    return SessionThumbnail(
      session: session,
      fontFamily: session.profile.fontFamily ??
          widget.appState.globalAppearance.fontFamily,
      backgroundOpacity: bgPath != null
          ? 1 - widget.appState.terminalBackgroundOpacity
          : 1.0,
    );
  }

  Widget _buildStageInfo(TerminalSession? session, bool isActive) {
    final isConnected =
        session != null && session.tab.status == TerminalStatus.connected;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.stage.name,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isConnected ? AppColors.success : AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Icon(Icons.circle, size: 8, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}
