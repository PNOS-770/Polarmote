import 'package:flutter/foundation.dart';

class AsmoteLog {
  static void debug(String tag, String message) {
    _write(level: 'debug', tag: tag, message: message);
  }

  static void info(String tag, String message) {
    _write(level: 'info', tag: tag, message: message);
  }

  static void warn(String tag, String message) {
    _write(level: 'warn', tag: tag, message: message);
  }

  static void error(String tag, String message) {
    _write(level: 'error', tag: tag, message: message);
  }

  static void _write({
    required String level,
    required String tag,
    required String message,
  }) {
    final normalizedTag = tag.trim().isEmpty ? 'asmote' : tag.trim();
    final normalizedMessage = message.trim();
    debugPrint('[$normalizedTag][$level] $normalizedMessage');
  }
}
