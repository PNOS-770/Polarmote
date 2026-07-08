import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../../models/terminal_session.dart';

class SessionThumbnail extends StatefulWidget {
  final TerminalSession session;
  final String fontFamily;
  final double backgroundOpacity;

  const SessionThumbnail({
    super.key,
    required this.session,
    required this.fontFamily,
    this.backgroundOpacity = 1.0,
  });

  @override
  State<SessionThumbnail> createState() => _SessionThumbnailState();
}

class _SessionThumbnailState extends State<SessionThumbnail> {
  late final ScrollController _scrollController;
  int _lastCursorY = -1;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.session.terminal.addListener(_onTerminalUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    widget.session.terminal.removeListener(_onTerminalUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTerminalUpdate() {
    if (!_scrollController.hasClients) return;
    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final cursorY = buffer.absoluteCursorY;
    if (cursorY == _lastCursorY) return;
    _lastCursorY = cursorY;

    const cellHeight = 7.0;
    const visibleLines = 15;
    final totalLines = buffer.lines.length;
    final targetLine =
        (cursorY - visibleLines ~/ 2).clamp(0, totalLines - visibleLines);
    final targetOffset = targetLine * cellHeight;
    final maxScroll = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(targetOffset.clamp(0, maxScroll));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox();
    return TerminalView(
      widget.session.terminal,
      autoResize: false,
      textStyle: TerminalStyle(
        fontFamily: widget.fontFamily,
        fontSize: 6,
        height: 1.0,
      ),
      textScaler: TextScaler.noScaling,
      padding: EdgeInsets.zero,
      backgroundOpacity: widget.backgroundOpacity,
      autofocus: false,
      readOnly: true,
      alwaysShowCursor: false,
      scrollController: _scrollController,
    );
  }
}

