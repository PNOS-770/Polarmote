import 'dart:io';

import 'package:flutter/services.dart';

class AndroidSshForegroundBridge {
  AndroidSshForegroundBridge._();

  static const MethodChannel _channel = MethodChannel('asmote/ssh_foreground');

  static Future<void> start({String? title}) async {
    if (!Platform.isAndroid) {
      return;
    }
    final normalizedTitle = title?.trim() ?? '';
    await _channel.invokeMethod<void>('start', {
      if (normalizedTitle.isNotEmpty) 'title': normalizedTitle,
    });
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('stop');
  }

  static Future<void> updateState({
    required String title,
    required int activeCount,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('updateState', {
      'title': title.trim(),
      'activeCount': activeCount < 0 ? 0 : activeCount,
    });
  }
}
