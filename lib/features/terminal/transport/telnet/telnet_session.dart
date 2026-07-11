import 'dart:async';
import 'dart:io';
import 'dart:typed_data';


import '../../models/terminal_session.dart';

class TelnetSession {
  TelnetSession({
    required this.session,
    required this.host,
    required this.port,
  });

  final TerminalSession session;
  final String host;
  final int port;

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  bool _closed = false;
  final _readyCompleter = Completer<void>();

  Future<void> get ready => _readyCompleter.future;

  Future<void> connect() async {
    try {
      
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 15),
      );
      _socket!.done.then((_) => _handleClose());
      _subscription = _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _handleClose,
      );
      _readyCompleter.complete();
      
    } catch (e) {
      _readyCompleter.completeError(e);
      rethrow;
    }
  }

  void _onData(Uint8List data) {
    if (_closed) return;
    session.terminal.write(_decode(data));
  }

  void _onError(Object error) {
    if (_closed) return;
    
  }

  void _handleClose() {
    if (_closed) return;
    _closed = true;
    
    session.onSessionClosed?.call();
  }

  void send(List<int> bytes) {
    if (_closed || _socket == null) return;
    try {
      _socket!.add(bytes);
    } catch (_) {}
  }

  void resize(int width, int height) {
    if (_closed || _socket == null) return;
    
    try {
      final buf = BytesBuilder();
      buf.add([0xFF, 0xFA, 0x1F]);
      buf.add([
        (width >> 8) & 0xFF,
        width & 0xFF,
        (height >> 8) & 0xFF,
        height & 0xFF,
      ]);
      buf.add([0xFF, 0xF0]);
      _socket!.add(buf.toBytes());
    } catch (_) {}
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    
    try {
      await _subscription?.cancel();
      _subscription = null;
      await _socket?.close();
      _socket = null;
    } catch (_) {}
  }

  String _decode(List<int> bytes) {
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}



