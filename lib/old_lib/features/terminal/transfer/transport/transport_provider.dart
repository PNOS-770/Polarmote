import 'dart:async';

abstract class TransportProvider {
  Future<void> uploadBatch({
    required List<String> localPaths,
    required String remoteDir,
    required void Function(int transferredBytes, int totalBytes) onProgress,
  });

  Future<int> downloadBatch({
    required List<String> remotePaths,
    required String localDir,
    required void Function(int transferredBytes, int totalBytes) onProgress,
  });

  Future<void> uploadLocalFile({
    required String localPath,
    required String remotePath,
    required void Function(int transferredBytes, int totalBytes) onProgress,
  });

  Future<int> downloadToLocalFile({
    required String remotePath,
    required String localPath,
    required void Function(int transferredBytes, int totalBytes) onProgress,
    int? knownSize,
  });

  Stream<List<int>> downloadFile({
    required String remotePath,
    int? length,
    void Function(int bytes)? onProgress,
  });

  Future<void> ensureParentDirs(String remotePath);

  Future<int?> probeRemoteFileSize(String remotePath);
}
