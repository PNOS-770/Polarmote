import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/design_system/design_system.dart';
import '../state/terminal_app_state.dart';
import 'common/shortcut_key_names.dart';
import 'common/terminal_localization.dart';
import 'dialogs/terminal_dialogs.dart';
import 'panels/terminal_main_panel.dart';

class TerminalHomePage extends StatefulWidget {
  const TerminalHomePage({super.key});

  @override
  State<TerminalHomePage> createState() => _TerminalHomePageState();
}

class _TerminalHomePageState extends State<TerminalHomePage> {
  final _globalFocusNode = FocusNode();

  void _switchStage(TerminalAppState appState, int direction) {
    final stages = appState.terminalStages;
    if (stages.length < 2) return;
    final currentId = appState.activeTerminalStageId;
    final idx = stages.indexWhere((s) => s.id == currentId);
    if (idx < 0) return;
    final target = (idx + direction) % stages.length;
    appState.switchTerminalStage(stages[target].id);
    appState.notifyState();
  }

  KeyEventResult _handleKeyEvent(TerminalAppState appState, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    for (final sb in appState.shortcutBindings) {
      if (sb.id != 'previousStage' && sb.id != 'nextStage') continue;
      final keys = sb.customKeys ?? sb.defaultKeys;
      for (final alt in keys.split(' / ')) {
        if (_matchShortcut(event, alt.trim())) {
          _switchStage(appState, sb.id == 'previousStage' ? -1 : 1);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  bool _matchShortcut(KeyEvent event, String combo) {
    final parts = combo.split('+').map((p) => p.trim()).toList();
    LogicalKeyboardKey? targetKey;
    var wantCtrl = false, wantAlt = false, wantShift = false, wantMeta = false;
    for (final part in parts) {
      switch (part) {
        case 'Ctrl': wantCtrl = true;
        case 'Alt': wantAlt = true;
        case 'Shift': wantShift = true;
        case 'Meta': wantMeta = true;
        default: targetKey = parseShortcutKeyName(part);
      }
    }
    if (targetKey == null || event.logicalKey != targetKey) return false;
    final kb = HardwareKeyboard.instance;
    return kb.isControlPressed == wantCtrl &&
        kb.isAltPressed == wantAlt &&
        kb.isShiftPressed == wantShift &&
        kb.isMetaPressed == wantMeta;
  }

  @override
  void dispose() {
    _globalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.terminalBackground,
      body: Consumer<TerminalAppState>(
        builder: (context, state, child) {
          if (state.lastError != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showErrorIfNeeded(context, state);
            });
          }
          if (state.hostKeyPromptToken > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showHostKeyPromptIfNeeded(context, state);
            });
          }

          return Focus(
            focusNode: _globalFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) => _handleKeyEvent(state, event),
            child: const MainPanel(),
          );
        },
      ),
    );
  }
}

