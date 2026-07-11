import 'dart:io';

import 'package:flutter/services.dart';

class AndroidTransferForegroundBridge {
  AndroidTransferForegroundBridge._();

  static const MethodChannel _channel = MethodChannel(
    'asmote/transfer_foreground',
  );

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

  static Future<void> updateProgress({
    required String title,
    required int progressPermille,
    required bool indeterminate,
    required int activeCount,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    final normalizedPermille = progressPermille.clamp(0, 1000);
    final normalizedPercent = (normalizedPermille / 10).round().clamp(0, 100);
    await _channel.invokeMethod<void>('updateProgress', {
      'title': title.trim(),
      'progressPermille': normalizedPermille,
      // Keep percent for compatibility with older native builds.
      'progressPercent': normalizedPercent,
      'indeterminate': indeterminate,
      'activeCount': activeCount < 0 ? 0 : activeCount,
    });
  }
}
