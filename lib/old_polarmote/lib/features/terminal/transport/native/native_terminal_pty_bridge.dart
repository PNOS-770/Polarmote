import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../shared/logging/asmote_log.dart';

class NativeTerminalPtyException implements Exception {
  const NativeTerminalPtyException(this.message);

  final String message;

  @override
  String toString() => 'NativeTerminalPtyException($message)';
}

class NativeTerminalPtySpawnConfig {
  const NativeTerminalPtySpawnConfig({
    required this.program,
    required this.args,
    this.cwd,
    this.env = const <String, String>{},
    this.cols = 120,
    this.rows = 34,
  });

  final String program;
  final List<String> args;
  final String? cwd;
  final Map<String, String> env;
  final int cols;
  final int rows;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'program': program,
      'args': args,
      'cwd': cwd,
      'env': env,
      'cols': cols,
      'rows': rows,
    };
  }
}

class NativeTerminalPtyBridge {
  NativeTerminalPtyBridge._();

  static final NativeTerminalPtyBridge instance = NativeTerminalPtyBridge._();

  final _NativePtyBindings? _bindings = _NativePtyBindings.tryLoad();

  bool get isSupported {
    final bindings = _bindings;
    if (bindings == null) {
      return false;
    }
    return bindings.isSupported;
  }

  String? get nativeBuildInfo => _bindings?.buildInfo;
  String? get nativeLibrarySource => _bindings?.loadedFrom;

  NativeTerminalPtySession spawn(NativeTerminalPtySpawnConfig config) {
    final bindings = _bindings;
    if (bindings == null) {
      throw const NativeTerminalPtyException('native pty core not available');
    }
    if (!bindings.isSupported) {
      throw const NativeTerminalPtyException(
        'native pty is not supported on this platform',
      );
    }
    final sessionId = bindings.spawn(jsonEncode(config.toJson()));
    if (sessionId == 0) {
      throw const NativeTerminalPtyException('failed to spawn native pty');
    }
    return NativeTerminalPtySession._(bindings: bindings, sessionId: sessionId);
  }
}

class NativeTerminalPtySession {
  NativeTerminalPtySession._({
    required _NativePtyBindings bindings,
    required int sessionId,
  }) : _bindings = bindings,
       _sessionId = sessionId {
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  static const Duration _pollInterval = Duration(milliseconds: 25);

  final _NativePtyBindings _bindings;
  final int _sessionId;
  Timer? _pollTimer;
  bool _closed = false;
  bool _polling = false;

  void Function(String text)? _onOutput;
  void Function(Uint8List bytes)? _onOutputBytes;
  void Function(int? exitCode, String? error)? onExit;
  final List<Uint8List> _pendingOutputBytes = <Uint8List>[];
  final StringBuffer _pendingOutputText = StringBuffer();

  void Function(String text)? get onOutput => _onOutput;
  set onOutput(void Function(String text)? callback) {
    _onOutput = callback;
    if (callback == null || _pendingOutputText.isEmpty) {
      return;
    }
    final buffered = _pendingOutputText.toString();
    _pendingOutputText.clear();
    callback(buffered);
  }

  void Function(Uint8List bytes)? get onOutputBytes => _onOutputBytes;
  set onOutputBytes(void Function(Uint8List bytes)? callback) {
    _onOutputBytes = callback;
    if (callback == null || _pendingOutputBytes.isEmpty) {
      return;
    }
    final buffered = List<Uint8List>.from(_pendingOutputBytes);
    _pendingOutputBytes.clear();
    for (final chunk in buffered) {
      callback(chunk);
    }
  }

  bool get isClosed => _closed;

  void write(String data) {
    if (_closed || data.isEmpty) {
      return;
    }
    final bytes = utf8.encode(data);
    final rc = _bindings.write(_sessionId, bytes);
    if (rc != 0) {
      throw NativeTerminalPtyException('native pty write failed with code $rc');
    }
  }

  void resize(int cols, int rows) {
    if (_closed) {
      return;
    }
    final safeCols = cols.clamp(1, 500).toInt();
    final safeRows = rows.clamp(1, 500).toInt();
    final rc = _bindings.resize(_sessionId, safeCols, safeRows);
    if (rc != 0) {
      throw NativeTerminalPtyException(
        'native pty resize failed with code $rc',
      );
    }
  }

  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _bindings.close(_sessionId);
  }

  void _poll() {
    if (_closed || _polling) {
      return;
    }
    _polling = true;
    try {
      final payload = _bindings.poll(_sessionId);
      if (payload.chunks.isNotEmpty) {
        final sink = StringBuffer();
        for (final chunk in payload.chunks) {
          if (chunk.isEmpty) {
            continue;
          }
          try {
            final bytes = base64Decode(chunk);
            final bytesCallback = _onOutputBytes;
            if (bytesCallback != null) {
              bytesCallback(bytes);
            } else {
              _pendingOutputBytes.add(Uint8List.fromList(bytes));
            }
            sink.write(_decodeBytes(bytes));
          } catch (_) {
            // Ignore malformed chunk from native side.
          }
        }
        final merged = sink.toString();
        if (merged.isNotEmpty) {
          final textCallback = _onOutput;
          if (textCallback != null) {
            textCallback(merged);
          } else {
            _pendingOutputText.write(merged);
          }
        }
      }
      if (payload.closed) {
        _closed = true;
        _pollTimer?.cancel();
        _pollTimer = null;
        _bindings.close(_sessionId);
        onExit?.call(payload.exitCode, payload.error);
      }
    } finally {
      _polling = false;
    }
  }

  String _decodeBytes(List<int> bytes) {
    if (Platform.isWindows) {
      try {
        return utf8.decode(bytes);
      } catch (_) {
        // Fall through to system encoding when stream still uses legacy codepage.
      }
    }
    try {
      return systemEncoding.decode(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

class _NativePtyPollPayload {
  const _NativePtyPollPayload({
    required this.chunks,
    required this.closed,
    required this.exitCode,
    required this.error,
  });

  final List<String> chunks;
  final bool closed;
  final int? exitCode;
  final String? error;

  static const empty = _NativePtyPollPayload(
    chunks: <String>[],
    closed: false,
    exitCode: null,
    error: null,
  );

  factory _NativePtyPollPayload.fromJson(Map<String, dynamic> json) {
    return _NativePtyPollPayload(
      chunks: (json['chunks'] is List)
          ? (json['chunks'] as List)
                .map((value) => value.toString())
                .toList(growable: false)
          : const <String>[],
      closed: json['closed'] == true,
      exitCode: _asIntNullable(json['exit_code']),
      error: json['error']?.toString(),
    );
  }
}

class _NativePtyBindings {
  _NativePtyBindings._(DynamicLibrary dylib, {required this.loadedFrom})
    : _isSupportedFn = dylib
          .lookupFunction<_PtySupportedNative, _PtySupportedDart>(
            'asmote_pty_is_supported',
          ),
      _spawnFn = dylib.lookupFunction<_PtySpawnNative, _PtySpawnDart>(
        'asmote_pty_spawn',
      ),
      _writeFn = dylib.lookupFunction<_PtyWriteNative, _PtyWriteDart>(
        'asmote_pty_write',
      ),
      _resizeFn = dylib.lookupFunction<_PtyResizeNative, _PtyResizeDart>(
        'asmote_pty_resize',
      ),
      _pollFn = dylib.lookupFunction<_PtyPollNative, _PtyPollDart>(
        'asmote_pty_poll',
      ),
      _closeFn = dylib.lookupFunction<_PtyCloseNative, _PtyCloseDart>(
        'asmote_pty_close',
      ),
      _freeCStringFn = dylib
          .lookupFunction<_FreeCStringNative, _FreeCStringDart>(
            'asmote_free_c_string',
          ) {
    try {
      _buildInfoFn = dylib.lookupFunction<_BuildInfoNative, _BuildInfoDart>(
        'asmote_build_info',
      );
    } catch (_) {
      _buildInfoFn = null;
    }
    _cachedBuildInfo = _queryBuildInfo();
  }

  final String loadedFrom;

  final _PtySupportedDart _isSupportedFn;
  final _PtySpawnDart _spawnFn;
  final _PtyWriteDart _writeFn;
  final _PtyResizeDart _resizeFn;
  final _PtyPollDart _pollFn;
  final _PtyCloseDart _closeFn;
  final _FreeCStringDart _freeCStringFn;
  late final _BuildInfoDart? _buildInfoFn;
  String? _cachedBuildInfo;

  bool get isSupported => _isSupportedFn() == 1;
  String? get buildInfo => _cachedBuildInfo;

  static _NativePtyBindings? tryLoad() {
    if (Platform.environment['ASMOTE_DISABLE_NATIVE_TERMINAL_PTY'] == '1') {
      return null;
    }
    final opened = _openLibrary();
    if (opened == null) {
      return null;
    }
    try {
      final bindings = _NativePtyBindings._(
        opened.library,
        loadedFrom: opened.source,
      );
      if (kDebugMode) {
        AsmoteLog.info('native_pty', 'loaded from ${bindings.loadedFrom}');
      }
      return bindings;
    } catch (_) {
      return null;
    }
  }

  int spawn(String configJson) {
    final ptr = configJson.toNativeUtf8();
    try {
      return _spawnFn(ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  int write(int sessionId, List<int> data) {
    final length = data.length;
    if (length == 0) {
      return _writeFn(sessionId, nullptr, 0);
    }
    final ptr = malloc<Uint8>(length);
    final typed = ptr.asTypedList(length);
    typed.setAll(0, data);
    try {
      return _writeFn(sessionId, ptr, length);
    } finally {
      malloc.free(ptr);
    }
  }

  int resize(int sessionId, int cols, int rows) {
    return _resizeFn(sessionId, cols, rows);
  }

  _NativePtyPollPayload poll(int sessionId) {
    final ptr = _pollFn(sessionId);
    final text = _takeOwnedString(ptr, fallback: '{}').trim();
    if (text.isEmpty) {
      return _NativePtyPollPayload.empty;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return _NativePtyPollPayload.fromJson(decoded);
      }
      if (decoded is Map) {
        return _NativePtyPollPayload.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
      return _NativePtyPollPayload.empty;
    } catch (_) {
      return _NativePtyPollPayload.empty;
    }
  }

  int close(int sessionId) {
    return _closeFn(sessionId);
  }

  String? _queryBuildInfo() {
    final fn = _buildInfoFn;
    if (fn == null) {
      return null;
    }
    final ptr = fn();
    final text = _takeOwnedString(ptr, fallback: '').trim();
    if (text.isEmpty) {
      return null;
    }
    return text;
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
      _freeCStringFn(ptr.cast<Int8>());
    }
  }

  static _OpenedLibrary? _openLibrary() {
    try {
      if (Platform.isIOS) {
        return _OpenedLibrary(
          library: DynamicLibrary.process(),
          source: '<process>',
        );
      }
    } catch (_) {
      return null;
    }

    final fileName = _libraryFileName();
    if (fileName == null) {
      return null;
    }

    final tried = <String>{};
    final candidates = <String>[..._candidatePaths(fileName), fileName];
    for (final candidate in candidates) {
      if (!tried.add(candidate)) {
        continue;
      }
      try {
        return _OpenedLibrary(
          library: DynamicLibrary.open(candidate),
          source: candidate,
        );
      } catch (_) {
        // Try next candidate.
      }
    }
    return null;
  }

  static String? _libraryFileName() {
    if (Platform.isWindows) {
      return 'asmote_native_core.dll';
    }
    if (Platform.isLinux || Platform.isAndroid) {
      return 'libasmote_native_core.so';
    }
    if (Platform.isMacOS) {
      return 'libasmote_native_core.dylib';
    }
    return null;
  }

  static Iterable<String> _candidatePaths(String fileName) sync* {
    final roots = <String>{
      Directory.current.path,
      Directory(Platform.resolvedExecutable).parent.path,
    };

    for (final root in roots) {
      yield p.join(
        root,
        'native',
        'asmote_native_core',
        'target',
        'release',
        fileName,
      );
      yield p.join(
        root,
        'native',
        'asmote_native_core',
        'target',
        'debug',
        fileName,
      );
      yield p.join(root, fileName);
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

class _OpenedLibrary {
  const _OpenedLibrary({required this.library, required this.source});

  final DynamicLibrary library;
  final String source;
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

typedef _PtySupportedNative = Int32 Function();
typedef _PtySupportedDart = int Function();

typedef _PtySpawnNative = Uint64 Function(Pointer<Utf8> configJson);
typedef _PtySpawnDart = int Function(Pointer<Utf8> configJson);

typedef _PtyWriteNative =
    Int32 Function(Uint64 sessionId, Pointer<Uint8> data, IntPtr len);
typedef _PtyWriteDart =
    int Function(int sessionId, Pointer<Uint8> data, int len);

typedef _PtyResizeNative =
    Int32 Function(Uint64 sessionId, Uint16 cols, Uint16 rows);
typedef _PtyResizeDart = int Function(int sessionId, int cols, int rows);

typedef _PtyPollNative = Pointer<Utf8> Function(Uint64 sessionId);
typedef _PtyPollDart = Pointer<Utf8> Function(int sessionId);

typedef _PtyCloseNative = Int32 Function(Uint64 sessionId);
typedef _PtyCloseDart = int Function(int sessionId);

typedef _FreeCStringNative = Void Function(Pointer<Int8> ptr);
typedef _FreeCStringDart = void Function(Pointer<Int8> ptr);

typedef _BuildInfoNative = Pointer<Utf8> Function();
typedef _BuildInfoDart = Pointer<Utf8> Function();
