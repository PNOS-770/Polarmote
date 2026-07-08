import 'package:flutter/foundation.dart';

/// Parses OSC (Operating System Command) escape sequences in terminal output.
///
/// Currently supports:
///   - OSC 133 (FinalTerm/Shell Integration): prompt markers, command boundaries
///
/// Future: OSC 633 (iTerm2), OSC 7 (current directory), OSC 9 (notification)
class OscParser {
  static final RegExp _osc133RegExp = RegExp(
    r'\x1B\]133;(A|B|C(?:;(-?\d+))?|D)(?:\x07|\x1B\\)',
  );

  bool shellIntegrationActive = false;
  int? lastExitCode;

  final List<void Function(int?)> _commandFinishedListeners = [];
  final List<VoidCallback> _promptListeners = [];
  final List<VoidCallback> _outputStartListeners = [];

  void addCommandFinishedListener(void Function(int?) listener) {
    _commandFinishedListeners.add(listener);
  }

  void removeCommandFinishedListener(void Function(int?) listener) {
    _commandFinishedListeners.remove(listener);
  }

  void addPromptListener(VoidCallback listener) {
    _promptListeners.add(listener);
  }

  void removePromptListener(VoidCallback listener) {
    _promptListeners.remove(listener);
  }

  void addOutputStartListener(VoidCallback listener) {
    _outputStartListeners.add(listener);
  }

  void removeOutputStartListener(VoidCallback listener) {
    _outputStartListeners.remove(listener);
  }

  /// Parses and strips known OSC sequences from [text].
  /// Returns cleaned text safe for terminal display.
  String process(String text) {
    if (!text.contains('\x1B]')) return text;
    text = _processOsc133(text);
    return text;
  }

  String _processOsc133(String text) {
    if (!text.contains('\x1B]133;')) return text;
    return text.replaceAllMapped(_osc133RegExp, (match) {
      shellIntegrationActive = true;
      final type = match.group(1);
      switch (type) {
        case 'A':
          for (final fn in _promptListeners) { fn(); }
        case 'B':
          for (final fn in _outputStartListeners) { fn(); }
        case 'C':
          lastExitCode = int.tryParse(match.group(2) ?? '');
          for (final fn in _commandFinishedListeners) { fn(lastExitCode); }
      }
      return '';
    });
  }
}

