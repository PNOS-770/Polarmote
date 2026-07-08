import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../models/host_entry.dart';
import '../transport_factory.dart';
import '../transport_provider.dart';
import 'native_transfer_bridge.dart';
import '../../../../../shared/logging/Polarmote_log.dart';

class NativeTransport implements TransportProvider {
  NativeTransport({
    required HostEntry profile,
    required TransferRuntimeOptions options,
    NativeTransferBridge? bridge,
  }) : _profile = profile,
       _options = options,
       _bridge = bridge ?? NativeTransferBridge.instance {
    if (!_bridge.isSupported) {
      throw StateError('Rust native transport core is not available');
    }
  }

  final HostEntry _profile;
  final TransferRuntimeOptions _options;
  final NativeTransferBridge _bridge;

  NativeTransferSessionConfig get _sessionConfig {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final connectTimeoutMs =
        _profile.connectTimeoutSeconds.clamp(3, 120) * 1000;
    return NativeTransferSessionConfig(
      host: _profile.host,
      port: _profile.port,
      username: _profile.username,
      password: _profile.authType == AuthType.password
          ? _profile.password
          : null,
      privateKeyPath: _profile.authType == AuthType.key
          ? _profile.privateKeyPath
          : null,
      privateKeyPassphrase: _profile.authType == AuthType.key
          ? (_profile.privateKeyPassphrase ?? _profile.password)
          : null,
      connectTimeoutMs: isMobile
          ? connectTimeoutMs.clamp(8000, 30000).toInt()
          : connectTimeoutMs.toInt(),
      ioTimeoutMs: isMobile ? 180000 : 15000,
      maxConcurrency: _options.nativeMaxConcurrency,
      defaultChunkSize: _options.defaultChunkSizeBytes,
      enableResume: _options.enableResume,
      retryMaxAttempts: _options.retryMaxAttempts,
      retryBaseBackoffMs: _options.retryBaseBackoffMs,
      retryMaxBackoffMs: _options.retryMaxBackoffMs,
    );
  }

  @override
  Future<void> uploadBatch({
    required List<String> localPaths,
    required String remoteDir,
    required void Function(int transferredBytes, int totalBytes) onProgress,
  }) {
    return _bridge.uploadBatch(
      sessionConfig: _sessionConfig,
      localPaths: localPaths,
      remoteDir: remoteDir,
      onProgress: onProgress,
    );
  }

  @override
  Future<int> downloadBatch({
    required List<String> remotePaths,
    required String localDir,
    required void Function(int transferredBytes, int totalBytes) onProgress,
  }) {
    return _bridge.downloadBatch(
      sessionConfig: _sessionConfig,
      remotePaths: remotePaths,
      localDir: localDir,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> uploadLocalFile({
    required String localPath,
    required String remotePath,
    required void Function(int transferredBytes, int totalBytes) onProgress,
  }) {
    return _bridge.uploadFile(
      sessionConfig: _sessionConfig,
      localPath: localPath,
      remotePath: remotePath,
      onProgress: onProgress,
    );
  }

  @override
  Future<int> downloadToLocalFile({
    required String remotePath,
    required String localPath,
    required void Function(int transferredBytes, int totalBytes) onProgress,
    int? knownSize,
  }) async {
    var latestTotal = knownSize ?? 0;
    final size = await _bridge.downloadFile(
      sessionConfig: _sessionConfig,
      remotePath: remotePath,
      localPath: localPath,
      onProgress: (transferred, total) {
        if (total > 0) {
          latestTotal = total;
        }
        onProgress(transferred, latestTotal);
      },
    );
    return size > 0 ? size : latestTotal;
  }

  @override
  Stream<List<int>> downloadFile({
    required String remotePath,
    int? length,
    void Function(int bytes)? onProgress,
  }) async* {
    final tempDir = await Directory.systemTemp.createTemp(
      'Polarmote-native-stream',
    );
    final baseName = p.basename(remotePath);
    final safeName = baseName.isEmpty ? 'download.bin' : baseName;
    final localPath = p.join(tempDir.path, safeName);

    await downloadToLocalFile(
      remotePath: remotePath,
      localPath: localPath,
      knownSize: length,
      onProgress: (transferredBytes, _) {
        onProgress?.call(transferredBytes);
      },
    );

    try {
      yield* File(localPath).openRead();
    } finally {
      unawaited(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (e) { PolarmoteLog.error('native_transport', '$e'); }
      }());
    }
  }

  @override
  Future<void> ensureParentDirs(String remotePath) {
    return _bridge.ensureParentDirs(
      sessionConfig: _sessionConfig,
      remotePath: remotePath,
    );
  }

  @override
  Future<int?> probeRemoteFileSize(String remotePath) {
    return _bridge.probeRemoteFileSize(
      sessionConfig: _sessionConfig,
      remotePath: remotePath,
    );
  }
}



