part of 'terminal_main_panel.dart';

bool _matchShortcutString(KeyEvent event, String shortcut) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
  final alternatives = shortcut.split(' / ');
  for (final alt in alternatives) {
    if (_matchSingleShortcut(event, alt.trim())) return true;
  }
  return false;
}

bool _matchSingleShortcut(KeyEvent event, String combo) {
  final parts = combo.split('+').map((p) => p.trim()).toList();
  LogicalKeyboardKey? targetKey;
  var wantCtrl = false, wantAlt = false, wantShift = false, wantMeta = false;
  for (final part in parts) {
    switch (part) {
      case 'Ctrl': wantCtrl = true;
      case 'Alt': wantAlt = true;
      case 'Shift': wantShift = true;
      case 'Meta': wantMeta = true;
      default: targetKey = _parseKeyName(part);
    }
  }
  if (targetKey == null || event.logicalKey != targetKey) return false;
  final kb = HardwareKeyboard.instance;
  return kb.isControlPressed == wantCtrl &&
      kb.isAltPressed == wantAlt &&
      kb.isShiftPressed == wantShift &&
      kb.isMetaPressed == wantMeta;
}

LogicalKeyboardKey? _parseKeyName(String name) {
  return parseShortcutKeyName(name);
}

String? _checkCustomShortcut(TerminalAppState appState, KeyEvent event, String actionId) {
  for (final sb in appState.shortcutBindings) {
    if (sb.id == actionId && sb.customKeys != null) {
      return _matchShortcutString(event, sb.customKeys!) ? sb.customKeys : null;
    }
    if (sb.id == actionId) {
      return _matchShortcutString(event, sb.defaultKeys) ? sb.defaultKeys : null;
    }
  }
  return null;
}

