import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/selection_mode.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  static const _longPressAutoScrollInterval = Duration(milliseconds: 16);
  static const _dragAutoScrollInterval = Duration(milliseconds: 16);
  static const _edgeAutoScrollMinTrigger = 44.0;
  static const _edgeAutoScrollMaxTrigger = 96.0;
  static const _maxAutoScrollLinesPerTick = 4;

  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  CellAnchor? _dragAnchor;
  CellOffset? _lastDragSelectionBegin;
  CellOffset? _lastDragSelectionEnd;
  Offset? _lastDragCurrentLocalPosition;
  Timer? _dragAutoScrollTimer;

  CellAnchor? _longPressAnchorBegin;
  CellAnchor? _longPressAnchorEnd;
  Offset? _lastLongPressCurrentLocalPosition;
  CellOffset? _lastLongPressSelectionBegin;
  CellOffset? _lastLongPressSelectionEnd;
  Timer? _longPressAutoScrollTimer;
  bool _longPressSelecting = false;

  @override
  void dispose() {
    _stopDragSelectionTracking();
    _stopLongPressSelection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      child: widget.child,
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressUp: onLongPressUp,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDoubleTapDown: onDoubleTapDown,
    );
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    _stopDragSelectionTracking();
    _stopLongPressSelection();
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    _stopDragSelectionTracking();
    _stopLongPressSelection();
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _stopDragSelectionTracking();
    _lastLongPressCurrentLocalPosition = details.localPosition;
    _longPressSelecting = true;
    _captureLongPressAnchor(details.localPosition);
    _updateLongPressSelection();
    _startLongPressAutoScroll();
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _lastLongPressCurrentLocalPosition = details.localPosition;
    _updateLongPressSelection();
  }

  void onLongPressUp() {
    _stopLongPressSelection();
  }

  void onDragStart(DragStartDetails details) {
    _stopLongPressSelection();
    if (details.kind != PointerDeviceKind.mouse) {
      renderTerminal.selectWord(details.localPosition);
      return;
    }
    final terminal = terminalView.widget.terminal;
    _dragAnchor?.dispose();
    _dragAnchor = terminal.buffer.createAnchorFromOffset(
      renderTerminal.getCellOffset(details.localPosition),
    );
    _lastDragSelectionBegin = null;
    _lastDragSelectionEnd = null;
    _lastDragCurrentLocalPosition = details.localPosition;
    _startDragAutoScroll();
    _updateDragSelection(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastDragCurrentLocalPosition = details.localPosition;
    _updateDragSelection(details.localPosition);
  }

  void onDragEnd(DragEndDetails details) {
    _stopDragSelectionTracking();
  }

  void _stopDragSelectionTracking() {
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
    _dragAnchor?.dispose();
    _dragAnchor = null;
    _lastDragSelectionBegin = null;
    _lastDragSelectionEnd = null;
    _lastDragCurrentLocalPosition = null;
  }

  void _startDragAutoScroll() {
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = Timer.periodic(
      _dragAutoScrollInterval,
      (_) => _tickDragAutoScroll(),
    );
  }

  void _tickDragAutoScroll() {
    final current = _lastDragCurrentLocalPosition;
    final position = terminalView.scrollPosition;
    if (current == null || position == null || !position.hasPixels) {
      return;
    }
    final delta = _computeEdgeAutoScrollDelta(current);
    if (delta == 0) {
      return;
    }
    final nextOffset = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((nextOffset - position.pixels).abs() < 0.1) {
      return;
    }
    position.jumpTo(nextOffset);
    _updateDragSelection(current);
  }

  void _updateDragSelection(Offset localPosition) {
    final anchor = _dragAnchor;
    if (anchor == null) {
      return;
    }
    if (!anchor.attached) {
      _stopDragSelectionTracking();
      return;
    }
    final terminal = terminalView.widget.terminal;
    final from = anchor.offset;
    final to = renderTerminal.getCellOffset(localPosition);

    final isForward = to.y > from.y || (to.y == from.y && to.x >= from.x);
    final begin = isForward ? from : to;
    final end = isForward
        ? CellOffset(
            (to.x + 1).clamp(0, terminal.viewWidth),
            to.y,
          )
        : from;

    if (_lastDragSelectionBegin == begin && _lastDragSelectionEnd == end) {
      return;
    }
    _lastDragSelectionBegin = begin;
    _lastDragSelectionEnd = end;

    widget.terminalController.setSelection(
      terminal.buffer.createAnchorFromOffset(begin),
      terminal.buffer.createAnchorFromOffset(end),
    );
  }

  void _startLongPressAutoScroll() {
    _longPressAutoScrollTimer?.cancel();
    _longPressAutoScrollTimer = Timer.periodic(
      _longPressAutoScrollInterval,
      (_) => _tickLongPressAutoScroll(),
    );
  }

  void _stopLongPressSelection() {
    _longPressAutoScrollTimer?.cancel();
    _longPressAutoScrollTimer = null;
    _longPressAnchorBegin?.dispose();
    _longPressAnchorEnd?.dispose();
    _longPressAnchorBegin = null;
    _longPressAnchorEnd = null;
    _lastLongPressCurrentLocalPosition = null;
    _lastLongPressSelectionBegin = null;
    _lastLongPressSelectionEnd = null;
    _longPressSelecting = false;
  }

  void _tickLongPressAutoScroll() {
    if (!_longPressSelecting) {
      _stopLongPressSelection();
      return;
    }
    final current = _lastLongPressCurrentLocalPosition;
    final position = terminalView.scrollPosition;
    if (current == null || position == null || !position.hasPixels) {
      return;
    }
    final delta = _computeEdgeAutoScrollDelta(current);
    if (delta == 0) {
      return;
    }
    final nextOffset = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((nextOffset - position.pixels).abs() < 0.1) {
      return;
    }
    position.jumpTo(nextOffset);
    _updateLongPressSelection();
  }

  double _computeEdgeAutoScrollDelta(Offset current) {
    final height = renderTerminal.size.height;
    final lineHeight = renderTerminal.lineHeight;
    if (height <= 0 || lineHeight <= 0) {
      return 0;
    }
    final trigger = (height * 0.14).clamp(
      _edgeAutoScrollMinTrigger,
      _edgeAutoScrollMaxTrigger,
    );
    if (current.dy < trigger) {
      final ratio = ((trigger - current.dy) / trigger).clamp(0.0, 1.0);
      final accelerated = ratio * ratio;
      final lines = (1 + (accelerated * (_maxAutoScrollLinesPerTick - 1)))
          .round()
          .clamp(1, _maxAutoScrollLinesPerTick);
      return -(lines * lineHeight);
    }
    if (current.dy > height - trigger) {
      final ratio = ((current.dy - (height - trigger)) / trigger).clamp(
        0.0,
        1.0,
      );
      final accelerated = ratio * ratio;
      final lines = (1 + (accelerated * (_maxAutoScrollLinesPerTick - 1)))
          .round()
          .clamp(1, _maxAutoScrollLinesPerTick);
      return lines * lineHeight;
    }
    return 0;
  }

  void _captureLongPressAnchor(Offset localPosition) {
    _longPressAnchorBegin?.dispose();
    _longPressAnchorEnd?.dispose();
    final anchor = renderTerminal.getCellOffset(localPosition);
    final anchorBoundary = _resolveWordBoundary(anchor);
    final terminal = terminalView.widget.terminal;
    _longPressAnchorBegin = terminal.buffer.createAnchorFromOffset(
      anchorBoundary.begin,
    );
    _longPressAnchorEnd = terminal.buffer.createAnchorFromOffset(
      anchorBoundary.end,
    );
    _lastLongPressSelectionBegin = null;
    _lastLongPressSelectionEnd = null;
  }

  BufferRangeLine _resolveWordBoundary(CellOffset offset) {
    final terminal = terminalView.widget.terminal;
    final boundary = terminal.buffer.getWordBoundary(offset);
    if (boundary != null) {
      return boundary;
    }
    final endX =
        offset.x + 1 > terminal.viewWidth ? terminal.viewWidth : offset.x + 1;
    return BufferRangeLine(
      CellOffset(offset.x, offset.y),
      CellOffset(endX, offset.y),
    );
  }

  void _updateLongPressSelection() {
    final current = _lastLongPressCurrentLocalPosition;
    final anchorBegin = _longPressAnchorBegin;
    final anchorEnd = _longPressAnchorEnd;
    if (current == null || anchorBegin == null || anchorEnd == null) {
      return;
    }
    if (!anchorBegin.attached || !anchorEnd.attached) {
      _stopLongPressSelection();
      return;
    }
    final terminal = terminalView.widget.terminal;
    final anchorRange =
        BufferRangeLine(anchorBegin.offset, anchorEnd.offset).normalized;
    final currentCell = renderTerminal.getCellOffset(current);
    final currentBoundary = _resolveWordBoundary(currentCell);
    var range = anchorRange.merge(currentBoundary).normalized;
    if (range.begin.y != range.end.y) {
      if (currentBoundary.begin.y > anchorRange.end.y) {
        range = BufferRangeLine(
          range.begin,
          CellOffset(terminal.viewWidth, range.end.y),
        );
      } else if (currentBoundary.end.y < anchorRange.begin.y) {
        range = BufferRangeLine(
          CellOffset(0, range.begin.y),
          range.end,
        );
      }
    }
    if (_lastLongPressSelectionBegin == range.begin &&
        _lastLongPressSelectionEnd == range.end) {
      return;
    }
    _lastLongPressSelectionBegin = range.begin;
    _lastLongPressSelectionEnd = range.end;
    widget.terminalController.setSelection(
      terminal.buffer.createAnchorFromOffset(range.begin),
      terminal.buffer.createAnchorFromOffset(range.end),
      mode: SelectionMode.line,
    );
  }
}
