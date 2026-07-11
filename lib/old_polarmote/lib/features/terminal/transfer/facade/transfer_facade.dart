import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../models/transfer_task.dart';
import '../control/cancellation_token.dart';
import '../transport/transport_provider.dart';

class TransferFacade {
  const TransferFacade(this.transport, {required this.direction});

  final TransportProvider transport;
  final TransferDirection direction;

  Future<int> uploadBatch({
    required List<String> localPaths,
    required String remoteDir,
    required CancellationToken cancellationToken,
    required void Function(double fraction) onProgress,
    void Function(int chunkBytes)? onChunk,
  }) async {
    var previousProgressBytes = 0;
    var totalBytes = 0;
    var lastUiReportedBytes = -1;
    final lastUiReportedAt = Stopwatch()..start();

    void report(int bytes, int total) {
      _ensureNotCancelled(cancellationToken);
      final delta = max(0, bytes - previousProgressBytes);
      previousProgressBytes = bytes;
      onChunk?.call(delta);
      if (total > 0) {
        totalBytes = total;
      }
      if (totalBytes <= 0) {
        return;
      }
      if (bytes <= lastUiReportedBytes) return;
      final isDone = bytes >= totalBytes;
      final deltaBytes = bytes - max(0, lastUiReportedBytes);
      final elapsedMs = lastUiReportedAt.elapsedMilliseconds;
      if (!isDone && deltaBytes < (256 * 1024) && elapsedMs < 180) {
        return;
      }
      lastUiReportedBytes = bytes;
      lastUiReportedAt.reset();
      final fraction = (bytes / max(1, totalBytes)).clamp(0.0, 1.0);
      onProgress(fraction);
    }

    await transport.uploadBatch(
      localPaths: localPaths,
      remoteDir: remoteDir,
      onProgress: report,
    );
    return totalBytes;
  }

  Future<int> downloadBatch({
    required List<String> remotePaths,
    required String localDir,
    required CancellationToken cancellationToken,
    required void Function(double fraction) onProgress,
    void Function(int chunkBytes)? onChunk,
  }) async {
    var previousProgressBytes = 0;
    var totalBytes = 0;
    var lastUiReportedBytes = -1;
    final lastUiReportedAt = Stopwatch()..start();

    void report(int bytes, int total) {
      _ensureNotCancelled(cancellationToken);
      final delta = max(0, bytes - previousProgressBytes);
      previousProgressBytes = bytes;
      onChunk?.call(delta);
      if (total > 0) {
        totalBytes = total;
      }
      if (totalBytes <= 0) {
        return;
      }
      if (bytes <= lastUiReportedBytes) return;
      final isDone = bytes >= totalBytes;
      final deltaBytes = bytes - max(0, lastUiReportedBytes);
      final elapsedMs = lastUiReportedAt.elapsedMilliseconds;
      if (!isDone && deltaBytes < (256 * 1024) && elapsedMs < 180) {
        return;
      }
      lastUiReportedBytes = bytes;
      lastUiReportedAt.reset();
      final fraction = (bytes / max(1, totalBytes)).clamp(0.0, 1.0);
      onProgress(fraction);
    }

    final total = await transport.downloadBatch(
      remotePaths: remotePaths,
      localDir: localDir,
      onProgress: report,
    );
    return total > 0 ? total : totalBytes;
  }

  Future<int> uploadFile({
    required String localPath,
    required String remotePath,
    required CancellationToken cancellationToken,
    required void Function(double fraction) onProgress,
    void Function(int chunkBytes)? onChunk,
  }) async {
    await transport.ensureParentDirs(remotePath);
    final file = File(localPath);
    final size = await file.length();

    var previousProgressBytes = 0;
    var lastUiReportedBytes = -1;
    final lastUiReportedAt = Stopwatch()..start();

    void report(int bytes) {
      _ensureNotCancelled(cancellationToken);
      final delta = max(0, bytes - previousProgressBytes);
      previousProgressBytes = bytes;
      onChunk?.call(delta);

      if (bytes <= lastUiReportedBytes) return;
      final isDone = bytes >= size;
      final deltaBytes = bytes - max(0, lastUiReportedBytes);
      final elapsedMs = lastUiReportedAt.elapsedMilliseconds;
      if (!isDone && deltaBytes < (256 * 1024) && elapsedMs < 180) {
        return;
      }
      lastUiReportedBytes = bytes;
      lastUiReportedAt.reset();
      final fraction = (bytes / max(1, size)).clamp(0.0, 1.0);
      onProgress(fraction);
    }

    await transport.uploadLocalFile(
      localPath: localPath,
      remotePath: remotePath,
      onProgress: (bytes, _) => report(bytes),
    );
    return size;
  }

  Future<int> downloadFile({
    required String remotePath,
    required String localPath,
    required CancellationToken cancellationToken,
    required void Function(double fraction) onProgress,
    void Function(int chunkBytes)? onChunk,
    int? knownSize,
  }) async {
    final size = knownSize ?? await _remoteFileSize(remotePath);
    var previousProgressBytes = 0;
    var lastUiReportedBytes = -1;
    final lastUiReportedAt = Stopwatch()..start();

    final downloadedSize = await transport.downloadToLocalFile(
      remotePath: remotePath,
      localPath: localPath,
      knownSize: size,
      onProgress: (bytes, totalBytes) {
        _ensureNotCancelled(cancellationToken);
        final delta = max(0, bytes - previousProgressBytes);
        previousProgressBytes = bytes;
        onChunk?.call(delta);

        final stableTotal = totalBytes > 0 ? totalBytes : size;
        if (stableTotal <= 0) {
          return;
        }
        if (bytes <= lastUiReportedBytes) return;
        final isDone = bytes >= stableTotal;
        final deltaBytes = bytes - max(0, lastUiReportedBytes);
        final elapsedMs = lastUiReportedAt.elapsedMilliseconds;
        if (!isDone && deltaBytes < (256 * 1024) && elapsedMs < 180) {
          return;
        }
        lastUiReportedBytes = bytes;
        lastUiReportedAt.reset();
        final fraction = (bytes / stableTotal).clamp(0.0, 1.0);
        onProgress(fraction);
      },
    );
    return downloadedSize > 0 ? downloadedSize : size;
  }

  Future<(Stream<List<int>>, int)> openDownloadStream({
    required String remotePath,
    required CancellationToken cancellationToken,
    required void Function(double fraction) onProgress,
    void Function(int chunkBytes)? onChunk,
    int? knownSize,
  }) async {
    final size = knownSize ?? await _remoteFileSize(remotePath);
    var lastReportedBytes = -1;
    final lastReportedAt = Stopwatch()..start();
    var previousProgressBytes = 0;
    final stream = transport.downloadFile(
      remotePath: remotePath,
      length: size > 0 ? size : null,
      onProgress: (bytes) {
        _ensureNotCancelled(cancellationToken);
        final delta = max(0, bytes - previousProgressBytes);
        previousProgressBytes = bytes;
        onChunk?.call(delta);
        if (size <= 0) return;
        if (bytes <= lastReportedBytes) return;
        final isDone = bytes >= size;
        final deltaBytes = bytes - max(0, lastReportedBytes);
        final elapsedMs = lastReportedAt.elapsedMilliseconds;
        if (!isDone && deltaBytes < (256 * 1024) && elapsedMs < 180) {
          return;
        }
        lastReportedBytes = bytes;
        lastReportedAt.reset();
        final fraction = (bytes / size).clamp(0.0, 1.0);
        onProgress(fraction);
      },
    );
    return (stream, size);
  }

  Future<int> _remoteFileSize(String remotePath) async {
    final size = await transport.probeRemoteFileSize(remotePath);
    return size ?? 0;
  }

  void _ensureNotCancelled(CancellationToken cancellationToken) {
    if (cancellationToken.isCancelled) {
      throw const TransferCancelledException();
    }
  }
}
