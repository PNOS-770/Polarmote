import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:safe_layout_x/safe_layout_x.dart' show BannerData, BannerType;

import '../../../../shared/constants/app_string.dart';
import '../../models/file_node.dart';
import '../../models/terminal_session.dart';
import '../../state/terminal_app_state.dart';
import '../../state/terminal_app_state_models.dart';
import '../common/terminal_formatters.dart';
import '../common/terminal_localization.dart';
import 'file_viewer_engine.dart';
import 'terminal_file_viewer_page.dart';

const int _maxInternalPreviewBytes = 1000 * 1024 * 1024;
const int _maxTextStreamPreviewBytes = 8 * 1024 * 1024;

Future<void> openFileNodeWithViewer(
  BuildContext context,
  TerminalAppState appState,
  TerminalSession session,
  FileNode node,
) async {
  if (node.isDirectory) {
    await appState.navigateToPath(session, node.path);
    return;
  }

  final kind = InternalFileViewerEngine.detect(node.name);
  if (kind == InternalFileViewerKind.unsupported) {
    await appState.openRemoteFileWithSystem(session, node);
    return;
  }
  appState.recordVisitedFile(session, node);
  final size = node.size;
  if (size != null && size > _maxInternalPreviewBytes) {
    if (session.profile.isLocal) {
      await appState.openRemoteFileWithSystem(session, node);
      return;
    }
    final languageCode = appState.locale.languageCode;
    final limitText = formatBytes(_maxInternalPreviewBytes);
    final actualText = formatBytes(size);
    final message = AppStrings.values.fileTooLargeManualDownloadVarVar.resolve(
      languageCode,
      params: {'limit': limitText, 'actual': actualText},
    );
    showBannerAndLog(
      appState,
      BannerData(
        id: 'manual-download-${DateTime.now().microsecondsSinceEpoch}',
        type: BannerType.warning,
        title: AppStrings.values.fileTooLarge.resolve(languageCode),
        message: message,
      ),
    );
    return;
  }

  if (!context.mounted) {
    return;
  }
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final isTextPreview = kind == InternalFileViewerKind.text;
  final isStreamingPreview =
      kind == InternalFileViewerKind.audio || kind == InternalFileViewerKind.video;
  final viewerKey = appState.internalViewerScrollKeyForNode(
    session,
    node,
    maxBytes: isTextPreview ? _maxTextStreamPreviewBytes : null,
  );
  InternalViewerPreparationResult? prepared;
  InternalViewerStreamPreparationResult? streamPrepared;
  if (session.profile.isLocal) {
    prepared = await appState.prepareFileForInternalViewerDetailed(
      session,
      node,
      maxBytes: isTextPreview ? _maxTextStreamPreviewBytes : null,
    );
  } else if (isStreamingPreview) {
    streamPrepared = await appState.prepareRemoteFileForInternalViewerStreaming(
      session,
      node,
      maxBytes: isTextPreview ? _maxTextStreamPreviewBytes : null,
    );
  } else {
    prepared = await _prepareRemoteFileWithProgress(
      rootNavigator,
      appState,
      session,
      node,
      maxBytes: isTextPreview ? _maxTextStreamPreviewBytes : null,
    );
  }
  final localPath = streamPrepared?.localPath ?? prepared?.localPath;
  if (localPath == null || localPath.isEmpty) return;
  final textPreviewTruncated = prepared?.truncated ?? false;
  if (!context.mounted) {
    if (!session.profile.isLocal) {
      if (streamPrepared != null) {
        streamPrepared.cancel();
      }
    }
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TerminalFileViewerPage(
        filePath: localPath,
        displayName: node.name,
        kind: kind,
        viewerKey: viewerKey,
        textPreviewTruncated: textPreviewTruncated,
        textPreviewMaxBytes: isTextPreview ? _maxTextStreamPreviewBytes : 0,
        downloadProgressStream: streamPrepared?.progressStream,
        onSaveText: kind == InternalFileViewerKind.text
            ? (content) => appState.saveEditableFileText(session, node, content)
            : null,
      ),
    ),
  );
}

Future<InternalViewerPreparationResult?> _prepareRemoteFileWithProgress(
  NavigatorState navigator,
  TerminalAppState appState,
  TerminalSession session,
  FileNode node, {
  int? maxBytes,
}) async {
  if (!navigator.mounted) {
    return null;
  }
  final progress = ValueNotifier<_FilePreviewLoadProgress>(
    _FilePreviewLoadProgress(downloadedBytes: 0, totalBytes: node.size),
  );
  final prepareFuture = appState.prepareFileForInternalViewerDetailed(
    session,
    node,
    onProgress: (downloadedBytes, totalBytes) {
      final current = progress.value;
      if (current.downloadedBytes == downloadedBytes &&
          current.totalBytes == totalBytes) {
        return;
      }
      progress.value = _FilePreviewLoadProgress(
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
      );
    },
    maxBytes: maxBytes,
  );
  final dialogContextCompleter = Completer<BuildContext>();
  final dialogFuture = showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (dialogContext) {
      if (!dialogContextCompleter.isCompleted) {
        dialogContextCompleter.complete(dialogContext);
      }
      return _FilePreviewLoadingDialog(
        appState: appState,
        fileName: node.name,
        progress: progress,
      );
    },
  );
  unawaited(() async {
    final dialogContext = await dialogContextCompleter.future;
    await prepareFuture;
    if (dialogContext.mounted && navigator.mounted) {
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

class _FilePreviewLoadProgress {
  const _FilePreviewLoadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final int downloadedBytes;
  final int? totalBytes;
}

class _FilePreviewLoadingDialog extends StatelessWidget {
  const _FilePreviewLoadingDialog({
    required this.appState,
    required this.fileName,
    required this.progress,
  });

  final TerminalAppState appState;
  final String fileName;
  final ValueListenable<_FilePreviewLoadProgress> progress;

  @override
  Widget build(BuildContext context) {
    final languageCode = appState.locale.languageCode;
    final loadingText = AppStrings.values.loadingFilePreview.resolve(
      languageCode,
    );
    return Dialog(
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: ValueListenableBuilder<_FilePreviewLoadProgress>(
          valueListenable: progress,
          builder: (context, value, _) {
            final totalBytes = value.totalBytes;
            final downloaded = value.downloadedBytes
                .clamp(0, totalBytes ?? value.downloadedBytes)
                .toInt();
            final percent = totalBytes != null && totalBytes > 0
                ? (downloaded / totalBytes).clamp(0.0, 1.0)
                : null;
            final progressLabel = totalBytes != null && totalBytes > 0
                ? '${formatBytes(downloaded)}/${formatBytes(totalBytes)}  ${(percent! * 100).toStringAsFixed(1)}%'
                : formatBytes(downloaded);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loadingText,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE6EAF0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progressLabel,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

