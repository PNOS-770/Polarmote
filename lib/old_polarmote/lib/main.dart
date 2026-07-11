import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app/asmote_app.dart';
import 'app/system_tray_manager.dart';
import 'shared/logging/asmote_log.dart';
import 'shared/notifications/asmote_system_notifications.dart';
import 'features/terminal/transfer/transport/native/native_transfer_bridge.dart';

RandomAccessFile? _lockFile;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AsmoteSystemNotifications.ensureInitialized();

  if (!await _lockInstance()) {
    return;
  }
  AsmoteSystemTray.addShutdownHook(() {
    _lockFile?.close();
    _lockFile = null;
  });

  unawaited(
    AsmoteSystemTray.init().catchError((error) {
      AsmoteLog.warn('system_tray', 'init failed: $error');
    }),
  );
  _logNativeTransferStartup();
  runApp(const AsmoteAppBootstrap());
}

Future<bool> _lockInstance() async {
  if (Platform.isAndroid || Platform.isIOS || kIsWeb) return true;
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/.instance_lock');
    _lockFile = await file.open(mode: FileMode.write);
    await _lockFile!.lock(FileLock.exclusive);
    return true;
  } catch (_) {
    AsmoteLog.warn('startup', 'another instance is already running');
    return false;
  }
}

void _logNativeTransferStartup() {
  try {
    final bridge = NativeTransferBridge.instance;
    if (!bridge.isSupported) {
      AsmoteLog.info('startup', 'startup: unavailable');
      return;
    }
    final buildInfo = bridge.nativeBuildInfo ?? 'unknown';
    AsmoteLog.info('startup', 'startup: available build=$buildInfo');
  } catch (error) {
    AsmoteLog.warn('startup', 'startup probe failed: $error');
  }
}
