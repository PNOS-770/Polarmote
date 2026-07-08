part of 'terminal_app_state_port_forward.dart';

class _ActivePortForwardRuntime {
  PortForwardRuntimeStatus status = PortForwardRuntimeStatus.stopped;
  PortForwardType type = PortForwardType.local;
  int? boundPort;
  String? lastError;
  String? diagnosticHint;
  String? serverAddress;
  DateTime? startedAt;
  DateTime? lastActivityAt;
  DateTime? lastHealthCheckAt;
  int lifecycleToken = 0;
  SSHClient? client;
  final List<SSHClient> auxiliaryClients = <SSHClient>[];
  ServerSocket? server;
  StreamSubscription<Socket>? serverSubscription;
  SSHRemoteForward? remoteForward;
  StreamSubscription<SSHForwardChannel>? remoteForwardSubscription;
  final Set<Socket> activeLocalSockets = <Socket>{};
  final Set<SSHForwardChannel> activeChannels = <SSHForwardChannel>{};

  Future<void> dispose() async {
    await serverSubscription?.cancel();
    serverSubscription = null;
    await remoteForwardSubscription?.cancel();
    remoteForwardSubscription = null;
    try { remoteForward?.close(); } catch (e) { PolarmoteLog.error('terminal_app_state_port_forward_types', '$e'); }
    remoteForward = null;
    try { await server?.close(); } catch (e) { PolarmoteLog.error('terminal_app_state_port_forward_types', '$e'); }
    server = null;
    for (final socket in activeLocalSockets.toList(growable: false)) {
      socket.destroy();
    }
    activeLocalSockets.clear();
    for (final channel in activeChannels.toList(growable: false)) {
      try { channel.destroy(); } catch (e) { PolarmoteLog.error('terminal_app_state_port_forward_types', '$e'); }
    }
    activeChannels.clear();
    try { client?.close(); } catch (e) { PolarmoteLog.error('terminal_app_state_port_forward_types', '$e'); }
    client = null;
    for (final auxiliary in auxiliaryClients.reversed) {
      try { auxiliary.close(); } catch (e) { PolarmoteLog.error('terminal_app_state_port_forward_types', '$e'); }
    }
    auxiliaryClients.clear();
  }
}

class _SocketChunkReader {
  _SocketChunkReader(this._iterator);

  final StreamIterator<List<int>> _iterator;
  final ListQueue<int> _buffer = ListQueue<int>();

  Future<List<int>> readExact(int length) async {
    if (length < 0) throw ArgumentError.value(length, 'length');
    if (length == 0) return const <int>[];
    while (_buffer.length < length) {
      final moved = await _iterator.moveNext();
      if (!moved) throw const SocketException('socket closed during SOCKS handshake');
      _buffer.addAll(_iterator.current);
    }
    final result = List<int>.filled(length, 0, growable: false);
    for (var i = 0; i < length; i++) {
      result[i] = _buffer.removeFirst();
    }
    return result;
  }

  Future<void> pumpToSink(StreamSink<List<int>> sink) async {
    if (_buffer.isNotEmpty) {
      sink.add(_buffer.toList(growable: false));
      _buffer.clear();
    }
    while (await _iterator.moveNext()) {
      final chunk = _iterator.current;
      if (chunk.isNotEmpty) sink.add(chunk);
    }
  }

  Future<void> cancel() async {
    await _iterator.cancel();
  }
}



