import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../shared/constants/app_string.dart';
import '../../models/file_node.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../diagnostics/path_error_diagnostics.dart';
import '../terminal_app_state.dart';
import '../terminal_app_state_models.dart';

extension TerminalAppStateExternalEdit on TerminalAppState {
  String internalViewerCacheKeyForHostAndNode(
    HostEntry host,
    FileNode node, {
    int? maxBytes,
  }) {
    return _internalViewerCacheKeyForHost(host, node, maxBytes: maxBytes);
  }

  String internalViewerScrollKeyForHostAndNode(
    HostEntry host,
    FileNode node, {
    int? maxBytes,
  }) {
    return _internalViewerScrollKeyForHost(host, node, maxBytes: maxBytes);
  }

  String internalViewerCacheKeyForNode(
    TerminalSession session,
    FileNode node, {
    int? maxBytes,
  }) {
    return _internalViewerCacheKey(session, node, maxBytes: maxBytes);
  }

  String internalViewerScrollKeyForNode(
    TerminalSession session,
    FileNode node, {
    int? maxBytes,
  }) {
    return _internalViewerScrollKey(session, node, maxBytes: maxBytes);
  }

  Future<String?> loadEditableFileText(
    TerminalSession session,
    FileNode node,
  ) async {
    try {
      final bytes = await _readFileAllBytes(session, node.path);
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } catch (e) {
      final diagnostic = diagnosePathError(e, path: node.path);
      final operation = AppStrings.values.readFile.resolve(locale.languageCode);
      setError(
        formatPathError(
          diagnostic,
          languageCode: locale.languageCode,
          operation: operation,
          path: node.path,
        ),
      );
      return null;
    }
  }

  Future<bool> saveEditableFileText(
    TerminalSession session,
    FileNode node,
    String content,
  ) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(content));
      if (session.profile.isLocal) {
        final file = File(node.path);
        await file.writeAsBytes(bytes, flush: true);
      } else {
        await ensureSftpReady(session);
        final sftp = session.sftp;
        if (sftp == null) {
          setError(AppStrings.values.sftpNotReady.resolve(locale.languageCode));
          return false;
        }
        final file = await sftp.open(
          node.path,
          mode:
              SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        try {
          final stream = Stream<Uint8List>.value(bytes);
          final writer = file.write(stream);
          await writer.done;
        } finally {
          await file.close();
        }
      }
      final currentDir = session.fileState.currentPath.isNotEmpty
          ? session.fileState.currentPath
          : session.fileState.rootPath;
      if (currentDir.isNotEmpty) {
        unawaited(refreshDirectory(session, currentDir));
      }
      return true;
    } catch (e) {
      final diagnostic = diagnosePathError(e, path: node.path);
      final operation = AppStrings.values.saveFile.resolve(locale.languageCode);
      setError(
        formatPathError(
          diagnostic,
          languageCode: locale.languageCode,
          operation: operation,
          path: node.path,
        ),
      );
      return false;
    }
  }

  Future<void> openRemoteFileWithSystem(
    TerminalSession session,
    FileNode node,
  ) async {
    if (session.profile.isLocal) {
      await _openLocalFile(node.path);
      return;
    }
    await ensureSftpReady(session);
    final sftp = session.sftp;
    if (sftp == null) {
      setError(AppStrings.values.sftpNotReady.resolve(locale.languageCode));
      return;
    }
    final dir = await _ensureExternalEditDir();
    final basename = p.basename(node.path);
    final localPath = p.join(
      dir.path,
      '${session.id}-${DateTime.now().microsecondsSinceEpoch}-$basename',
    );
    await _downloadRemoteToLocal(session, node.path, localPath);
    _registerExternalEdit(session.id, node.path, localPath);
    await _openLocalFile(localPath);
  }

  Future<String?> prepareFileForInternalViewer(
    TerminalSession session,
    FileNode node, {
    void Function(int downloadedBytes, int? totalBytes)? onProgress,
  }) async {
    final prepared = await prepareFileForInternalViewerDetailed(
      session,
      node,
      onProgress: onProgress,
    );
    return prepared?.localPath;
  }

  Future<InternalViewerPreparationResult?> prepareFileForInternalViewerDetailed(
    TerminalSession session,
    FileNode node, {
    void Function(int downloadedBytes, int? totalBytes)? onProgress,
    int? maxBytes,
  }) async {
    try {
      if (session.profile.isLocal) {
        final localFile = File(node.path);
        final totalBytes = node.size ?? await localFile.length();
        final hasLimit = maxBytes != null && maxBytes > 0;
        final truncated = hasLimit && totalBytes > maxBytes;
        return InternalViewerPreparationResult(
          localPath: node.path,
          truncated: truncated,
          downloadedBytes: truncated ? maxBytes : totalBytes,
          totalBytes: totalBytes,
        );
      }
      final cacheKey = _internalViewerCacheKey(
        session,
        node,
        maxBytes: maxBytes,
      );
      final cached = await _resolveCachedInternalViewerResult(cacheKey);
      if (cached != null) {
        onProgress?.call(cached.downloadedBytes, cached.totalBytes);
        return cached;
      }
      final dir = await _ensureInternalViewerDir();
      final localPath = _internalViewerCacheFilePath(dir, cacheKey, node.name);
      final diskCached = await _resolveCachedInternalViewerResultFromDisk(
        cacheKey: cacheKey,
        localPath: localPath,
        totalBytes: node.size,
        maxBytes: maxBytes,
      );
      if (diskCached != null) {
        onProgress?.call(diskCached.downloadedBytes, diskCached.totalBytes);
        return diskCached;
      }
      final inFlight = internalViewerPreparingCache[cacheKey];
      if (inFlight != null) {
        final shared = await inFlight;
        if (shared != null) {
          onProgress?.call(shared.downloadedBytes, shared.totalBytes);
        }
        return shared;
      }

      final prepareFuture = () async {
        await ensureSftpReady(session);
        final sftp = session.sftp;
        if (sftp == null) {
          setError(AppStrings.values.sftpNotReady.resolve(locale.languageCode));
          return null;
        }
        await _pruneInternalViewerDir(dir);
        final downloaded = await _downloadRemoteToLocal(
          session,
          node.path,
          localPath,
          expectedSize: node.size,
          onProgress: onProgress,
          maxBytes: maxBytes,
        );
        final prepared = InternalViewerPreparationResult(
          localPath: localPath,
          truncated: downloaded.truncated,
          downloadedBytes: downloaded.downloadedBytes,
          totalBytes: node.size,
        );
        internalViewerPreparedCache[cacheKey] = prepared;
        return prepared;
      }();
      internalViewerPreparingCache[cacheKey] = prepareFuture;
      try {
        return await prepareFuture;
      } finally {
        if (identical(internalViewerPreparingCache[cacheKey], prepareFuture)) {
          internalViewerPreparingCache.remove(cacheKey);
        }
      }
    } catch (error) {
      final diagnostic = diagnosePathError(error, path: node.path);
      final operation = locale.languageCode == 'zh'
          ? '准备文件预览'
          : 'Prepare preview';
      setError(
        formatPathError(
          diagnostic,
          languageCode: locale.languageCode,
          operation: operation,
          path: node.path,
        ),
      );
      return null;
    }
  }

  Future<InternalViewerPreparationResult?>
  prepareRemoteFileForInternalViewerByHostDetailed(
    HostEntry host,
    FileNode node, {
    void Function(int downloadedBytes, int? totalBytes)? onProgress,
    int? maxBytes,
  }) async {
    try {
      if (host.isLocal) {
        final localFile = File(node.path);
        final totalBytes = node.size ?? await localFile.length();
        final hasLimit = maxBytes != null && maxBytes > 0;
        final truncated = hasLimit && totalBytes > maxBytes;
        return InternalViewerPreparationResult(
          localPath: node.path,
          truncated: truncated,
          downloadedBytes: truncated ? maxBytes : totalBytes,
          totalBytes: totalBytes,
        );
      }
      final cacheKey = _internalViewerCacheKeyForHost(
        host,
        node,
        maxBytes: maxBytes,
      );
      final cached = await _resolveCachedInternalViewerResult(cacheKey);
      if (cached != null) {
        onProgress?.call(cached.downloadedBytes, cached.totalBytes);
        return cached;
      }
      final dir = await _ensureInternalViewerDir();
      final localPath = _internalViewerCacheFilePath(dir, cacheKey, node.name);
      final diskCached = await _resolveCachedInternalViewerResultFromDisk(
        cacheKey: cacheKey,
        localPath: localPath,
        totalBytes: node.size,
        maxBytes: maxBytes,
      );
      if (diskCached != null) {
        onProgress?.call(diskCached.downloadedBytes, diskCached.totalBytes);
        return diskCached;
      }
      final inFlight = internalViewerPreparingCache[cacheKey];
      if (inFlight != null) {
        final shared = await inFlight;
        if (shared != null) {
          onProgress?.call(shared.downloadedBytes, shared.totalBytes);
        }
        return shared;
      }

      final prepareFuture = () async {
        await _pruneInternalViewerDir(dir);
        final downloaded = await _downloadRemoteToLocalByHost(
          host,
          node.path,
          localPath,
          expectedSize: node.size,
          onProgress: onProgress,
          maxBytes: maxBytes,
        );
        final prepared = InternalViewerPreparationResult(
          localPath: localPath,
          truncated: downloaded.truncated,
          downloadedBytes: downloaded.downloadedBytes,
          totalBytes: node.size,
        );
        internalViewerPreparedCache[cacheKey] = prepared;
        return prepared;
      }();
      internalViewerPreparingCache[cacheKey] = prepareFuture;
      try {
        return await prepareFuture;
      } finally {
        if (identical(internalViewerPreparingCache[cacheKey], prepareFuture)) {
          internalViewerPreparingCache.remove(cacheKey);
        }
      }
    } catch (error) {
      final diagnostic = diagnosePathError(error, path: node.path);
      final operation = locale.languageCode == 'zh'
          ? '准备文件预览'
          : 'Prepare preview';
      setError(
        formatPathError(
          diagnostic,
          languageCode: locale.languageCode,
          operation: operation,
          path: node.path,
        ),
      );
      return null;
    }
  }

  Future<InternalViewerStreamPreparationResult?>
  prepareRemoteFileForInternalViewerStreaming(
    TerminalSession session,
    FileNode node, {
    int? maxBytes,
  }) async {
    final cacheKey = _internalViewerCacheKey(session, node, maxBytes: maxBytes);
    if (session.profile.isLocal) {
      final prepared = await prepareFileForInternalViewerDetailed(
        session,
        node,
        maxBytes: maxBytes,
      );
      if (prepared == null) {
        return null;
      }
      return _immediateStreamPreparationResult(prepared);
    }
    final cached = await _resolveCachedInternalViewerResult(cacheKey);
    if (cached != null) {
      return _immediateStreamPreparationResult(cached);
    }
    final active = internalViewerStreamingCache[cacheKey];
    if (active != null) {
      return active;
    }
    final dir = await _ensureInternalViewerDir();
    final localPath = _internalViewerCacheFilePath(dir, cacheKey, node.name);
    final diskCached = await _resolveCachedInternalViewerResultFromDisk(
      cacheKey: cacheKey,
      localPath: localPath,
      totalBytes: node.size,
      maxBytes: maxBytes,
    );
    if (diskCached != null) {
      return _immediateStreamPreparationResult(diskCached);
    }
    await ensureSftpReady(session);
    final sftp = session.sftp;
    if (sftp == null) {
      setError(AppStrings.values.sftpNotReady.resolve(locale.languageCode));
      return null;
    }
    try {
      await _pruneInternalViewerDir(dir);
      final progressController =
          StreamController<InternalViewerDownloadProgress>.broadcast();
      final completion = Completer<InternalViewerPreparationResult?>();
      var cancelled = false;
      late final InternalViewerStreamPreparationResult streamResult;

      void emitProgress({
        required int downloadedBytes,
        required bool done,
        required bool truncated,
        String? error,
      }) {
        if (progressController.isClosed) {
          return;
        }
        progressController.add(
          InternalViewerDownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: node.size,
            done: done,
            truncated: truncated,
            error: error,
          ),
        );
      }

      emitProgress(downloadedBytes: 0, done: false, truncated: false);
      unawaited(() async {
        try {
          final downloaded = await _downloadRemoteToLocal(
            session,
            node.path,
            localPath,
            expectedSize: node.size,
            onProgress: (downloadedBytes, totalBytes) {
              emitProgress(
                downloadedBytes: downloadedBytes,
                done: false,
                truncated: false,
              );
            },
            maxBytes: maxBytes,
            isCancelled: () => cancelled,
          );
          if (downloaded.cancelled) {
            completion.complete(null);
            return;
          }
          final prepared = InternalViewerPreparationResult(
            localPath: localPath,
            truncated: downloaded.truncated,
            downloadedBytes: downloaded.downloadedBytes,
            totalBytes: node.size,
          );
          emitProgress(
            downloadedBytes: prepared.downloadedBytes,
            done: true,
            truncated: prepared.truncated,
          );
          internalViewerPreparedCache[cacheKey] = prepared;
          completion.complete(prepared);
        } catch (error) {
          final message = '$error';
          emitProgress(
            downloadedBytes: 0,
            done: true,
            truncated: false,
            error: message,
          );
          if (!completion.isCompleted) {
            completion.complete(null);
          }
        } finally {
          if (identical(internalViewerStreamingCache[cacheKey], streamResult)) {
            internalViewerStreamingCache.remove(cacheKey);
          }
          await progressController.close();
        }
      }());

      streamResult = InternalViewerStreamPreparationResult(
        localPath: localPath,
        progressStream: progressController.stream,
        completion: completion.future,
        cancel: () {
          cancelled = true;
        },
      );
      internalViewerStreamingCache[cacheKey] = streamResult;
      return streamResult;
    } catch (error) {
      final diagnostic = diagnosePathError(error, path: node.path);
      final operation = locale.languageCode == 'zh'
          ? '准备文件预览'
          : 'Prepare preview';
      setError(
        formatPathError(
          diagnostic,
          languageCode: locale.languageCode,
          operation: operation,
          path: node.path,
        ),
      );
      return null;
    }
  }

  String _internalViewerCacheKey(
    TerminalSession session,
    FileNode node, {
    int? maxBytes,
  }) {
    return _internalViewerCacheKeyForHost(
      session.profile,
      node,
      maxBytes: maxBytes,
    );
  }

  String _internalViewerCacheKeyForHost(
    HostEntry host,
    FileNode node, {
    int? maxBytes,
  }) {
    final profileKey = _stableProfileKeyForHost(host);
    final normalizedPath = p.posix.normalize(node.path.replaceAll('\\', '/'));
    final sizeKey = node.size?.toString() ?? 'unknown';
    final modifiedKey =
        node.modified?.toUtc().millisecondsSinceEpoch.toString() ?? 'unknown';
    final limitKey = maxBytes != null && maxBytes > 0
        ? maxBytes.toString()
        : 'full';
    return '$profileKey|$normalizedPath|$sizeKey|$modifiedKey|$limitKey';
  }

  String _internalViewerScrollKey(
    TerminalSession session,
    FileNode node, {
    int? maxBytes,
  }) {
    return _internalViewerScrollKeyForHost(
      session.profile,
      node,
      maxBytes: maxBytes,
    );
  }

  String _internalViewerScrollKeyForHost(
    HostEntry host,
    FileNode node, {
    int? maxBytes,
  }) {
    final profileKey = _stableProfileKeyForHost(host);
    final normalizedPath = p.posix.normalize(node.path.replaceAll('\\', '/'));
    final limitKey = maxBytes != null && maxBytes > 0
        ? maxBytes.toString()
        : 'full';
    return '$profileKey|$normalizedPath|$limitKey';
  }

  String _stableProfileKeyForHost(HostEntry host) {
    final profileId = host.id.trim();
    if (profileId.isNotEmpty) {
      return profileId;
    }
    final hostName = host.host.trim();
    final username = host.username.trim();
    final port = host.port;
    final connection = host.connectionType.name;
    return '$connection|$username@$hostName:$port';
  }

  String _internalViewerCacheFilePath(
    Directory dir,
    String cacheKey,
    String fileName,
  ) {
    final digest = _stableCacheDigest(cacheKey);
    final ext = p.extension(fileName.trim());
    final safeExt = RegExp(r'^\.[a-zA-Z0-9]{1,12}$').hasMatch(ext) ? ext : '';
    return p.join(dir.path, 'cache-$digest$safeExt');
  }

  Future<InternalViewerPreparationResult?>
  _resolveCachedInternalViewerResultFromDisk({
    required String cacheKey,
    required String localPath,
    required int? totalBytes,
    required int? maxBytes,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      return null;
    }
    final length = await file.length();
    if (length <= 0) {
      return null;
    }
    final expectedBytes = _expectedDownloadedBytes(
      totalBytes: totalBytes,
      maxBytes: maxBytes,
    );
    if (expectedBytes != null && length < expectedBytes) {
      return null;
    }
    final downloadedBytes = expectedBytes == null
        ? length
        : math.min(length, expectedBytes);
    final safeMaxBytes = maxBytes != null && maxBytes > 0 ? maxBytes : null;
    final truncated =
        totalBytes != null && safeMaxBytes != null && totalBytes > safeMaxBytes;
    final prepared = InternalViewerPreparationResult(
      localPath: localPath,
      truncated: truncated,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
    );
    internalViewerPreparedCache[cacheKey] = prepared;
    return prepared;
  }

  int? _expectedDownloadedBytes({
    required int? totalBytes,
    required int? maxBytes,
  }) {
    if (totalBytes == null) {
      return null;
    }
    final safeMaxBytes = maxBytes != null && maxBytes > 0 ? maxBytes : null;
    if (safeMaxBytes == null) {
      return totalBytes;
    }
    return math.min(totalBytes, safeMaxBytes);
  }

  String _stableCacheDigest(String input) {
    var hash = 1469598103934665603;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 1099511628211) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  Future<InternalViewerPreparationResult?> _resolveCachedInternalViewerResult(
    String cacheKey,
  ) async {
    final cached = internalViewerPreparedCache[cacheKey];
    if (cached == null) {
      return null;
    }
    final file = File(cached.localPath);
    if (!await file.exists()) {
      internalViewerPreparedCache.remove(cacheKey);
      return null;
    }
    final length = await file.length();
    if (length < cached.downloadedBytes) {
      internalViewerPreparedCache.remove(cacheKey);
      return null;
    }
    return cached;
  }

  InternalViewerStreamPreparationResult _immediateStreamPreparationResult(
    InternalViewerPreparationResult prepared,
  ) {
    final event = InternalViewerDownloadProgress(
      downloadedBytes: prepared.downloadedBytes,
      totalBytes: prepared.totalBytes,
      done: true,
      truncated: prepared.truncated,
    );
    final stream = Stream<InternalViewerDownloadProgress>.multi((controller) {
      controller.add(event);
      controller.close();
    }, isBroadcast: true);
    return InternalViewerStreamPreparationResult(
      localPath: prepared.localPath,
      progressStream: stream,
      completion: Future<InternalViewerPreparationResult?>.value(prepared),
      cancel: () {},
    );
  }

  Future<Directory> _ensureExternalEditDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'external-edit'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _ensureInternalViewerDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'internal-viewer'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _pruneInternalViewerDir(Directory dir) async {
    try {
      final files = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          files.add(entity);
        }
      }
      if (files.length <= 80) {
        return;
      }
      final statPairs = <(File, DateTime)>[];
      for (final file in files) {
        final stat = await file.stat();
        statPairs.add((file, stat.modified));
      }
      statPairs.sort((a, b) => b.$2.compareTo(a.$2));
      for (final entry in statPairs.skip(80)) {
        try {
          await entry.$1.delete();
        } catch (_) {}
      }
    } catch (_) {
      // Ignore cache prune failures.
    }
  }

  Future<_DownloadRemoteToLocalResult> _downloadRemoteToLocal(
    TerminalSession session,
    String remotePath,
    String localPath, {
    int? expectedSize,
    void Function(int downloadedBytes, int? totalBytes)? onProgress,
    int? maxBytes,
    bool Function()? isCancelled,
  }) async {
    final sftp = session.sftp;
    if (sftp == null) {
      return const _DownloadRemoteToLocalResult(
        downloadedBytes: 0,
        truncated: false,
        cancelled: false,
      );
    }
    return _downloadRemoteToLocalViaSftp(
      sftp,
      remotePath,
      localPath,
      expectedSize: expectedSize,
      onProgress: onProgress,
      maxBytes: maxBytes,
      isCancelled: isCancelled,
    );
  }

  Future<_DownloadRemoteToLocalResult> _downloadRemoteToLocalByHost(
    HostEntry host,
    String remotePath,
    String localPath, {
    int? expectedSize,
    void Function(int downloadedBytes, int? totalBytes)? onProgress,
    int? maxBytes,
    bool Function()? isCancelled,
  }) async {
    final auxiliaryClients = <SSHClient>[];
    SSHClient? client;
    SftpClient? sftp;
    try {
      client = await connectSshClientForHost(
        host,
        auxiliaryClients: auxiliaryClients,
      );
      sftp = await client.sftp();
      return await _downloadRemoteToLocalViaSftp(
        sftp,
        remotePath,
        localPath,
        expectedSize: expectedSize,
        onProgress: onProgress,
        maxBytes: maxBytes,
        isCancelled: isCancelled,
      );
    } finally {
      if (sftp != null) {
        try {
          sftp.close();
        } catch (_) {}
      }
      if (client != null) {
        try {
          client.close();
        } catch (_) {}
      }
      for (final aux in auxiliaryClients.reversed) {
        try {
          aux.close();
        } catch (_) {}
      }
    }
  }

  Future<_DownloadRemoteToLocalResult> _downloadRemoteToLocalViaSftp(
    SftpClient sftp,
    String remotePath,
    String localPath, {
    int? expectedSize,
    void Function(int downloadedBytes, int? totalBytes)? onProgress,
    int? maxBytes,
    bool Function()? isCancelled,
  }) async {
    await Directory(p.dirname(localPath)).create(recursive: true);
    final file = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    final sink = File(localPath).openWrite();
    var downloaded = 0;
    var truncated = false;
    var cancelled = false;
    var bytesSinceLastFlush = 0;
    var lastFlushAt = DateTime.now();
    DateTime? lastProgressEmitAt;
    void emitProgress({bool force = false}) {
      if (onProgress == null) {
        return;
      }
      final now = DateTime.now();
      if (!force &&
          lastProgressEmitAt != null &&
          now.difference(lastProgressEmitAt!).inMilliseconds < 80) {
        return;
      }
      lastProgressEmitAt = now;
      onProgress(downloaded, expectedSize);
    }

    emitProgress(force: true);
    try {
      await for (final chunk in file.read()) {
        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }
        if (chunk.isEmpty) {
          continue;
        }
        final safeMaxBytes = maxBytes != null && maxBytes > 0 ? maxBytes : null;
        if (safeMaxBytes != null && downloaded >= safeMaxBytes) {
          truncated = true;
          break;
        }
        if (safeMaxBytes != null && downloaded + chunk.length > safeMaxBytes) {
          final remaining = safeMaxBytes - downloaded;
          if (remaining > 0) {
            final partial = chunk.sublist(0, remaining);
            downloaded += partial.length;
            sink.add(partial);
          }
          truncated = true;
          emitProgress(force: true);
          break;
        }
        downloaded += chunk.length;
        sink.add(chunk);
        bytesSinceLastFlush += chunk.length;
        final now = DateTime.now();
        if (bytesSinceLastFlush >= 256 * 1024 ||
            now.difference(lastFlushAt).inMilliseconds >= 420) {
          await sink.flush();
          bytesSinceLastFlush = 0;
          lastFlushAt = now;
        }
        emitProgress();
      }
    } finally {
      await sink.flush();
      await sink.close();
      await file.close();
      emitProgress(force: true);
    }
    return _DownloadRemoteToLocalResult(
      downloadedBytes: downloaded,
      truncated: truncated,
      cancelled: cancelled,
    );
  }

  Future<void> _openLocalFile(String path) async {
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        final detail = result.message.trim().isEmpty
            ? result.type.name
            : result.message.trim();
        setError(
          AppStrings.values.failedToOpenLocalFileVar.resolve(
            locale.languageCode,
            params: {'error': detail},
          ),
        );
      }
    } catch (e) {
      final diagnostic = diagnosePathError(e, path: path);
      final operation = locale.languageCode == 'zh'
          ? '打开本地文件'
          : 'Open local file';
      setError(
        formatPathError(
          diagnostic,
          languageCode: locale.languageCode,
          operation: operation,
          path: path,
        ),
      );
    }
  }

  Future<Uint8List> _readFileAllBytes(
    TerminalSession session,
    String path,
  ) async {
    if (session.profile.isLocal) {
      try {
        return await File(path).readAsBytes();
      } catch (error) {
        if (!Platform.isAndroid) {
          rethrow;
        }
        return _readLocalFileBytesByShell(path);
      }
    }
    await ensureSftpReady(session);
    final sftp = session.sftp;
    if (sftp == null) {
      throw StateError(
        AppStrings.values.sftpNotReady.resolve(locale.languageCode),
      );
    }
    final file = await sftp.open(path, mode: SftpFileOpenMode.read);
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in file.read()) {
        if (chunk.isNotEmpty) {
          bytes.add(chunk);
        }
      }
    } finally {
      await file.close();
    }
    return bytes.takeBytes();
  }

  Future<Uint8List> _readLocalFileBytesByShell(String path) async {
    final shell = File('/system/bin/sh').existsSync() ? '/system/bin/sh' : 'sh';
    final encodedPath = jsonEncode(path);
    const scriptPrefix = 'cat -- ';
    final script = '$scriptPrefix$encodedPath';
    final result = await Process.run(
      shell,
      ['-c', script],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      final message = result.stderr?.toString().trim().isNotEmpty == true
          ? result.stderr.toString().trim()
          : 'exit ${result.exitCode}';
      throw FileSystemException(message, path);
    }
    final stdout = result.stdout;
    if (stdout is List<int>) {
      return Uint8List.fromList(stdout);
    }
    if (stdout is String) {
      return Uint8List.fromList(utf8.encode(stdout));
    }
    return Uint8List(0);
  }

  void _registerExternalEdit(
    String sessionId,
    String remotePath,
    String localPath,
  ) {
    final entry = ExternalEditEntry(
      sessionId: sessionId,
      remotePath: remotePath,
      localPath: localPath,
    );
    entry.suppressUntil = DateTime.now().add(const Duration(seconds: 1));
    externalEdits[localPath] = entry;
    externalEditSubscriptions[localPath]?.cancel();
    final parent = Directory(p.dirname(localPath));
    externalEditSubscriptions[localPath] = parent
        .watch(recursive: false)
        .listen((event) {
          if (event is FileSystemDeleteEvent) return;
          final eventPath = p.normalize(event.path);
          final targetPath = p.normalize(localPath);
          if (!_sameLocalPath(eventPath, targetPath)) return;
          _scheduleExternalUpload(localPath);
        });
    unawaited(_cacheExternalFileSignature(entry));
  }

  void _scheduleExternalUpload(String localPath) {
    final entry = externalEdits[localPath];
    if (entry == null) return;
    final now = DateTime.now();
    if (entry.suppressUntil != null && now.isBefore(entry.suppressUntil!)) {
      return;
    }
    if (entry.uploading) {
      return;
    }
    externalEditDebounceTimers[localPath]?.cancel();
    externalEditDebounceTimers[localPath] = Timer(
      const Duration(milliseconds: 300),
      () {
        unawaited(_uploadExternalEdit(localPath));
      },
    );
  }

  Future<void> _uploadExternalEdit(String localPath) async {
    final entry = externalEdits[localPath];
    if (entry == null) return;
    if (!await _hasExternalFileChanged(entry)) {
      return;
    }
    final session = findSessionById(entry.sessionId);
    if (session == null) {
      disposeExternalEdit(localPath);
      return;
    }
    if (session.tab.status != TerminalStatus.connected) {
      setError(
        AppStrings.values.sessionNotConnected.resolve(locale.languageCode),
      );
      return;
    }
    await ensureSftpReady(session);
    if (session.sftp == null) return;
    try {
      entry.uploading = true;
      await _uploadLocalDirect(session, localPath, entry.remotePath);
      await _cacheExternalFileSignature(entry);
      entry.suppressUntil = DateTime.now().add(
        const Duration(milliseconds: 500),
      );
      final currentDir = session.fileState.currentPath.isNotEmpty
          ? session.fileState.currentPath
          : session.fileState.rootPath;
      if (currentDir.isNotEmpty) {
        unawaited(refreshDirectory(session, currentDir));
      }
    } catch (e) {
      setError(
        AppStrings.values.externalEditSyncFailedVar.resolve(
          locale.languageCode,
          params: {'error': '$e'},
        ),
      );
      addStructuredLog(
        category: TerminalLogCategory.externalEdit,
        level: TerminalLogLevel.error,
        message: AppStrings.values.externalEditSyncFailedVar.resolve(
          locale.languageCode,
          params: {'error': '$e'},
        ),
      );
    } finally {
      entry.uploading = false;
    }
  }

  Future<void> _cacheExternalFileSignature(ExternalEditEntry entry) async {
    final file = File(entry.localPath);
    if (!await file.exists()) {
      entry.lastModified = null;
      entry.lastSize = null;
      return;
    }
    final stat = await file.stat();
    entry.lastModified = stat.modified;
    entry.lastSize = stat.size;
  }

  Future<bool> _hasExternalFileChanged(ExternalEditEntry entry) async {
    final file = File(entry.localPath);
    if (!await file.exists()) {
      return false;
    }
    final stat = await file.stat();
    final modified = stat.modified;
    final size = stat.size;
    if (entry.lastModified == null || entry.lastSize == null) {
      return true;
    }
    return !modified.isAtSameMomentAs(entry.lastModified!) ||
        size != entry.lastSize;
  }

  bool _sameLocalPath(String a, String b) {
    final left = p.normalize(a);
    final right = p.normalize(b);
    if (Platform.isWindows) {
      return left.toLowerCase() == right.toLowerCase();
    }
    return left == right;
  }

  Future<void> _uploadLocalDirect(
    TerminalSession session,
    String localPath,
    String remotePath,
  ) async {
    final sftp = session.sftp;
    if (sftp == null) return;
    final file = await sftp.open(
      remotePath,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    final stream = File(
      localPath,
    ).openRead().map((chunk) => Uint8List.fromList(chunk));
    final writer = file.write(stream);
    await writer.done;
    await file.close();
  }
}

class _DownloadRemoteToLocalResult {
  const _DownloadRemoteToLocalResult({
    required this.downloadedBytes,
    required this.truncated,
    required this.cancelled,
  });

  final int downloadedBytes;
  final bool truncated;
  final bool cancelled;
}
