import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart' hide formatBytes;
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';
import '../../models/transfer_task.dart';
import '../../models/file_node.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_formatters.dart';
import '../file_tree/file_icon_resolver.dart';
import '../dialogs/terminal_dialogs.dart' show openVisitedFileEntry;
import 'modal_panel_base.dart';

/// 传输状态模态面板
class TransferModalPanel extends StatelessWidget {
  const TransferModalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context);

    return ModalPanelBase(
      title: l(appState, AppStrings.values.transfers),
      width: 750,
      height: 550,
      child: Column(
        children: [
          Expanded(child: _buildTransferList(context, appState)),
          _buildFooter(context, appState),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, TerminalAppState appState) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          PrimaryButton(
            onPressed: () async {
              final timestamp = DateTime.now().microsecondsSinceEpoch;
              final title = t(
                context,
                AppStrings.values.startupSectionCacheCleanup,
              );
              try {
                final result = await appState.clearFilePreviewCache();
                if (!context.mounted) return;
                final message = t(
                  context,
                  AppStrings.values.filePreviewCacheClearedVarVar,
                  params: {
                    'deleted': '${result.deleted}',
                    'failed': '${result.failed}',
                  },
                );
                showBannerAndLog(
                  appState,
                  BannerData(
                    id: 'cache-cleanup-$timestamp',
                    type: result.failed == 0
                        ? BannerType.success
                        : BannerType.warning,
                    title: title,
                    message: message,
                  ),
                );
                appState.addStructuredLog(
                  category: TerminalLogCategory.system,
                  message: '$title: $message',
                );
              } catch (error) {
                if (!context.mounted) return;
                final message = '$error';
                showBannerAndLog(
                  appState,
                  BannerData(
                    id: 'cache-cleanup-$timestamp',
                    type: BannerType.error,
                    title: title,
                    message: message,
                  ),
                );
                appState.addStructuredLog(
                  category: TerminalLogCategory.system,
                  message: '$title: $message',
                );
              }
            },
            icon: Icons.cleaning_services_outlined,
            label: t(context, AppStrings.values.clearFilePreviewCache),
            size: ButtonSize.small,
          ),
          const SizedBox(width: 12),
          const Spacer(),
          Text(
            t(context, AppStrings.values.recentVisitedFiles),
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          SecondaryButton(
            onPressed: () {
              final recentFiles = appState.recentVisitedFiles(limit: 60);
              showDialog<void>(
                context: context,
                builder: (_) => RecentFilesDialog(
                  title: t(context, AppStrings.values.recentVisitedFiles),
                  emptyLabel: t(context, AppStrings.values.noRecentVisitedFiles),
                  closeLabel: t(context, AppStrings.values.close),
                  clearAllLabel: t(context, AppStrings.values.clearVisitedFiles),
                  clearAllConfirmLabel: t(context, AppStrings.values.clearVisitedFilesConfirm),
                  clearAllCancelLabel: t(context, AppStrings.values.cancel),
                  files: recentFiles.map((e) {
                    final node = FileNode.file(
                      e.displayName,
                      e.filePath,
                      size: e.fileSize,
                      modified: e.fileModifiedAt,
                    );
                    final iconStyle = FileIconResolver.resolve(node);
                    final iconWidget = iconStyle.svgAssetPath != null
                        ? SvgPicture.asset(
                            iconStyle.svgAssetPath!,
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                          )
                        : Icon(iconStyle.icon, size: 18, color: iconStyle.color);
                    return VisitedFileDisplayData(
                      displayName: e.displayName,
                      filePath: e.filePath,
                      lastVisitedAt: e.lastVisitedAt,
                      fileSize: e.fileSize,
                      hostLabel: e.host,
                      isLocal: e.isLocal,
                      icon: iconWidget,
                    );
                  }).toList(),
                  onOpenFile: (data) {
                    final idx = recentFiles.indexWhere((e) =>
                        e.filePath == data.filePath &&
                        e.lastVisitedAt == data.lastVisitedAt);
                    if (idx >= 0) {
                      openVisitedFileEntry(context, appState, recentFiles[idx]);
                    }
                  },
                  onDeleteFile: (data) {
                    final idx = recentFiles.indexWhere((e) =>
                        e.filePath == data.filePath &&
                        e.lastVisitedAt == data.lastVisitedAt);
                    if (idx >= 0) {
                      appState.removeVisitedFile(recentFiles[idx]);
                    }
                  },
                  onClearAll: () => appState.clearVisitedFiles(),
                ),
              );
            },
            label: t(context, AppStrings.values.quickJump),
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  Widget _buildTransferList(BuildContext context, TerminalAppState appState) {
    final allTransfers = <TransferTask>[];
    for (final session in appState.sessions) {
      allTransfers.addAll(session.transferQueue);
    }

    if (allTransfers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_done,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l(appState, AppStrings.values.noActiveTransfers),
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: allTransfers.length,
      itemBuilder: (context, index) {
        final task = allTransfers[index];
        return _buildTransferItem(context, appState, task);
      },
    );
  }

  Widget _buildTransferItem(
    BuildContext context,
    TerminalAppState appState,
    TransferTask task,
  ) {
    final statusIcon = switch (task.status) {
      TransferStatus.queued => Icons.schedule,
      TransferStatus.running => Icons.sync,
      TransferStatus.completed => Icons.check_circle,
      TransferStatus.failed => Icons.error,
      TransferStatus.paused => Icons.pause,
      TransferStatus.canceled => Icons.cancel,
    };

    final statusColor = switch (task.status) {
      TransferStatus.queued => AppColors.textSecondary,
      TransferStatus.running => AppColors.primary,
      TransferStatus.completed => AppColors.success,
      TransferStatus.failed => AppColors.error,
      TransferStatus.paused => AppColors.textTertiary,
      TransferStatus.canceled => AppColors.textTertiary,
    };

    final transferred = (task.size * task.progress).toInt();

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(
          task.name,
          style: AppTextStyles.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${formatBytes(transferred)} / ${formatBytes(task.size)}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            ),
            if (task.status == TransferStatus.running)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
          ],
        ),
        trailing: task.status == TransferStatus.running
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  // TODO: Cancel transfer
                },
              )
            : null,
      ),
    );
  }

  /// 显示传输面板
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (context) => const TransferModalPanel(),
    );
  }
}

