import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/constants/app_string.dart';
typedef ShutdownHook = void Function();

class PolarmoteSystemTray {
  PolarmoteSystemTray._();

  static final SystemTray _tray = SystemTray();
  static bool _initialized = false;
  static final List<ShutdownHook> _shutdownHooks = [];

  static void addShutdownHook(ShutdownHook hook) {
    _shutdownHooks.add(hook);
  }

  static Future<void> init() async {
    if (!_isDesktop) return;
    if (_initialized) return;

    // --- Step 1: window manager setup (always, even if tray fails) ---
    try {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow();
      await windowManager.setMinimumSize(const Size(800, 500));
      
    } catch (e) {
      
      return;
    }

    // --- Step 2: tray icon ---
    try {
      final iconData = await rootBundle.load('assets/images/app_icon.ico');
      final tempDir = Directory.systemTemp;
      final now = DateTime.now().millisecondsSinceEpoch;
      final tempIcon = File('${tempDir.path}${Platform.pathSeparator}plrmote_$now.ico');

      try {
        await for (final entry in tempDir.list()) {
          if (entry is File && entry.path.endsWith('.ico') &&
              (entry.path.contains('plrmote_') || entry.path.contains('Polarmote_tray_icon'))) {
            await entry.delete();
          }
        }
      } catch (_) {}
      await tempIcon.writeAsBytes(iconData.buffer.asUint8List(), flush: true);
      

      const trayChannel = MethodChannel('flutter/system_tray');
      final ok = await trayChannel.invokeMethod<bool>('InitSystemTray', <String, String>{
        'title': 'Polarmote',
        'iconpath': tempIcon.path,
        'tooltip': 'Polarmote',
      });
      

      // Force a NIM_MODIFY by updating tooltip — this can re-register the
      // icon's callback HWND and fix event delivery on some Windows builds.
      if (ok == true) {
        await _tray.setSystemTrayInfo(toolTip: 'Polarmote');
        
      }
    } catch (_) {
      // System tray init errors are non-fatal
    }

    // --- Step 3: event handler + menu ---
    try {
      _tray.registerSystemTrayEventHandler((eventName) {
        
        try {
          if (eventName == 'rightMouseUp' || eventName == 'rightMouseDown') {
            
            _tray.popUpContextMenu();
          } else if (eventName == 'leftMouseUp' ||
              eventName == 'leftMouseDblClk') {
            windowManager.show();
            windowManager.focus();
          }
        } catch (_) {
          // System tray event errors are non-fatal
        }
      });
      

      final locale = Platform.localeName.startsWith('zh') ? 'zh' : 'en';
      await _buildMenu(locale);
      

      _initialized = true;
    } catch (_) {
      // System tray setup errors are non-fatal
    }
  }

  static Future<void> _buildMenu(String locale) async {
    await _tray.setContextMenu([
      MenuItem(
        label: AppStrings.values.trayShow.resolve(locale),
        onClicked: () async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuItem(
        label: AppStrings.values.trayHide.resolve(locale),
        onClicked: () async {
          await windowManager.hide();
        },
      ),
      MenuSeparator(),
      MenuItem(
        label: AppStrings.values.trayQuit.resolve(locale),
        onClicked: () {
          for (final hook in _shutdownHooks) {
            hook();
          }
          _shutdownHooks.clear();
          windowManager.destroy();
          exit(0);
        },
      ),
    ]);
  }

  static void dispose() {
    if (!_initialized) return;
    _tray.setSystemTrayInfo(toolTip: '');
  }

  static bool get _isDesktop {
    return !Platform.isAndroid && !Platform.isIOS && !kIsWeb;
  }
}



