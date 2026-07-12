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
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../models/terminal_adaptive_throttle.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import '../common/terminal_ui_palette.dart';
import '../../../../shared/design_system/design_system.dart';
import '../stage_manager/grid_stage_panel.dart';
import '../common/stage_background_picker.dart';
import '../common/stage_context_menu.dart';
import '../common/command_executor.dart';
import '../common/cascading_menu.dart';
import '../session_tree/session_tree_panel.dart';
import '../file_tree/terminal_file_tree.dart';
import '../mobile/mobile_terminal_layout.dart';
import '../dialogs/terminal_dialogs.dart';
import '../modal_panels/transfer_modal_panel.dart';
import '../modal_panels/port_forward_modal_panel.dart';
import '../modal_panels/lan_scan_modal_panel.dart';
import '../modal_panels/log_viewer_modal_panel.dart';
import 'terminal_home_panels.dart';
import 'terminal_status_bar.dart';

part 'terminal_pane.dart';
part 'terminal_panel_shortcuts.dart';


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
            emptyPaneTreeKey: _emptyPaneTreeKey(state),
            recoveryToken: state.keyboardRecoveryToken,
            splitEnabled: state.terminalSplitViewEnabled,
            splitPanes: state.terminalSplitPanes
                .map((pane) => '${pane.id}:${pane.sessionId}')
                .toList(growable: false),
            activeSplitPaneId: state.activeTerminalSplitPaneId,
            maximizedSplitPaneId: state.maximizedTerminalSplitPaneId,
            splitPrimaryRatio: state.terminalSplitPrimaryRatio,
            splitSecondaryRatio: state.terminalSplitSecondaryRatio,
            mobileHorizontalScrollEnabled:
                state.terminalHorizontalScrollEnabled,
            mobileTerminalColumns: state.mobileTerminalColumns,
            stageManagerEnabled: state.stageManagerEnabled,
            stageCount: state.terminalStages.length,
            activeStageId: state.activeTerminalStageId,
            stageChangeToken: state.stageChangeToken,
            showThumbnailBackground: state.showThumbnailBackground,
            selectedHostIdsHash: state.selectedHostIds.hashCode,
            restorationInProgress: false,
          );
        },
        builder: (context, selection, child) {
          return _TerminalArea(
            appState: appState,
          );
        },
      ),
    );
  }
}

class _TerminalAreaSelection {
  const _TerminalAreaSelection({
    required this.activeIndex,
    required this.sessionIds,
    required this.emptyPaneTreeKey,
    required this.recoveryToken,
    required this.splitEnabled,
    required this.splitPanes,
    required this.activeSplitPaneId,
    required this.maximizedSplitPaneId,
    required this.splitPrimaryRatio,
    required this.splitSecondaryRatio,
    required this.mobileHorizontalScrollEnabled,
    required this.mobileTerminalColumns,
    required this.stageManagerEnabled,
    required this.stageCount,
    required this.activeStageId,
    required this.stageChangeToken,
    required this.showThumbnailBackground,
    required this.selectedHostIdsHash,
    required this.restorationInProgress,
  });

  final int activeIndex;
  final List<String> sessionIds;
  final String emptyPaneTreeKey;
  final int recoveryToken;
  final bool splitEnabled;
  final List<String> splitPanes;
  final String activeSplitPaneId;
  final String maximizedSplitPaneId;
  final double splitPrimaryRatio;
  final double splitSecondaryRatio;
  final bool mobileHorizontalScrollEnabled;
  final int mobileTerminalColumns;
  final bool stageManagerEnabled;
  final int stageCount;
  final String activeStageId;
  final int stageChangeToken;
  final bool showThumbnailBackground;
  final int selectedHostIdsHash;
  final bool restorationInProgress;

  @override
  bool operator ==(Object other) {
    return other is _TerminalAreaSelection &&
        other.activeIndex == activeIndex &&
        other.recoveryToken == recoveryToken &&
        other.splitEnabled == splitEnabled &&
        listEquals(other.splitPanes, splitPanes) &&
        other.activeSplitPaneId == activeSplitPaneId &&
        other.maximizedSplitPaneId == maximizedSplitPaneId &&
        other.splitPrimaryRatio == splitPrimaryRatio &&
        other.splitSecondaryRatio == splitSecondaryRatio &&
        other.mobileHorizontalScrollEnabled == mobileHorizontalScrollEnabled &&
        other.mobileTerminalColumns == mobileTerminalColumns &&
        listEquals(other.sessionIds, sessionIds) &&
        other.emptyPaneTreeKey == emptyPaneTreeKey &&
        other.stageManagerEnabled == stageManagerEnabled &&
        other.stageCount == stageCount &&
        other.activeStageId == activeStageId &&
        other.stageChangeToken == stageChangeToken &&
        other.showThumbnailBackground == showThumbnailBackground &&
        other.selectedHostIdsHash == selectedHostIdsHash &&
        other.restorationInProgress == restorationInProgress;
  }

  @override
  int get hashCode => Object.hash(
    activeIndex,
    recoveryToken,
    splitEnabled,
    Object.hashAll(splitPanes),
    activeSplitPaneId,
    maximizedSplitPaneId,
    splitPrimaryRatio,
    splitSecondaryRatio,
    mobileHorizontalScrollEnabled,
    mobileTerminalColumns,
    Object.hashAll(sessionIds),
    emptyPaneTreeKey,
    stageManagerEnabled,
    stageCount,
    activeStageId,
    stageChangeToken,
    restorationInProgress,
    showThumbnailBackground,
    selectedHostIdsHash,
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

enum _TerminalMenuAction { copy, paste, selectAll, openUrl, toggleBlockSelect, selectBackground, closeSession }

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
  final Map<String, String> _pendingSearchPaneSessionIds = <String, String>{};
  final Map<String, String> _pendingSearchPaneQueries = <String, String>{};
  final Map<String, Widget> _cachedPaneWidgets = {};

  bool _splitEnabled = false;
  int _lastSessionCount = -1;

  String _focusedStageId = '';
  String _lastScrolledStageId = '';
  bool _showFileTreePanel = true;
  double _fileTreeHeight = 220;
  final ScrollController _stageTabScrollController = ScrollController();

  int _searchCurrentIndex = 0;
  List<_SearchMatch> _searchMatches = [];

  final List<TerminalHighlight> _searchHighlights = [];

  /// Global key handler registered via HardwareKeyboard.instance.addHandler.
  /// Fires for all key events regardless of focus, so shortcuts like lanScan
  /// work even when no terminal pane has focus.
  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final context = _terminalStackKey.currentContext;
    if (context == null) return false;
    // If a dialog/overlay is on top (e.g., settings, capture dialog),
    // don't intercept shortcuts — let them reach the focused widget.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    return _handleSplitShortcut(context, event) == KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    widget.appState.addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
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
    _stageTabScrollController.dispose();
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
    if (!appState.sessions.contains(session)) return;
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
        const PopupMenuDivider(height: 1),
        compactMenuItem(
          value: _TerminalMenuAction.closeSession,
          label: l(appState, AppStrings.values.commandBarCloseSession),
          shortcut: appState.shortcutBindings
              .where((sb) => sb.id == 'closeSession')
              .firstOrNull
              ?.effectiveKeys,
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    if (!appState.sessions.contains(session)) {
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
          if (!appState.sessions.contains(session)) {
            return;
          }
          if (!confirmed) {
            return;
          }
          final payload = _prepareTerminalPastePayload(text);
          if (payload.isEmpty) {
            return;
          }
          session.lastUserInputTime = DateTime.now();
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
            final stage = appState.activeTerminalStageId.isEmpty || appState.terminalStages.isEmpty
                ? null
                : appState.terminalStages.firstWhere(
                    (s) => s.id == appState.activeTerminalStageId,
                    orElse: () => appState.terminalStages.first,
                  );
            final currentBgId = stage?.backgroundImageId ?? '';
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
                        color: AppColors.grey200,
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
                              Icons.broken_image, size: 14, color: AppColors.textTertiary,
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
        if (result != null && context.mounted && appState.activeTerminalStageId.isNotEmpty) {
          appState.setStageBackgroundImage(appState.activeTerminalStageId, result);
        }
        return;
      case _TerminalMenuAction.closeSession:
        appState.closeSession(session.id);
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
    final cached = _cachedPaneWidgets[session.id];
    if (cached != null) {
      return cached;
    }
    final captureKey = GlobalKey();
    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final pane = _TerminalPane(
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
      onSplitShortcut: (event) => _handleSplitShortcut(context, event),
      onShowMenu: (position) => _showTerminalMenu(
        context: context,
        appState: appState,
        paneId: paneId,
        session: session,
        controller: _controllerForSession(session),
        position: position,
      ),
      captureKey: captureKey,
    );

    // On mobile, let TerminalView handle gestures and focus internally.
    // On desktop, wrap with Listener for right-click menu and focus.
    Widget result;
    if (isMobile) {
      result = pane;
    } else {
      result = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            _showTerminalMenu(
              context: context,
              appState: appState,
              paneId: paneId,
              session: session,
              controller: _controllerForSession(session),
              position: event.position,
            );
          } else {
            final fn = _focusNodeForSession(session);
            if (!fn.hasFocus) fn.requestFocus();
          }
        },
        child: pane,
      );
    }
    _cachedPaneWidgets[session.id] = result;
    return result;
  }

  KeyEventResult _handleSplitShortcut(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final appState = widget.appState;

    final customNewSession = _checkCustomShortcut(appState, event, 'newSession');
    if (customNewSession != null) {
      showHostDialog(context, appState);
      return KeyEventResult.handled;
    }
    final customQuickConnect = _checkCustomShortcut(appState, event, 'quickConnect');
    if (customQuickConnect != null) {
      showQuickConnectDialog(context, appState);
      return KeyEventResult.handled;
    }
    final customCloseSession = _checkCustomShortcut(appState, event, 'closeSession');
    if (customCloseSession != null) {
      final session = appState.activeSession;
      if (session != null) {
        appState.closeSession(session.id);
        return KeyEventResult.handled;
      }
    }
    final customCloseAll = _checkCustomShortcut(appState, event, 'closeAllSessions');
    if (customCloseAll != null) {
      final sessionIds = appState.sessions.map((s) => s.id).toList();
      for (final id in sessionIds) {
        appState.closeSession(id);
      }
      return KeyEventResult.handled;
    }
    final customSettings = _checkCustomShortcut(appState, event, 'openSettings');
    if (customSettings != null) {
      showSettingsDialog(context, appState);
      return KeyEventResult.handled;
    }

    final customPrevStage = _checkCustomShortcut(appState, event, 'previousStage');
    if (customPrevStage != null) {
      _switchToStage(appState, -1);
      return KeyEventResult.handled;
    }
    final customNextStage = _checkCustomShortcut(appState, event, 'nextStage');
    if (customNextStage != null) {
      _switchToStage(appState, 1);
      return KeyEventResult.handled;
    }

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
      if (_focusedStageId.isNotEmpty) {
        setState(() => _focusedStageId = '');
        _updateSessionBackgroundMode();
        return KeyEventResult.handled;
      }
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

    final broadcastMatch = _checkCustomShortcut(appState, event, 'splitBroadcast');
    if (broadcastMatch != null) {
      appState.toggleBroadcast();
      return KeyEventResult.handled;
    }

    if (!_splitEnabled) {
      final customSplitAction = _checkCustomShortcut(appState, event, 'splitMaximize');
      if (customSplitAction != null) return KeyEventResult.ignored;
    } else {
      final customMaximize = _checkCustomShortcut(appState, event, 'splitMaximize');
      if (customMaximize != null) {
        final paneId = appState.activeTerminalSplitPaneId;
        if (paneId.isNotEmpty) {
          appState.toggleMaximizedTerminalSplitPane(paneId);
          return KeyEventResult.handled;
        }
      }
    }

    final customNewScript = _checkCustomShortcut(appState, event, 'newScript');
    if (customNewScript != null) {
      showScriptEditorDialog(context, appState);
      return KeyEventResult.handled;
    }
    final customRunScript = _checkCustomShortcut(appState, event, 'runScript');
    if (customRunScript != null) {
      appState.showScriptMonitorInline = false;
      showScriptsPanelDialog(context, appState);
      return KeyEventResult.handled;
    }
    final customScriptList = _checkCustomShortcut(appState, event, 'scriptList');
    if (customScriptList != null) {
      appState.showScriptMonitorInline = false;
      showScriptsPanelDialog(context, appState);
      return KeyEventResult.handled;
    }
    final customScriptMonitor = _checkCustomShortcut(appState, event, 'scriptMonitor');
    if (customScriptMonitor != null) {
      appState.showScriptMonitorInline = true;
      showScriptsPanelDialog(context, appState);
      return KeyEventResult.handled;
    }
    final customTransfer = _checkCustomShortcut(appState, event, 'transferManager');
    if (customTransfer != null) {
      TransferModalPanel.show(context);
      return KeyEventResult.handled;
    }
    final customPortFwd = _checkCustomShortcut(appState, event, 'portForwarding');
    if (customPortFwd != null) {
      PortForwardModalPanel.show(context);
      return KeyEventResult.handled;
    }
    final customLanScan = _checkCustomShortcut(appState, event, 'lanScan');
    if (customLanScan != null) {
      LanScanPanel.show(context);
      return KeyEventResult.handled;
    }

    final customLogViewer = _checkCustomShortcut(appState, event, 'logViewer');
    if (customLogViewer != null) {
      LogViewerModalPanel.show(context);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _requestSearchPane(
    TerminalAppState appState,
    String paneId,
    String sessionId,
  ) {
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


  void _updateSessionBackgroundMode() {
    final focused = _focusedStageId;
    final focusedStage = widget.appState.terminalStages
        .where((s) => s.id == focused)
        .firstOrNull;
    final focusedSessionIds = focusedStage?.sessionIds.toSet() ?? {};
    for (final s in widget.appState.sessions) {
      s.setBackgroundMode(!focusedSessionIds.contains(s.id));
    }
  }

  void _onStageTapFromGrid(String stageId) {
    widget.appState.switchTerminalStage(stageId);
    setState(() {
      _focusedStageId = stageId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateSessionBackgroundMode();
      _ensureSftpForFocusedStage();
    });
  }

  void _ensureSftpForFocusedStage() {
    final session = widget.appState.activeSession;
    if (session == null) return;
    if (!session.profile.isLocal && session.sftp != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.appState.ensureSftpReady(session));
    });
  }

  void _onStageSecondaryTapFromGrid(String stageId, TapDownDetails details) {
    final stage = widget.appState.terminalStages.firstWhere(
      (s) => s.id == stageId,
      orElse: () => widget.appState.terminalStages.first,
    );
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    final session = stage.sessionIds
        .map((sid) => widget.appState.terminalSessionById(sid))
        .whereType<TerminalSession>()
        .firstOrNull;

    showStageCardContextMenu(
      context: context,
      appState: widget.appState,
      stage: stage,
      position: position,
      includeBackground: true,
      onBackgroundTap: () =>
          showStageBackgroundPicker(context, widget.appState, stage),
      onEditSession: session != null
          ? () => showHostDialog(context, widget.appState, host: session.profile)
          : null,
      editSessionLabel: l(widget.appState, AppStrings.values.editSession),
      selectBackgroundLabel:
          l(widget.appState, AppStrings.values.selectBackground),
      renameLabel: l(widget.appState, AppStrings.values.renameStage),
      renameTitle: l(widget.appState, AppStrings.values.renameStageTitle),
      renameConfirm: l(widget.appState, AppStrings.values.rename),
      renameCancel: l(widget.appState, AppStrings.values.cancel),
      closeSessionLabel:
          l(widget.appState, AppStrings.values.commandBarCloseSession),
      deleteLabel: l(widget.appState, AppStrings.values.deleteStage),
      deleteTitle: l(widget.appState, AppStrings.values.deleteStage),
      deleteMessage: l(widget.appState, AppStrings.values.deleteVar),
      deleteConfirm: l(widget.appState, AppStrings.values.delete),
      deleteCancel: l(widget.appState, AppStrings.values.cancel),
    );
  }

  void _showCreateStageDialog(BuildContext context) {
    final appState = widget.appState;
    showInputDialog(
      context,
      title: l(appState, AppStrings.values.createStageTitle),
      hint: l(appState, AppStrings.values.enterStageName),
      initialValue: 'Stage ${appState.terminalStages.length + 1}',
      confirmText: l(appState, AppStrings.values.create),
      cancelText: l(appState, AppStrings.values.cancel),
    ).then((name) {
      if (name != null && name.trim().isNotEmpty) {
        appState.createTerminalStage(name.trim());
      }
    });
  }

  void _showGridMenu(BuildContext context) {
    final appState = widget.appState;
    String? shortcut(String id) {
      final idx = appState.shortcutBindings.indexWhere((s) => s.id == id);
      if (idx < 0) return null;
      final keys = appState.shortcutBindings[idx].effectiveKeys;
      return keys.isEmpty ? null : keys;
    }

    final categories = [
      MenuCategoryData(
        'sessions',
        Icons.terminal,
        l(appState, AppStrings.values.commandBarSessions),
        [
          MenuItemData('new_session', Icons.add,
              l(appState, AppStrings.values.commandBarNewSession),
              shortcut: shortcut('newSession')),
          MenuItemData('quick_connect', Icons.flash_on,
              l(appState, AppStrings.values.commandBarQuickConnect),
              shortcut: shortcut('quickConnect')),
          MenuItemData('close_all', Icons.highlight_off,
              l(appState, AppStrings.values.commandBarCloseAllSessions),
              shortcut: shortcut('closeAllSessions')),
        ],
      ),
      MenuCategoryData(
        'scripts',
        Icons.code,
        l(appState, AppStrings.values.commandBarScripts),
        [
          MenuItemData('new_script', Icons.add,
              l(appState, AppStrings.values.commandBarNewScript),
              shortcut: shortcut('newScript')),
          MenuItemData('script_list', Icons.list,
              l(appState, AppStrings.values.commandBarScriptList),
              shortcut: shortcut('scriptList')),
          MenuItemData('script_monitor', Icons.monitor_heart,
              l(appState, AppStrings.values.commandBarScriptMonitor),
              shortcut: shortcut('scriptMonitor')),
        ],
      ),
      MenuCategoryData(
        'files',
        Icons.folder,
        l(appState, AppStrings.values.commandBarTransfer),
        [
          MenuItemData('transfer_manager', Icons.compare_arrows,
              l(appState, AppStrings.values.commandBarTransferManager),
              shortcut: shortcut('transferManager')),
        ],
      ),
      MenuCategoryData(
        'tools',
        Icons.build,
        l(appState, AppStrings.values.commandBarTools),
        [
          MenuItemData('port_forwarding', Icons.route,
              l(appState, AppStrings.values.settingsPortForwarding),
              shortcut: shortcut('portForwarding')),
          MenuItemData('lan_scan', Icons.wifi_find,
              l(appState, AppStrings.values.lanScan),
              shortcut: shortcut('lanScan')),
        ],
      ),
      MenuCategoryData(
        'settings',
        Icons.settings,
        l(appState, AppStrings.values.commandBarSettings),
        [
          MenuItemData('open_settings', Icons.settings,
              l(appState, AppStrings.values.commandBarSettings),
              shortcut: shortcut('openSettings')),
        ],
      ),
    ];
    CascadingMenuOverlay.show(context, categories, (cmd) {
      executeTerminalCommand(context, appState, cmd);
    });
  }

  Widget _buildGridHeader(BuildContext context, TerminalAppState appState) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('stage_menu_btn'),
            iconSize: 20,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.menu, color: AppColors.textSecondary),
            onPressed: () => _showGridMenu(context),
            tooltip: l(appState, AppStrings.values.commandBarMore),
          ),
          Container(width: 1, height: 20, color: AppColors.border),
          const SizedBox(width: 10),
          Icon(Icons.dashboard, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Text(
            l(appState, AppStrings.values.stageOverview),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${appState.terminalStages.length}',
              style: AppTextStyles.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  void _switchToStage(TerminalAppState appState, int direction) {
    final stages = appState.terminalStages;
    if (stages.length < 2) return;
    final idx = stages.indexWhere((s) => s.id == _focusedStageId);
    if (idx < 0) return;
    final target = (idx + direction) % stages.length;
    final targetId = stages[target].id;
    appState.switchTerminalStage(targetId);
    setState(() => _focusedStageId = targetId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateSessionBackgroundMode();
      _ensureSftpForFocusedStage();
    });
  }

  static const double _stageTabWidth = 180;

  Widget _buildStageTabs(TerminalAppState appState) {
    final stages = appState.terminalStages;
    final currentId = _focusedStageId.isNotEmpty ? _focusedStageId : appState.activeTerminalStageId;
    if (currentId != _lastScrolledStageId) {
      _lastScrolledStageId = currentId;
      final currentIndex = stages.indexWhere((s) => s.id == currentId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || currentIndex < 0) return;
        final target = currentIndex * _stageTabWidth - _stageTabScrollController.position.viewportDimension / 2 + _stageTabWidth / 2;
        final clamped = target.clamp(0.0, _stageTabScrollController.position.maxScrollExtent);
        if (_stageTabScrollController.hasClients && _stageTabScrollController.offset != clamped) {
          _stageTabScrollController.animateTo(clamped, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
        }
      });
    }
    return SizedBox(
      height: 32,
      child: ListView.builder(
        controller: _stageTabScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: stages.length,
        itemExtent: _stageTabWidth,
        itemBuilder: (context, index) {
          final s = stages[index];
          final isActive = s.id == currentId;
          return GestureDetector(
            onTap: () {
              if (!isActive) {
                appState.switchTerminalStage(s.id);
                setState(() => _focusedStageId = s.id);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _updateSessionBackgroundMode();
                  _ensureSftpForFocusedStage();
                });
              }
            },
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                color: isActive ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? AppColors.accent : AppColors.border.withValues(alpha: 0.4),
                    width: isActive ? 2 : 1,
                  ),
                  right: index < stages.length - 1
                      ? BorderSide(color: AppColors.border.withValues(alpha: 0.3))
                      : BorderSide.none,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFocusedHeader(
      BuildContext context, TerminalAppState appState, TerminalSession? session) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: l(appState, AppStrings.values.back),
            waitDuration: const Duration(milliseconds: 250),
            child: SizedBox(
              width: 40,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  hoverColor: AppColors.grey100,
                  onTap: () {
                    setState(() => _focusedStageId = '');
                    _updateSessionBackgroundMode();
                  },
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(Icons.arrow_back_ios_new,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            iconSize: 20,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.menu, color: AppColors.textSecondary),
            onPressed: () => _showGridMenu(context),
            tooltip: l(appState, AppStrings.values.commandBarMore),
          ),
          Container(
              width: 1, height: 20, color: AppColors.border),
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: _buildStageTabs(appState),
          ),
          if (session != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: HeaderIconButton(
            icon: Icons.folder_open,
            iconSize: 16,
            isActive: _showFileTreePanel,
            activeColor: AppColors.accent,
            tooltip: l(appState, AppStrings.values.showFileTree),
            onPressed: () => setState(() => _showFileTreePanel = !_showFileTreePanel),
          ),
          ),
        ],
      ),
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
      // remove cached panes for disposed sessions
      final activeIds = sessions.map((s) => s.id).toSet();
      _cachedPaneWidgets.removeWhere((id, _) => !activeIds.contains(id));
    }

    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobile) {
      final session = appState.activeSession;
      _splitEnabled = appState.terminalSplitViewEnabled;

      Widget terminalContent;
      if (session == null) {
        terminalContent = Container(
          color: AppColors.terminalBackground,
          child: const SessionTreePanel(),
        );
      } else {
        final paneId = appState.terminalSplitPanes
                .where((p) => p.sessionId == session.id)
                .map((p) => p.id)
                .firstOrNull ??
            (appState.terminalSplitPanes.isNotEmpty
                ? appState.terminalSplitPanes.first.id
                : 'pane-0');
        terminalContent =
            _buildPane(context, appState, session, showTitle: false, paneId: paneId);
      }

      return Container(
        key: _terminalStackKey,
        color: AppColors.terminalBackground,
        child: MobileTerminalLayout(
          terminalContent: Container(
            key: ValueKey(appState.activeTerminalStageId),
            child: terminalContent,
          ),
        ),
      );
    }

    // Desktop: Grid overview
    if (_focusedStageId.isEmpty) {
      return Container(
        key: _terminalStackKey,
        child: Stack(
          children: [
            const Positioned.fill(child: BreatheGrid()),
            Container(
              color: AppColors.terminalTreeBackground.withValues(alpha: 0.85),
              child: Column(
                children: [
                  _buildGridHeader(context, appState),
                  Expanded(
                    child: GridStagePanel(
                      appState: appState,
                      onStageTap: _onStageTapFromGrid,
                      onStageSecondaryTap: _onStageSecondaryTapFromGrid,
                      onCreateStage: () => _showCreateStageDialog(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Desktop: Focused stage — verify stage still exists
    if (!appState.terminalStages.any((s) => s.id == _focusedStageId)) {
      _focusedStageId = '';
      _updateSessionBackgroundMode();
      return build(context);
    }

    if (appState.activeTerminalStageId != _focusedStageId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appState.switchTerminalStage(_focusedStageId);
      });
    }

    final session = appState.activeSession;
    _splitEnabled = appState.terminalSplitViewEnabled;

    Widget terminalContent;
    if (session == null) {
      terminalContent = Container(
        color: AppColors.terminalBackground,
        child: const SessionTreePanel(),
      );
    } else {
      final paneId = appState.terminalSplitPanes
              .where((p) => p.sessionId == session.id)
              .map((p) => p.id)
              .firstOrNull ??
          (appState.terminalSplitPanes.isNotEmpty
              ? appState.terminalSplitPanes.first.id
              : 'pane-0');
      terminalContent =
          _buildPane(context, appState, session, showTitle: false, paneId: paneId);
    }

    final showFileTree = _showFileTreePanel && session != null;
    final currentStage = appState.terminalStages.where(
      (s) => s.id == _focusedStageId,
    ).firstOrNull;
    if (currentStage != null && _fileTreeHeight != currentStage.fileTreeHeight) {
      _fileTreeHeight = currentStage.fileTreeHeight;
    }

    return Container(
      key: _terminalStackKey,
      color: AppColors.terminalBackground,
      child: Stack(
        children: [
          Column(
            children: [
              _buildFocusedHeader(context, appState, session),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: showFileTree ? _fileTreeHeight + 6 : 0,
                  ),
                  child: RepaintBoundary(child: terminalContent),
                ),
              ),
            ],
          ),
          if (showFileTree)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FileTreePanel(
                key: ValueKey('filetree_${session.id}'),
                appState: appState,
                session: session,
                initialHeight: _fileTreeHeight,
                onHeightChanged: (h) {
                  final needsRebuild = h != _fileTreeHeight;
                  if (needsRebuild) {
                    setState(() { _fileTreeHeight = h; });
                  }
                  final stageIdx = appState.terminalStages.indexWhere(
                    (s) => s.id == _focusedStageId,
                  );
                  if (stageIdx >= 0 &&
                      h != appState.terminalStages[stageIdx].fileTreeHeight) {
                    appState.terminalStages[stageIdx] =
                        appState.terminalStages[stageIdx].copyWith(
                      fileTreeHeight: h,
                    );
                    appState.scheduleStateSave();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FileTreeSelector {
  const _FileTreeSelector({
    required this.version,
    required this.showHiddenFiles,
    required this.transferVersion,
  });
  final int version;
  final bool showHiddenFiles;
  final int transferVersion;

  @override
  bool operator ==(Object other) =>
      other is _FileTreeSelector &&
      other.version == version &&
      other.showHiddenFiles == showHiddenFiles &&
      other.transferVersion == transferVersion;

  @override
  int get hashCode => Object.hash(version, showHiddenFiles, transferVersion);
}

class _FileTreePanel extends StatefulWidget {
  const _FileTreePanel({
    super.key,
    required this.appState,
    required this.session,
    required this.onHeightChanged,
    this.initialHeight = 220,
  });
  final TerminalAppState appState;
  final TerminalSession session;
  final ValueChanged<double> onHeightChanged;
  final double initialHeight;

  @override
  State<_FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<_FileTreePanel> {
  late double _height;
  static const double _minHeight = 100;
  static const double _maxHeight = 500;

  @override
  void initState() {
    super.initState();
    _height = widget.initialHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onHeightChanged(_height);
    });
  }

  @override
  void didUpdateWidget(_FileTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.id != oldWidget.session.id) {
      _height = widget.initialHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onHeightChanged(_height);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDivider(),
        SizedBox(
          height: _height,
          child: ClipRect(
            child: Container(
              color: Colors.white,
              child: RepaintBoundary(
                child: Selector<TerminalAppState, _FileTreeSelector>(
                  selector: (_, state) => _FileTreeSelector(
                    version: state.activeSession?.fileState.version ?? -1,
                    showHiddenFiles: state.showHiddenFiles,
                    transferVersion: state.activeSession?.transferVersion ?? -1,
                  ),
                  builder: (_, sel, __) => FileTree(
                    appState: widget.appState,
                    session: widget.session,
                    showHidden: sel.showHiddenFiles,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onPanUpdate: (details) {
          final newHeight = (_height - details.delta.dy)
              .clamp(_minHeight, _maxHeight);
          if (newHeight != _height) {
            setState(() { _height = newHeight; });
            widget.onHeightChanged(_height);
          }
        },
        child: Container(
          height: 6,
          color: AppColors.backgroundGrey,
          child: Center(
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
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
      color: AppColors.overlay,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.h5.copyWith(color: AppColors.terminalForeground),
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


