import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

class SingleInstance {
  static final SingleInstance _instance = SingleInstance._();
  factory SingleInstance() => _instance;
  SingleInstance._();

  final _showController = StreamController<void>.broadcast();
  ServerSocket? _server;

  Stream<void> get onShow => _showController.stream;

  Future<void> start() async {
    if (Platform.isAndroid || Platform.isIOS || kIsWeb) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = _server!.port;
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/.instance_port').writeAsString('$port');

      _server!.listen((socket) async {
        try {
          final message =
              await utf8.decodeStream(socket.timeout(const Duration(seconds: 3)));
          if (message == 'show') {
            await windowManager.show();
            await windowManager.focus();
            _showController.add(null);
          }
        } catch (_) {
          // Ignore client errors
        }
        try {
          socket.close();
        } catch (_) {}
      });
    } catch (_) {
      // Server start failures are non-fatal
    }
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  static Future<bool> notifyFirstInstance() async {
    if (Platform.isAndroid || Platform.isIOS || kIsWeb) return false;
    for (var i = 0; i < 10; i++) {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/.instance_port');
        if (!await file.exists()) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final portStr = await file.readAsString();
        final port = int.tryParse(portStr.trim());
        if (port == null || port <= 0) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 2),
        );
        socket.add(utf8.encode('show'));
        await socket.flush();
        await socket.close();
        return true;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    return false;
  }
}
