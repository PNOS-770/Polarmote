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
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import '../../../../shared/design_system/design_system.dart';
import '../stage_manager/stage_manager_sidebar.dart';
import '../session_tree/session_tree_panel.dart';
import '../mobile/mobile_terminal_layout.dart';
import '../dialogs/terminal_dialogs.dart';
import '../modal_panels/file_tree_modal_panel.dart';
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
            statuses: sessions
                .map((s) => s.tab.status.index)
                .toList(growable: false),
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
    required this.statuses,
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
  });

  final int activeIndex;
  final List<String> sessionIds;
  final List<int> statuses;
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
        listEquals(other.statuses, statuses) &&
        other.emptyPaneTreeKey == emptyPaneTreeKey &&
        other.stageManagerEnabled == stageManagerEnabled &&
        other.stageCount == stageCount &&
        other.activeStageId == activeStageId &&
        other.stageChangeToken == stageChangeToken &&
        other.showThumbnailBackground == showThumbnailBackground &&
        other.selectedHostIdsHash == selectedHostIdsHash;
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
    Object.hashAll(statuses),
    emptyPaneTreeKey,
    stageManagerEnabled,
    stageCount,
    activeStageId,
    stageChangeToken,
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

class _SplitPaneSlot {
  const _SplitPaneSlot({required this.pane, required this.session});
  final TerminalSplitPaneConfig pane;
  final TerminalSession? session;
}

enum _TerminalMenuAction { copy, paste, selectAll, openUrl, toggleBlockSelect, selectBackground }

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

  bool _splitEnabled = false;
  int _lastSessionCount = -1;

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
  }

  @override
  void dispose() {
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
    }
  }

  Widget _buildPane(
    BuildContext context,
    TerminalAppState appState,
    TerminalSession session, {
    required bool showTitle,
    required String paneId,
  }) {
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
    if (isMobile) return pane;

    return Listener(
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
          _focusNodeForSession(session).requestFocus();
        }
      },
      child: pane,
    );
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

    final broadcastMatch = _checkCustomShortcut(appState, event, 'splitBroadcast');
    if (broadcastMatch != null) {
      appState.toggleBroadcast();
      return KeyEventResult.handled;
    }

    if (!_splitEnabled) {
      final customSplitAction = _checkCustomShortcut(appState, event, 'splitMaximize') ??
          _checkCustomShortcut(appState, event, 'splitPrev') ??
          _checkCustomShortcut(appState, event, 'splitNext');
      if (customSplitAction != null) return KeyEventResult.ignored;
      // Continue checking non-split shortcuts below
    } else {
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
    final customSftp = _checkCustomShortcut(appState, event, 'sftpBrowser');
    if (customSftp != null) {
      FileTreeModalPanel.show(context);
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

  KeyEventResult _navigateSplitPane(TerminalAppState appState, int direction) {
    final slots = _splitSlots(appState);
    if (slots.isEmpty) return KeyEventResult.ignored;
    final currentIndex = slots.indexWhere(
      (slot) => slot.pane.id == appState.activeTerminalSplitPaneId,
    );
    final index = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (index + direction + slots.length) % slots.length;
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

    Widget terminalContent;
    // 始终使用 Stage 模式渲染终端，侧边栏只控制可见性
    if (session == null) {
      terminalContent = Container(
        color: AppColors.terminalBackground,
        child: const SessionTreePanel(),
      );
    } else {
      final paneId = appState.terminalSplitPanes
          .where((p) => p.sessionId == session.id)
          .map((p) => p.id)
          .firstOrNull
          ?? (appState.terminalSplitPanes.isNotEmpty
              ? appState.terminalSplitPanes.first.id
              : 'pane-0');
      terminalContent = _buildPane(context, appState, session, showTitle: false, paneId: paneId);
    }

    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile) {
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

    return Container(
      key: _terminalStackKey,
      color: AppColors.terminalBackground,
      child: Row(
        children: [
          if (appState.stageManagerEnabled)
            StageManagerSidebar(
              appState: appState,
              onStageClick: (stageId) {
                appState.switchTerminalStage(stageId);
              },
              onStageShiftClick: (stageId) {
                // Shift+Click: 不再需要，一个 Stage 只对应一个会话
              },
            )
          else
            GestureDetector(
              onTap: () => appState.toggleStageManager(),
              child: Container(
                width: 10,
                color: AppColors.terminalBackground,
                child: Center(
                  child: Icon(Icons.chevron_right, size: 14, color: AppColors.textSecondary),
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: Container(
                key: ValueKey(appState.activeTerminalStageId),
                child: terminalContent,
              ),
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





