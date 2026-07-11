import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app/Polarmote_app.dart';
import 'app/system_tray_manager.dart';
import 'shared/notifications/Polarmote_system_notifications.dart';

RandomAccessFile? _lockFile;

Future<void> main(List<String> args) async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      MediaKit.ensureInitialized();
      await PolarmoteSystemNotifications.ensureInitialized();

      if (!await _lockInstance()) {
        return;
      }
      PolarmoteSystemTray.addShutdownHook(() {
        _lockFile?.close();
        _lockFile = null;
      });

      unawaited(
        PolarmoteSystemTray.init().catchError((_) {}),
      );
      runApp(const PolarmoteAppBootstrap());
    },
    (error, stack) {},
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
    return false;
  }
}
