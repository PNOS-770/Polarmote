import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

part 'native_transfer_bridge_internal.dart';

class NativeTransferException implements Exception {
  const NativeTransferException(this.message);

  final String message;

  @override
  String toString() => 'NativeTransferException($message)';
}

class NativeTransferSessionConfig {
  const NativeTransferSessionConfig({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKeyPath,
    this.privateKeyPassphrase,
    this.connectTimeoutMs = 8000,
    this.ioTimeoutMs = 15000,
    this.maxConcurrency = 4,
    this.defaultChunkSize = 1024 * 1024,
    this.enableResume = true,
    this.retryMaxAttempts = 2,
    this.retryBaseBackoffMs = 250,
    this.retryMaxBackoffMs = 10000,
  });

  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;
  final String? privateKeyPassphrase;
  final int connectTimeoutMs;
  final int ioTimeoutMs;
  final int maxConcurrency;
  final int defaultChunkSize;
  final bool enableResume;
  final int retryMaxAttempts;
  final int retryBaseBackoffMs;
  final int retryMaxBackoffMs;

  Map<String, Object?> toJson() {
    return {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'private_key_path': privateKeyPath,
      'private_key_passphrase': privateKeyPassphrase,
      'connect_timeout_ms': connectTimeoutMs,
      'io_timeout_ms': ioTimeoutMs,
      'max_concurrency': maxConcurrency,
      'default_chunk_size': defaultChunkSize,
      'enable_resume': enableResume,
      'retry_max_attempts': retryMaxAttempts,
      'retry_base_backoff_ms': retryBaseBackoffMs,
      'retry_max_backoff_ms': retryMaxBackoffMs,
    };
  }
}

class NativeTransferBridge {
  NativeTransferBridge._();

  static final NativeTransferBridge instance = NativeTransferBridge._();

  static const Duration _defaultTaskTimeout = Duration(hours: 12);
  static const Duration _metadataTaskTimeout = Duration(minutes: 2);
  static const Duration _pollInterval = Duration(milliseconds: 45);
  static const Duration _sessionIdleTtl = Duration(seconds: 45);

  final _NativeBindings? _bindings = _NativeBindings.tryLoad();
  final _NativeSessionManager _sessionManager = _NativeSessionManager();

  bool get isSupported => _bindings != null;
  String? get nativeBuildInfo => _bindings?.buildInfo;
  String? get nativeLibrarySource => _bindings?.loadedFrom;

  NativeSessionPoolStats poolStatsForSessionConfig(
    NativeTransferSessionConfig config,
  ) {
    if (!isSupported) {
      return const NativeSessionPoolStats(busySessions: 0, totalSessions: 0);
    }
    final key = _sessionConfigKey(config);
    return _sessionManager.snapshotForKey(key);
  }

  NativeSessionPoolStats poolStatsGlobal() {
    if (!isSupported) {
      return const NativeSessionPoolStats(busySessions: 0, totalSessions: 0);
    }
    return _sessionManager.snapshotGlobal();
  }

  Future<void> ensureParentDirs({
    required NativeTransferSessionConfig sessionConfig,
    required String remotePath,
  }) async {
    await _runTask(
      sessionConfig: sessionConfig,
      task: {
        'task_id': _nextTaskId('mkdir'),
        'kind': 'ensure_parent_dirs',
        'remote_path': remotePath,
      },
      timeout: _metadataTaskTimeout,
    );
  }

  Future<int?> probeRemoteFileSize({
    required NativeTransferSessionConfig sessionConfig,
    required String remotePath,
  }) async {
    final result = await _runTask(
      sessionConfig: sessionConfig,
      task: {
        'task_id': _nextTaskId('stat'),
        'kind': 'probe_remote_file_size',
        'remote_path': remotePath,
      },
      timeout: _metadataTaskTimeout,
    );
    return result.valueU64;
  }

  Future<void> uploadFile({
    required NativeTransferSessionConfig sessionConfig,
    required String localPath,
    required String remotePath,
    required void Function(int transferredBytes, int totalBytes) onProgress,
    int? chunkSize,
  }) async {
    await _runTask(
      sessionConfig: sessionConfig,
      task: {
        'task_id': _nextTaskId('up'),
        'kind': 'upload',
        'remote_path': remotePath,
        'local_path': localPath,
        if (chunkSize != null) 'chunk_size': chunkSize,
      },
      onProgress: (transferred, total) {
        onProgress(transferred, total ?? 0);
      },
    );
  }

  Future<void> uploadBatch({
    required NativeTransferSessionConfig sessionConfig,
    required List<String> localPaths,
    required String remoteDir,
    required void Function(int transferredBytes, int totalBytes) onProgress,
    int? chunkSize,
  }) async {
    await _runTask(
      sessionConfig: sessionConfig,
      task: {
        'task_id': _nextTaskId('up-batch'),
        'kind': 'upload_batch',
        'target_dir': remoteDir,
        'local_paths': localPaths,
        if (chunkSize != null) 'chunk_size': chunkSize,
      },
      onProgress: (transferred, total) {
        onProgress(transferred, total ?? 0);
      },
    );
  }

  Future<int> downloadFile({
    required NativeTransferSessionConfig sessionConfig,
    required String remotePath,
    required String localPath,
    required void Function(int transferredBytes, int totalBytes) onProgress,
    int? chunkSize,
  }) async {
    final result = await _runTask(
      sessionConfig: sessionConfig,
      task: {
        'task_id': _nextTaskId('down'),
        'kind': 'download',
        'remote_path': remotePath,
        'local_path': localPath,
        if (chunkSize != null) 'chunk_size': chunkSize,
      },
      onProgress: (transferred, total) {
        onProgress(transferred, total ?? 0);
      },
    );
    if (result.totalBytes != null && result.totalBytes! > 0) {
      return result.totalBytes!;
    }
    return result.transferredBytes;
  }

  Future<int> downloadBatch({
    required NativeTransferSessionConfig sessionConfig,
    required List<String> remotePaths,
    required String localDir,
    required void Function(int transferredBytes, int totalBytes) onProgress,
    int? chunkSize,
  }) async {
    final result = await _runTask(
      sessionConfig: sessionConfig,
      task: {
        'task_id': _nextTaskId('down-batch'),
        'kind': 'download_batch',
        'target_dir': localDir,
        'remote_paths': remotePaths,
        if (chunkSize != null) 'chunk_size': chunkSize,
      },
      onProgress: (transferred, total) {
        onProgress(transferred, total ?? 0);
      },
    );
    if (result.totalBytes != null && result.totalBytes! > 0) {
      return result.totalBytes!;
    }
    return result.transferredBytes;
  }

  Future<_NativeTaskResult> _runTask({
    required NativeTransferSessionConfig sessionConfig,
    required Map<String, Object?> task,
    void Function(int transferredBytes, int? totalBytes)? onProgress,
    Duration timeout = _defaultTaskTimeout,
  }) async {
    final bindings = _bindings;
    if (bindings == null) {
      throw const NativeTransferException('native transfer core not available');
    }

    return _sessionManager.runTask(
      bindings: bindings,
      sessionConfig: sessionConfig,
      idleTtl: _sessionIdleTtl,
      run: (context) async {
        if (bindings.supportsRuntimeApi) {
          return _runTaskRuntimeV2(
            bindings: bindings,
            context: context,
            sessionConfig: sessionConfig,
            task: task,
            onProgress: onProgress,
            timeout: timeout,
          );
        }
        return _runTaskLegacy(
          bindings: bindings,
          sessionId: context.sessionId,
          task: task,
          onProgress: onProgress,
          timeout: timeout,
        );
      },
    );
  }

  Future<_NativeTaskResult> _runTaskLegacy({
    required _NativeBindings bindings,
    required int sessionId,
    required Map<String, Object?> task,
    required Duration timeout,
    void Function(int transferredBytes, int? totalBytes)? onProgress,
  }) async {
    final taskId = task['task_id']?.toString() ?? _nextTaskId('task');
    final enqueueRc = bindings.enqueueTransfer(sessionId, jsonEncode(task));
    if (enqueueRc != 0) {
      throw NativeTransferException(
        'enqueue transfer failed with code $enqueueRc',
      );
    }

    final deadline = DateTime.now().add(timeout);
    while (true) {
      final events = bindings.pollEvents(sessionId);
      for (final event in events) {
        if (event.taskId != taskId) {
          continue;
        }
        switch (event.eventType) {
          case 'progress':
            if (onProgress != null) {
              try {
                onProgress(event.transferredBytes ?? 0, event.totalBytes);
              } catch (error, stackTrace) {
                bindings.cancelTask(sessionId, taskId);
                Error.throwWithStackTrace(error, stackTrace);
              }
            }
          case 'completion':
            return _NativeTaskResult(
              transferredBytes: event.transferredBytes ?? 0,
              totalBytes: event.totalBytes,
              valueU64: event.valueU64,
            );
          case 'error':
            throw NativeTransferException(
              event.message ?? 'native transfer failed',
            );
          case 'cancelled':
            throw const NativeTransferException('native transfer cancelled');
          default:
            break;
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        break;
      }
      await Future.delayed(_pollInterval);
    }

    bindings.cancelTask(sessionId, taskId);
    throw const NativeTransferException('native transfer timeout');
  }

  Future<_NativeTaskResult> _runTaskRuntimeV2({
    required _NativeBindings bindings,
    required _NativeSessionContext context,
    required NativeTransferSessionConfig sessionConfig,
    required Map<String, Object?> task,
    required Duration timeout,
    void Function(int transferredBytes, int? totalBytes)? onProgress,
  }) async {
    final graphSpec = _buildGraphSpecFromLegacyTask(task, sessionConfig);
    final graphId = bindings.submitGraph(
      context.sessionId,
      graphSpec.graphJson,
    );
    if (graphId == 0) {
      throw const NativeTransferException('submit graph failed');
    }

    const graphCompletedGracePeriod = Duration(seconds: 5);

    final deadline = DateTime.now().add(timeout);
    final hintedTotalBytes = graphSpec.totalBytesHint;
    final transferredByNode = <int, int>{};
    final totalByNode = <int, int>{};
    int? latestValueU64;
    /// Timestamp when all known data bytes were first fully transferred.
    /// Null until data transfer is confirmed complete.
    DateTime? allDataTransferredAt;

    int aggregateTransferred() {
      var sum = 0;
      for (final value in transferredByNode.values) {
        sum += value;
      }
      return sum;
    }

    int? aggregateTotal() {
      if (totalByNode.isEmpty) {
        return null;
      }
      var sum = 0;
      for (final value in totalByNode.values) {
        sum += value;
      }
      return sum;
    }

    void emitProgress() {
      if (onProgress == null) {
        return;
      }
      final transferred = aggregateTransferred();
      final aggregatedTotal = aggregateTotal();
      final total = switch ((hintedTotalBytes, aggregatedTotal)) {
        (int hinted, int aggregated) => max(hinted, aggregated),
        (int hinted, null) => hinted,
        (null, int aggregated) => aggregated,
        (null, null) => null,
      };
      // Track when all known data bytes have been fully transferred.
      if (total != null && total > 0 && transferred >= total) {
        allDataTransferredAt ??= DateTime.now();
      }
      var safeTotal = total;
      if (safeTotal != null && safeTotal > 0 && transferred >= safeTotal) {
        // Runtime V2 may discover/expand work incrementally, so aggregated total
        // can temporarily equal transferred before graph actually completes.
        // After the grace period, report true 100% so the UI doesn't appear stuck.
        if (allDataTransferredAt != null &&
            DateTime.now().difference(allDataTransferredAt!) >=
                graphCompletedGracePeriod) {
          // Use real total — progress becomes 1.0.
        } else {
          safeTotal = transferred + 1;
        }
      }
      try {
        onProgress(transferred, safeTotal);
      } catch (error, stackTrace) {
        bindings.cancelGraph(context.sessionId, graphId);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    while (true) {
      final batch = bindings.pollEventsCursor(
        context.sessionId,
        context.nextEventCursor,
      );
      context.nextEventCursor = batch.nextCursor;
      for (final event in batch.events) {
        if (event.graphId != graphId) {
          continue;
        }
        switch (event.eventType) {
          case 'node_progress':
            final nodeId = event.nodeId;
            if (nodeId != null) {
              if (event.transferredBytes != null) {
                transferredByNode[nodeId] = event.transferredBytes!;
              }
              if (event.totalBytes != null) {
                totalByNode[nodeId] = event.totalBytes!;
              }
            }
            emitProgress();
          case 'node_completed':
            final nodeId = event.nodeId;
            if (nodeId != null) {
              final nodeTransferred =
                  event.transferredBytes ?? transferredByNode[nodeId] ?? 0;
              transferredByNode[nodeId] = nodeTransferred;
              final nodeTotal = event.totalBytes;
              if (nodeTotal != null) {
                totalByNode[nodeId] = nodeTotal;
              } else if (!totalByNode.containsKey(nodeId)) {
                totalByNode[nodeId] = nodeTransferred;
              }
            }
            latestValueU64 = event.valueU64 ?? latestValueU64;
            emitProgress();
          case 'node_failed':
            throw NativeTransferException(
              event.message ?? 'native transfer failed',
            );
          case 'node_retrying':
            latestValueU64 = event.valueU64 ?? latestValueU64;
          case 'graph_failed':
            throw NativeTransferException(
              event.message ?? 'native transfer failed',
            );
          case 'graph_cancelled':
            throw const NativeTransferException('native transfer cancelled');
          case 'graph_completed':
            final transferred = aggregateTransferred();
            final aggregatedTotal = aggregateTotal();
            final total = switch ((hintedTotalBytes, aggregatedTotal)) {
              (int hinted, int aggregated) => max(hinted, aggregated),
              (int hinted, null) => hinted,
              (null, int aggregated) => aggregated,
              (null, null) => null,
            };
            return _NativeTaskResult(
              transferredBytes: transferred,
              totalBytes: total,
              valueU64: latestValueU64,
            );
          default:
            break;
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        break;
      }
      await Future.delayed(_pollInterval);
    }

    bindings.cancelGraph(context.sessionId, graphId);
    throw const NativeTransferException('native transfer timeout');
  }

  _NativeGraphSpec _buildGraphSpecFromLegacyTask(
    Map<String, Object?> task,
    NativeTransferSessionConfig sessionConfig,
  ) {
    final taskId = task['task_id']?.toString();
    final kind = task['kind']?.toString() ?? '';
    final chunkSize = _asIntNullable(task['chunk_size']);
    var nodeId = 1;
    final nodes = <Object?>[];
    var hintedTotalBytes = 0;
    var hasTotalHint = false;

    Map<String, Object?> retryPolicy() {
      final maxAttempts = sessionConfig.retryMaxAttempts.clamp(1, 12);
      final baseBackoff = sessionConfig.retryBaseBackoffMs.clamp(100, 120000);
      final maxBackoff = sessionConfig.retryMaxBackoffMs.clamp(
        baseBackoff,
        300000,
      );
      return <String, Object?>{
        'max_attempts': maxAttempts,
        'base_backoff_ms': baseBackoff,
        'max_backoff_ms': maxBackoff,
      };
    }

    void addNode(Map<String, Object?> operation, {String? displayName}) {
      nodes.add(<String, Object?>{
        'node_id': nodeId++,
        'operation': operation,
        'retry_policy': retryPolicy(),
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      });
    }

    if (kind == 'upload_batch') {
      final targetDir = task['target_dir']?.toString() ?? '';
      final localPaths = _asStringList(task['local_paths']);
      for (final localPath in localPaths) {
        final normalized = localPath.trim();
        if (normalized.isEmpty) {
          continue;
        }
        final localType = FileSystemEntity.typeSync(
          normalized,
          followLinks: true,
        );
        final baseName = _basenameSafe(normalized);
        if (localType == FileSystemEntityType.file) {
          final remotePath = _joinRemotePath(targetDir, baseName);
          addNode(<String, Object?>{
            'upload_file': <String, Object?>{
              'local_path': normalized,
              'remote_path': remotePath,
              if (chunkSize != null) 'chunk_size': chunkSize,
            },
          }, displayName: baseName.isEmpty ? normalized : baseName);
          try {
            hintedTotalBytes += File(normalized).lengthSync();
            hasTotalHint = true;
          } catch (_) {
            // Ignore local stat failure and keep transfer flow available.
          }
        } else if (localType == FileSystemEntityType.directory) {
          final scanned = _appendUploadDirectoryNodes(
            localRoot: normalized,
            targetDir: targetDir,
            chunkSize: chunkSize,
            addNode: addNode,
          );
          if (scanned != null) {
            hintedTotalBytes += scanned.totalBytes;
            hasTotalHint = true;
          } else {
            addNode(<String, Object?>{
              'upload_batch': <String, Object?>{
                'local_paths': <String>[normalized],
                'target_dir': targetDir,
                if (chunkSize != null) 'chunk_size': chunkSize,
              },
            }, displayName: baseName.isEmpty ? normalized : baseName);
          }
        } else {
          addNode(<String, Object?>{
            'upload_batch': <String, Object?>{
              'local_paths': <String>[normalized],
              'target_dir': targetDir,
              if (chunkSize != null) 'chunk_size': chunkSize,
            },
          }, displayName: baseName.isEmpty ? normalized : baseName);
        }
      }
    } else if (kind == 'download_batch') {
      final targetDir = task['target_dir']?.toString() ?? '';
      final remotePaths = _asStringList(task['remote_paths']);
      for (final remotePath in remotePaths) {
        final normalized = remotePath.trim();
        if (normalized.isEmpty) {
          continue;
        }
        addNode(<String, Object?>{
          'download_batch': <String, Object?>{
            'remote_paths': <String>[normalized],
            'target_dir': targetDir,
            if (chunkSize != null) 'chunk_size': chunkSize,
          },
        }, displayName: p.posix.basename(normalized));
      }
    }

    if (nodes.isEmpty) {
      addNode(_v2OperationFromLegacyTask(task), displayName: taskId);
      if (kind == 'upload') {
        final localPath = task['local_path']?.toString().trim() ?? '';
        if (localPath.isNotEmpty) {
          try {
            hintedTotalBytes += File(localPath).lengthSync();
            hasTotalHint = true;
          } catch (_) {
            // Ignore local stat failure and keep transfer flow available.
          }
        }
      }
    }

    final payload = <String, Object?>{
      if (taskId != null && taskId.isNotEmpty) 'name': taskId,
      'nodes': nodes,
    };
    return _NativeGraphSpec(
      graphJson: jsonEncode(payload),
      totalBytesHint: hasTotalHint ? hintedTotalBytes : null,
    );
  }

  Map<String, Object?> _v2OperationFromLegacyTask(Map<String, Object?> task) {
    final kind = task['kind']?.toString() ?? '';
    final chunkSize = _asIntNullable(task['chunk_size']);

    switch (kind) {
      case 'upload':
        return <String, Object?>{
          'upload_file': <String, Object?>{
            'local_path': task['local_path']?.toString() ?? '',
            'remote_path': task['remote_path']?.toString() ?? '',
            if (chunkSize != null) 'chunk_size': chunkSize,
          },
        };
      case 'download':
        return <String, Object?>{
          'download_file': <String, Object?>{
            'remote_path': task['remote_path']?.toString() ?? '',
            'local_path': task['local_path']?.toString() ?? '',
            if (chunkSize != null) 'chunk_size': chunkSize,
          },
        };
      case 'upload_batch':
        return <String, Object?>{
          'upload_batch': <String, Object?>{
            'local_paths': task['local_paths'] is List
                ? (task['local_paths'] as List)
                      .map((value) => value.toString())
                      .toList(growable: false)
                : const <String>[],
            'target_dir': task['target_dir']?.toString() ?? '',
            if (chunkSize != null) 'chunk_size': chunkSize,
          },
        };
      case 'download_batch':
        return <String, Object?>{
          'download_batch': <String, Object?>{
            'remote_paths': task['remote_paths'] is List
                ? (task['remote_paths'] as List)
                      .map((value) => value.toString())
                      .toList(growable: false)
                : const <String>[],
            'target_dir': task['target_dir']?.toString() ?? '',
            if (chunkSize != null) 'chunk_size': chunkSize,
          },
        };
      case 'ensure_parent_dirs':
        return <String, Object?>{
          'ensure_remote_parent': <String, Object?>{
            'remote_path': task['remote_path']?.toString() ?? '',
          },
        };
      case 'probe_remote_file_size':
        return <String, Object?>{
          'probe_remote_file_size': <String, Object?>{
            'remote_path': task['remote_path']?.toString() ?? '',
          },
        };
      default:
        throw NativeTransferException(
          'unsupported native transfer task kind: $kind',
        );
    }
  }

  List<String> _asStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  _UploadDirectoryExpansion? _appendUploadDirectoryNodes({
    required String localRoot,
    required String targetDir,
    required int? chunkSize,
    required void Function(
      Map<String, Object?> operation, {
      String? displayName,
    })
    addNode,
  }) {
    final directory = Directory(localRoot);
    if (!directory.existsSync()) {
      return null;
    }

    final rootName = _basenameSafe(localRoot);
    if (rootName.isEmpty) {
      return null;
    }
    final rootRemote = _joinRemotePath(targetDir, rootName);
    final checkpoint = <Map<String, Object?>>[];
    final checkpointNames = <String?>[];
    var totalBytes = 0;

    void stagedAdd(Map<String, Object?> operation, {String? displayName}) {
      checkpoint.add(operation);
      checkpointNames.add(displayName);
    }

    try {
      stagedAdd(<String, Object?>{
        'mkdir_remote': <String, Object?>{
          'path': rootRemote,
          'mode': 0x1ED, // 0755
        },
      }, displayName: rootName);

      void walk(Directory dir, String relativePrefix) {
        final entries = dir.listSync(followLinks: false).toList(growable: false)
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final entry in entries) {
          final name = p.basename(entry.path);
          if (name.isEmpty) {
            continue;
          }
          final relative = relativePrefix.isEmpty
              ? name
              : '$relativePrefix/$name';
          if (entry is Directory) {
            stagedAdd(<String, Object?>{
              'mkdir_remote': <String, Object?>{
                'path': _joinRemotePath(targetDir, relative),
                'mode': 0x1ED, // 0755
              },
            }, displayName: relative);
            walk(entry, relative);
            continue;
          }
          if (entry is! File) {
            continue;
          }
          stagedAdd(<String, Object?>{
            'upload_file': <String, Object?>{
              'local_path': entry.path,
              'remote_path': _joinRemotePath(targetDir, relative),
              if (chunkSize != null) 'chunk_size': chunkSize,
            },
          }, displayName: relative);
          try {
            totalBytes += entry.lengthSync();
          } catch (_) {
            // Ignore local stat failure and keep transfer flow available.
          }
        }
      }

      walk(directory, rootName);
      for (var i = 0; i < checkpoint.length; i++) {
        addNode(checkpoint[i], displayName: checkpointNames[i]);
      }
      return _UploadDirectoryExpansion(totalBytes: totalBytes);
    } catch (_) {
      return null;
    }
  }

  String _basenameSafe(String path) {
    final normalized = p.normalize(path.trim());
    final name = p.basename(normalized);
    if (name.isNotEmpty) {
      return name;
    }
    return normalized;
  }

  String _joinRemotePath(String base, String child) {
    final normalizedBase = base.replaceAll('\\', '/').trim();
    final normalizedChild = child.replaceAll('\\', '/').trim();
    if (normalizedBase.isEmpty) {
      return normalizedChild;
    }
    if (normalizedChild.isEmpty) {
      return normalizedBase;
    }
    final childClean = normalizedChild.replaceAll(RegExp(r'^/+'), '');
    if (normalizedBase == '/') {
      return '/$childClean';
    }
    final baseClean = normalizedBase.replaceAll(RegExp(r'/+$'), '');
    return '$baseClean/$childClean';
  }

  String _nextTaskId(String prefix) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$stamp';
  }

  String _sessionConfigKey(NativeTransferSessionConfig config) {
    return jsonEncode(config.toJson());
  }
}

