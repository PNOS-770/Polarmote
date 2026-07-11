import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';
import 'package:xterm/xterm.dart';

import '../common/shortcut_key_names.dart';
import '../../../../shared/constants/app_string.dart';
import '../../models/host_entry.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';
import '../../../../shared/design_system/design_system.dart';
import '../dialogs/terminal_dialogs.dart';
import 'terminal_home_panels.dart';

part 'terminal_pane.dart';

class MainPanel extends StatelessWidget {
  const MainPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context, listen: false);

    return SafePanelLayout(
      body: Selector<TerminalAppState, _TerminalAreaSelection>(
        selector: (context, state) {
          final sessions = state.sessions;
          return _TerminalAreaSelection(
            activeIndex: state.activeSessionIndex,
            sessionIds: sessions.map((s) => s.id).toList(growable: false),
            statuses: sessions
                .map((s) => s.tab.status.index)
                .toList(growable: false),
            emptyPaneTreeKey: _emptyPaneTreeKey(state),
            recoveryToken: state.keyboardRecoveryToken,
            splitEnabled: state.terminalSplitViewEnabled,
            splitLayout: state.terminalSplitLayout.index,
            splitPanes: state.terminalSplitPanes
                .map((pane) => '${pane.id}:${pane.sessionId}')
                .toList(growable: false),
            splitTreeKey: state.terminalSplitTree?.toJson().toString() ?? '',
            activeSplitPaneId: state.activeTerminalSplitPaneId,
            maximizedSplitPaneId: state.maximizedTerminalSplitPaneId,
            splitPrimaryRatio: state.terminalSplitPrimaryRatio,
            splitSecondaryRatio: state.terminalSplitSecondaryRatio,
            mobileHorizontalScrollEnabled:
                state.terminalHorizontalScrollEnabled,
            mobileTerminalColumns: state.mobileTerminalColumns,
          );
        },
        builder: (context, selection, child) {
          return _TerminalArea(
            appState: appState,
          );
        },
      ),
      bottom: _BroadcastInputBar(appState: appState),
    );
  }
}

class _TerminalAreaSelection {
  const _TerminalAreaSelection({
    required this.activeIndex,
    required this.sessionIds,
    required this.statuses,
    required this.emptyPaneTreeKey,
    required this.recoveryToken,
    required this.splitEnabled,
    required this.splitLayout,
    required this.splitPanes,
    required this.splitTreeKey,
    required this.activeSplitPaneId,
    required this.maximizedSplitPaneId,
    required this.splitPrimaryRatio,
    required this.splitSecondaryRatio,
    required this.mobileHorizontalScrollEnabled,
    required this.mobileTerminalColumns,
  });

  final int activeIndex;
  final List<String> sessionIds;
  final List<int> statuses;
  final String emptyPaneTreeKey;
  final int recoveryToken;
  final bool splitEnabled;
  final int splitLayout;
  final List<String> splitPanes;
  final String splitTreeKey;
  final String activeSplitPaneId;
  final String maximizedSplitPaneId;
  final double splitPrimaryRatio;
  final double splitSecondaryRatio;
  final bool mobileHorizontalScrollEnabled;
  final int mobileTerminalColumns;

  @override
  bool operator ==(Object other) {
    return other is _TerminalAreaSelection &&
        other.activeIndex == activeIndex &&
        other.recoveryToken == recoveryToken &&
        other.splitEnabled == splitEnabled &&
        other.splitLayout == splitLayout &&
        listEquals(other.splitPanes, splitPanes) &&
        other.splitTreeKey == splitTreeKey &&
        other.activeSplitPaneId == activeSplitPaneId &&
        other.maximizedSplitPaneId == maximizedSplitPaneId &&
        other.splitPrimaryRatio == splitPrimaryRatio &&
        other.splitSecondaryRatio == splitSecondaryRatio &&
        other.mobileHorizontalScrollEnabled == mobileHorizontalScrollEnabled &&
        other.mobileTerminalColumns == mobileTerminalColumns &&
        listEquals(other.sessionIds, sessionIds) &&
        listEquals(other.statuses, statuses) &&
        other.emptyPaneTreeKey == emptyPaneTreeKey;
  }

  @override
  int get hashCode => Object.hash(
    activeIndex,
    recoveryToken,
    splitEnabled,
    splitLayout,
    Object.hashAll(splitPanes),
    splitTreeKey,
    activeSplitPaneId,
    maximizedSplitPaneId,
    splitPrimaryRatio,
    splitSecondaryRatio,
    mobileHorizontalScrollEnabled,
    mobileTerminalColumns,
    Object.hashAll(sessionIds),
    Object.hashAll(statuses),
    emptyPaneTreeKey,
  );
}

String _emptyPaneTreeKey(TerminalAppState state) {
  final parts = <String>[
    state.locale.languageCode,
    state.sessionQuery,
    state.sessionGroupFilter,
    state.sessionSortMode.name,
    state.sessionFilterOnlineOnly ? 'online' : 'all',
    state.sessionFilterPinnedOnly ? 'pinned' : 'unpinned',
  ];
  final pinnedIds = state.pinnedHostIds.toList(growable: false)..sort();
  for (final id in pinnedIds) {
    parts.add('pin:$id');
  }
  for (final host in state.hosts) {
    parts.addAll([
      host.id,
      host.name,
      host.host,
      host.port.toString(),
      host.username,
      host.group,
      host.connectionType.name,
      host.localShellType.name,
      host.serialPortPath ?? '',
      host.serialBaudRate.toString(),
      host.serialDataBits.toString(),
      host.serialStopBits.toString(),
      host.serialParity.name,
      host.lastConnected?.millisecondsSinceEpoch.toString() ?? '',
      state.hostSessionStatus(host.id)?.index.toString() ?? 'none',
    ]);
  }
  return parts.join('\u001f');
}

enum _TerminalMenuAction { copy, paste, selectAll, openUrl, toggleBlockSelect, selectBackground }

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

enum _SplitPaneAction {
  selectSession,
  search,
  closeSession,
  splitRight,
  splitDown,
  removePane,
  maximize,
  restore,
  selectBackground,
  newSession,
}

class _SplitPaneSlot {
  const _SplitPaneSlot({required this.pane, required this.session});

  final TerminalSplitPaneConfig pane;
  final TerminalSession? session;
}

class _EmptyPaneHostNode {
  _EmptyPaneHostNode({required this.name, required this.key});

  final String name;
  final String key;
  final Map<String, _EmptyPaneHostNode> children = {};
  final List<HostEntry> hosts = [];

  factory _EmptyPaneHostNode.root() => _EmptyPaneHostNode(name: '', key: '');

  int get hostCount {
    var count = hosts.length;
    for (final child in children.values) {
      count += child.hostCount;
    }
    return count;
  }

  _EmptyPaneHostNode ensureChild(String segment) {
    final childKey = key.isEmpty ? segment : '$key/$segment';
    return children.putIfAbsent(
      segment,
      () => _EmptyPaneHostNode(name: segment, key: childKey),
    );
  }
}

class _EmptyPaneHostRowData {
  const _EmptyPaneHostRowData.folder({
    required this.folder,
    required this.depth,
    required this.expanded,
  }) : host = null;

  const _EmptyPaneHostRowData.host({required this.host, required this.depth})
    : folder = null,
      expanded = false;

  final _EmptyPaneHostNode? folder;
  final HostEntry? host;
  final int depth;
  final bool expanded;
}

class _SplitDragDivider extends StatefulWidget {
  const _SplitDragDivider({
    required this.vertical,
    required this.onDelta,
    required this.onDragEnd,
  });

  final bool vertical;
  final ValueChanged<double> onDelta;
  final VoidCallback onDragEnd;

  @override
  State<_SplitDragDivider> createState() => _SplitDragDividerState();
}

class _SplitDragDividerState extends State<_SplitDragDivider> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovering || _dragging;
    final hitSize = active ? 14.0 : 12.0;
    final lineThickness = active ? 3.0 : 1.5;
    final lineColor = active
        ? TerminalUiPalette.accent
        : Colors.white.withValues(alpha: 0.72);
    return MouseRegion(
      cursor: widget.vertical
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (details) {
          widget.onDelta(widget.vertical ? details.delta.dx : details.delta.dy);
        },
        onPanEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        onPanCancel: () {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        child: SizedBox(
          width: widget.vertical ? hitSize : double.infinity,
          height: widget.vertical ? double.infinity : hitSize,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(999),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: TerminalUiPalette.accent.withValues(
                            alpha: 0.38,
                          ),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [],
              ),
              width: widget.vertical ? lineThickness : double.infinity,
              height: widget.vertical ? double.infinity : lineThickness,
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalArea extends StatefulWidget {
  const _TerminalArea({
    required this.appState,
  });

  final TerminalAppState appState;

  @override
  State<_TerminalArea> createState() => _TerminalAreaState();
}

class _TerminalAreaState extends State<_TerminalArea> {
  final GlobalKey _terminalStackKey = GlobalKey();
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

  Future<bool> _confirmPasteIfNeeded(
    BuildContext context,
    TerminalAppState appState,
    String text,
  ) async {
    if (!appState.confirmPaste) {
      return true;
    }
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final preview = normalized.length <= 240
        ? normalized
        : '${normalized.substring(0, 240)}...';
    final confirm = await showConfirmDialog(
      context,
      title: l(appState, AppStrings.values.confirmPaste),
      message: '${l(appState, AppStrings.values.confirmPasteContent)}\n\n$preview',
      confirmText: l(appState, AppStrings.values.paste),
      cancelText: l(appState, AppStrings.values.cancel),
    );
    return confirm ?? false;
  }

  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, TerminalController> _terminalControllers = {};
  final Map<String, ScrollController> _terminalScrollControllers = {};
  final Set<String> _emptyPaneExpandedGroups = <String>{};
  final Map<String, String> _pendingClosePaneSessionIds = <String, String>{};
  final Map<String, String> _pendingSearchPaneSessionIds = <String, String>{};
  final Map<String, String> _pendingSearchPaneQueries = <String, String>{};
  bool _emptyPaneExpansionTouched = false;
  bool _splitEnabled = false;
  int _lastSessionCount = -1;

  bool _searchRegex = false;
  bool _searchCaseSensitive = false;
  int _searchCurrentIndex = 0;
  List<_SearchMatch> _searchMatches = [];

  final List<TerminalHighlight> _searchHighlights = [];

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
    for (final controller in _terminalControllers.values) {
      controller.dispose();
    }
    _terminalControllers.clear();
    for (final controller in _terminalScrollControllers.values) {
      controller.dispose();
    }
    _terminalScrollControllers.clear();
    super.dispose();
  }

  FocusNode _focusNodeForSession(TerminalSession session) {
    return _focusNodes.putIfAbsent(session.id, () => FocusNode());
  }

  void _pruneFocusNodes(List<TerminalSession> sessions) {
    final ids = sessions.map((s) => s.id).toSet();
    final stale = _focusNodes.keys.where((id) => !ids.contains(id)).toList();
    for (final id in stale) {
      _focusNodes.remove(id)?.dispose();
    }
  }

  TerminalController _controllerForSession(TerminalSession session) {
    return _terminalControllers.putIfAbsent(
      session.id,
      () => TerminalController(),
    );
  }

  ScrollController _scrollControllerForSession(
    TerminalSession session, {
    String paneId = '',
  }) {
    final key = paneId.isEmpty ? session.id : '$paneId:${session.id}';
    return _terminalScrollControllers.putIfAbsent(
      key,
      () => ScrollController(),
    );
  }

  void _pruneControllers(List<TerminalSession> sessions) {
    final ids = sessions.map((s) => s.id).toSet();
    final stale = _terminalControllers.keys
        .where((id) => !ids.contains(id))
        .toList();
    for (final id in stale) {
      _terminalControllers.remove(id)?.dispose();
    }
    final staleScrollControllers = _terminalScrollControllers.keys.where((id) {
      final sessionId = id.contains(':') ? id.split(':').last : id;
      return !ids.contains(sessionId);
    }).toList();
    for (final id in staleScrollControllers) {
      _terminalScrollControllers.remove(id)?.dispose();
    }
  }

  String _selectedOrAllText(
    TerminalSession session,
    TerminalController controller,
  ) {
    final selection = controller.selection;
    if (selection != null) {
      return _normalizeTerminalClipboardText(
        session.terminal.buffer.getText(selection),
      );
    }
    return _normalizeTerminalClipboardText(session.terminal.buffer.getText());
  }

  String _selectedTerminalText(
    TerminalSession session,
    TerminalController controller,
  ) {
    final selection = controller.selection;
    if (selection == null) return '';
    return _normalizeTerminalClipboardText(
      session.terminal.buffer.getText(selection),
    ).trim();
  }

  bool _looksLikeUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  void _openUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l(widget.appState, AppStrings.values.urlCopiedVar, params: {'url': url})),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  TerminalSession? _sessionForPane(TerminalAppState appState, String paneId) {
    appState.ensureTerminalSplitPanes();
    for (final pane in appState.terminalSplitPanes) {
      if (pane.id == paneId && pane.sessionId.isNotEmpty) {
        return appState.terminalSessionById(pane.sessionId);
      }
    }
    return null;
  }

  Future<void> _showTerminalMenu({
    required BuildContext context,
    required TerminalAppState appState,
    required String paneId,
    required TerminalSession session,
    required TerminalController controller,
    required Offset position,
  }) async {
    appState.focusTerminalSplitPane(paneId);
    if (_sessionForPane(appState, paneId)?.id != session.id) {
      return;
    }
    final menuText = _selectedOrAllText(session, controller);
    final hasText = menuText.isNotEmpty;
    final selectedText = _selectedTerminalText(session, controller);
    final action = await showCompactMenu<_TerminalMenuAction>(
      context: context,
      position: position,
      items: [
        compactMenuItem(
          value: _TerminalMenuAction.copy,
          enabled: hasText,
          label: l(appState, AppStrings.values.copy),
        ),
        compactMenuItem(
          value: _TerminalMenuAction.paste,
          label: l(appState, AppStrings.values.paste),
        ),
        compactMenuItem(
          value: _TerminalMenuAction.selectAll,
          label: l(appState, AppStrings.values.selectAll),
        ),
        if (_looksLikeUrl(selectedText))
          compactMenuItem(
            value: _TerminalMenuAction.openUrl,
            label: l(appState, AppStrings.values.openUrl),
          ),
        compactMenuItem(
          value: _TerminalMenuAction.toggleBlockSelect,
          label: controller.selectionMode == SelectionMode.block
              ? l(appState, AppStrings.values.selectionModeLine)
              : l(appState, AppStrings.values.selectionModeBlock),
        ),
        compactMenuItem(
          value: _TerminalMenuAction.selectBackground,
          label: l(appState, AppStrings.values.selectBackground),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    appState.focusTerminalSplitPane(paneId);
    if (_sessionForPane(appState, paneId)?.id != session.id) {
      return;
    }
    switch (action) {
      case _TerminalMenuAction.copy:
        if (selectedText.isEmpty) {
          return;
        }
        await Clipboard.setData(ClipboardData(text: selectedText));
        return;
      case _TerminalMenuAction.paste:
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (!context.mounted) {
          return;
        }
        final raw = data?.text;
        final text = raw == null ? null : _normalizeTerminalClipboardText(raw);
        if (text != null && text.isNotEmpty) {
          final confirmed = await _confirmPasteIfNeeded(
            context,
            appState,
            text,
          );
          if (!context.mounted) {
            return;
          }
          appState.focusTerminalSplitPane(paneId);
          if (_sessionForPane(appState, paneId)?.id != session.id) {
            return;
          }
          if (!confirmed) {
            return;
          }
          final payload = _prepareTerminalPastePayload(text);
          if (payload.isEmpty) {
            return;
          }
          session.sendInput(payload);
          controller.clearSelection();
        }
        return;
      case _TerminalMenuAction.selectAll:
        final terminal = session.terminal;
        final startY = (terminal.buffer.height - terminal.viewHeight).clamp(
          0,
          terminal.buffer.height - 1,
        );
        final endY = terminal.buffer.height - 1;
        controller.setSelection(
          terminal.buffer.createAnchor(0, startY),
          terminal.buffer.createAnchor(terminal.viewWidth, endY),
          mode: SelectionMode.line,
        );
        final text = _selectedOrAllText(session, controller);
        if (text.isEmpty) {
          return;
        }
        await Clipboard.setData(ClipboardData(text: text));
        return;
      case _TerminalMenuAction.openUrl:
        final url = selectedText.trim();
        if (url.isNotEmpty) {
          _openUrl(url);
        }
        return;
      case _TerminalMenuAction.toggleBlockSelect:
        controller.setSelectionMode(
          controller.selectionMode == SelectionMode.block
              ? SelectionMode.line
              : SelectionMode.block,
        );
        return;
      case _TerminalMenuAction.selectBackground:
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) {
            final images = appState.terminalBackgroundImages;
            final bgIdx = appState.terminalSplitPanes.indexWhere((p) => p.id == paneId);
            final currentBgId = bgIdx >= 0 ? appState.terminalSplitPanes[bgIdx].backgroundImageId : '';
            return SimpleDialog(
              title: Text(l(appState, AppStrings.values.selectBackground)),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: '' == currentBgId
                          ? const Icon(Icons.check, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(l(appState, AppStrings.values.noBackground)),
                  ]),
                ),
                for (final image in images)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, image.id),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          width: 32,
                          height: 24,
                          child: Image.file(
                            File(image.path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image, size: 14, color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(image.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (image.id == currentBgId)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.check, size: 14),
                        ),
                    ]),
                  ),
              ],
            );
          },
        );
        if (result != null && context.mounted) {
          appState.setTerminalSplitPaneBackground(paneId, result);
        }
        return;
    }
  }

  Widget _buildPane(
    BuildContext context,
    TerminalAppState appState,
    TerminalSession session, {
    required bool showTitle,
    required String paneId,
  }) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        appState.focusTerminalSplitPane(paneId);
        _focusNodeForSession(session).requestFocus();
      },
      child: _TerminalPane(
        session: session,
        appState: appState,
        paneId: paneId,
        focusNode: _focusNodeForSession(session),
        controller: _controllerForSession(session),
        verticalScrollController: _scrollControllerForSession(
          session,
          paneId: paneId,
        ),
        showTitle: showTitle,
        onSplitShortcut: _handleSplitShortcut,
        onShowMenu: (position) => _showTerminalMenu(
          context: context,
          appState: appState,
          paneId: paneId,
          session: session,
          controller: _controllerForSession(session),
          position: position,
        ),
      ),
    );
  }

  KeyEventResult _handleSplitShortcut(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final appState = widget.appState;

    final customSearch = _checkCustomShortcut(appState, event, 'search');
    if (customSearch != null) {
      final paneId = appState.activeTerminalSplitPaneId;
      if (paneId.isNotEmpty) {
        final session = _sessionForPane(appState, paneId);
        if (session != null) {
          if (_searchHighlights.isNotEmpty) {
            _clearSearch();
            _controllerForSession(session).clearSelection();
          }
          _requestSearchPane(appState, paneId, session.id);
          return KeyEventResult.handled;
        }
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final paneId = appState.activeTerminalSplitPaneId;
      if (paneId.isNotEmpty && _pendingSearchPaneSessionIds.containsKey(paneId)) {
        _cancelSearchPane(paneId);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.f3 && _searchMatches.isNotEmpty) {
      final paneId = appState.activeTerminalSplitPaneId;
      if (paneId.isNotEmpty) {
        final session = _sessionForPane(appState, paneId);
        if (session != null) {
          _navigateSearch(appState, paneId, session, HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
          return KeyEventResult.handled;
        }
      }
    }

    if (!_splitEnabled) {
      final customSplitAction = _checkCustomShortcut(appState, event, 'splitMaximize') ??
          _checkCustomShortcut(appState, event, 'splitPrev') ??
          _checkCustomShortcut(appState, event, 'splitNext');
      if (customSplitAction != null) return KeyEventResult.ignored;
      return KeyEventResult.ignored;
    }

    final customMaximize = _checkCustomShortcut(appState, event, 'splitMaximize');
    if (customMaximize != null) {
      final paneId = appState.activeTerminalSplitPaneId;
      if (paneId.isNotEmpty) {
        appState.toggleMaximizedTerminalSplitPane(paneId);
        return KeyEventResult.handled;
      }
    }
    final customPrev = _checkCustomShortcut(appState, event, 'splitPrev');
    if (customPrev != null) {
      return _navigateSplitPane(appState, -1);
    }
    final customNext = _checkCustomShortcut(appState, event, 'splitNext');
    if (customNext != null) {
      return _navigateSplitPane(appState, 1);
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _navigateSplitPane(TerminalAppState appState, int direction) {
    final slots = _splitSlots(appState);
    if (slots.isEmpty) return KeyEventResult.ignored;
    final currentIndex = slots.indexWhere(
      (slot) => slot.pane.id == appState.activeTerminalSplitPaneId,
    );
    final index = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (index + direction + slots.length) % slots.length;
    appState.focusTerminalSplitPane(slots[nextIndex].pane.id);
    final session = slots[nextIndex].session;
    if (session != null) {
      _focusNodeForSession(session).requestFocus();
    }
    return KeyEventResult.handled;
  }

  void _requestSearchPane(
    TerminalAppState appState,
    String paneId,
    String sessionId,
  ) {
    appState.focusTerminalSplitPane(paneId);
    if (_sessionForPane(appState, paneId)?.id != sessionId) {
      return;
    }
    setState(() {
      _pendingSearchPaneSessionIds[paneId] = sessionId;
      _pendingSearchPaneQueries[paneId] = '';
    });
  }

  void _cancelSearchPane(String paneId) {
    setState(() {
      _pendingSearchPaneSessionIds.remove(paneId);
      _pendingSearchPaneQueries.remove(paneId);
    });
  }

  void _clearSearch() {
    for (final h in _searchHighlights) {
      h.dispose();
    }
    _searchHighlights.clear();
    setState(() {
      _searchMatches = [];
      _searchCurrentIndex = 0;
    });
  }

  void _executePaneSearch(TerminalAppState appState, String paneId, TerminalSession session, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final buffer = session.terminal.buffer;
    final matches = <_SearchMatch>[];
    final pattern = _searchRegex
        ? RegExp(trimmed, caseSensitive: _searchCaseSensitive)
        : null;
    for (var y = 0; y < buffer.height; y++) {
      final line = buffer.lines[y];
      final text = line.getText();
      if (_searchRegex) {
        for (final m in pattern!.allMatches(text)) {
          matches.add(_SearchMatch(line: y, start: m.start, end: m.end));
        }
      } else {
        var start = 0;
        final searchIn = _searchCaseSensitive ? text : text.toLowerCase();
        final target = _searchCaseSensitive ? trimmed : trimmed.toLowerCase();
        while (true) {
          final idx = searchIn.indexOf(target, start);
          if (idx < 0) break;
          matches.add(_SearchMatch(line: y, start: idx, end: idx + target.length));
          start = idx + 1;
        }
      }
    }
    for (final h in _searchHighlights) {
      h.dispose();
    }
    _searchHighlights.clear();
    final controller = _controllerForSession(session);
    for (final m in matches) {
      _searchHighlights.add(
        controller.highlight(
          p1: buffer.createAnchor(m.start, m.line),
          p2: buffer.createAnchor(m.end, m.line),
                          color: TerminalUiPalette.accent.withValues(alpha: 0.55),
        ),
      );
    }
    setState(() {
      _searchMatches = matches;
      _searchCurrentIndex = 0;
    });
    if (matches.isNotEmpty) {
      _navigateSearch(appState, paneId, session, 0);
    }
    _cancelSearchPane(paneId);
  }

  void _navigateSearch(TerminalAppState appState, String paneId, TerminalSession session, int direction) {
    if (_searchMatches.isEmpty) return;
    final next = (_searchCurrentIndex + direction) % _searchMatches.length;
    final idx = next < 0 ? _searchMatches.length - 1 : next;
    setState(() => _searchCurrentIndex = idx);
    final match = _searchMatches[idx];
    final buffer = session.terminal.buffer;
    final controller = _controllerForSession(session);
    controller.setSelection(
      buffer.createAnchor(match.start, match.line),
      buffer.createAnchor(match.end, match.line),
    );
  }

  List<_SplitPaneSlot> _splitSlots(TerminalAppState appState) {
    appState.ensureTerminalSplitPanes();
    return [
      for (final pane in appState.terminalSplitPanes)
        _SplitPaneSlot(
          pane: pane,
          session: appState.terminalSessionById(pane.sessionId),
        ),
    ];
  }

  Future<void> _showPaneSessionMenu(
    BuildContext context,
    TerminalAppState appState,
    String paneId,
    Offset position,
  ) async {
    appState.focusTerminalSplitPane(paneId);
    final action = await showCompactMenu<String>(
      context: context,
      position: position,
      items: [
        for (final session in appState.sessions)
          compactMenuItem(
            value: session.id,
            label: session.tab.title.trim().isEmpty
                ? session.profile.name
                : session.tab.title,
          ),
      ],
    );
    if (action != null) {
      appState.focusTerminalSplitPane(paneId);
      appState.setTerminalSplitPaneSession(paneId, action);
    }
  }

  Future<void> _showNewSessionForPane(
    BuildContext context,
    TerminalAppState appState,
    String paneId,
  ) async {
    appState.focusTerminalSplitPane(paneId);
    final existingIds = appState.sessions.map((session) => session.id).toSet();
    await showHostDialog(context, appState);
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!context.mounted) return;
      appState.focusTerminalSplitPane(paneId);
      for (final session in appState.sessions.reversed) {
        if (!existingIds.contains(session.id)) {
          appState.setTerminalSplitPaneSession(paneId, session.id);
          return;
        }
      }
    }
  }

  Future<void> _connectHostForPane(
    BuildContext context,
    TerminalAppState appState,
    String paneId,
    HostEntry host,
  ) async {
    appState.focusTerminalSplitPane(paneId);
    if (appState.reuseSessionForNewPane) {
      final existingSession = appState.terminalSessionForHost(host);
      if (existingSession != null) {
        appState.setTerminalSplitPaneSession(paneId, existingSession.id);
        if (existingSession.tab.status == TerminalStatus.disconnected) {
          unawaited(appState.reconnectSession(existingSession));
        }
        return;
      }
    }
    final existingIds = appState.sessions.map((session) => session.id).toSet();
    unawaited(appState.connectToHost(host));
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!context.mounted) return;
      for (final session in appState.sessions.reversed) {
        if (!existingIds.contains(session.id) &&
            session.profile.id == host.id) {
          appState.setTerminalSplitPaneSession(paneId, session.id);
          return;
        }
      }
    }
  }

  Future<void> _showPaneActionMenu({
    required BuildContext context,
    required TerminalAppState appState,
    required _SplitPaneSlot slot,
    required Offset position,
  }) async {
    final paneId = slot.pane.id;
    appState.focusTerminalSplitPane(paneId);
    final menuSession = _sessionForPane(appState, paneId);
    final maximized = appState.maximizedTerminalSplitPaneId == paneId;
    final action = await showCompactMenu<_SplitPaneAction>(
      context: context,
      position: position,
      items: [
        compactMenuItem(
          value: _SplitPaneAction.selectSession,
          label: l(appState, AppStrings.values.selectSession),
        ),
        compactMenuItem(
          value: maximized
              ? _SplitPaneAction.restore
              : _SplitPaneAction.maximize,
          label: maximized
              ? l(appState, AppStrings.values.restorePane)
              : l(appState, AppStrings.values.maximizePane),
        ),
        compactMenuItem(
          value: _SplitPaneAction.splitRight,
          label: l(appState, AppStrings.values.splitRight),
        ),
        compactMenuItem(
          value: _SplitPaneAction.splitDown,
          label: l(appState, AppStrings.values.splitDown),
        ),
        if (appState.terminalSplitPanes.length > 1)
          compactMenuItem(
            value: _SplitPaneAction.removePane,
            label: l(appState, AppStrings.values.removePane),
          ),
        if (menuSession != null)
          compactMenuItem(
            value: _SplitPaneAction.search,
            label: l(appState, AppStrings.values.searchOutput),
          ),
        if (menuSession != null)
          compactMenuItem(
            value: _SplitPaneAction.closeSession,
            label: l(appState, AppStrings.values.disconnectPaneTerminal),
          ),
        compactMenuItem(
          value: _SplitPaneAction.newSession,
          label: l(appState, AppStrings.values.newSession),
        ),
        compactMenuItem(
          value: _SplitPaneAction.selectBackground,
          label: l(appState, AppStrings.values.selectBackground),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    appState.focusTerminalSplitPane(paneId);
    final currentSession = _sessionForPane(appState, paneId);
    switch (action) {
      case _SplitPaneAction.selectSession:
        await _showPaneSessionMenu(context, appState, paneId, position);
        return;
      case _SplitPaneAction.closeSession:
        if (currentSession != null) {
          _requestClosePaneSession(appState, paneId, currentSession.id);
        }
        return;
      case _SplitPaneAction.maximize:
      case _SplitPaneAction.restore:
        appState.toggleMaximizedTerminalSplitPane(paneId);
        return;
      case _SplitPaneAction.splitRight:
        appState.splitTerminalSplitPane(paneId, TerminalSplitAxis.row);
        return;
      case _SplitPaneAction.splitDown:
        appState.splitTerminalSplitPane(paneId, TerminalSplitAxis.column);
        return;
      case _SplitPaneAction.removePane:
        appState.removeTerminalSplitPane(paneId);
        return;
      case _SplitPaneAction.search:
        if (currentSession != null) {
          if (_searchHighlights.isNotEmpty) {
            _clearSearch();
            _controllerForSession(currentSession).clearSelection();
          }
          _requestSearchPane(appState, paneId, currentSession.id);
        }
        return;
      case _SplitPaneAction.newSession:
        await _showNewSessionForPane(context, appState, paneId);
        return;
      case _SplitPaneAction.selectBackground:
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) {
            final images = appState.terminalBackgroundImages;
            final bgIdx = appState.terminalSplitPanes.indexWhere((p) => p.id == paneId);
            final currentBgId = bgIdx >= 0 ? appState.terminalSplitPanes[bgIdx].backgroundImageId : '';
            if (images.isEmpty) {
              return AlertDialog(
                backgroundColor: AppColors.cardBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.radiusDialog,
                ),
                title: Text(
                  l(appState, AppStrings.values.selectBackground),
                  style: AppTextStyles.h4,
                ),
                content: Text(
                  l(appState, AppStrings.values.noneSelected),
                  style: AppTextStyles.body,
                ),
                actionsPadding: const EdgeInsets.all(AppSpacing.lg),
                actions: [
                  PrimaryButton(
                    onPressed: () => Navigator.pop(ctx),
                    label: l(appState, AppStrings.values.ok),
                    size: ButtonSize.medium,
                  ),
                ],
              );
            }
            return SimpleDialog(
              title: Text(l(appState, AppStrings.values.selectBackground)),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: '' == currentBgId
                          ? const Icon(Icons.check, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(l(appState, AppStrings.values.noBackground)),
                  ]),
                ),
                for (final image in images)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, image.id),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          width: 32,
                          height: 24,
                          child: Image.file(
                            File(image.path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image, size: 14, color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(image.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (image.id == currentBgId)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.check, size: 14),
                        ),
                    ]),
                  ),
              ],
            );
          },
        );
        if (result != null && context.mounted) {
          appState.setTerminalSplitPaneBackground(paneId, result);
        }
        return;
    }
  }

  Widget _buildPaneHeaderAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: TerminalUiPalette.textSecondary),
        ),
      ),
    );
  }

  void _openPaneSection(
    TerminalAppState appState,
    String paneId,
    NavSection section, {
    String? sessionId,
  }) {
    appState.focusTerminalSplitPane(paneId);
    if (sessionId != null &&
        _sessionForPane(appState, paneId)?.id != sessionId) {
      return;
    }
    appState.setNavSection(section);
  }

  void _requestClosePaneSession(
    TerminalAppState appState,
    String paneId,
    String sessionId,
  ) {
    appState.focusTerminalSplitPane(paneId);
    if (_sessionForPane(appState, paneId)?.id != sessionId) {
      return;
    }
    setState(() {
      _pendingClosePaneSessionIds[paneId] = sessionId;
    });
  }

  void _cancelClosePaneSession(String paneId) {
    setState(() {
      _pendingClosePaneSessionIds.remove(paneId);
    });
  }

  Future<void> _confirmClosePaneSession(
    TerminalAppState appState,
    String paneId,
    String sessionId,
  ) async {
    appState.focusTerminalSplitPane(paneId);
    setState(() {
      _pendingClosePaneSessionIds.remove(paneId);
    });
    if (_sessionForPane(appState, paneId)?.id != sessionId) {
      return;
    }
    appState.clearTerminalSplitPane(paneId);
    final stillVisibleInAnotherPane = appState.terminalSplitPanes.any(
      (pane) => pane.id != paneId && pane.sessionId == sessionId,
    );
    if (!stillVisibleInAnotherPane) {
      await appState.closeSession(sessionId);
    }
  }

  Widget _buildClosePaneConfirmLayer(
    TerminalAppState appState,
    String paneId,
    TerminalSession session,
  ) {
    final title = session.tab.title.trim().isEmpty
        ? session.profile.name
        : session.tab.title.trim();
    return ColoredBox(
      color: const Color(0x99000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: TerminalUiPalette.cardBackground,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.power_settings_new,
                        size: 17,
                        color: TerminalUiPalette.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l(appState, AppStrings.values.disconnectPaneConfirmTitle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TerminalUiPalette.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l(appState, AppStrings.values.disconnectPaneConfirmBodyVar,
                        params: {'title': title}),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TerminalUiPalette.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SecondaryButton(
                        onPressed: () => _cancelClosePaneSession(paneId),
                        label: l(appState, AppStrings.values.cancel),
                        size: ButtonSize.small,
                      ),
                      const SizedBox(width: 8),
                      PrimaryButton(
                        onPressed: () => unawaited(
                          _confirmClosePaneSession(
                            appState,
                            paneId,
                            session.id,
                          ),
                        ),
                        label: l(appState, AppStrings.values.disconnectPaneTerminal),
                        size: ButtonSize.small,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaneSearchLayer(
    BuildContext context,
    TerminalAppState appState,
    String paneId,
    TerminalSession session,
  ) {
    return GestureDetector(
      onTap: () => _cancelSearchPane(paneId),
      child: ColoredBox(
        color: const Color(0x99000000),
        child: GestureDetector(
          onTap: () {},
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: TerminalUiPalette.cardBackground,
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.search,
                            size: 17,
                            color: TerminalUiPalette.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l(appState, AppStrings.values.searchThisPane),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TerminalUiPalette.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AppTextField(
                        hint: l(appState, AppStrings.values.searchHint),
                        onChanged: (value) {
                          _pendingSearchPaneQueries[paneId] = value;
                        },
                        onSubmitted: (value) => _executePaneSearch(
                          appState,
                          paneId,
                          session,
                          value,
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _CompactToggle(
                            label: l(appState, AppStrings.values.searchRegex),
                            value: _searchRegex,
                            onChanged: (v) => setState(() => _searchRegex = v),
                          ),
                          const SizedBox(width: 8),
                          _CompactToggle(
                            label: l(appState, AppStrings.values.searchCaseSensitive),
                            value: _searchCaseSensitive,
                            onChanged: (v) => setState(() => _searchCaseSensitive = v),
                          ),
                          const Spacer(),
                          Text(
                            _searchMatches.isEmpty
                                ? l(appState, AppStrings.values.noMatches)
                                : '${_searchCurrentIndex + 1}/${_searchMatches.length}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: _searchMatches.isEmpty ? null : () => _navigateSearch(appState, paneId, session, -1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: _searchMatches.isEmpty ? null : () => _navigateSearch(appState, paneId, session, 1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SecondaryButton(
                            onPressed: () => _cancelSearchPane(paneId),
                            label: l(appState, AppStrings.values.cancel),
                            size: ButtonSize.small,
                          ),
                          const SizedBox(width: 8),
                          PrimaryButton(
                            onPressed: () => _executePaneSearch(
                              appState,
                              paneId,
                              session,
                              _pendingSearchPaneQueries[paneId] ?? '',
                            ),
                            label: l(appState, AppStrings.values.search),
                            size: ButtonSize.small,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitPaneFrame(
    BuildContext context,
    TerminalAppState appState,
    _SplitPaneSlot slot,
  ) {
    final session = slot.session;
    final active = appState.activeTerminalSplitPaneId == slot.pane.id;
    final title = session == null
        ? l(appState, AppStrings.values.emptyPane)
        : (session.tab.title.trim().isEmpty
              ? session.profile.name
              : session.tab.title);
    final statusColor = session == null
        ? TerminalUiPalette.textSecondary
        : switch (session.tab.status) {
            TerminalStatus.connected => TerminalUiPalette.success,
            TerminalStatus.connecting => TerminalUiPalette.warning,
            TerminalStatus.reconnecting => TerminalUiPalette.info,
            TerminalStatus.disconnected => TerminalUiPalette.error,
          };
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? TerminalUiPalette.accent : Colors.transparent,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 30,
            color: active
                ? TerminalUiPalette.cardBackground
                : TerminalUiPalette.panelBackground,
            padding: const EdgeInsets.only(left: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maximized =
                    appState.maximizedTerminalSplitPaneId == slot.pane.id;
                var budget = constraints.maxWidth - 32;
                bool afford(int cost) {
                  if (budget >= cost) {
                    budget -= cost;
                    return true;
                  }
                  return false;
                }
                final showFile = session != null && afford(22);
                final showSearch = session != null && afford(22);
                final showMore = afford(24);
                final showMax = afford(22);
                final showDisconnect = session != null && afford(22);
                return Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: TerminalUiPalette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (showFile)
                      _buildPaneHeaderAction(
                        tooltip: l(appState, AppStrings.values.showFileTree),
                        icon: Icons.folder_outlined,
                        onTap: () => _openPaneSection(
                          appState,
                          slot.pane.id,
                          NavSection.sftp,
                          sessionId: session.id,
                        ),
                      ),
                    if (showSearch)
                      _buildPaneHeaderAction(
                        tooltip: _pendingSearchPaneSessionIds.containsKey(slot.pane.id) || _searchHighlights.isNotEmpty
                            ? l(appState, AppStrings.values.cancel)
                            : l(appState, AppStrings.values.searchOutput),
                        icon: _pendingSearchPaneSessionIds.containsKey(slot.pane.id) || _searchHighlights.isNotEmpty
                            ? Icons.highlight_off
                            : Icons.search,
                        onTap: () {
                          if (_pendingSearchPaneSessionIds.containsKey(slot.pane.id)) {
                            _cancelSearchPane(slot.pane.id);
                          } else if (_searchHighlights.isNotEmpty) {
                            _clearSearch();
                            _controllerForSession(session).clearSelection();
                          } else {
                            _requestSearchPane(
                              appState,
                              slot.pane.id,
                              session.id,
                            );
                          }
                        },
                      ),
                    if (showMax)
                      _buildPaneHeaderAction(
                        tooltip: maximized
                            ? l(appState, AppStrings.values.restorePane)
                            : l(appState, AppStrings.values.maximizePane),
                        icon: maximized
                            ? Icons.close_fullscreen
                            : Icons.open_in_full,
                        onTap: () {
                          appState.focusTerminalSplitPane(slot.pane.id);
                          appState.toggleMaximizedTerminalSplitPane(slot.pane.id);
                        },
                      ),
                    if (showDisconnect)
                      _buildPaneHeaderAction(
                        tooltip: l(appState, AppStrings.values.disconnectPaneTerminal),
                        icon: Icons.power_settings_new,
                        onTap: () => _requestClosePaneSession(
                          appState,
                          slot.pane.id,
                          session.id,
                        ),
                      ),
                    if (showMore)
                      Tooltip(
                      message: l(appState, AppStrings.values.more),
                      child: InkWell(
                        onTapDown: (details) {
                          appState.focusTerminalSplitPane(slot.pane.id);
                          _showPaneActionMenu(
                            context: context,
                            appState: appState,
                            slot: slot,
                            position: details.globalPosition,
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.more_horiz, size: 16),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        Expanded(
          child: Stack(
              children: [
                Positioned.fill(
                  child: session == null
                      ? _buildEmptySplitPane(context, appState, slot.pane.id)
                      : _buildPane(
                          context,
                          appState,
                          session,
                          showTitle: false,
                          paneId: slot.pane.id,
                        ),
                ),
                if (_pendingClosePaneSessionIds[slot.pane.id] == session?.id &&
                    session != null)
                  Positioned.fill(
                    child: _buildClosePaneConfirmLayer(
                      appState,
                      slot.pane.id,
                      session,
                    ),
                  ),
                if (_pendingSearchPaneSessionIds[slot.pane.id] == session?.id &&
                    session != null)
                  Positioned.fill(
                    child: _buildPaneSearchLayer(
                      context,
                      appState,
                      slot.pane.id,
                      session,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySplitPane(
    BuildContext context,
    TerminalAppState appState,
    String paneId,
  ) {
    final hosts = appState.visibleHosts();
    final root = _buildEmptyPaneHostTree(appState, hosts);
    final defaultExpandedKey = _emptyPaneDefaultExpandedKey(root);
    final rows = _flattenEmptyPaneHostRows(root, defaultExpandedKey);
    return ColoredBox(
      color: const Color(0xFF111111),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 12 || constraints.maxWidth < 80) {
            return const SizedBox.expand();
          }
          final compact = constraints.maxHeight < 52;
          final padding = compact
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
              : const EdgeInsets.fromLTRB(10, 8, 10, 8);
          final list = rows.isEmpty
              ? Center(
                  child: Text(
                    l(appState, AppStrings.values.noSessionsAvailableConnect),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemExtent: 26,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final folder = row.folder;
                    if (folder != null) {
                      return _buildEmptyPaneFolderRow(
                        folder,
                        row.depth,
                        row.expanded,
                      );
                    }
                    return _buildEmptyPaneHostItem(
                      context,
                      appState,
                      paneId,
                      row.host!,
                      row.depth,
                    );
                  },
                );
          return ClipRect(
            child: Padding(
              padding: padding,
              child: compact
                  ? list
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l(appState, AppStrings.values.connectSessionToPane),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(child: list),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  _EmptyPaneHostNode _buildEmptyPaneHostTree(
    TerminalAppState appState,
    List<HostEntry> hosts,
  ) {
    final fallback = l(appState, AppStrings.values.defaultValue);
    final root = _EmptyPaneHostNode.root();
    for (final host in hosts) {
      final group = host.group.trim().isEmpty ? fallback : host.group.trim();
      final segments = group
          .split(RegExp(r'[\\/]+'))
          .map((segment) => segment.trim())
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      var cursor = root;
      for (final segment in segments) {
        cursor = cursor.ensureChild(segment);
      }
      cursor.hosts.add(host);
    }
    _sortEmptyPaneHostTree(root, appState);
    return root;
  }

  void _sortEmptyPaneHostTree(
    _EmptyPaneHostNode node,
    TerminalAppState appState,
  ) {
    final sortedChildren = node.children.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    node.children
      ..clear()
      ..addEntries(sortedChildren.map((child) => MapEntry(child.name, child)));
    node.hosts.sort((a, b) => _compareEmptyPaneHosts(a, b, appState));
    for (final child in sortedChildren) {
      _sortEmptyPaneHostTree(child, appState);
    }
  }

  int _compareEmptyPaneHosts(
    HostEntry a,
    HostEntry b,
    TerminalAppState appState,
  ) {
    final aConnected =
        appState.hostSessionStatus(a.id) == TerminalStatus.connected;
    final bConnected =
        appState.hostSessionStatus(b.id) == TerminalStatus.connected;
    if (aConnected != bConnected) {
      return aConnected ? -1 : 1;
    }
    return (a.name.trim().isEmpty ? a.host : a.name).toLowerCase().compareTo(
      (b.name.trim().isEmpty ? b.host : b.name).toLowerCase(),
    );
  }

  String? _emptyPaneDefaultExpandedKey(_EmptyPaneHostNode root) {
    if (_emptyPaneExpansionTouched ||
        _emptyPaneExpandedGroups.isNotEmpty ||
        root.children.isEmpty) {
      return null;
    }
    return root.children.values.first.key;
  }

  List<_EmptyPaneHostRowData> _flattenEmptyPaneHostRows(
    _EmptyPaneHostNode root,
    String? defaultExpandedKey,
  ) {
    final rows = <_EmptyPaneHostRowData>[];

    void appendNode(_EmptyPaneHostNode node, int depth) {
      for (final child in node.children.values) {
        final expanded =
            child.key == defaultExpandedKey ||
            _emptyPaneExpandedGroups.contains(child.key);
        rows.add(
          _EmptyPaneHostRowData.folder(
            folder: child,
            depth: depth,
            expanded: expanded,
          ),
        );
        if (expanded) {
          appendNode(child, depth + 1);
        }
      }
      for (final host in node.hosts) {
        rows.add(_EmptyPaneHostRowData.host(host: host, depth: depth));
      }
    }

    appendNode(root, 0);
    return rows;
  }

  Widget _buildEmptyPaneFolderRow(
    _EmptyPaneHostNode folder,
    int depth,
    bool expanded,
  ) {
    final indent = (depth * 14).clamp(0, 56).toDouble();
    return Material(
      color: expanded ? const Color(0xFF191919) : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            _emptyPaneExpansionTouched = true;
            if (expanded) {
              _emptyPaneExpandedGroups.remove(folder.key);
            } else {
              _emptyPaneExpandedGroups.add(folder.key);
            }
          });
        },
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: 6),
          child: Row(
            children: [
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 15,
                color: Colors.white54,
              ),
              const SizedBox(width: 2),
              Icon(
                expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 14,
                color: Colors.white54,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${folder.hostCount}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPaneHostItem(
    BuildContext context,
    TerminalAppState appState,
    String paneId,
    HostEntry host,
    int depth,
  ) {
    final status = appState.hostSessionStatus(host.id);
    final connected = status == TerminalStatus.connected;
    final existingSession = appState.terminalSessionForHost(host);
    final indent = (depth * 14 + 17).clamp(0, 73).toDouble();
    return Material(
      color: connected ? const Color(0xFF183E2C) : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            unawaited(_connectHostForPane(context, appState, paneId, host)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showBadge = constraints.maxWidth > 180;
            return Padding(
              padding: EdgeInsets.only(left: indent, right: 6),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _emptyPaneHostStatusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      host.name.trim().isEmpty ? _connectionTypeLabel(host) : host.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (showBadge) ...[
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 68),
                      child: Text(
                        existingSession == null
                            ? _connectionTypeLabel(host)
                            : _statusLabel(appState, status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: _emptyPaneHostStatusColor(status),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _connectionTypeLabel(HostEntry host) {
    final appState = widget.appState;
    return switch (host.connectionType) {
      ConnectionType.ssh => l(appState, AppStrings.values.connectionSsh),
      ConnectionType.serial => l(
        appState,
        AppStrings.values.badgeConnectionTypeSerial,
      ),
      ConnectionType.telnet => l(appState, AppStrings.values.connectionTelnet),
      ConnectionType.local => switch (host.localShellType) {
        LocalShellType.powershell => l(
          appState,
          AppStrings.values.localShellPowerShell,
        ),
        LocalShellType.powershellAdmin => l(
          appState,
          AppStrings.values.localShellPowerShellAdmin,
        ),
        LocalShellType.commandPrompt => l(
          appState,
          AppStrings.values.badgeLocalShellCmd,
        ),
        LocalShellType.wsl => l(appState, AppStrings.values.localShellWsl),
        LocalShellType.bash => l(appState, AppStrings.values.localShellBash),
        LocalShellType.systemDefault => l(
          appState,
          AppStrings.values.badgeLocalShellLocal,
        ),
      },
    };
  }

  String _statusLabel(TerminalAppState appState, TerminalStatus? status) {
    return switch (status) {
      TerminalStatus.connected => l(appState, AppStrings.values.connected),
      TerminalStatus.connecting => l(appState, AppStrings.values.connecting),
      TerminalStatus.reconnecting => l(
        appState,
        AppStrings.values.reconnecting,
      ),
      TerminalStatus.disconnected ||
      null => l(appState, AppStrings.values.disconnected),
    };
  }

  Color _emptyPaneHostStatusColor(TerminalStatus? status) {
    return switch (status) {
      TerminalStatus.connected => TerminalUiPalette.success,
      TerminalStatus.connecting => TerminalUiPalette.warning,
      TerminalStatus.reconnecting => TerminalUiPalette.warning,
      TerminalStatus.disconnected || null => Colors.white38,
    };
  }

  Widget _buildSplitContent(
    BuildContext context,
    TerminalAppState appState,
    List<_SplitPaneSlot> slots,
  ) {
    final tree = appState.terminalSplitTree;
    if (!_splitEnabled || slots.length <= 1 || tree == null) {
      if (slots.isEmpty) {
        return _buildEmptySplitPane(context, appState, 'pane-0');
      }
      return _buildSplitPaneFrame(context, appState, slots.first);
    }
    final maximized = appState.maximizedTerminalSplitPaneId;
    if (maximized.isNotEmpty) {
      final slot = slots.firstWhere(
        (item) => item.pane.id == maximized,
        orElse: () => slots.first,
      );
      return _buildSplitPaneFrame(context, appState, slot);
    }
    final slotByPaneId = {for (final slot in slots) slot.pane.id: slot};
    return _buildSplitTreeNode(context, appState, tree, slotByPaneId);
  }

  Widget _buildSplitTreeNode(
    BuildContext context,
    TerminalAppState appState,
    TerminalSplitTreeNode node,
    Map<String, _SplitPaneSlot> slotByPaneId,
  ) {
    if (node.isLeaf) {
      final slot = slotByPaneId[node.paneId];
      if (slot == null) {
        return _buildEmptySplitPane(context, appState, node.paneId);
      }
      return _buildSplitPaneFrame(context, appState, slot);
    }
    final first = node.first;
    final second = node.second;
    final axis = node.axis ?? TerminalSplitAxis.row;
    if (first == null || second == null) {
      return _buildEmptySplitPane(context, appState, 'pane-0');
    }
    final ratio = node.ratio.clamp(0.15, 0.85).toDouble();
    final firstChild = Expanded(
      flex: (ratio * 1000).round(),
      child: _buildSplitTreeNode(context, appState, first, slotByPaneId),
    );
    final secondChild = Expanded(
      flex: ((1 - ratio) * 1000).round(),
      child: _buildSplitTreeNode(context, appState, second, slotByPaneId),
    );
    final verticalDivider = axis == TerminalSplitAxis.row;
    return LayoutBuilder(
      builder: (context, constraints) {
        final divider = _SplitDragDivider(
          vertical: verticalDivider,
          onDelta: (delta) {
            final extent = verticalDivider
                ? constraints.maxWidth
                : constraints.maxHeight;
            if (extent > 0) {
              appState.adjustTerminalSplitNodeRatio(
                node.id,
                delta / extent,
                persist: false,
              );
            }
          },
          onDragEnd: appState.saveTerminalSplitLayoutState,
        );
        if (axis == TerminalSplitAxis.row) {
          return Row(children: [firstChild, divider, secondChild]);
        }
        return Column(children: [firstChild, divider, secondChild]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final sessions = appState.sessions;
    if (sessions.length != _lastSessionCount) {
      _lastSessionCount = sessions.length;
      _pruneFocusNodes(sessions);
      _pruneControllers(sessions);
    }
    final session = appState.activeSession;
    _splitEnabled = appState.terminalSplitViewEnabled;
    if (session == null && !_splitEnabled) {
      return PlaceholderPanel(
        title: l(appState, AppStrings.values.noSessions),
        description: l(
          appState,
          AppStrings.values.createANewSessionOrQuickConnect,
        ),
        actionLabel: l(appState, AppStrings.values.newSession),
        onAction: () => showHostDialog(context, appState),
      );
    }
    final slots = _splitSlots(appState);

    return Container(
      key: _terminalStackKey,
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Expanded(
            child: ClipRect(
              child: _buildSplitContent(context, appState, slots),
            ),
          ),

        ],
      ),
    );
  }
}

class _TerminalOverlay extends StatelessWidget {
  const _TerminalOverlay({
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SafeContainer(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.h5.copyWith(color: Colors.white),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 12),
                    PrimaryButton(
                      onPressed: onAction,
                      label: actionLabel!,
                      size: ButtonSize.medium,
                    ),
                  ],
                ],
              ),
          ),
        ),
      ),
    );
  }
}

class _SearchMatch {
  const _SearchMatch({required this.line, required this.start, required this.end});
  final int line;
  final int start;
  final int end;
}

class _CompactToggle extends StatelessWidget {
  const _CompactToggle({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: value ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, color: value ? Colors.white : Colors.white54)),
      ),
    );
  }
}

class _BroadcastInputBar extends StatefulWidget {
  final TerminalAppState appState;
  const _BroadcastInputBar({required this.appState});

  @override
  State<_BroadcastInputBar> createState() => _BroadcastInputBarState();
}

class _BroadcastInputBarState extends State<_BroadcastInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _onKeyEvent;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _broadcast(String data) {
    if (data.isEmpty) return;
    for (final session in widget.appState.sessions) {
      if (session.tab.status == TerminalStatus.connected) {
        session.sendInput(data, trackForHistory: false);
      }
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isMod = isCtrl || isMeta;

    if (key == LogicalKeyboardKey.enter && !isMod && !HardwareKeyboard.instance.isShiftPressed) {
      final text = _controller.text;
      if (text.isNotEmpty) {
        _broadcast('$text\n');
      } else {
        _broadcast('\n');
      }
      _controller.clear();
      return KeyEventResult.handled;
    }

    if (isMod && key == LogicalKeyboardKey.keyC) {
      if (_controller.selection.isValid && _controller.selection.start != _controller.selection.end) {
        return KeyEventResult.ignored;
      }
      _broadcast('\x03');
      return KeyEventResult.handled;
    }

    if (isMod && key == LogicalKeyboardKey.keyD) {
      _broadcast('\x04');
      return KeyEventResult.handled;
    }

    if (isMod && key == LogicalKeyboardKey.keyZ) {
      _broadcast('\x1A');
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 100),
      decoration: BoxDecoration(
        color: TerminalUiPalette.cardBackground,
        border: const Border(
          top: BorderSide(color: TerminalUiPalette.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 6, right: 4),
            child: Icon(Icons.campaign, size: 14, color: TerminalUiPalette.warning),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: l(widget.appState, AppStrings.values.broadcastInputHint),
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: TerminalUiPalette.textSecondary,
                ),
                contentPadding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
