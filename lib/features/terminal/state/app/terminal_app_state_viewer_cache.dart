part of 'terminal_app_state_external_edit.dart';

extension TerminalAppStateViewerCache on TerminalAppState {
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
    if (profileId.isNotEmpty) return profileId;
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
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length <= 0) return null;
    final expectedBytes = _expectedDownloadedBytes(
      totalBytes: totalBytes,
      maxBytes: maxBytes,
    );
    if (expectedBytes != null && length < expectedBytes) return null;
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
    if (totalBytes == null) return null;
    final safeMaxBytes = maxBytes != null && maxBytes > 0 ? maxBytes : null;
    if (safeMaxBytes == null) return totalBytes;
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
    if (cached == null) return null;
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
        if (entity is File) files.add(entity);
      }
      if (files.length <= 80) return;
      final statPairs = <(File, DateTime)>[];
      for (final file in files) {
        final stat = await file.stat();
        statPairs.add((file, stat.modified));
      }
      statPairs.sort((a, b) => b.$2.compareTo(a.$2));
      for (final entry in statPairs.skip(80)) {
        try { await entry.$1.delete(); } catch (_) {}
      }
    } catch (_) {}
  }
}



