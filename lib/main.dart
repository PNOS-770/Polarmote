import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app/Polarmote_app.dart';
import 'app/system_tray_manager.dart';
import 'shared/logging/Polarmote_log.dart';
import 'shared/notifications/Polarmote_system_notifications.dart';
import 'features/terminal/transfer/transport/native/native_transfer_bridge.dart';

RandomAccessFile? _lockFile;

Future<void> main(List<String> args) async {
  // 设置全局错误处理
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    PolarmoteLog.error(
      'flutter_error',
      'Uncaught Flutter error: ${details.exception}\n${details.stack}',
    );
  };

  // 捕获异步错误
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      
      // ✅ 初始化日志系统
      await PolarmoteLog.initialize();
      PolarmoteLog.info('startup', 'Application starting...');
      
      MediaKit.ensureInitialized();
      await PolarmoteSystemNotifications.ensureInitialized();

      if (!await _lockInstance()) {
        return;
      }
      PolarmoteSystemTray.addShutdownHook(() {
        _lockFile?.close();
        _lockFile = null;
        // 关闭日志系统
        PolarmoteLog.close();
      });

      unawaited(
        PolarmoteSystemTray.init().catchError((error) {
          PolarmoteLog.warn('system_tray', 'init failed: $error');
        }),
      );
      _logNativeTransferStartup();
      runApp(const PolarmoteAppBootstrap());
    },
    (error, stack) {
      PolarmoteLog.error(
        'uncaught_error',
        'Uncaught error: $error\n$stack',
      );
    },
  );
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
    PolarmoteLog.warn('startup', 'another instance is already running');
    return false;
  }
}

void _logNativeTransferStartup() {
  try {
    final bridge = NativeTransferBridge.instance;
    if (!bridge.isSupported) {
      PolarmoteLog.info('startup', 'startup: unavailable');
      return;
    }
    final buildInfo = bridge.nativeBuildInfo ?? 'unknown';
    PolarmoteLog.info('startup', 'startup: available build=$buildInfo');
  } catch (error) {
    PolarmoteLog.warn('startup', 'startup probe failed: $error');
  }
}

