import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:safe_layout_x/safe_layout_x.dart';

import '../common/shortcut_key_names.dart';
import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/utils/secret_encryption.dart';
import '../../models/file_node.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../state/terminal_app_state.dart';
import '../../state/terminal_app_state_models.dart';
import '../common/compact_more_menu_button.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';
import '../common/vscode_action_icons.dart';
import '../file_viewer/file_viewer_engine.dart';
import '../file_viewer/file_open_controller.dart';
import '../file_viewer/terminal_file_viewer_page.dart';

part 'terminal_dialogs_settings.dart';
part 'terminal_dialogs_settings_shortcuts.dart';
part 'terminal_dialogs_settings_widgets.dart';
part 'terminal_dialogs_host.dart';
part 'terminal_dialogs_quick_connect.dart';
part 'terminal_dialogs_session.dart';
part 'terminal_dialogs_settings_base.dart';

enum _FileAction { download, rename, delete }

enum _FilesAction { download, delete }

class _HostKeyDecision {
  const _HostKeyDecision({required this.trust, required this.remember});

  final bool trust;
  final bool remember;
}

Future<void> showAddTextDialog(
  BuildContext context,
  String title,
  String hint,
  ValueChanged<String> onSubmit,
) async {
  final result = await showInputDialog(
    context,
    title: title,
    hint: hint,
    confirmText: t(context, AppStrings.values.save),
    cancelText: t(context, AppStrings.values.cancel),
    validator: (v) =>
        (v == null || v.trim().isEmpty) ? ' ' : null,
  );
  if (result != null && result.trim().isNotEmpty) {
    onSubmit(result.trim());
  }
}

Future<InternalViewerPreparationResult?>
_prepareVisitedRemoteWithProgressDialog(
  BuildContext context,
  TerminalAppState appState,
  HostEntry host,
  FileNode node, {
  int? maxBytes,
}) async {
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  if (!rootNavigator.mounted) {
    return null;
  }
  final progress = ValueNotifier<_VisitedFileLoadProgress>(
    _VisitedFileLoadProgress(downloadedBytes: 0, totalBytes: node.size),
  );
  final prepareFuture = appState
      .prepareRemoteFileForInternalViewerByHostDetailed(
        host,
        node,
        maxBytes: maxBytes,
        onProgress: (downloadedBytes, totalBytes) {
          final current = progress.value;
          if (current.downloadedBytes == downloadedBytes &&
              current.totalBytes == totalBytes) {
            return;
          }
          progress.value = _VisitedFileLoadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          );
        },
      );
  final dialogContextCompleter = Completer<BuildContext>();
  final dialogFuture = showDialog<void>(
    context: rootNavigator.context,
    barrierDismissible: false,
    builder: (dialogContext) {
      if (!dialogContextCompleter.isCompleted) {
        dialogContextCompleter.complete(dialogContext);
      }
      return _VisitedFileLoadingDialog(
        appState: appState,
        fileName: node.name,
        progress: progress,
      );
    },
  );
  unawaited(() async {
    final dialogContext = await dialogContextCompleter.future;
    await prepareFuture;
    if (dialogContext.mounted && rootNavigator.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }());
  try {
    await dialogFuture;
  } finally {
    progress.dispose();
  }
  return await prepareFuture;
}

Future<void> openVisitedFileEntry(
  BuildContext context,
  TerminalAppState appState,
  VisitedFileEntry entry,
) async {
  void notifyOpenFailure({
    required BannerType type,
    required String message,
    TerminalLogLevel level = TerminalLogLevel.error,
  }) {
    showBannerAndLog(
      appState,
      BannerData(
        id: 'open-visited-${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        title: t(context, AppStrings.values.logs),
        message: message,
      ),
    );
    appState.addStructuredLog(
      category: TerminalLogCategory.system,
      level: level,
      message: message,
    );
  }

  try {
    final node = FileNode.file(
      entry.displayName.trim().isEmpty
          ? p.basename(entry.filePath)
          : entry.displayName,
      entry.filePath,
      size: entry.fileSize,
      modified: entry.fileModifiedAt,
    );
    final kind = InternalFileViewerEngine.detect(node.name);
    if (kind == InternalFileViewerKind.unsupported) {
      return;
    }
    const maxTextStreamPreviewBytes = 8 * 1024 * 1024;
    final isTextPreview = kind == InternalFileViewerKind.text;

    if (entry.isLocal) {
      TerminalSession? session;
      for (final item in appState.sessions.reversed) {
        if (item.profile.isLocal) {
          session = item;
          break;
        }
      }
      if (session == null) {
        notifyOpenFailure(
          type: BannerType.warning,
          level: TerminalLogLevel.warn,
          message: t(context, AppStrings.values.visitedFileLocalSessionMissing),
        );
        return;
      }
      await openFileNodeWithViewer(context, appState, session, node);
      return;
    }

    final host = appState.resolveHostForVisitedFile(entry);
    if (host == null) {
      notifyOpenFailure(
        type: BannerType.warning,
        level: TerminalLogLevel.warn,
        message: t(context, AppStrings.values.visitedFileHostNotFound),
      );
      return;
    }
    final preparedWithProgress = await _prepareVisitedRemoteWithProgressDialog(
      context,
      appState,
      host,
      node,
      maxBytes: isTextPreview ? maxTextStreamPreviewBytes : null,
    );
    if (!context.mounted) return;
    final localPath = preparedWithProgress?.localPath;
    if (localPath == null || localPath.isEmpty) {
      notifyOpenFailure(
        type: BannerType.error,
        message: t(
          context,
          AppStrings.values.visitedFileDownloadOrConnectFailed,
        ),
      );
      return;
    }
    final viewerKey = appState.internalViewerScrollKeyForHostAndNode(
      host,
      node,
      maxBytes: isTextPreview ? maxTextStreamPreviewBytes : null,
    );
    // Find a matching session for saving support
    TerminalSession? visitedSession;
    for (final item in appState.sessions.reversed) {
      if (!item.profile.isLocal && item.profile.id == entry.hostId) {
        visitedSession = item;
        break;
      }
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalFileViewerPage(
          filePath: localPath,
          displayName: node.name,
          kind: kind,
          viewerKey: viewerKey,
          textPreviewTruncated: preparedWithProgress?.truncated ?? false,
          textPreviewMaxBytes: isTextPreview ? maxTextStreamPreviewBytes : 0,
          onSaveText: visitedSession != null && kind == InternalFileViewerKind.text
              ? (content) => appState.saveEditableFileText(visitedSession!, node, content)
              : null,
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    final message = t(
      context,
      AppStrings.values.visitedFileOpenFailedVar,
      params: {'error': '$error'},
    );
    notifyOpenFailure(type: BannerType.error, message: message);
  }
}

String _formatRecentHostTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

Future<void> showRecentHostsDialog(
  BuildContext context,
  TerminalAppState appState,
) async {
  final recentHosts = appState.recentHosts(limit: 40);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(t(context, AppStrings.values.recentSessions)),
        content: SizedBox(
          width: 720,
          child: recentHosts.isEmpty
              ? Center(
                  child: Text(
                    t(context, AppStrings.values.noSessions),
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: recentHosts.length,
                  itemBuilder: (_, index) {
                    final host = recentHosts[index];
                    final subtitle =
                        _formatRecentHostTime(host.lastConnected!);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: AppRadius.radiusLG,
                        color: AppColors.backgroundGrey,
                      ),
                      child: ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(
                          horizontal: 0,
                          vertical: -2,
                        ),
                        title: Text(
                          host.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall,
                        ),
                        subtitle: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                        trailing: Icon(
                          appState.hostSessionStatus(host.id) ==
                                  TerminalStatus.connected
                              ? Icons.circle
                              : Icons.open_in_new,
                          size: 14,
                          color:
                              appState.hostSessionStatus(host.id) ==
                                      TerminalStatus.connected
                                  ? AppColors.success
                                  : null,
                        ),
                        onTap: () async {
                          Navigator.of(dialogContext).pop();
                          if (!context.mounted) return;
                          await appState.connectToHost(host);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          SecondaryButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: t(context, AppStrings.values.close),
            size: ButtonSize.medium,
          ),
        ],
      );
    },
  );
}



