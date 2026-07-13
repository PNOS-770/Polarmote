part of 'terminal_main_panel.dart';

class _TerminalPane extends StatefulWidget {
  const _TerminalPane({
    required this.session,
    required this.appState,
    required this.paneId,
    required this.focusNode,
    required this.controller,
    required this.verticalScrollController,
    required this.showTitle,
    required this.onShowMenu,
    required this.onSplitShortcut,
    this.captureKey,
  });

  final TerminalSession session;
  final TerminalAppState appState;
  final String paneId;
  final FocusNode focusNode;
  final TerminalController controller;
  final ScrollController verticalScrollController;
  final bool showTitle;
  final Future<void> Function(Offset position) onShowMenu;
  final KeyEventResult Function(KeyEvent event) onSplitShortcut;
  final GlobalKey? captureKey;

  @override
  State<_TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<_TerminalPane> {
  final ScrollController _horizontalScrollController = ScrollController();
  TerminalCursorShape _lastCursorShape = TerminalCursorShape.block;
  String? _lastBackgroundPath;
  double _lastBackgroundOpacity = 0.15;
  TerminalStatus _lastSessionStatus = TerminalStatus.connected;

  bool _ghostActive = false;
  int _ghostStartCol = 0;
  int _ghostEndCol = 0;
  Timer? _ghostDebounceTimer;


  void _clearGhostState() {
    _ghostActive = false;
    _ghostStartCol = 0;
    _ghostEndCol = 0;
  }

  void _acceptGhostText() {
    if (!_ghostActive) return;
    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final line = buffer.currentLine;
    final normalStyle = CursorStyle(
      foreground: terminal.cursor.foreground,
      background: terminal.cursor.background,
      attrs: terminal.cursor.attrs & ~CellAttr.faint,
    );
    for (var i = _ghostStartCol; i < _ghostEndCol; i++) {
      final codePoint = line.getCodePoint(i);
      if (codePoint != 0) {
        line.setCell(i, codePoint, 1, normalStyle);
      }
    }
    buffer.setCursorX(_ghostEndCol);
    terminal.unsetCursorFaint();
    terminal.notifyListeners();
    _clearGhostState();
  }

  void _scheduleGhostTextUpdate() {
    _ghostDebounceTimer?.cancel();
    _ghostDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) _updateGhostText();
    });
  }

  void _updateGhostText() {
    if (!mounted) return;
    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final cursorX = buffer.cursorX;
    final line = buffer.currentLine;
    final currentText = line.getText(0, cursorX).trimRight();

    if (currentText.isEmpty) {
      if (_ghostActive) {
        line.eraseRange(_ghostStartCol, _ghostEndCol, terminal.cursor);
        _clearGhostState();
      }
      return;
    }

    final hostKey = widget.session.profile.host.isEmpty
        ? 'local'
        : '${widget.session.profile.username}@${widget.session.profile.host}:${widget.session.profile.port}';
    final history = widget.appState.commandHistoryByHost[hostKey] ?? [];

    String? bestMatch;
    for (var i = history.length - 1; i >= 0; i--) {
      final cmd = history[i].trim();
      final words = cmd.split(RegExp(r'\s+'));
      final first = words.isNotEmpty ? words.first : '';
      if (first.length > currentText.length &&
          first.toLowerCase().startsWith(currentText.toLowerCase())) {
        bestMatch = first;
        break;
      }
    }

    if (bestMatch == null) {
      if (_ghostActive) {
        line.eraseRange(_ghostStartCol, _ghostEndCol, terminal.cursor);
        _clearGhostState();
      }
      return;
    }

    final suffix = bestMatch.substring(currentText.length);
    if (suffix.isEmpty) {
      if (_ghostActive) {
        line.eraseRange(_ghostStartCol, _ghostEndCol, terminal.cursor);
        _clearGhostState();
      }
      return;
    }

    if (_ghostActive &&
        (_ghostStartCol != cursorX || _ghostEndCol != cursorX + suffix.length)) {
      line.eraseRange(_ghostStartCol, _ghostEndCol, terminal.cursor);
      _clearGhostState();
    }

    if (_ghostActive) return;

    _ghostStartCol = cursorX;
    _ghostEndCol = cursorX + suffix.length;

    terminal.setCursorFaint();
    for (var i = 0; i < suffix.length; i++) {
      buffer.writeChar(suffix.codeUnitAt(i));
    }
    buffer.setCursorX(cursorX);
    terminal.unsetCursorFaint();
    _ghostActive = true;
    terminal.notifyListeners();
  }

  void _sendSessionInput(String payload) {
    if (payload.isEmpty) return;
    widget.session.lastUserInputTime = DateTime.now();
    widget.session.sendInput(payload);
  }

  double _estimateTerminalCellWidth(
    BuildContext context,
    TerminalStyle style,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: 'mmmmmmmmmm', style: style.toTextStyle()),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final measured = painter.width / 10;
    if (measured.isFinite && measured > 0) {
      return measured;
    }
    return (style.fontSize * 0.6).clamp(6.0, 20.0);
  }

  String _normalizeCommittedEnterText(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  bool _hasCommittedEnterText(String text) {
    if (text.isEmpty) return false;
    if (text == '\n') return false;
    return text.runes.any((rune) => rune >= 0x20 || rune == 0x09);
  }

  String _normalizeTerminalClipboardText(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  String _prepareTerminalPastePayload(String text) {
    var normalized = _normalizeTerminalClipboardText(text);
    const bracketedOpen = '\x1B[200~';
    const bracketedClose = '\x1B[201~';
    if (normalized.startsWith(bracketedOpen) &&
        normalized.endsWith(bracketedClose) &&
        normalized.length > (bracketedOpen.length + bracketedClose.length)) {
      normalized = normalized.substring(
        bracketedOpen.length,
        normalized.length - bracketedClose.length,
      );
    }
    return normalized;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty) return;
    final payload = _prepareTerminalPastePayload(raw);
    if (payload.isEmpty) return;
    _sendSessionInput(payload);
    widget.controller.clearSelection();
  }

  Future<void> _copySelectionToClipboard() async {
    final selection = widget.controller.selection;
    if (selection == null) return;
    final text = _normalizeTerminalClipboardText(
      widget.session.terminal.buffer.getText(selection),
    );
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  KeyEventResult _handleTerminalKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    final splitShortcutResult = widget.onSplitShortcut(event);
    if (splitShortcutResult == KeyEventResult.handled) {
      return splitShortcutResult;
    }

    final customCopy = _checkCustomShortcut(widget.appState, event, 'copy');
    if (customCopy != null) {
      final hasSelection = widget.controller.selection != null;
      if (hasSelection) {
        unawaited(_copySelectionToClipboard());
        return KeyEventResult.handled;
      }
    }
    final customPaste = _checkCustomShortcut(widget.appState, event, 'paste');
    if (customPaste != null) {
      unawaited(_pasteFromClipboard());
      return KeyEventResult.handled;
    }
    final customSelectAll = _checkCustomShortcut(widget.appState, event, 'selectAll');
    if (customSelectAll != null) {
      final terminal = widget.session.terminal;
      final startY = (terminal.buffer.height - terminal.viewHeight).clamp(0, terminal.buffer.height - 1);
      final endY = terminal.buffer.height - 1;
      widget.controller.setSelection(
        terminal.buffer.createAnchor(0, startY),
        terminal.buffer.createAnchor(terminal.viewWidth, endY),
        mode: SelectionMode.line,
      );
      return KeyEventResult.handled;
    }
    final customBlockSelect = _checkCustomShortcut(widget.appState, event, 'blockSelect');
    if (customBlockSelect != null) {
      final newMode = widget.controller.selectionMode == SelectionMode.line
          ? SelectionMode.block
          : SelectionMode.line;
      widget.controller.setSelectionMode(newMode);
      return KeyEventResult.handled;
    }

    if (alt && !ctrl && !meta && !shift && key == LogicalKeyboardKey.keyB) {
      final newMode = widget.controller.selectionMode == SelectionMode.line
          ? SelectionMode.block
          : SelectionMode.line;
      widget.controller.setSelectionMode(newMode);
      return KeyEventResult.handled;
    }

    if (_ghostActive) {
      if (key == LogicalKeyboardKey.arrowRight && !ctrl && !alt && !meta) {
        _acceptGhostText();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.tab && !ctrl && !meta && !alt) {
      return KeyEventResult.ignored;
    }

    final hasSelection = widget.controller.selection != null;
    final enterPressed =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (enterPressed && !ctrl && !meta && !alt) {
      final committedText = _normalizeCommittedEnterText(event.character ?? '');
      if (_hasCommittedEnterText(committedText)) {
        _sendSessionInput(committedText);
        _sendSessionInput('\r');
        return KeyEventResult.handled;
      }
    }
    final smartCtrlCCopy =
        ctrl &&
        !meta &&
        !shift &&
        key == LogicalKeyboardKey.keyC &&
        hasSelection;
    final pasteShortcut =
        (ctrl && !meta && !alt && key == LogicalKeyboardKey.keyV) ||
        (meta && !ctrl && !alt && key == LogicalKeyboardKey.keyV) ||
        (shift && !ctrl && !meta && !alt && key == LogicalKeyboardKey.insert);
    if (pasteShortcut) {
      unawaited(_pasteFromClipboard());
      return KeyEventResult.handled;
    }
    final copyShortcut =
        smartCtrlCCopy ||
        (ctrl && shift && key == LogicalKeyboardKey.keyC) ||
        (ctrl && key == LogicalKeyboardKey.insert) ||
        (meta && key == LogicalKeyboardKey.keyC);
    if (!copyShortcut) {
      _scheduleGhostTextUpdate();
      return KeyEventResult.ignored;
    }
    if (!hasSelection) {
      return KeyEventResult.ignored;
    }
    unawaited(_copySelectionToClipboard());
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    widget.session.terminal.removeListener(_onTerminalChanged);
    widget.session.onUserInput = null;
    _ghostDebounceTimer?.cancel();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _lastSessionStatus = widget.session.tab.status;
    widget.appState.addListener(_onAppStateChanged);
    widget.session.onUserInput = _onUserInput;
    widget.session.terminal.addListener(_onTerminalChanged);
  }
  
  void _onTerminalChanged() {
    // TerminalView 内部已订阅终端变化自行渲染，无需外层 setState
  }

  void _logBackgroundError(Object error) {
    widget.appState.addStructuredLog(category: TerminalLogCategory.system, message: 'Background image load error: $error', notifyListeners: false);
  }

  void _onUserInput(String sessionId, String data) {
    if (!widget.appState.broadcastEnabled) return;
    for (final s in widget.appState.sessions) {
      if (s.id != sessionId && s.tab.status == TerminalStatus.connected) {
        s.sendInput(data);
      }
    }
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    var needsRebuild = false;
    // 恢复期间仍然需要刷新会话状态（connecting → connected）
    if (!widget.appState.restorationInProgress) {
      final cursorShape = widget.appState.globalAppearance.cursorShape;
      if (cursorShape != _lastCursorShape) {
        _lastCursorShape = cursorShape;
        needsRebuild = true;
      }
      final bgPath = widget.appState.backgroundImagePathForActiveStage();
      if (bgPath != _lastBackgroundPath) {
        _lastBackgroundPath = bgPath;
        needsRebuild = true;
      }
      final bgOpacity = widget.appState.terminalBackgroundOpacity;
      if (bgOpacity != _lastBackgroundOpacity) {
        _lastBackgroundOpacity = bgOpacity;
        needsRebuild = true;
      }
    }
    // 会话状态变化（connecting ↔ connected / disconnected）始终需要刷新
    final status = widget.session.tab.status;
    if (status != _lastSessionStatus) {
      _lastSessionStatus = status;
      needsRebuild = true;
    }
    if (needsRebuild) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerColor = switch (widget.session.tab.status) {
      TerminalStatus.connected => const Color(0xFF22C55E),
      TerminalStatus.connecting => const Color(0xFFF59E0B),
      TerminalStatus.reconnecting => const Color(0xFFFB923C),
      TerminalStatus.disconnected => const Color(0xFFEF4444),
    };
    final title = widget.session.tab.title.trim().isEmpty
        ? widget.session.profile.name
        : widget.session.tab.title;
    final isDesktop = isDesktopPlatform();
    final profile = widget.session.profile;
    final appState = widget.appState;
    final global = appState.globalAppearance;
    final fontFamily = profile.fontFamily ?? global.fontFamily;
    final fontSize = profile.fontSize ?? global.fontSize;
    final lineHeight = profile.lineHeight ?? global.lineHeight;
    final terminalTextStyle = TerminalStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: lineHeight,
    );
    const terminalTextScaler = TextScaler.noScaling;
    final bgPath = appState.backgroundImagePathForActiveStage();
    final bgOpacity = appState.terminalBackgroundOpacity;
    final cursorShape = global.cursorShape;
    final cursorType = switch (cursorShape) {
      TerminalCursorShape.verticalBar => TerminalCursorType.verticalBar,
      TerminalCursorShape.underline => TerminalCursorType.underline,
      TerminalCursorShape.block => TerminalCursorType.block,
    };
    final terminalView = TerminalView(
      widget.session.terminal,
      key: ValueKey('terminal_${cursorShape.name}'),
      controller: widget.controller,
      scrollController: widget.verticalScrollController,
      focusNode: widget.focusNode,
      autofocus: true,
      backgroundOpacity: 1 - bgOpacity,
      keyboardType: TextInputType.multiline,
      hardwareKeyboardOnly: false,
      mobileSelectionToolbarEnabled: !isDesktop,
      textStyle: terminalTextStyle,
      textScaler: terminalTextScaler,
      cursorType: cursorType,
      onKeyEvent: _handleTerminalKeyEvent,
    );
    final terminalViewport =
        widget.appState.terminalAccessibilitySemanticsEnabled
        ? terminalView
        : ExcludeSemantics(child: terminalView);
    
    // 检测是否在替代缓冲区（如 vim, OpenCode 等 TUI 应用）
    final isUsingAltBuffer = widget.session.terminal.isUsingAltBuffer;
    
    Widget verticalScrollableTerminal;
    if (isUsingAltBuffer) {
      // 在替代缓冲区时不渲染 RawScrollbar，避免 ScrollController
      // 绑定多个 ScrollPosition 导致崩溃
      verticalScrollableTerminal = terminalViewport;
    } else {
      verticalScrollableTerminal = RawScrollbar(
        controller: widget.verticalScrollController,
        thickness: 8,
        radius: const Radius.circular(4),
        thumbColor: Colors.white.withValues(alpha: 0.34),
        trackColor: Colors.white.withValues(alpha: 0.08),
        trackBorderColor: Colors.transparent,
        notificationPredicate: (notification) {
          return notification.metrics.axis == Axis.vertical;
        },
        child: terminalViewport,
      );
    }
    final enableMobileHorizontalScroll =
        widget.appState.terminalHorizontalScrollEnabled;
    final terminalContent = enableMobileHorizontalScroll
        ? LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = _estimateTerminalCellWidth(
                context,
                terminalTextStyle,
                terminalTextScaler,
              );
              final viewportWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : (widget.appState.mobileTerminalColumns * cellWidth);
              final targetWidth =
                  (widget.appState.mobileTerminalColumns * cellWidth) + 2;
              final contentWidth = targetWidth > viewportWidth
                  ? targetWidth
                  : viewportWidth;
              return Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                notificationPredicate: (notification) {
                  return notification.metrics.axis == Axis.horizontal;
                },
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  child: SizedBox(
                    width: contentWidth,
                    child: verticalScrollableTerminal,
                  ),
                ),
              );
            },
          )
        : verticalScrollableTerminal;

    final body = Stack(
      children: [
        if (bgPath != null && bgPath.isNotEmpty)
          Positioned.fill(
            child: Opacity(
              opacity: bgOpacity.clamp(0.0, 1.0),
              child: Image.file(
                File(bgPath),
                fit: BoxFit.cover,
                errorBuilder: (_, error, __) {
                  _logBackgroundError(error);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        RepaintBoundary(
          key: widget.captureKey,
          child: terminalContent,
        ),
        if (widget.session.tab.status == TerminalStatus.connecting)
          _TerminalOverlay(
            label: l(widget.appState, AppStrings.values.connecting),
          ),
        if (widget.session.tab.status == TerminalStatus.reconnecting)
          _TerminalOverlay(
            label: l(widget.appState, AppStrings.values.reconnecting),
          ),
        if (widget.session.tab.status == TerminalStatus.disconnected)
          _TerminalOverlay(
            label: l(widget.appState, AppStrings.values.disconnected),
            actionLabel: l(widget.appState, AppStrings.values.reconnect),
            onAction: () =>
                unawaited(widget.appState.reconnectSession(widget.session)),
          ),
      ],
    );

    Widget paneContent;
    if (!widget.showTitle) {
      paneContent = body;
    } else {
      paneContent = Column(
        children: [
          Container(
            height: 28,
            color: headerColor,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: paneContent),
        if (widget.session.tab.status == TerminalStatus.connected)
          widget.session.profile.isLocal
              ? _LocalStatusBar(session: widget.session, appState: widget.appState)
              : TerminalStatusBar(session: widget.session, appState: widget.appState),
      ],
    );
  }
}

class _LocalStatusBar extends StatelessWidget {
  const _LocalStatusBar({required this.session, required this.appState});
  final TerminalSession session;
  final TerminalAppState appState;

  @override
  Widget build(BuildContext context) {
    final diagnostics = session.getAdaptiveThrottleDiagnostics();
    final levelName = diagnostics['currentLevel'] as String;
    final level = ThrottleLevel.values.byName(levelName);
    final showThrottle = appState.performanceSettings.adaptiveThrottleEnabled;

    return Container(
      height: 22,
      decoration: const BoxDecoration(
        color: TerminalUiPalette.statusBarBg,
        border: Border(
          top: BorderSide(color: TerminalUiPalette.statusBarBorder, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Icon(Icons.computer, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            session.tab.title.isNotEmpty ? session.tab.title : session.profile.name,
            style: AppTextStyles.captionSmall,
          ),
          if (showThrottle) ...[
            const SizedBox(width: 8),
            _ThrottleBadge(level: level, diagnostics: diagnostics),
          ],
          const Spacer(),
          Text(
            t(context, AppStrings.values.localTerminalStatusLabel),
            style: AppTextStyles.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThrottleBadge extends StatelessWidget {
  const _ThrottleBadge({required this.level, required this.diagnostics});
  final ThrottleLevel level;
  final Map<String, dynamic> diagnostics;

  String _levelText(BuildContext context) {
    return switch (level) {
      ThrottleLevel.normal => t(context, AppStrings.values.throttleLevelNormal),
      ThrottleLevel.moderate => t(context, AppStrings.values.throttleLevelModerate),
      ThrottleLevel.high => t(context, AppStrings.values.throttleLevelHigh),
      ThrottleLevel.critical => t(context, AppStrings.values.throttleLevelCritical),
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = ThrottleLevelStyles.getColor(level);
    final icon = ThrottleLevelStyles.getIndicatorIcon(level);
    final flushMs = diagnostics['flushIntervalMs'];
    final bufferKB = diagnostics['bufferSizeKB'];
    final msText = t(context, AppStrings.values.millisecondsAbbreviation);
    final kbText = t(context, AppStrings.values.kilobytesAbbreviation);

    return Tooltip(
      message: '$flushMs$msText • $bufferKB$kbText',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            _levelText(context),
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}




