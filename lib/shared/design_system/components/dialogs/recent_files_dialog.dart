import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_text_styles.dart';
import '../buttons/app_buttons.dart';

class VisitedFileDisplayData {
  const VisitedFileDisplayData({
    required this.displayName,
    required this.filePath,
    required this.lastVisitedAt,
    this.fileSize,
    this.hostLabel,
    this.isLocal = false,
    this.icon,
  });

  final String displayName;
  final String filePath;
  final DateTime lastVisitedAt;
  final int? fileSize;
  final String? hostLabel;
  final bool isLocal;
  final Widget? icon;
}

class RecentFilesDialog extends StatelessWidget {
  const RecentFilesDialog({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.files,
    required this.onOpenFile,
    this.onDeleteFile,
    this.onClearAll,
    this.closeLabel = 'Close',
    this.deleteConfirmLabel,
    this.clearAllLabel,
    this.clearAllConfirmLabel,
    this.clearAllCancelLabel,
  });

  final String title;
  final String emptyLabel;
  final List<VisitedFileDisplayData> files;
  final void Function(VisitedFileDisplayData file) onOpenFile;
  final void Function(VisitedFileDisplayData file)? onDeleteFile;
  final VoidCallback? onClearAll;
  final String closeLabel;
  final String? deleteConfirmLabel;
  final String? clearAllLabel;
  final String? clearAllConfirmLabel;
  final String? clearAllCancelLabel;

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = onDeleteFile != null || onClearAll != null;
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
      title: Row(
        children: [
          Expanded(child: Text(title, style: AppTextStyles.h4)),
          if (canEdit && files.isNotEmpty)
            GestureDetector(
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.cardBackground,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
                    title: Text(
                      clearAllConfirmLabel ?? 'Clear all?',
                      style: AppTextStyles.h4,
                    ),
                    content: Text(
                      clearAllLabel ?? 'This will remove all recent visited files.',
                      style: AppTextStyles.body,
                    ),
                    actions: [
                      AppTextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        label: clearAllCancelLabel ?? 'Cancel',
                        size: ButtonSize.small,
                      ),
                      PrimaryButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        label: clearAllConfirmLabel ?? 'Clear All',
                        size: ButtonSize.small,
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  onClearAll?.call();
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_sweep, size: 14, color: AppColors.error),
                    const SizedBox(width: 4),
                    Text(
                      clearAllLabel ?? 'Clear All',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: files.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: AppColors.textSecondary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      emptyLabel,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (_, index) => _FileEntryCard(
                  file: files[index],
                  formattedTime: _formatTime(files[index].lastVisitedAt),
                  fileSizeText: _formatFileSize(files[index].fileSize),
                  showDelete: onDeleteFile != null,
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenFile(files[index]);
                  },
                  onDelete: onDeleteFile != null
                      ? () => onDeleteFile!(files[index])
                      : null,
                ),
              ),
      ),
      actions: [
        SecondaryButton(
          onPressed: () => Navigator.of(context).pop(),
          label: closeLabel,
          size: ButtonSize.medium,
        ),
      ],
    );
  }
}

class _FileEntryCard extends StatelessWidget {
  const _FileEntryCard({
    required this.file,
    required this.formattedTime,
    required this.fileSizeText,
    required this.showDelete,
    required this.onTap,
    this.onDelete,
  });

  final VisitedFileDisplayData file;
  final String formattedTime;
  final String fileSizeText;
  final bool showDelete;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final hasDelete = showDelete && onDelete != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.backgroundGrey,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: file.icon ?? Icon(
                    Icons.insert_drive_file,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              file.filePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 11,
                            color: AppColors.textSecondary.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            formattedTime,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary.withValues(alpha: 0.6),
                            ),
                          ),
                          if (fileSizeText.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.storage,
                              size: 11,
                              color: AppColors.textSecondary.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              fileSizeText,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (file.icon == null)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: null,
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: file.isLocal
                        ? AppColors.accent.withValues(alpha: 0.1)
                        : AppColors.textSecondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    file.isLocal ? 'Local' : (file.hostLabel ?? 'SSH'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: file.isLocal
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (hasDelete) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

