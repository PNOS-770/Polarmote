import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

class CustomKeyboardListener extends StatelessWidget {
  final Widget child;

  final FocusNode focusNode;

  final bool autofocus;

  final void Function(String) onInsert;

  final void Function(String?) onComposing;

  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  const CustomKeyboardListener({
    super.key,
    required this.child,
    required this.focusNode,
    this.autofocus = false,
    required this.onInsert,
    required this.onComposing,
    required this.onKeyEvent,
  });

  String? _extractCommittedTextOnEnter(KeyEvent keyEvent) {
    if (keyEvent is! KeyDownEvent) {
      return null;
    }
    final key = keyEvent.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return null;
    }
    final raw = keyEvent.character;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    var normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    while (normalized.endsWith('\n')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent keyEvent) {
    // For IME commit-on-enter (common on desktop Chinese IME), insert committed
    // text first, then let enter be processed as terminal submit.
    final committedText = _extractCommittedTextOnEnter(keyEvent);
    if (committedText != null) {
      onInsert(committedText);
      final handled = onKeyEvent(focusNode, keyEvent);
      return handled == KeyEventResult.ignored
          ? KeyEventResult.handled
          : handled;
    }

    // First try to handle the key event directly.
    final handled = onKeyEvent(focusNode, keyEvent);
    if (handled == KeyEventResult.ignored) {
      // If it was not handled, but the key corresponds to a character,
      // insert the character.
      if (keyEvent.character != null && keyEvent.character != "") {
        onInsert(keyEvent.character!);
        return KeyEventResult.handled;
      }
    }
    return handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: _onKeyEvent,
      child: child,
    );
  }
}
