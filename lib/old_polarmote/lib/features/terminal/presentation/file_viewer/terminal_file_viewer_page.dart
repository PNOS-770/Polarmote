import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../state/terminal_app_state_models.dart';
import '../../state/terminal_app_state.dart';
import 'file_viewer_engine.dart';
import 'viewers/audio_file_viewer.dart';
import 'viewers/image_file_viewer.dart';
import 'viewers/pdf_file_viewer.dart';
import 'viewers/text_stream_file_viewer.dart';
import 'viewers/unsupported_file_viewer.dart';
import 'viewers/video_file_viewer.dart';

class TerminalFileViewerPage extends StatelessWidget {
  const TerminalFileViewerPage({
    required this.filePath,
    required this.displayName,
    required this.kind,
    this.viewerKey,
    this.textPreviewTruncated = false,
    this.textPreviewMaxBytes = 0,
    this.downloadProgressStream,
    this.onSaveText,
    super.key,
  });

  final String filePath;
  final String displayName;
  final InternalFileViewerKind kind;
  final String? viewerKey;
  final bool textPreviewTruncated;
  final int textPreviewMaxBytes;
  final Stream<InternalViewerDownloadProgress>? downloadProgressStream;
  final TextSaveCallback? onSaveText;

  Future<void> _openInSystem(BuildContext context) async {
    try {
      await OpenFilex.open(filePath);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Open failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    TerminalAppState? appState;
    try {
      appState = Provider.of<TerminalAppState>(context, listen: false);
    } catch (_) {
      appState = null;
    }

    final sharedProgressStream = downloadProgressStream == null
        ? null
        : (downloadProgressStream!.isBroadcast
              ? downloadProgressStream!
              : downloadProgressStream!.asBroadcastStream());
    final key = viewerKey?.trim() ?? '';
    final initialScrollOffset =
        (appState != null && key.isNotEmpty)
            ? (appState.filePreviewScrollOffsetForKey(key) ?? 0.0)
            : 0.0;
    final int initialPdfPageNumber = initialScrollOffset <= 0
        ? 1
        : initialScrollOffset.round().clamp(1, 1000000).toInt();
    final viewer = switch (kind) {
      InternalFileViewerKind.image => ImageFileViewer(filePath: filePath),
      InternalFileViewerKind.audio => AudioFileViewer(
        filePath: filePath,
        downloadProgressStream: sharedProgressStream,
      ),
      InternalFileViewerKind.video => VideoFileViewer(
        filePath: filePath,
        downloadProgressStream: sharedProgressStream,
        showProgressOverlay: false,
      ),
      InternalFileViewerKind.pdf => PdfFileViewer(
        filePath: filePath,
        initialPageNumber: initialPdfPageNumber,
        onPersistPageNumber: (pageNumber) {
          if (appState == null || key.isEmpty) return;
          appState.setFilePreviewScrollOffsetForKey(
            key,
            pageNumber.toDouble(),
          );
        },
      ),
      InternalFileViewerKind.text => TextStreamFileViewer(
        filePath: filePath,
        truncated: textPreviewTruncated,
        maxPreviewBytes: textPreviewMaxBytes,
        downloadProgressStream: sharedProgressStream,
        onSave: onSaveText,
        initialScrollOffset: initialScrollOffset,
        onPersistScrollOffset: (offset) {
          if (appState == null || key.isEmpty) return;
          appState.setFilePreviewScrollOffsetForKey(key, offset);
        },
      ),
      InternalFileViewerKind.unsupported => const UnsupportedFileViewer(),
    };
    final lightTheme = Theme.of(context).copyWith(
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        secondary: Colors.black,
        surface: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.black,
      ),
      iconTheme: const IconThemeData(color: Colors.black87),
      textTheme: Theme.of(
        context,
      ).textTheme.apply(bodyColor: Colors.black87),
    );
    const scaffoldColor = Colors.white;
    const appBarColor = Colors.white;
    const appBarForeground = Colors.black;
    return Theme(
      data: lightTheme,
      child: Scaffold(
        backgroundColor: scaffoldColor,
        appBar: AppBar(
          backgroundColor: appBarColor,
          foregroundColor: appBarForeground,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (kind == InternalFileViewerKind.video &&
                sharedProgressStream != null)
              _AppBarDownloadProgress(
                stream: sharedProgressStream,
              ),
            IconButton(
              tooltip: 'Open in system',
              onPressed: () => _openInSystem(context),
              icon: const Icon(Icons.open_in_new),
            ),
          ],
        ),
        body: ScrollConfiguration(
          behavior: const _NoAutoScrollbarBehavior(),
          child: viewer,
        ),
      ),
    );
  }
}

class _NoAutoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoAutoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _AppBarDownloadProgress extends StatelessWidget {
  const _AppBarDownloadProgress({required this.stream});

  final Stream<InternalViewerDownloadProgress> stream;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)}MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)}GB';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<InternalViewerDownloadProgress>(
      stream: stream,
      builder: (context, snapshot) {
        final progress = snapshot.data;
        if (progress == null) {
          return const SizedBox.shrink();
        }
        final total = progress.totalBytes;
        final downloaded = progress.downloadedBytes;
        final bytesText = total != null && total > 0
            ? '${_formatBytes(downloaded)}/${_formatBytes(total)}'
            : _formatBytes(downloaded);
        final percent = total != null && total > 0
            ? ' ${(downloaded / total * 100).clamp(0, 100).toStringAsFixed(1)}%'
            : '';
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  progress.done ? 'Downloaded' : 'Downloading',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$bytesText$percent',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
