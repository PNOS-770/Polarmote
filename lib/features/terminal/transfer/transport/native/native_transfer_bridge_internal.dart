part of 'native_transfer_bridge.dart';

class _NativeTaskResult {
  const _NativeTaskResult({
    required this.transferredBytes,
    required this.totalBytes,
    required this.valueU64,
  });

  final int transferredBytes;
  final int? totalBytes;
  final int? valueU64;
}

class _NativeGraphSpec {
  const _NativeGraphSpec({
    required this.graphJson,
    required this.totalBytesHint,
  });

  final String graphJson;
  final int? totalBytesHint;
}

class _UploadDirectoryExpansion {
  const _UploadDirectoryExpansion({required this.totalBytes});

  final int totalBytes;
}

class NativeSessionPoolStats {
  const NativeSessionPoolStats({
    required this.busySessions,
    required this.totalSessions,
  });

  final int busySessions;
  final int totalSessions;
}

class _NativeSessionManager {
  final Map<String, List<_NativeSessionEntry>> _entries = {};
  final Set<String> _busyEntryIds = <String>{};
  final _AsyncMutex _managerMutex = _AsyncMutex();
  int _entrySeed = 0;

  Future<T> runTask<T>({
    required _NativeBindings bindings,
    required NativeTransferSessionConfig sessionConfig,
    required Duration idleTtl,
    required Future<T> Function(_NativeSessionContext context) run,
  }) async {
    final key = jsonEncode(sessionConfig.toJson());
    final lease = await _acquireLease(
      key: key,
      configJson: key,
      idleTtl: idleTtl,
    );
    try {
      return await lease.entry.runWithSession(bindings, run);
    } finally {
      await lease.release();
    }
  }

  Future<_NativeSessionLease> _acquireLease({
    required String key,
    required String configJson,
    required Duration idleTtl,
  }) {
    return _managerMutex.protect(() async {
      final bucket = _entries.putIfAbsent(key, () => <_NativeSessionEntry>[]);
      _NativeSessionEntry? selected;
      for (final entry in bucket) {
        if (_busyEntryIds.contains(entry.id)) {
          continue;
        }
        selected = entry;
        break;
      }

      if (selected == null) {
        selected = _NativeSessionEntry(
          id: '$key#${_entrySeed++}',
          key: key,
          configJson: configJson,
          idleTtl: idleTtl,
          onEvict: _evict,
        );
        bucket.add(selected);
      }

      final chosen = selected;
      _busyEntryIds.add(chosen.id);
      return _NativeSessionLease(
        entry: chosen,
        release: () => _release(chosen),
      );
    });
  }

  Future<void> _release(_NativeSessionEntry entry) {
    return _managerMutex.protect(() async {
      _busyEntryIds.remove(entry.id);
    });
  }

  void _evict(String key, String entryId) {
    unawaited(
      _managerMutex.protect(() async {
        final bucket = _entries[key];
        if (bucket == null) {
          _busyEntryIds.remove(entryId);
          return;
        }
        bucket.removeWhere((entry) => entry.id == entryId);
        _busyEntryIds.remove(entryId);
        if (bucket.isEmpty) {
          _entries.remove(key);
        }
      }),
    );
  }

  NativeSessionPoolStats snapshotForKey(String key) {
    final bucket = _entries[key];
    if (bucket == null || bucket.isEmpty) {
      return const NativeSessionPoolStats(busySessions: 0, totalSessions: 0);
    }
    var busy = 0;
    for (final entry in bucket) {
      if (_busyEntryIds.contains(entry.id)) {
        busy += 1;
      }
    }
    return NativeSessionPoolStats(
      busySessions: busy,
      totalSessions: bucket.length,
    );
  }

  NativeSessionPoolStats snapshotGlobal() {
    var total = 0;
    for (final bucket in _entries.values) {
      total += bucket.length;
    }
    return NativeSessionPoolStats(
      busySessions: _busyEntryIds.length,
      totalSessions: total,
    );
  }
}

class _NativeSessionEntry {
  _NativeSessionEntry({
    required this.id,
    required this.key,
    required this.configJson,
    required this.idleTtl,
    required this.onEvict,
  });

  final String id;
  final String key;
  final String configJson;
  final Duration idleTtl;
  final void Function(String key, String entryId) onEvict;
  final _AsyncMutex _mutex = _AsyncMutex();
  int? _sessionId;
  int _nextEventCursor = 0;
  Timer? _idleTimer;

  Future<T> runWithSession<T>(
    _NativeBindings bindings,
    Future<T> Function(_NativeSessionContext context) run,
  ) {
    return _mutex.protect(() async {
      _cancelIdleTimer();
      final sessionId = _sessionId ??= _createSession(bindings);
      final context = _NativeSessionContext(
        sessionId: sessionId,
        nextEventCursor: _nextEventCursor,
      );
      try {
        final result = await run(context);
        _nextEventCursor = context.nextEventCursor;
        return result;
      } catch (_) {
        _destroySession(bindings);
        rethrow;
      } finally {
        _scheduleIdleCleanup(bindings);
      }
    });
  }

  int _createSession(_NativeBindings bindings) {
    final sessionId = bindings.openSession(configJson);
    if (sessionId == 0) {
      throw const NativeTransferException(
        'failed to create native transfer session',
      );
    }
    _nextEventCursor = 0;
    return sessionId;
  }

  void _destroySession(_NativeBindings bindings) {
    final sessionId = _sessionId;
    _sessionId = null;
    _nextEventCursor = 0;
    if (sessionId == null) {
      return;
    }
    bindings.closeSession(sessionId);
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _scheduleIdleCleanup(_NativeBindings bindings) {
    _cancelIdleTimer();
    _idleTimer = Timer(idleTtl, () {
      _destroySession(bindings);
      onEvict(key, id);
    });
  }
}

class _NativeSessionLease {
  const _NativeSessionLease({required this.entry, required this.release});

  final _NativeSessionEntry entry;
  final Future<void> Function() release;
}

class _NativeSessionContext {
  _NativeSessionContext({
    required this.sessionId,
    required this.nextEventCursor,
  });

  final int sessionId;
  int nextEventCursor;
}

class _AsyncMutex {
  Future<void> _tail = Future.value();

  Future<T> protect<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = completer.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
  }
}

class _NativeEvent {
  const _NativeEvent({
    required this.eventType,
    required this.taskId,
    required this.graphId,
    required this.nodeId,
    required this.transferredBytes,
    required this.totalBytes,
    required this.valueU64,
    required this.message,
  });

  final String eventType;
  final String taskId;
  final int? graphId;
  final int? nodeId;
  final int? transferredBytes;
  final int? totalBytes;
  final int? valueU64;
  final String? message;

  factory _NativeEvent.fromJson(Map<String, dynamic> json) {
    return _NativeEvent(
      eventType: json['event_type']?.toString() ?? '',
      taskId: json['task_id']?.toString() ?? '',
      graphId: _asIntNullable(json['graph_id']),
      nodeId: _asIntNullable(json['node_id']),
      transferredBytes: _asIntNullable(json['transferred_bytes']),
      totalBytes: _asIntNullable(json['total_bytes']),
      valueU64: _asIntNullable(json['value_u64']),
      message: json['message']?.toString(),
    );
  }
}

class _NativeEventPollResponse {
  const _NativeEventPollResponse({
    required this.events,
    required this.nextCursor,
  });

  final List<_NativeEvent> events;
  final int nextCursor;
}

class _NativeBindings {
  _NativeBindings._(DynamicLibrary dylib, {required this.loadedFrom}) {
    try {
      _createSession = dylib
          .lookupFunction<_CreateSessionNative, _CreateSessionDart>(
            'Polarmote_create_session',
          );
    } catch (_) {
      _createSession = null;
    }
    try {
      _destroySession = dylib
          .lookupFunction<_DestroySessionNative, _DestroySessionDart>(
            'Polarmote_destroy_session',
          );
    } catch (_) {
      _destroySession = null;
    }
    try {
      _enqueueTransfer = dylib
          .lookupFunction<_EnqueueTransferNative, _EnqueueTransferDart>(
            'Polarmote_enqueue_transfer',
          );
    } catch (_) {
      _enqueueTransfer = null;
    }
    try {
      _cancelTask = dylib.lookupFunction<_CancelTaskNative, _CancelTaskDart>(
        'Polarmote_cancel_task',
      );
    } catch (_) {
      _cancelTask = null;
    }
    try {
      _queryProgress = dylib
          .lookupFunction<_QueryProgressNative, _QueryProgressDart>(
            'Polarmote_query_progress',
          );
    } catch (_) {
      _queryProgress = null;
    }
    try {
      _pollEvents = dylib.lookupFunction<_PollEventsNative, _PollEventsDart>(
        'Polarmote_poll_events',
      );
    } catch (_) {
      _pollEvents = null;
    }

    try {
      _runtimeCreate = dylib
          .lookupFunction<_RuntimeCreateNative, _RuntimeCreateDart>(
            'Polarmote_runtime_create',
          );
    } catch (_) {
      _runtimeCreate = null;
    }
    try {
      _runtimeDestroy = dylib
          .lookupFunction<_RuntimeDestroyNative, _RuntimeDestroyDart>(
            'Polarmote_runtime_destroy',
          );
    } catch (_) {
      _runtimeDestroy = null;
    }
    try {
      _sessionOpen = dylib.lookupFunction<_SessionOpenNative, _SessionOpenDart>(
        'Polarmote_session_open',
      );
    } catch (_) {
      _sessionOpen = null;
    }
    try {
      _sessionClose = dylib
          .lookupFunction<_SessionCloseNative, _SessionCloseDart>(
            'Polarmote_session_close',
          );
    } catch (_) {
      _sessionClose = null;
    }
    try {
      _sessionSubmitGraph = dylib
          .lookupFunction<_SessionSubmitGraphNative, _SessionSubmitGraphDart>(
            'Polarmote_session_submit_graph',
          );
    } catch (_) {
      _sessionSubmitGraph = null;
    }
    try {
      _sessionCancelGraph = dylib
          .lookupFunction<_SessionCancelGraphNative, _SessionCancelGraphDart>(
            'Polarmote_session_cancel_graph',
          );
    } catch (_) {
      _sessionCancelGraph = null;
    }
    try {
      _sessionPollEventsCursor = dylib
          .lookupFunction<
            _SessionPollEventsCursorNative,
            _SessionPollEventsCursorDart
          >('Polarmote_session_poll_events_cursor');
    } catch (_) {
      _sessionPollEventsCursor = null;
    }

    _freeCString = dylib.lookupFunction<_FreeCStringNative, _FreeCStringDart>(
      'Polarmote_free_c_string',
    );
    try {
      _buildInfo = dylib.lookupFunction<_BuildInfoNative, _BuildInfoDart>(
        'Polarmote_build_info',
      );
    } catch (_) {
      _buildInfo = null;
    }

    var runtimeId = 0;
    if (_hasRuntimeSymbols) {
      try {
        runtimeId = _runtimeCreate!(nullptr.cast<Utf8>());
      } catch (_) {
        runtimeId = 0;
      }
    }
    _runtimeId = runtimeId;
    if (!supportsRuntimeApi && !supportsLegacyApi) {
      throw const NativeTransferException('native transfer symbols not found');
    }
    _cachedBuildInfo = _queryBuildInfo();
  }

  final String loadedFrom;

  late final _CreateSessionDart? _createSession;
  late final _DestroySessionDart? _destroySession;
  late final _EnqueueTransferDart? _enqueueTransfer;
  late final _CancelTaskDart? _cancelTask;
  late final _QueryProgressDart? _queryProgress;
  late final _PollEventsDart? _pollEvents;
  late final _RuntimeCreateDart? _runtimeCreate;
  late final _RuntimeDestroyDart? _runtimeDestroy;
  late final _SessionOpenDart? _sessionOpen;
  late final _SessionCloseDart? _sessionClose;
  late final _SessionSubmitGraphDart? _sessionSubmitGraph;
  late final _SessionCancelGraphDart? _sessionCancelGraph;
  late final _SessionPollEventsCursorDart? _sessionPollEventsCursor;
  late final int _runtimeId;
  late final _FreeCStringDart _freeCString;
  late final _BuildInfoDart? _buildInfo;
  String? _cachedBuildInfo;
  String? get buildInfo => _cachedBuildInfo;

  bool get supportsLegacyApi =>
      _createSession != null &&
      _destroySession != null &&
      _enqueueTransfer != null &&
      _cancelTask != null &&
      _pollEvents != null;

  bool get _hasRuntimeSymbols =>
      _runtimeCreate != null &&
      _runtimeDestroy != null &&
      _sessionOpen != null &&
      _sessionClose != null &&
      _sessionSubmitGraph != null &&
      _sessionCancelGraph != null &&
      _sessionPollEventsCursor != null;

  bool get supportsRuntimeApi => _hasRuntimeSymbols && _runtimeId > 0;

  static _NativeBindings? tryLoad() {
    if (Platform.environment['Polarmote_DISABLE_NATIVE_TRANSFER'] == '1') {
      return null;
    }
    if (Platform.isIOS) {
      try {
        final bindings = _NativeBindings._(
          DynamicLibrary.process(),
          loadedFrom: '<process>',
        );
        bindings.logLoaded();
        return bindings;
      } catch (error) {
        PolarmoteLog.warn(
          'native_transfer',
          'failed to initialize from <process>: $error',
        );
        return null;
      }
    }

    final candidates = _libraryCandidates();
    final tried = <String>{};
    Object? lastError;
    for (final candidate in candidates) {
      if (!tried.add(candidate)) {
        continue;
      }
      try {
        final library = DynamicLibrary.open(candidate);
        try {
          final bindings = _NativeBindings._(library, loadedFrom: candidate);
          bindings.logLoaded();
          return bindings;
        } catch (error) {
          lastError = error;
          PolarmoteLog.warn(
            'native_transfer',
            'loaded "$candidate" but initialization failed: $error',
          );
        }
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      PolarmoteLog.warn('native_transfer', 'failed to load native core: $lastError');
    }
    return null;
  }

  int openSession(String configJson) {
    final ptr = configJson.toNativeUtf8();
    try {
      if (supportsRuntimeApi) {
        return _sessionOpen!(_runtimeId, ptr);
      }
      final create = _createSession;
      if (create == null) {
        return 0;
      }
      return create(ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  void closeSession(int sessionId) {
    if (supportsRuntimeApi) {
      _sessionClose!(_runtimeId, sessionId);
      return;
    }
    _destroySession?.call(sessionId);
  }

  int enqueueTransfer(int sessionId, String taskJson) {
    final enqueue = _enqueueTransfer;
    if (enqueue == null) {
      return -1;
    }
    final ptr = taskJson.toNativeUtf8();
    try {
      return enqueue(sessionId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  int cancelTask(int sessionId, String taskId) {
    final cancel = _cancelTask;
    if (cancel == null) {
      return -1;
    }
    final ptr = taskId.toNativeUtf8();
    try {
      return cancel(sessionId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  Map<String, dynamic> queryProgress(int sessionId, String taskId) {
    final query = _queryProgress;
    if (query == null) {
      return const <String, dynamic>{};
    }
    final taskPtr = taskId.toNativeUtf8();
    try {
      final resultPtr = query(sessionId, taskPtr);
      final text = _takeOwnedString(resultPtr, fallback: '{}');
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    } finally {
      malloc.free(taskPtr);
    }
  }

  List<_NativeEvent> pollEvents(int sessionId) {
    final poll = _pollEvents;
    if (poll == null) {
      return const <_NativeEvent>[];
    }
    final ptr = poll(sessionId);
    final text = _takeOwnedString(ptr, fallback: '[]');
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        return const <_NativeEvent>[];
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(_NativeEvent.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <_NativeEvent>[];
    }
  }

  int submitGraph(int sessionId, String graphJson) {
    final submit = _sessionSubmitGraph;
    if (!supportsRuntimeApi || submit == null) {
      return 0;
    }
    final ptr = graphJson.toNativeUtf8();
    try {
      return submit(_runtimeId, sessionId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  int cancelGraph(int sessionId, int graphId) {
    final cancel = _sessionCancelGraph;
    if (!supportsRuntimeApi || cancel == null) {
      return -1;
    }
    return cancel(_runtimeId, sessionId, graphId);
  }

  _NativeEventPollResponse pollEventsCursor(int sessionId, int cursor) {
    final poll = _sessionPollEventsCursor;
    if (!supportsRuntimeApi || poll == null) {
      return _NativeEventPollResponse(
        events: const <_NativeEvent>[],
        nextCursor: cursor,
      );
    }
    final ptr = poll(_runtimeId, sessionId, cursor, 256);
    final text = _takeOwnedString(ptr, fallback: '{}');
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return _NativeEventPollResponse(
          events: const <_NativeEvent>[],
          nextCursor: cursor,
        );
      }
      final payload = Map<String, dynamic>.from(decoded);
      final eventsRaw = payload['events'];
      final nextCursor = _asIntNullable(payload['next_cursor']) ?? cursor;
      if (eventsRaw is! List) {
        return _NativeEventPollResponse(
          events: const <_NativeEvent>[],
          nextCursor: nextCursor,
        );
      }
      final events = eventsRaw
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .map(_NativeEvent.fromJson)
          .toList(growable: false);
      return _NativeEventPollResponse(events: events, nextCursor: nextCursor);
    } catch (_) {
      return _NativeEventPollResponse(
        events: const <_NativeEvent>[],
        nextCursor: cursor,
      );
    }
  }

  String? _queryBuildInfo() {
    final fn = _buildInfo;
    if (fn == null) {
      return null;
    }
    final ptr = fn();
    final text = _takeOwnedString(ptr, fallback: '');
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void logLoaded() {
    final sourceMeta = _sourceMeta();
    final buildMeta = buildInfo;
    final apiMeta = supportsRuntimeApi ? 'api=runtime_v2' : 'api=legacy_v1';
    if (buildMeta == null) {
      PolarmoteLog.info('native_transfer', 'loaded ($sourceMeta, $apiMeta)');
      return;
    }
    PolarmoteLog.info(
      'native_transfer',
      'loaded ($sourceMeta, $apiMeta) build=$buildMeta',
    );
  }

  String _sourceMeta() {
    final source = loadedFrom.trim();
    if (source.isEmpty) {
      return 'source=unknown';
    }
    if (source == '<process>') {
      return 'source=<process>';
    }
    try {
      final file = File(source);
      if (!file.existsSync()) {
        return 'source=$source';
      }
      final stat = file.statSync();
      return 'source=$source, mtime=${stat.modified.toIso8601String()}, size=${stat.size}';
    } catch (_) {
      return 'source=$source';
    }
  }

  String _takeOwnedString(Pointer<Utf8> ptr, {required String fallback}) {
    if (ptr.address == 0) {
      return fallback;
    }
    try {
      return ptr.toDartString();
    } catch (_) {
      return fallback;
    } finally {
      _freeCString(ptr.cast<Int8>());
    }
  }

  static Iterable<String> _libraryCandidates() sync* {
    final fileName = _libraryFileName();
    if (fileName == null) {
      return;
    }
    yield* _candidatePaths(fileName);
    yield fileName;
  }

  static String? _libraryFileName() {
    if (Platform.isWindows) {
      return 'Polarmote_native_core.dll';
    }
    if (Platform.isLinux || Platform.isAndroid) {
      return 'libPolarmote_native_core.so';
    }
    if (Platform.isMacOS) {
      return 'libPolarmote_native_core.dylib';
    }
    return null;
  }

  static Iterable<String> _candidatePaths(String fileName) sync* {
    final roots = <String>{
      Directory.current.path,
      Directory(Platform.resolvedExecutable).parent.path,
    };

    for (final root in roots) {
      yield p.join(root, fileName);
      yield p.join(
        root,
        'native',
        'Polarmote_native_core',
        'target',
        'debug',
        fileName,
      );
      yield p.join(
        root,
        'native',
        'Polarmote_native_core',
        'target',
        'release',
        fileName,
      );
    }

    if (Platform.isWindows) {
      for (final root in roots) {
        yield p.join(
          root,
          'build',
          'windows',
          'x64',
          'runner',
          'Debug',
          fileName,
        );
        yield p.join(
          root,
          'build',
          'windows',
          'x64',
          'runner',
          'Release',
          fileName,
        );
      }
    }

    if (Platform.isLinux) {
      for (final root in roots) {
        yield p.join(
          root,
          'build',
          'linux',
          'x64',
          'debug',
          'bundle',
          'lib',
          fileName,
        );
        yield p.join(
          root,
          'build',
          'linux',
          'x64',
          'release',
          'bundle',
          'lib',
          fileName,
        );
      }
    }

    if (Platform.isMacOS) {
      for (final root in roots) {
        yield p.join(
          root,
          'build',
          'macos',
          'Build',
          'Products',
          'Debug',
          fileName,
        );
        yield p.join(
          root,
          'build',
          'macos',
          'Build',
          'Products',
          'Release',
          fileName,
        );
      }
    }
  }
}

int? _asIntNullable(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

typedef _CreateSessionNative = Uint64 Function(Pointer<Utf8> configJson);
typedef _CreateSessionDart = int Function(Pointer<Utf8> configJson);

typedef _DestroySessionNative = Int32 Function(Uint64 sessionId);
typedef _DestroySessionDart = int Function(int sessionId);

typedef _EnqueueTransferNative =
    Int32 Function(Uint64 sessionId, Pointer<Utf8> taskJson);
typedef _EnqueueTransferDart =
    int Function(int sessionId, Pointer<Utf8> taskJson);

typedef _CancelTaskNative =
    Int32 Function(Uint64 sessionId, Pointer<Utf8> taskId);
typedef _CancelTaskDart = int Function(int sessionId, Pointer<Utf8> taskId);

typedef _QueryProgressNative =
    Pointer<Utf8> Function(Uint64 sessionId, Pointer<Utf8> taskId);
typedef _QueryProgressDart =
    Pointer<Utf8> Function(int sessionId, Pointer<Utf8> taskId);

typedef _PollEventsNative = Pointer<Utf8> Function(Uint64 sessionId);
typedef _PollEventsDart = Pointer<Utf8> Function(int sessionId);

typedef _RuntimeCreateNative = Uint64 Function(Pointer<Utf8> configJson);
typedef _RuntimeCreateDart = int Function(Pointer<Utf8> configJson);

typedef _RuntimeDestroyNative = Int32 Function(Uint64 runtimeId);
typedef _RuntimeDestroyDart = int Function(int runtimeId);

typedef _SessionOpenNative =
    Uint64 Function(Uint64 runtimeId, Pointer<Utf8> configJson);
typedef _SessionOpenDart =
    int Function(int runtimeId, Pointer<Utf8> configJson);

typedef _SessionCloseNative =
    Int32 Function(Uint64 runtimeId, Uint64 sessionId);
typedef _SessionCloseDart = int Function(int runtimeId, int sessionId);

typedef _SessionSubmitGraphNative =
    Uint64 Function(
      Uint64 runtimeId,
      Uint64 sessionId,
      Pointer<Utf8> graphJson,
    );
typedef _SessionSubmitGraphDart =
    int Function(int runtimeId, int sessionId, Pointer<Utf8> graphJson);

typedef _SessionCancelGraphNative =
    Int32 Function(Uint64 runtimeId, Uint64 sessionId, Uint64 graphId);
typedef _SessionCancelGraphDart =
    int Function(int runtimeId, int sessionId, int graphId);

typedef _SessionPollEventsCursorNative =
    Pointer<Utf8> Function(
      Uint64 runtimeId,
      Uint64 sessionId,
      Uint64 cursor,
      Uint32 limit,
    );
typedef _SessionPollEventsCursorDart =
    Pointer<Utf8> Function(int runtimeId, int sessionId, int cursor, int limit);

typedef _FreeCStringNative = Void Function(Pointer<Int8> ptr);
typedef _FreeCStringDart = void Function(Pointer<Int8> ptr);

typedef _BuildInfoNative = Pointer<Utf8> Function();
typedef _BuildInfoDart = Pointer<Utf8> Function();

