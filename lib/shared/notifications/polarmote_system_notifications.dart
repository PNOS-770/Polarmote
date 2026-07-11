import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PolarmoteSystemNotifications {
  PolarmoteSystemNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get _isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows);

  static Future<void> ensureInitialized() async {
    if (!_isSupported || _initialized) {
      return;
    }
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        windows: WindowsInitializationSettings(
          appName: 'Polarmote',
          appUserModelId: 'com.example.Polarmote',
          guid: '6f187320-3e84-4f7a-9559-15453f50f6ec',
        ),
      );
      await _plugin.initialize(settings: settings);
      if (Platform.isAndroid) {
        final androidPlugin = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            'Polarmote_script_result',
            'Script Result',
            description: 'Script execution result notifications.',
            importance: Importance.high,
          ),
        );
      }
      _initialized = true;
    } catch (error) {
      
    }
  }

  static Future<void> showScriptResult({
    required String title,
    required String body,
    required bool failed,
  }) async {
    if (!_isSupported) {
      return;
    }
    await ensureInitialized();
    if (!_initialized) {
      return;
    }
    final id = DateTime.now().microsecondsSinceEpoch.remainder(0x7fffffff);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'Polarmote_script_result',
        'Script Result',
        channelDescription: 'Script execution result notifications.',
        importance: failed ? Importance.max : Importance.defaultImportance,
        priority: failed ? Priority.high : Priority.defaultPriority,
        category: AndroidNotificationCategory.status,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
      linux: LinuxNotificationDetails(
        icon: AssetsLinuxIcon('assets/images/app_icon_128.png'),
      ),
      windows: WindowsNotificationDetails(
        images: <WindowsImage>[
          WindowsImage(
            WindowsImage.getAssetUri('assets/images/app_icon_128.png'),
            altText: 'Polarmote',
            placement: WindowsImagePlacement.appLogoOverride,
            crop: WindowsImageCrop.circle,
          ),
        ],
      ),
    );
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (error) {
      
    }
  }
}

