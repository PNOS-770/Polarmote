import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/core.dart';

/// Handles scrolling gestures in the alternate screen buffer. In alternate
/// screen buffer, the terminal don't have a scrollback buffer, instead, the
/// scroll gestures are converted to escape sequences based on the current
/// report mode declared by the application.
class TerminalScrollGestureHandler extends StatefulWidget {
  const TerminalScrollGestureHandler({
    super.key,
    required this.terminal,
    required this.getCellOffset,
    this.simulateScroll = true,
    required this.child,
  });

  final Terminal terminal;

  /// Returns the cell offset for the pixel offset.
  final CellOffset Function(Offset) getCellOffset;

  /// Whether to simulate scroll events in the terminal when the application
  /// doesn't declare it supports mouse wheel events. true by default as it
  /// is the default behavior of most terminals.
  final bool simulateScroll;

  final Widget child;

  @override
  State<TerminalScrollGestureHandler> createState() =>
      _TerminalScrollGestureHandlerState();
}

class _TerminalScrollGestureHandlerState
    extends State<TerminalScrollGestureHandler> {
  /// Whether to intercept scroll events. True when the terminal app has
  /// requested mouse reporting (mouseMode != none), matching the behavior of
  /// Windows Terminal and other desktop terminals.
  var _interceptScroll = false;

  /// Tracks the last pointer position in local coordinates for mouse event
  /// coordinate calculation.
  var lastPointerPosition = Offset.zero;

  @override
  void initState() {
    widget.terminal.addListener(_onTerminalUpdated);
    _interceptScroll = _shouldIntercept(widget.terminal);
    super.initState();
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalUpdated);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TerminalScrollGestureHandler oldWidget) {
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalUpdated);
      widget.terminal.addListener(_onTerminalUpdated);
      _interceptScroll = _shouldIntercept(widget.terminal);
    }
    super.didUpdateWidget(oldWidget);
  }

  bool _shouldIntercept(Terminal terminal) {
    return terminal.mouseMode != MouseMode.none || terminal.isUsingAltBuffer;
  }

  void _onTerminalUpdated() {
    final shouldIntercept = _shouldIntercept(widget.terminal);
    if (_interceptScroll != shouldIntercept) {
      _interceptScroll = shouldIntercept;
      setState(() {});
    }
  }

  /// Send a single scroll event to the terminal. If [simulateScroll] is true,
  /// then if the application doesn't recognize mouse wheel events, this method
  /// will simulate scroll events by sending up/down arrow keys.
  void _sendScrollEvent(bool up) {
    final position = widget.getCellOffset(lastPointerPosition);

    final handled = widget.terminal.mouseInput(
      up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown,
      TerminalMouseButtonState.down,
      position,
    );

    if (!handled && widget.simulateScroll) {
      widget.terminal.keyInput(
        up ? TerminalKey.arrowUp : TerminalKey.arrowDown,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_interceptScroll) {
      return widget.child;
    }

    // 当应用启用了鼠标报告模式时，截获滚轮事件并转换为 SGR 鼠标序列
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          lastPointerPosition = event.localPosition;
          final scrollDelta = event.scrollDelta.dy;
          // 每次滚轮事件发送一次按键
          if (scrollDelta.abs() > 1) {
            _sendScrollEvent(scrollDelta < 0);
          }
        }
      },
      onPointerDown: (event) {
        lastPointerPosition = event.localPosition;
      },
      child: widget.child,
    );
  }
}
