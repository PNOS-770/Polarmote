import 'package:flutter/material.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../state/terminal_app_state.dart';

Future<void> showStageCardContextMenu({
  required BuildContext context,
  required TerminalAppState appState,
  required TerminalStage stage,
  required RelativeRect position,
  bool includeBackground = false,
  VoidCallback? onBackgroundTap,
  VoidCallback? onEditSession,
  String editSessionLabel = 'Edit Session',
  String renameLabel = 'Rename',
  String renameTitle = 'Rename Stage',
  String renameConfirm = 'OK',
  String renameCancel = 'Cancel',
  String closeSessionLabel = 'Close Session',
  String selectBackgroundLabel = 'Select Background',
  String deleteLabel = 'Delete',
  String deleteTitle = 'Delete Stage',
  String deleteMessage = 'Delete {name}?',
  String deleteConfirm = 'Delete',
  String deleteCancel = 'Cancel',
}) async {
  final result = await showMenu<String>(
    context: context,
    position: position,
    color: AppColors.cardBackground,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.radiusDialog,
      side: BorderSide(color: AppColors.border),
    ),
    items: [
      PopupMenuItem(
        value: 'rename',
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        height: 28,
        child: Row(
          children: [
            Icon(Icons.edit, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              renameLabel,
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
      if (includeBackground)
        PopupMenuItem(
          value: 'background',
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          height: 28,
          child: Row(
            children: [
              Icon(Icons.image, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                selectBackgroundLabel,
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      if (stage.sessionIds.isNotEmpty && onEditSession != null)
        PopupMenuItem(
          value: 'edit_session',
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          height: 28,
          child: Row(
            children: [
              Icon(Icons.settings, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                editSessionLabel,
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      if (stage.sessionIds.isNotEmpty)
        PopupMenuItem(
          value: 'close_session',
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          height: 28,
          child: Row(
            children: [
              Icon(Icons.close, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                closeSessionLabel,
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      if (appState.terminalStages.length > 1)
        PopupMenuItem(
          value: 'delete',
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          height: 28,
          child: Row(
            children: [
              Icon(Icons.delete, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Text(
                deleteLabel,
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
          ),
        ),
    ],
  );

  switch (result) {
    case 'rename':
      if (!context.mounted) return;
      final name = await showInputDialog(
        context,
        title: renameTitle,
        initialValue: stage.name,
        confirmText: renameConfirm,
        cancelText: renameCancel,
      );
      if (name != null && name.trim().isNotEmpty) {
        appState.renameStage(stage.id, name.trim());
      }
    case 'background':
      onBackgroundTap?.call();
    case 'edit_session':
      onEditSession?.call();
    case 'close_session':
      for (final sid in stage.sessionIds) {
        if (appState.sessions.any((s) => s.id == sid)) {
          appState.closeSession(sid);
          break;
        }
      }
    case 'delete':
      if (!context.mounted) return;
      // 空白 stage（无活跃 session）直接删除，不弹确认框
      final hasActiveSession = stage.sessionIds.any(
        (sid) => appState.sessions.any((s) => s.id == sid),
      );
      if (hasActiveSession) {
        final message = deleteMessage.replaceAll('{name}', stage.name);
        final confirmed = await showConfirmDialog(
          context,
          title: deleteTitle,
          message: message,
          confirmText: deleteConfirm,
          cancelText: deleteCancel,
          destructive: true,
        );
        if (confirmed != true) return;
      }
      if (context.mounted) {
        appState.removeStageById(stage.id);
      }
  }
}

