import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:super_native_extensions/raw_clipboard.dart';

import '../../../../shared/constants/app_string.dart';
import '../../models/file_node.dart';
import '../../models/terminal_session.dart';
import '../../models/transfer_task.dart';
import '../control/cancellation_token.dart';
import '../facade/transfer_facade.dart';
import '../../../../shared/logging/Polarmote_log.dart';

typedef QueueTransferTaskRunner =
    Future<void> Function(
      TerminalSession session, {
      required String batchId,
      required String name,
      required TransferDirection direction,
      String? sourcePath,
      String? destinationPath,
      int size,
      bool priority,
      void Function(String taskId)? onTaskCreated,
      required Future<void> Function(String taskId) run,
    });

typedef StartTransferBatchRunner =
    void Function(
      TerminalSession session,
      int total, {
      required String batchId,
    });

class UploadDownloadFlowEngine {
  const UploadDownloadFlowEngine({
    required this.languageCode,
    required this.createTransferFacade,
    required this.cancellationTokenForTask,
    required this.registerTaskCancelCleanup,
    required this.queueTransferTask,
    required this.startTransferBatch,
    required this.updateTransfer,
    required this.findTransferTask,
    required this.finishTransfer,
    required this.markCancelledIfNeeded,
    required this.ensureNotCancelled,
    required this.nextTransferId,
    required this.resolveDesktopDirectory,
  });

  static final _random = Random();

  final String languageCode;
  final TransferFacade Function(
    TerminalSession session, {
    required TransferDirection direction,
  })
  createTransferFacade;
  final CancellationToken Function(TerminalSession session, String taskId)
  cancellationTokenForTask;
  final void Function(
    TerminalSession session,
    String taskId,
    Future<void> Function() cleanup,
  )
  registerTaskCancelCleanup;
  final QueueTransferTaskRunner queueTransferTask;
  final StartTransferBatchRunner startTransferBatch;
  final void Function(
    TerminalSession session,
    String id,
    double progress, {
    TransferStatus? status,
    int? size,
  })
  updateTransfer;
  final TransferTask? Function(TerminalSession session, String id)
  findTransferTask;
  final void Function(TerminalSession session, String id) finishTransfer;
  final void Function(TerminalSession session, String id) markCancelledIfNeeded;
  final void Function(TerminalSession session, String taskId)
  ensureNotCancelled;
  final String Function(String prefix) nextTransferId;
  final Future<Directory> Function() resolveDesktopDirectory;

  static const String _localTransferTempRootName = 'Polarmote-transfer-temp';

  Future<void> uploadFiles(
    TerminalSession session,
    List<String> localPaths,
    String remoteDir,
  ) async {
    final sanitized = _sanitizeLocalPaths(localPaths);
    if (sanitized.isEmpty) return;

    final facade = createTransferFacade(
      session,
      direction: TransferDirection.upload,
    );
    final queueFutures = <Future<void>>[];
    for (final localPath in sanitized) {
      final itemName = p.basename(localPath.trim());
      final batchId = nextTransferId('batch-up');
      startTransferBatch(session, 1, batchId: batchId);
      queueFutures.add(
        queueTransferTask(
          session,
          batchId: batchId,
          name: itemName.isEmpty ? localPath : itemName,
          direction: TransferDirection.upload,
          sourcePath: localPath,
          destinationPath: remoteDir,
          priority: false,
          run: (taskId) async {
            final token = cancellationTokenForTask(session, taskId);
            _markTaskRunning(session, taskId);
            final size = await facade.uploadBatch(
              localPaths: [localPath],
              remoteDir: remoteDir,
              cancellationToken: token,
              onProgress: (fraction) =>
                  updateTransfer(session, taskId, fraction),
              onChunk: (_) => ensureNotCancelled(session, taskId),
            );
            updateTransfer(session, taskId, 1, size: size);
            finishTransfer(session, taskId);
          },
        ),
      );
    }
    await Future.wait(queueFutures);
  }

  Future<void> downloadFiles(
    TerminalSession session,
    List<String> remotePaths,
    String localDir, {
    bool cleanupLocalDirOnCancel = false,
  }) async {
    final sanitized = remotePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (sanitized.isEmpty) return;

    final facade = createTransferFacade(
      session,
      direction: TransferDirection.download,
    );
    final batchId = nextTransferId('batch-down');
    startTransferBatch(session, 1, batchId: batchId);

    await queueTransferTask(
      session,
      batchId: batchId,
      name: _batchDisplayName(
        sanitized,
        fallback: AppStrings.values.transfers.resolve(languageCode),
      ),
      direction: TransferDirection.download,
      sourcePath: _compactPathList(sanitized),
      destinationPath: localDir,
      priority: false,
      onTaskCreated: cleanupLocalDirOnCancel
          ? (taskId) {
              registerTaskCancelCleanup(
                session,
                taskId,
                () => cleanupDragFolder(localDir),
              );
            }
          : null,
      run: (taskId) async {
        final token = cancellationTokenForTask(session, taskId);
        _markTaskRunning(session, taskId);
        final size = await facade.downloadBatch(
          remotePaths: sanitized,
          localDir: localDir,
          cancellationToken: token,
          onProgress: (fraction) => updateTransfer(session, taskId, fraction),
          onChunk: (_) => ensureNotCancelled(session, taskId),
        );
        updateTransfer(session, taskId, 1, size: size);
        finishTransfer(session, taskId);
      },
    );
  }

  Future<void> streamRemoteForDrag({
    required TerminalSession session,
    required FileNode node,
    required VirtualFileEventSinkProvider sinkProvider,
    required WriteProgress progress,
  }) async {
    if (node.isDirectory) {
      await _streamRemoteDirectoryAsZip(
        session: session,
        remotePath: node.path,
        displayName: node.name,
        sinkProvider: sinkProvider,
        progress: progress,
      );
    } else {
      await _streamRemoteFile(
        session: session,
        remotePath: node.path,
        displayName: node.name,
        sinkProvider: sinkProvider,
        progress: progress,
      );
    }
  }

  Future<String> prepareFolderDragDirectory(String folderName) async {
    return prepareDesktopDropFolder(folderName);
  }

  Future<String> _dragTempDir() async {
    final dir = Directory(
      p.join(Directory.systemTemp.path, _localTransferTempRootName),
    );
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> prepareDesktopDropFolder(String folderName) async {
    final temp = await _dragTempDir();
    final uuid = _uuidV4();
    final target = p.join(temp, '$uuid-$folderName');
    await Directory(target).create(recursive: true);
    return target;
  }

  Future<String> prepareDesktopDropFile(String fileName) async {
    final temp = await _dragTempDir();
    final uuid = _uuidV4();
    final ext = p.extension(fileName);
    final stem = p.basenameWithoutExtension(fileName);
    final target = p.join(temp, '$stem-$uuid$ext');
    await File(target).create(recursive: true);
    return target;
  }

  Future<String> prepareDesktopDropDirectoryBundle(String folderName) async {
    final temp = await _dragTempDir();
    final uuid = _uuidV4();
    final target = p.join(temp, '$folderName-$uuid');
    await Directory(target).create(recursive: true);
    return target;
  }

  String _uuidV4() {
    // dart:math Random-based UUID v4. Good enough for temp file names.
    final r = _random;
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    return [
      bytes.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      bytes.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      bytes.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      bytes.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      bytes.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ].join('-');
  }

  Future<void> cleanupDragFolder(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) { PolarmoteLog.error('upload_download_flow_engine', '$e'); }
  }

  Future<void> cleanupDragFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) { PolarmoteLog.error('upload_download_flow_engine', '$e'); }
  }

  Future<void> downloadSelectionToLocal(
    TerminalSession session,
    List<FileNode> nodes,
    String localDir,
  ) async {
    final paths = nodes.map((node) => node.path).toList(growable: false);
    await downloadFiles(
      session,
      paths,
      localDir,
      cleanupLocalDirOnCancel: true,
    );
  }

  Future<void> downloadFileToLocal(
    TerminalSession session,
    String remotePath,
    String localPath, {
    String? displayName,
  }) async {
    final facade = createTransferFacade(
      session,
      direction: TransferDirection.download,
    );
    final batchId = nextTransferId('batch-down');
    startTransferBatch(session, 1, batchId: batchId);
    await queueTransferTask(
      session,
      batchId: batchId,
      name: displayName ?? p.basename(remotePath),
      direction: TransferDirection.download,
      sourcePath: remotePath,
      destinationPath: localPath,
      priority: true,
      onTaskCreated: (taskId) {
        registerTaskCancelCleanup(
          session,
          taskId,
          () => cleanupDragFile(localPath),
        );
      },
      run: (taskId) async {
        final token = cancellationTokenForTask(session, taskId);
        _markTaskRunning(session, taskId);
        final size = await facade.downloadFile(
          remotePath: remotePath,
          localPath: localPath,
          cancellationToken: token,
          onProgress: (fraction) => updateTransfer(session, taskId, fraction),
          onChunk: (_) => ensureNotCancelled(session, taskId),
        );
        updateTransfer(session, taskId, 1, size: size);
        finishTransfer(session, taskId);
      },
    );
  }

  Future<void> downloadDirectoryToLocal(
    TerminalSession session,
    String remotePath,
    String localDir,
  ) {
    return downloadFiles(
      session,
      [remotePath],
      localDir,
      cleanupLocalDirOnCancel: true,
    );
  }

  List<String> _sanitizeLocalPaths(List<String> localPaths) {
    final sanitized =
        localPaths
            .map((path) => path.trim())
            .where(
              (path) =>
                  path.isNotEmpty &&
                  !path.contains('*') &&
                  !path.contains('?') &&
                  !p.split(path).contains('..'),
            )
            .toSet()
            .toList(growable: false)
          ..sort((a, b) => b.length.compareTo(a.length));

    final compacted = <String>[];
    bool isSameOrChild(String path, String parentPath) {
      var normalizedPath = path.replaceAll('\\', '/');
      var normalizedParent = parentPath.replaceAll('\\', '/');
      if (Platform.isWindows) {
        normalizedPath = normalizedPath.toLowerCase();
        normalizedParent = normalizedParent.toLowerCase();
      }
      if (normalizedPath == normalizedParent) return true;
      return normalizedPath.startsWith('$normalizedParent/');
    }

    for (final path in sanitized) {
      final parentCovered = compacted.any(
        (existing) => isSameOrChild(existing, path),
      );
      if (!parentCovered) {
        compacted.add(path);
      }
    }
    return compacted;
  }

  String _batchDisplayName(List<String> paths, {required String fallback}) {
    if (paths.isEmpty) {
      return fallback;
    }
    final names = paths
        .map((value) => p.basename(value.trim()))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) {
      return fallback;
    }
    final first = names.first;
    final extra = names.length - 1;
    if (extra <= 0) {
      return first;
    }
    if (languageCode == 'en') {
      return '$first (+$extra)';
    }
    return '$first（+$extra）';
  }

  String _compactPathList(List<String> paths) {
    if (paths.isEmpty) {
      return '';
    }
    final normalized = paths
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return '';
    }
    final first = normalized.first;
    if (normalized.length == 1) {
      return first;
    }
    return '$first (+${normalized.length - 1})';
  }

  void _markTaskRunning(TerminalSession session, String taskId) {
    final current = findTransferTask(session, taskId);
    final progress = (current?.progress ?? 0).clamp(0.0, 1.0).toDouble();
    updateTransfer(session, taskId, progress, status: TransferStatus.running);
  }

  Future<Directory> _ensureLocalTransferTempRoot() async {
    final root = Directory(
      p.join(Directory.systemTemp.path, _localTransferTempRootName),
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> _createManagedLocalTempDir(String prefix) async {
    final root = await _ensureLocalTransferTempRoot();
    return Directory(
      p.join(root.path, '$prefix-${DateTime.now().millisecondsSinceEpoch}'),
    )..createSync(recursive: true);
  }

  Future<void> _streamRemoteFile({
    required TerminalSession session,
    required String remotePath,
    required String displayName,
    required VirtualFileEventSinkProvider sinkProvider,
    required WriteProgress progress,
  }) async {
    final facade = createTransferFacade(
      session,
      direction: TransferDirection.download,
    );
    final batchId = nextTransferId('batch-down');
    startTransferBatch(session, 1, batchId: batchId);
    await queueTransferTask(
      session,
      batchId: batchId,
      name: displayName,
      direction: TransferDirection.download,
      sourcePath: remotePath,
      destinationPath: '<drag-stream>',
      priority: true,
      run: (taskId) async {
        final token = cancellationTokenForTask(session, taskId);
        _markTaskRunning(session, taskId);
        final (stream, size) = await facade.openDownloadStream(
          remotePath: remotePath,
          cancellationToken: token,
          onProgress: (fraction) => updateTransfer(session, taskId, fraction),
          onChunk: (_) => ensureNotCancelled(session, taskId),
        );
        updateTransfer(session, taskId, 0, size: size);
        final sink = sinkProvider(fileSize: size);
        try {
          await for (final chunk in stream) {
            ensureNotCancelled(session, taskId);
            sink.add(chunk);
            final current = findTransferTask(session, taskId);
            if (current != null) {
              progress.updateProgress(current.progress);
            }
          }
        } finally {
          await Future.sync(() => sink.close());
        }
        finishTransfer(session, taskId);
      },
    );
  }

  Future<void> _streamRemoteDirectoryAsZip({
    required TerminalSession session,
    required String remotePath,
    required String displayName,
    required VirtualFileEventSinkProvider sinkProvider,
    required WriteProgress progress,
  }) async {
    final facade = createTransferFacade(
      session,
      direction: TransferDirection.download,
    );
    final tempDir = await _createManagedLocalTempDir('drag-dir');
    final batchId = nextTransferId('batch-down');
    startTransferBatch(session, 1, batchId: batchId);

    await queueTransferTask(
      session,
      batchId: batchId,
      name: '$displayName.zip',
      direction: TransferDirection.download,
      sourcePath: remotePath,
      destinationPath: '<drag-stream>',
      priority: true,
      run: (taskId) async {
        final token = cancellationTokenForTask(session, taskId);
        _markTaskRunning(session, taskId);
        await facade.downloadBatch(
          remotePaths: [remotePath],
          localDir: tempDir.path,
          cancellationToken: token,
          onProgress: (fraction) => updateTransfer(
            session,
            taskId,
            (fraction * 0.85).clamp(0.0, 0.85),
          ),
          onChunk: (_) => ensureNotCancelled(session, taskId),
        );

        final folderName = p.basename(remotePath.replaceAll('\\', '/'));
        final downloadedRoot = Directory(p.join(tempDir.path, folderName));
        final zipSource = await downloadedRoot.exists()
            ? downloadedRoot
            : tempDir;
        final zipPath = p.join(tempDir.path, '$displayName.zip');

        final encoder = ZipFileEncoder();
        encoder.create(zipPath);
        encoder.addDirectory(zipSource, includeDirName: true);
        encoder.close();

        final zipFile = File(zipPath);
        final zipSize = await zipFile.length();
        final sink = sinkProvider(fileSize: zipSize);
        var sent = 0;
        try {
          await for (final chunk in zipFile.openRead()) {
            ensureNotCancelled(session, taskId);
            sink.add(chunk);
            sent += chunk.length;
            final packFraction = zipSize <= 0
                ? 1.0
                : (sent / zipSize).clamp(0.0, 1.0);
            final merged = 0.85 + (packFraction * 0.15);
            updateTransfer(session, taskId, merged.clamp(0.0, 1.0));
            final current = findTransferTask(session, taskId);
            if (current != null) {
              progress.updateProgress(current.progress);
            }
          }
        } finally {
          await Future.sync(() => sink.close());
        }
        updateTransfer(session, taskId, 1, size: zipSize);
        finishTransfer(session, taskId);
      },
    );

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}


