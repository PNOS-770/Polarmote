import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/range.dart';

import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';
import 'package:xterm/src/ui/gesture/gesture_handler.dart';
import 'package:xterm/src/ui/input_map.dart';
import 'package:xterm/src/ui/keyboard_listener.dart';
import 'package:xterm/src/ui/keyboard_visibility.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/scroll_handler.dart';
import 'package:xterm/src/ui/shortcut/actions.dart';
import 'package:xterm/src/ui/shortcut/shortcuts.dart';
import 'package:xterm/src/ui/selection_mode.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/terminal_theme.dart';
import 'package:xterm/src/ui/themes.dart';

enum _SelectionHandleType { start, end }

class _SelectionHandleAnchors {
  const _SelectionHandleAnchors({
    required this.start,
    required this.end,
  });

  final Offset start;
  final Offset end;
}

class TerminalView extends StatefulWidget {
  const TerminalView(
    this.terminal, {
    super.key,
    this.controller,
    this.theme = TerminalThemes.defaultTheme,
    this.textStyle = const TerminalStyle(),
    this.textScaler,
    this.padding,
    this.scrollController,
    this.autoResize = true,
    this.backgroundOpacity = 1,
    this.focusNode,
    this.autofocus = false,
    this.onTapUp,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.mouseCursor = SystemMouseCursors.text,
    this.keyboardType = TextInputType.emailAddress,
    this.keyboardAppearance = Brightness.dark,
    this.cursorType = TerminalCursorType.block,
    this.alwaysShowCursor = false,
    this.deleteDetection = false,
    this.shortcuts,
    this.onKeyEvent,
    this.readOnly = false,
    this.hardwareKeyboardOnly = false,
    this.simulateScroll = true,
    this.mobileSelectionToolbarEnabled = false,
    this.selectionToolbarBuilder,
  });

  /// The underlying terminal that this widget renders.
  final Terminal terminal;

  final TerminalController? controller;

  /// The theme to use for this terminal.
  final TerminalTheme theme;

  /// The style to use for painting characters.
  final TerminalStyle textStyle;

  final TextScaler? textScaler;

  /// Padding around the inner [Scrollable] widget.
  final EdgeInsets? padding;

  /// Scroll controller for the inner [Scrollable] widget.
  final ScrollController? scrollController;

  /// Should this widget automatically notify the underlying terminal when its
  /// size changes. [true] by default.
  final bool autoResize;

  /// Opacity of the terminal background. Set to 0 to make the terminal
  /// background transparent.
  final double backgroundOpacity;

  /// An optional focus node to use as the focus node for this widget.
  final FocusNode? focusNode;

  /// True if this widget will be selected as the initial focus when no other
  /// node in its scope is currently focused.
  final bool autofocus;

  /// Callback for when the user taps on the terminal.
  final void Function(TapUpDetails, CellOffset)? onTapUp;

  /// Function called when the user taps on the terminal with a secondary
  /// button.
  final void Function(TapDownDetails, CellOffset)? onSecondaryTapDown;

  /// Function called when the user stops holding down a secondary button.
  final void Function(TapUpDetails, CellOffset)? onSecondaryTapUp;

  /// The mouse cursor for mouse pointers that are hovering over the terminal.
  /// [SystemMouseCursors.text] by default.
  final MouseCursor mouseCursor;

  /// The type of information for which to optimize the text input control.
  /// [TextInputType.emailAddress] by default.
  final TextInputType keyboardType;

  /// The appearance of the keyboard. [Brightness.dark] by default.
  ///
  /// This setting is only honored on iOS devices.
  final Brightness keyboardAppearance;

  /// The type of cursor to use. [TerminalCursorType.block] by default.
  final TerminalCursorType cursorType;

  /// Whether to always show the cursor. This is useful for debugging.
  /// [false] by default.
  final bool alwaysShowCursor;

  /// Workaround to detect delete key for platforms and IMEs that does not
  /// emit hardware delete event. Prefered on mobile platforms. [false] by
  /// default.
  final bool deleteDetection;

  /// Shortcuts for this terminal. This has higher priority than input handler
  /// of the terminal If not provided, [defaultTerminalShortcuts] will be used.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Keyboard event handler of the terminal. This has higher priority than
  /// [shortcuts] and input handler of the terminal.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// True if no input should send to the terminal.
  final bool readOnly;

  /// True if only hardware keyboard events should be used as input. This will
  /// also prevent any on-screen keyboard to be shown.
  final bool hardwareKeyboardOnly;

  /// If true, when the terminal is in alternate buffer (for example running
  /// vim, man, etc), if the application does not declare that it can handle
  /// scrolling, the terminal will simulate scrolling by sending up/down arrow
  /// keys to the application. This is standard behavior for most terminal
  /// emulators. True by default.
  final bool simulateScroll;

  /// Enables a mobile-only selection toolbar with copy/paste/select-all.
  ///
  /// This is only effective on Android/iOS and ignored on desktop/web.
  final bool mobileSelectionToolbarEnabled;

  /// Optional builder for custom selection toolbar button items.
  /// If provided, this overrides the default copy/paste/select-all items.
  final List<ContextMenuButtonItem> Function(BuildContext context, bool hasSelectionText)? selectionToolbarBuilder;

  @override
  State<TerminalView> createState() => TerminalViewState();
}

class TerminalViewState extends State<TerminalView> {
  static const double _selectionHandleTouchRadius = 26;
  static const double _selectionHandleDropSize = 20;
  static const double _selectionHandleOutwardOffset = 2;
  static const _selectionHandleAutoScrollInterval = Duration(milliseconds: 16);
  static const _selectionHandleAutoScrollMinTrigger = 44.0;
  static const _selectionHandleAutoScrollMaxTrigger = 96.0;
  static const _selectionHandleMaxAutoScrollLinesPerTick = 4;

  late FocusNode _focusNode;

  late final ShortcutManager _shortcutManager;

  final _customTextEditKey = GlobalKey<CustomTextEditState>();

  final _scrollableKey = GlobalKey<ScrollableState>();

  final _viewportKey = GlobalKey();

  String? _composingText;

  late TerminalController _controller;

  late ScrollController _scrollController;

  OverlayEntry? _selectionToolbarOverlayEntry;
  TextSelectionToolbarAnchors? _selectionToolbarAnchors;
  OverlayEntry? _selectionHandleOverlayEntry;
  _SelectionHandleAnchors? _selectionHandleAnchors;
  bool _selectionHandleDragging = false;
  _SelectionHandleType? _activeSelectionHandleType;
  Offset? _lastSelectionHandleGlobalPosition;
  Offset? _selectionHandlePointerOffset;
  Timer? _selectionHandleAutoScrollTimer;
  bool _selectionToolbarUpdateScheduled = false;

  RenderTerminal get renderTerminal =>
      _viewportKey.currentContext!.findRenderObject() as RenderTerminal;

  @override
  void initState() {
    _focusNode = widget.focusNode ?? FocusNode();
    _controller = widget.controller ?? TerminalController();
    _scrollController = widget.scrollController ?? ScrollController();
    widget.terminal.addListener(_onTerminalStateChanged);
    _focusNode.addListener(_onFocusStateChanged);
    _controller.addListener(_onSelectionChanged);
    _scrollController.addListener(_onScrollPositionChanged);
    _shortcutManager = ShortcutManager(
      shortcuts: widget.shortcuts ?? defaultTerminalShortcuts,
    );
    super.initState();
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalStateChanged);
      widget.terminal.addListener(_onTerminalStateChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_onFocusStateChanged);
      if (oldWidget.focusNode == null) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusStateChanged);
    }
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onSelectionChanged);
      if (oldWidget.controller == null) {
        _controller.dispose();
      }
      _controller = widget.controller ?? TerminalController();
      _controller.addListener(_onSelectionChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      _scrollController.removeListener(_onScrollPositionChanged);
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = widget.scrollController ?? ScrollController();
      _scrollController.addListener(_onScrollPositionChanged);
    }
    _shortcutManager.shortcuts = widget.shortcuts ?? defaultTerminalShortcuts;
    if (!_isMobileSelectionToolbarEnabled) {
      _hideSelectionToolbar();
    } else {
      _scheduleSelectionToolbarUpdate();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalStateChanged);
    _focusNode.removeListener(_onFocusStateChanged);
    _controller.removeListener(_onSelectionChanged);
    _scrollController.removeListener(_onScrollPositionChanged);
    _stopSelectionHandleAutoScroll();
    _hideSelectionToolbar();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _shortcutManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Scrollable(
      key: _scrollableKey,
      controller: _scrollController,
      viewportBuilder: (context, offset) {
        return _TerminalView(
          key: _viewportKey,
          terminal: widget.terminal,
          controller: _controller,
          offset: offset,
          padding: MediaQuery.of(context).padding,
          autoResize: widget.autoResize,
          textStyle: widget.textStyle,
          textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
          theme: widget.theme,
          focusNode: _focusNode,
          cursorType: widget.cursorType,
          alwaysShowCursor: widget.alwaysShowCursor,
          onEditableRect: _onEditableRect,
          composingText: _composingText,
        );
      },
    );

    child = TerminalScrollGestureHandler(
      terminal: widget.terminal,
      simulateScroll: widget.simulateScroll,
      getCellOffset: (offset) => renderTerminal.getCellOffset(offset),
      child: child,
    );

    if (!widget.hardwareKeyboardOnly) {
      child = CustomTextEdit(
        key: _customTextEditKey,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        inputType: widget.keyboardType,
        keyboardAppearance: widget.keyboardAppearance,
        deleteDetection: widget.deleteDetection,
        onInsert: _onInsert,
        onDelete: () {
          _scrollToBottom();
          widget.terminal.keyInput(TerminalKey.backspace);
        },
        onComposing: _onComposing,
        onAction: (action) {
          _scrollToBottom();
          if (_shouldSendEnterForAction(action)) {
            widget.terminal.keyInput(TerminalKey.enter);
          }
        },
        onKeyEvent: _handleKeyEvent,
        readOnly: widget.readOnly,
        child: child,
      );
    } else if (!widget.readOnly) {
      // Only listen for key input from a hardware keyboard.
      child = CustomKeyboardListener(
        child: child,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onInsert: _onInsert,
        onComposing: _onComposing,
        onKeyEvent: _handleKeyEvent,
      );
    }

    child = TerminalActions(
      terminal: widget.terminal,
      controller: _controller,
      child: child,
    );

    child = KeyboardVisibilty(
      onKeyboardShow: _onKeyboardShow,
      child: child,
    );

    child = TerminalGestureHandler(
      terminalView: this,
      terminalController: _controller,
      onTapUp: _onTapUp,
      onTapDown: _onTapDown,
      onSecondaryTapDown:
          widget.onSecondaryTapDown != null ? _onSecondaryTapDown : null,
      onSecondaryTapUp:
          widget.onSecondaryTapUp != null ? _onSecondaryTapUp : null,
      readOnly: widget.readOnly,
      child: child,
    );

    child = MouseRegion(
      cursor: widget.mouseCursor,
      child: child,
    );

    child = Container(
      color:
          widget.theme.background.withValues(alpha: widget.backgroundOpacity),
      padding: widget.padding,
      child: child,
    );

    return child;
  }

  void requestKeyboard() {
    _customTextEditKey.currentState?.requestKeyboard();
  }

  void closeKeyboard() {
    _customTextEditKey.currentState?.closeKeyboard();
  }

  Rect get cursorRect {
    return renderTerminal.cursorOffset & renderTerminal.cellSize;
  }

  Rect get globalCursorRect {
    return renderTerminal.localToGlobal(renderTerminal.cursorOffset) &
        renderTerminal.cellSize;
  }

  ScrollPosition? get scrollPosition => _scrollableKey.currentState?.position;

  void _onTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onTapUp?.call(details, offset);
  }

  void _onTapDown(_) {
    _hideSelectionToolbar();
    if (_controller.selection != null) {
      _controller.clearSelection();
    } else {
      if (!widget.hardwareKeyboardOnly) {
        _customTextEditKey.currentState?.requestKeyboard();
      } else {
        _focusNode.requestFocus();
      }
    }
  }

  void _onSecondaryTapDown(TapDownDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapDown?.call(details, offset);
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapUp?.call(details, offset);
  }

  bool get hasInputConnection {
    return _customTextEditKey.currentState?.hasInputConnection == true;
  }

  void _onInsert(String text) {
    if (text.isEmpty) {
      return;
    }
    _hideSelectionToolbar();

    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final segments = normalized.split('\n');

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.isNotEmpty) {
        _insertTextSegment(segment);
      }
      if (i < segments.length - 1) {
        widget.terminal.keyInput(TerminalKey.enter);
      }
    }

    _scrollToBottom();
  }

  void _insertTextSegment(String text) {
    final key = charToTerminalKey(text);

    // On mobile platforms there is no guarantee that virtual keyboard will
    // generate hardware key events. So we need first try to send the key
    // as a hardware key event. If it fails, then we send it as a text input.
    final consumed = key == null ? false : widget.terminal.keyInput(key);

    if (!consumed) {
      widget.terminal.textInput(text);
    }
  }

  bool _shouldSendEnterForAction(TextInputAction action) {
    return switch (action) {
      TextInputAction.done ||
      TextInputAction.go ||
      TextInputAction.send ||
      TextInputAction.search ||
      TextInputAction.newline =>
        true,
      _ => false,
    };
  }

  void _onComposing(String? text) {
    setState(() => _composingText = text);
  }

  KeyEventResult _handleKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _hideSelectionToolbar();
    }

    final resultOverride = widget.onKeyEvent?.call(focusNode, event);
    if (resultOverride != null && resultOverride != KeyEventResult.ignored) {
      return resultOverride;
    }

    // ignore: invalid_use_of_protected_member
    final shortcutResult = _shortcutManager.handleKeypress(
      focusNode.context!,
      event,
    );

    if (shortcutResult != KeyEventResult.ignored) {
      return shortcutResult;
    }

    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    final key = keyToTerminalKey(event.logicalKey);

    if (key == null) {
      return KeyEventResult.ignored;
    }

    final handled = widget.terminal.keyInput(
      key,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );

    if (handled) {
      _scrollToBottom();
    }

    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onKeyboardShow() {
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _onEditableRect(Rect rect, Rect caretRect) {
    _customTextEditKey.currentState?.setEditableRect(rect, caretRect);
  }

  void _scrollToBottom() {
    final position = _scrollableKey.currentState?.position;
    if (position != null) {
      position.jumpTo(position.maxScrollExtent);
    }
  }

  bool get _isMobileSelectionToolbarEnabled {
    if (!widget.mobileSelectionToolbarEnabled || kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  void _onSelectionChanged() {
    if (!_isMobileSelectionToolbarEnabled) {
      _hideSelectionToolbar();
      return;
    }
    _scheduleSelectionToolbarUpdate();
  }

  void _onFocusStateChanged() {
    if (!_focusNode.hasFocus) {
      _hideSelectionToolbar();
    }
  }

  void _onTerminalStateChanged() {
    if (_selectionToolbarOverlayEntry == null &&
        _selectionHandleOverlayEntry == null) {
      return;
    }
    _scheduleSelectionToolbarUpdate();
  }

  void _onScrollPositionChanged() {
    if (_selectionToolbarOverlayEntry == null &&
        _selectionHandleOverlayEntry == null) {
      return;
    }
    _scheduleSelectionToolbarUpdate();
  }

  void _scheduleSelectionToolbarUpdate() {
    if (!_isMobileSelectionToolbarEnabled ||
        _selectionToolbarUpdateScheduled ||
        !mounted) {
      return;
    }
    _selectionToolbarUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionToolbarUpdateScheduled = false;
      if (!mounted) {
        return;
      }
      _updateSelectionToolbar();
    });
  }

  void _updateSelectionToolbar() {
    if (!_isMobileSelectionToolbarEnabled) {
      _hideSelectionToolbar();
      return;
    }

    final selection = _controller.selection;
    if (selection == null || selection.isCollapsed) {
      _hideSelectionToolbar();
      return;
    }

    _updateSelectionHandleOverlay(selection);

    if (_selectionHandleDragging) {
      _hideSelectionToolbarOnly();
      return;
    }

    final anchors = _computeSelectionToolbarAnchors(selection);
    if (anchors == null) {
      _hideSelectionToolbarOnly();
      return;
    }

    _selectionToolbarAnchors = anchors;
    if (_selectionToolbarOverlayEntry == null) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        return;
      }
      _selectionToolbarOverlayEntry = OverlayEntry(
        builder: _buildSelectionToolbarOverlay,
      );
      overlay.insert(_selectionToolbarOverlayEntry!);
      return;
    }

    _selectionToolbarOverlayEntry!.markNeedsBuild();
  }

  void _updateSelectionHandleOverlay(BufferRange selection) {
    final anchors = _computeSelectionHandleAnchors(selection);
    if (anchors == null) {
      _hideSelectionHandlesOnly();
      return;
    }

    _selectionHandleAnchors = anchors;
    if (_selectionHandleOverlayEntry == null) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        return;
      }
      _selectionHandleOverlayEntry = OverlayEntry(
        builder: _buildSelectionHandleOverlay,
      );
      overlay.insert(_selectionHandleOverlayEntry!);
      return;
    }

    _selectionHandleOverlayEntry!.markNeedsBuild();
  }

  RenderTerminal? _resolveRenderTerminal() {
    final render = _viewportKey.currentContext?.findRenderObject();
    if (render is! RenderTerminal || !render.attached || !render.hasSize) {
      return null;
    }
    return render;
  }

  TextSelectionToolbarAnchors? _computeSelectionToolbarAnchors(
    BufferRange selection,
  ) {
    final render = _resolveRenderTerminal();
    if (render == null) {
      return null;
    }

    final terminal = widget.terminal;
    final viewWidth = terminal.viewWidth;
    final bufferHeight = terminal.buffer.height;
    if (viewWidth <= 0 || bufferHeight <= 0 || render.size.height <= 0) {
      return null;
    }

    final normalized = selection.normalized;
    final visibleTopLine = render.getCellOffset(const Offset(0, 0)).y;
    final visibleBottomLine =
        render.getCellOffset(Offset(0, render.size.height - 1)).y;
    if (normalized.end.y < visibleTopLine ||
        normalized.begin.y > visibleBottomLine) {
      return null;
    }

    final targetLine = normalized.begin.y < visibleTopLine
        ? visibleTopLine
        : normalized.begin.y;
    var startX = targetLine == normalized.begin.y ? normalized.begin.x : 0;
    var endX = targetLine == normalized.end.y ? normalized.end.x : viewWidth;

    startX = startX.clamp(0, viewWidth - 1);
    final minEndX = startX + 1;
    endX = endX.clamp(minEndX, viewWidth);

    final leftGlobal = render.localToGlobal(
      render.getOffset(CellOffset(startX, targetLine)),
    );
    final rightGlobal = render.localToGlobal(
      render.getOffset(CellOffset(endX, targetLine)),
    );
    final centerX = (leftGlobal.dx + rightGlobal.dx) / 2;
    final topY = leftGlobal.dy;
    final bottomY = topY + render.lineHeight;

    return TextSelectionToolbarAnchors(
      primaryAnchor: Offset(centerX, topY),
      secondaryAnchor: Offset(centerX, bottomY),
    );
  }

  _SelectionHandleAnchors? _computeSelectionHandleAnchors(
      BufferRange selection) {
    final render = _resolveRenderTerminal();
    if (render == null) {
      return null;
    }

    final terminal = widget.terminal;
    final viewWidth = terminal.viewWidth;
    final bufferHeight = terminal.buffer.height;
    if (viewWidth <= 0 || bufferHeight <= 0 || render.size.height <= 0) {
      return null;
    }

    final normalized = selection.normalized;
    final visibleTopLine = render.getCellOffset(const Offset(0, 0)).y;
    final visibleBottomLine =
        render.getCellOffset(Offset(0, render.size.height - 1)).y;
    if (normalized.end.y < visibleTopLine ||
        normalized.begin.y > visibleBottomLine) {
      return null;
    }

    final startLine =
        normalized.begin.y.clamp(visibleTopLine, visibleBottomLine);
    final endLine = normalized.end.y.clamp(visibleTopLine, visibleBottomLine);
    var startX = (startLine == normalized.begin.y ? normalized.begin.x : 0)
        .clamp(0, viewWidth - 1);
    var endX = (endLine == normalized.end.y ? normalized.end.x : viewWidth)
        .clamp(1, viewWidth);
    if (startLine == endLine && endX <= startX) {
      endX = (startX + 1).clamp(1, viewWidth);
    }

    final startGlobal = render.localToGlobal(
      render.getOffset(CellOffset(startX, startLine)),
    );
    final endGlobal = render.localToGlobal(
      render.getOffset(CellOffset(endX, endLine)),
    );

    return _SelectionHandleAnchors(
      start: Offset(
        startGlobal.dx - _selectionHandleOutwardOffset,
        startGlobal.dy + render.lineHeight,
      ),
      end: Offset(
        endGlobal.dx + _selectionHandleOutwardOffset,
        endGlobal.dy + render.lineHeight,
      ),
    );
  }

  Widget _buildSelectionToolbarOverlay(BuildContext context) {
    final anchors = _selectionToolbarAnchors;
    if (anchors == null) {
      return const SizedBox.shrink();
    }
    final hasSelectionText = _selectedText().isNotEmpty;
    final customItems = widget.selectionToolbarBuilder?.call(context, hasSelectionText);
    if (customItems != null) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors,
        buttonItems: customItems,
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: [
        ContextMenuButtonItem(
          onPressed: hasSelectionText ? _onCopyPressed : null,
          type: ContextMenuButtonType.copy,
        ),
        ContextMenuButtonItem(
          onPressed: widget.readOnly ? null : _onPastePressed,
          type: ContextMenuButtonType.paste,
        ),
        ContextMenuButtonItem(
          onPressed: _onSelectAllPressed,
          type: ContextMenuButtonType.selectAll,
        ),
      ],
    );
  }

  Widget _buildSelectionHandleOverlay(BuildContext context) {
    final anchors = _selectionHandleAnchors;
    if (anchors == null) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: [
        _buildSelectionHandleWidget(
            context, _SelectionHandleType.start, anchors.start),
        _buildSelectionHandleWidget(
            context, _SelectionHandleType.end, anchors.end),
      ],
    );
  }

  Widget _buildSelectionHandleWidget(
    BuildContext context,
    _SelectionHandleType type,
    Offset anchor,
  ) {
    final color = CupertinoDynamicColor.resolve(
      CupertinoColors.activeBlue,
      context,
    );
    final diameter = _selectionHandleTouchRadius * 2;
    return Positioned(
      left: anchor.dx - _selectionHandleTouchRadius,
      top: anchor.dy - _selectionHandleTouchRadius,
      width: diameter,
      height: diameter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) =>
            _onSelectionHandleDragStart(type, details.globalPosition),
        onPanUpdate: (details) =>
            _onSelectionHandleDragUpdate(type, details.globalPosition),
        onPanEnd: (_) => _onSelectionHandleDragEnd(),
        onPanCancel: _onSelectionHandleDragEnd,
        onLongPressStart: (details) =>
            _onSelectionHandleDragStart(type, details.globalPosition),
        onLongPressMoveUpdate: (details) =>
            _onSelectionHandleDragUpdate(type, details.globalPosition),
        onLongPressEnd: (_) => _onSelectionHandleDragEnd(),
        onLongPressCancel: _onSelectionHandleDragEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left:
                  _selectionHandleTouchRadius - (_selectionHandleDropSize / 2),
              top: _selectionHandleTouchRadius,
              child: Transform.rotate(
                alignment: Alignment.topCenter,
                angle: type == _SelectionHandleType.start
                    ? math.pi / 4
                    : -math.pi / 4,
                child: _SelectionHandleDrop(
                  color: color,
                  size: _selectionHandleDropSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Offset? _anchorForSelectionHandle(_SelectionHandleType type) {
    final anchors = _selectionHandleAnchors;
    if (anchors == null) {
      return null;
    }
    return type == _SelectionHandleType.start ? anchors.start : anchors.end;
  }

  void _onSelectionHandleDragStart(
    _SelectionHandleType type,
    Offset globalPosition,
  ) {
    _selectionHandleDragging = true;
    _activeSelectionHandleType = type;
    final tip = _anchorForSelectionHandle(type) ?? globalPosition;
    _selectionHandlePointerOffset = globalPosition - tip;
    _lastSelectionHandleGlobalPosition = tip;
    _hideSelectionToolbarOnly();
    _startSelectionHandleAutoScroll();
  }

  void _onSelectionHandleDragUpdate(
    _SelectionHandleType fallbackType,
    Offset globalPosition,
  ) {
    if (!_selectionHandleDragging) {
      return;
    }
    final pointerOffset = _selectionHandlePointerOffset ?? Offset.zero;
    final tipGlobal = globalPosition - pointerOffset;
    _lastSelectionHandleGlobalPosition = tipGlobal;
    final activeType = _activeSelectionHandleType ?? fallbackType;
    _applySelectionHandleDrag(activeType, tipGlobal);
  }

  void _applySelectionHandleDrag(_SelectionHandleType type, Offset global) {
    if (!_selectionHandleDragging) {
      return;
    }
    final render = _resolveRenderTerminal();
    final range = _controller.selection?.normalized;
    if (render == null || range == null) {
      return;
    }

    final terminal = widget.terminal;
    final maxLine = terminal.buffer.height - 1;
    final viewWidth = terminal.viewWidth;
    if (maxLine < 0 || viewWidth <= 0) {
      return;
    }

    final local = render.globalToLocal(global);
    final offset = render.getCellOffset(local);
    final cell = CellOffset(
      offset.x.clamp(0, viewWidth - 1),
      offset.y.clamp(0, maxLine),
    );
    final draggedAsEnd = CellOffset((cell.x + 1).clamp(1, viewWidth), cell.y);

    if (type == _SelectionHandleType.start) {
      final opposite = range.end;
      if (cell.isBefore(opposite)) {
        _setSelectionAnchors(cell, opposite);
        return;
      }
      _activeSelectionHandleType = _SelectionHandleType.end;
      _setSelectionAnchors(opposite, draggedAsEnd);
      return;
    }

    final opposite = range.begin;
    if (opposite.isBefore(draggedAsEnd)) {
      _setSelectionAnchors(opposite, draggedAsEnd);
      return;
    }
    _activeSelectionHandleType = _SelectionHandleType.start;
    _setSelectionAnchors(cell, opposite);
  }

  void _setSelectionAnchors(CellOffset begin, CellOffset end) {
    final terminal = widget.terminal;
    _controller.setSelection(
      terminal.buffer.createAnchorFromOffset(begin),
      terminal.buffer.createAnchorFromOffset(end),
    );
  }

  void _startSelectionHandleAutoScroll() {
    _selectionHandleAutoScrollTimer?.cancel();
    _selectionHandleAutoScrollTimer = Timer.periodic(
      _selectionHandleAutoScrollInterval,
      (_) => _tickSelectionHandleAutoScroll(),
    );
  }

  void _tickSelectionHandleAutoScroll() {
    final global = _lastSelectionHandleGlobalPosition;
    final activeType = _activeSelectionHandleType;
    final position = _scrollableKey.currentState?.position;
    final render = _resolveRenderTerminal();
    if (global == null ||
        activeType == null ||
        position == null ||
        !position.hasPixels ||
        render == null) {
      return;
    }

    final local = render.globalToLocal(global);
    final delta = _computeSelectionHandleAutoScrollDelta(render, local);
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
    _applySelectionHandleDrag(activeType, global);
  }

  double _computeSelectionHandleAutoScrollDelta(
    RenderTerminal render,
    Offset local,
  ) {
    final height = render.size.height;
    final lineHeight = render.lineHeight;
    if (height <= 0 || lineHeight <= 0) {
      return 0;
    }
    final trigger = (height * 0.14).clamp(
      _selectionHandleAutoScrollMinTrigger,
      _selectionHandleAutoScrollMaxTrigger,
    );
    if (local.dy < trigger) {
      final ratio = ((trigger - local.dy) / trigger).clamp(0.0, 1.0);
      final accelerated = ratio * ratio;
      final lines =
          (1 + (accelerated * (_selectionHandleMaxAutoScrollLinesPerTick - 1)))
              .round()
              .clamp(1, _selectionHandleMaxAutoScrollLinesPerTick);
      return -(lines * lineHeight);
    }
    if (local.dy > height - trigger) {
      final ratio = ((local.dy - (height - trigger)) / trigger).clamp(
        0.0,
        1.0,
      );
      final accelerated = ratio * ratio;
      final lines =
          (1 + (accelerated * (_selectionHandleMaxAutoScrollLinesPerTick - 1)))
              .round()
              .clamp(1, _selectionHandleMaxAutoScrollLinesPerTick);
      return lines * lineHeight;
    }
    return 0;
  }

  void _stopSelectionHandleAutoScroll() {
    _selectionHandleAutoScrollTimer?.cancel();
    _selectionHandleAutoScrollTimer = null;
  }

  void _onSelectionHandleDragEnd() {
    _selectionHandleDragging = false;
    _activeSelectionHandleType = null;
    _lastSelectionHandleGlobalPosition = null;
    _selectionHandlePointerOffset = null;
    _stopSelectionHandleAutoScroll();
    _scheduleSelectionToolbarUpdate();
  }

  String _selectedText() {
    final selection = _controller.selection;
    if (selection == null) {
      return '';
    }
    return widget.terminal.buffer.getText(selection);
  }

  String _normalizeTerminalClipboardText(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  void _onCopyPressed() {
    unawaited(_copySelectionToClipboard());
  }

  Future<void> _copySelectionToClipboard() async {
    final text = _normalizeTerminalClipboardText(_selectedText());
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _hideSelectionToolbar();
  }

  void _onPastePressed() {
    unawaited(_pasteFromClipboard());
  }

  Future<void> _pasteFromClipboard() async {
    if (widget.readOnly) {
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    final normalized = _normalizeTerminalClipboardText(text);
    if (normalized.isEmpty) {
      return;
    }
    widget.terminal.paste(normalized);
    _scrollToBottom();
    _controller.clearSelection();
    _hideSelectionToolbar();
  }

  void _onSelectAllPressed() {
    final terminal = widget.terminal;
    final height = terminal.buffer.height;
    if (height <= 0) {
      return;
    }
    _controller.setSelection(
      terminal.buffer.createAnchor(0, 0),
      terminal.buffer.createAnchor(terminal.viewWidth, height - 1),
      mode: SelectionMode.line,
    );
    _scheduleSelectionToolbarUpdate();
  }

  void _hideSelectionToolbar() {
    _selectionHandleDragging = false;
    _activeSelectionHandleType = null;
    _lastSelectionHandleGlobalPosition = null;
    _selectionHandlePointerOffset = null;
    _stopSelectionHandleAutoScroll();
    _hideSelectionToolbarOnly();
    _hideSelectionHandlesOnly();
  }

  void _hideSelectionToolbarOnly() {
    _selectionToolbarAnchors = null;
    _selectionToolbarOverlayEntry?.remove();
    _selectionToolbarOverlayEntry = null;
  }

  void _hideSelectionHandlesOnly() {
    _selectionHandleAnchors = null;
    _selectionHandleOverlayEntry?.remove();
    _selectionHandleOverlayEntry = null;
  }
}

class _SelectionHandleDrop extends StatelessWidget {
  const _SelectionHandleDrop({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PhysicalShape(
      color: color,
      elevation: 2,
      clipper: const _SelectionHandleTeardropClipper(),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _SelectionHandleTeardropClipper extends CustomClipper<Path> {
  const _SelectionHandleTeardropClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.5, 0);
    path.quadraticBezierTo(w * 0.9, h * 0.18, w * 0.9, h * 0.56);
    path.quadraticBezierTo(w * 0.82, h * 0.95, w * 0.5, h);
    path.quadraticBezierTo(w * 0.18, h * 0.95, w * 0.1, h * 0.56);
    path.quadraticBezierTo(w * 0.1, h * 0.18, w * 0.5, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _TerminalView extends LeafRenderObjectWidget {
  const _TerminalView({
    super.key,
    required this.terminal,
    required this.controller,
    required this.offset,
    required this.padding,
    required this.autoResize,
    required this.textStyle,
    required this.textScaler,
    required this.theme,
    required this.focusNode,
    required this.cursorType,
    required this.alwaysShowCursor,
    this.onEditableRect,
    this.composingText,
  });

  final Terminal terminal;

  final TerminalController controller;

  final ViewportOffset offset;

  final EdgeInsets padding;

  final bool autoResize;

  final TerminalStyle textStyle;

  final TextScaler textScaler;

  final TerminalTheme theme;

  final FocusNode focusNode;

  final TerminalCursorType cursorType;

  final bool alwaysShowCursor;

  final EditableRectCallback? onEditableRect;

  final String? composingText;

  @override
  RenderTerminal createRenderObject(BuildContext context) {
    return RenderTerminal(
      terminal: terminal,
      controller: controller,
      offset: offset,
      padding: padding,
      autoResize: autoResize,
      textStyle: textStyle,
      textScaler: textScaler,
      theme: theme,
      focusNode: focusNode,
      cursorType: cursorType,
      alwaysShowCursor: alwaysShowCursor,
      onEditableRect: onEditableRect,
      composingText: composingText,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderTerminal renderObject) {
    renderObject
      ..terminal = terminal
      ..controller = controller
      ..offset = offset
      ..padding = padding
      ..autoResize = autoResize
      ..textStyle = textStyle
      ..textScaler = textScaler
      ..theme = theme
      ..focusNode = focusNode
      ..cursorType = cursorType
      ..alwaysShowCursor = alwaysShowCursor
      ..onEditableRect = onEditableRect
      ..composingText = composingText;
  }
}
