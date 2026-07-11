part of 'terminal_dialogs.dart';

mixin _ShortcutsTabMixin on State<TerminalSettingsPanel> {
  String? _editingScriptShortcutKey;
  final FocusNode _scriptCaptureFocus = FocusNode();
  bool _conflictsAutoResolved = false;
  String? _scrollToBindingId;
  static const Map<String, String> _shortcutBindingGroup = {
    'copy': 'clipboard',
    'paste': 'clipboard',
    'selectAll': 'clipboard',
    'search': 'search',
    'blockSelect': 'selection',
    'splitMaximize': 'panes',
    'splitBroadcast': 'panes',
    'newSession': 'sessions',
    'quickConnect': 'sessions',
    'closeSession': 'sessions',
    'closeAllSessions': 'sessions',
    'newScript': 'scripts',
    'runScript': 'scripts',
    'scriptList': 'scripts',
    'scriptMonitor': 'scripts',
    'transferManager': 'files',
    'portForwarding': 'tools',
    'lanScan': 'tools',
    'logViewer': 'tools',
    'openSettings': 'settings',
    'previousStage': 'sessions',
    'nextStage': 'sessions',
  };

  String _shortcutGroupLabel(String key) {
    return switch (key) {
      'clipboard' => t(context, AppStrings.values.shortcutGroupClipboard),
      'search' => t(context, AppStrings.values.shortcutGroupSearch),
      'panes' => t(context, AppStrings.values.shortcutGroupPanes),
      'selection' => t(context, AppStrings.values.shortcutGroupSelection),
      'sessions' => t(context, AppStrings.values.shortcutGroupSessions),
      'scripts' => t(context, AppStrings.values.shortcutGroupScripts),
      'files' => t(context, AppStrings.values.shortcutGroupFiles),
      'tools' => t(context, AppStrings.values.shortcutGroupTools),
      'settings' => t(context, AppStrings.values.shortcutGroupSettings),
      _ => key,
    };
  }

  Widget _buildShortcutsTab(TerminalAppState appState) {
    if (_conflictingIds(appState).isNotEmpty && !_conflictsAutoResolved) {
      _conflictsAutoResolved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoResolveConflicts(appState);
      });
    }

    final bindings = appState.shortcutBindings.toList();
    final conflictingIds = _conflictingIds(appState);
    final hasConflicts = conflictingIds.isNotEmpty;

    final grouped = <String, List<ShortcutBinding>>{};
    for (final sb in bindings) {
      final group = _shortcutBindingGroup[sb.id] ?? 'clipboard';
      grouped.putIfAbsent(group, () => []).add(sb);
    }

    final groupOrder = ['clipboard', 'search', 'panes', 'selection', 'sessions', 'scripts', 'files', 'tools', 'settings'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasConflicts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: TerminalUiPalette.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TerminalUiPalette.warning),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: TerminalUiPalette.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(context, AppStrings.values.shortcutConflictBanner),
                      style: const TextStyle(fontSize: 12, color: TerminalUiPalette.warning),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_conflictsAutoResolved)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: TerminalUiPalette.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TerminalUiPalette.accent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 16, color: TerminalUiPalette.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(context, AppStrings.values.shortcutConflictResolved),
                      style: const TextStyle(fontSize: 12, color: TerminalUiPalette.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ...groupOrder.where((g) => grouped.containsKey(g)).expand((g) {
          final items = grouped[g]!;
          return [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                _shortcutGroupLabel(g),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: TerminalUiPalette.textSecondary),
              ),
            ),
            ...items.map((sb) => _buildShortcutRow(appState, sb, conflictingIds)),
          ];
        }),
        const SizedBox(height: 16),
        _SectionTitle(label: t(context, AppStrings.values.scriptShortcuts)),
        const SizedBox(height: 4),
        _buildScriptShortcutsSection(appState),
      ],
    );
  }

  Widget _buildScriptShortcutsSection(TerminalAppState appState) {
    final scriptBindings = appState.scriptShortcutBindings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final scriptsById = {
      for (final script in appState.scripts) script.id: script,
    };
    final conflictingScriptKeys = _conflictingScriptKeys(appState);
    if (scriptBindings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          t(context, AppStrings.values.noScriptShortcuts),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }
    return Column(
      children: scriptBindings.map((entry) {
        final script = scriptsById[entry.value];
        final name = script?.name ?? entry.value;
        final isEditing = _editingScriptShortcutKey == entry.key;
        final hasConflict = conflictingScriptKeys.contains(entry.key);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasConflict
                  ? TerminalUiPalette.error
                  : isEditing
                      ? TerminalUiPalette.accent
                      : TerminalUiPalette.border,
            ),
            color: TerminalUiPalette.pageBackground,
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (hasConflict) ...[
                      const Icon(Icons.warning_amber_rounded, size: 14, color: TerminalUiPalette.error),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isEditing)
                _buildScriptCaptureWidget(appState, entry)
              else
                GestureDetector(
                  onTap: () => setState(() => _editingScriptShortcutKey = entry.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasConflict
                          ? TerminalUiPalette.error.withValues(alpha: 0.15)
                          : TerminalUiPalette.cardBackground,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasConflict ? TerminalUiPalette.error : TerminalUiPalette.accent,
                      ),
                    ),
                  ),
                ),
              if (!isEditing) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    appState.scriptShortcutBindings.remove(entry.key);
                    appState.scheduleStateSave();
                    appState.notifyState();
                  },
                  child: const Icon(Icons.close, size: 16, color: TerminalUiPalette.textSecondary),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScriptCaptureWidget(TerminalAppState appState, MapEntry<String, String> entry) {
    return Focus(
      focusNode: _scriptCaptureFocus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.escape) {
          setState(() => _editingScriptShortcutKey = null);
          return KeyEventResult.handled;
        }
        final isModifier = key == LogicalKeyboardKey.controlLeft ||
            key == LogicalKeyboardKey.controlRight ||
            key == LogicalKeyboardKey.shiftLeft ||
            key == LogicalKeyboardKey.shiftRight ||
            key == LogicalKeyboardKey.altLeft ||
            key == LogicalKeyboardKey.altRight ||
            key == LogicalKeyboardKey.metaLeft ||
            key == LogicalKeyboardKey.metaRight;
        if (!isModifier) {
          final parts = <String>[];
          final kb = HardwareKeyboard.instance;
          if (kb.isControlPressed) parts.add('Ctrl');
          if (kb.isAltPressed) parts.add('Alt');
          if (kb.isShiftPressed) parts.add('Shift');
          if (kb.isMetaPressed) parts.add('Meta');
          parts.add(shortcutKeyName(key) ?? '');
          final captured = parts.join('+');
          appState.scriptShortcutBindings.remove(entry.key);
          appState.scriptShortcutBindings[captured] = entry.value;
          appState.shortcutConflictToken++;
          appState.scheduleStateSave();
          appState.notifyState();
          setState(() => _editingScriptShortcutKey = null);
        }
        return KeyEventResult.handled;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: TerminalUiPalette.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: TerminalUiPalette.accent),
        ),
        child: Text(
          t(context, AppStrings.values.pressNewShortcut),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TerminalUiPalette.accent),
        ),
      ),
    );
  }

  String _shortcutName(ShortcutBinding sb) {
    return switch (sb.id) {
      'copy' => t(context, AppStrings.values.shortcutCopy),
      'paste' => t(context, AppStrings.values.shortcutPaste),
      'selectAll' => t(context, AppStrings.values.shortcutSelectAll),
      'search' => t(context, AppStrings.values.shortcutFind),
      'blockSelect' => t(context, AppStrings.values.shortcutBlockSelect),
      'splitMaximize' => t(context, AppStrings.values.shortcutSplitMaximize),
      'splitBroadcast' => t(context, AppStrings.values.shortcutSplitBroadcast),
      'newSession' => t(context, AppStrings.values.shortcutNewSession),
      'quickConnect' => t(context, AppStrings.values.shortcutQuickConnect),
      'closeSession' => t(context, AppStrings.values.shortcutCloseSession),
      'closeAllSessions' => t(context, AppStrings.values.shortcutCloseAllSessions),
      'newScript' => t(context, AppStrings.values.shortcutNewScript),
      'runScript' => t(context, AppStrings.values.shortcutRunScript),
      'scriptList' => t(context, AppStrings.values.shortcutScriptList),
      'scriptMonitor' => t(context, AppStrings.values.shortcutScriptMonitor),
      'transferManager' => t(context, AppStrings.values.shortcutTransferManager),
      'portForwarding' => t(context, AppStrings.values.shortcutPortForwarding),
      'lanScan' => t(context, AppStrings.values.shortcutLanScan),
      'logViewer' => t(context, AppStrings.values.shortcutLogViewer),
      'openSettings' => t(context, AppStrings.values.shortcutOpenSettings),
      'previousStage' => t(context, AppStrings.values.shortcutPreviousStage),
      'nextStage' => t(context, AppStrings.values.shortcutNextStage),
      _ => sb.name,
    };
  }

  Set<String> _conflictingIds(TerminalAppState appState) {
    final conflictIds = <String>{};
    final usedKeys = <String, String>{};
    for (final sb in appState.shortcutBindings) {
      final keys = sb.effectiveKeys;
      if (keys.isEmpty) continue;
      for (final alt in keys.split(' / ')) {
        final trimmed = alt.trim();
        if (trimmed.isEmpty) continue;
        if (usedKeys.containsKey(trimmed)) {
          conflictIds.add(sb.id);
          conflictIds.add(usedKeys[trimmed]!);
        } else {
          usedKeys[trimmed] = sb.id;
        }
      }
    }
    for (final entry in appState.scriptShortcutBindings.entries) {
      for (final alt in entry.key.split(' / ')) {
        final trimmed = alt.trim();
        if (trimmed.isEmpty) continue;
        if (usedKeys.containsKey(trimmed)) {
          conflictIds.add(usedKeys[trimmed]!);
        }
      }
    }
    return conflictIds;
  }

  Set<String> _conflictingScriptKeys(TerminalAppState appState) {
    final usedKeys = <String>{};
    final conflictKeys = <String>{};
    for (final sb in appState.shortcutBindings) {
      final keys = sb.effectiveKeys;
      if (keys.isEmpty) continue;
      for (final alt in keys.split(' / ')) {
        final trimmed = alt.trim();
        if (trimmed.isNotEmpty) {
          usedKeys.add(trimmed);
        }
      }
    }
    for (final entry in appState.scriptShortcutBindings.entries) {
      for (final alt in entry.key.split(' / ')) {
        final trimmed = alt.trim();
        if (trimmed.isNotEmpty && usedKeys.contains(trimmed)) {
          conflictKeys.add(entry.key);
        }
      }
    }
    return conflictKeys;
  }

  ShortcutBinding? _findConflictingBinding(TerminalAppState appState, String excludeId, String key) {
    for (final sb in appState.shortcutBindings) {
      if (sb.id == excludeId) continue;
      for (final alt in sb.effectiveKeys.split(' / ')) {
        if (alt.trim() == key) return sb;
      }
    }
    return null;
  }

  Widget _buildShortcutRow(TerminalAppState appState, ShortcutBinding sb, Set<String> conflictingIds) {
    final isCustom = sb.isCustomized;
    final hasConflict = conflictingIds.contains(sb.id);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasConflict
              ? TerminalUiPalette.error
              : isCustom
                  ? TerminalUiPalette.accent
                  : TerminalUiPalette.border,
        ),
        color: TerminalUiPalette.pageBackground,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (hasConflict) ...[
                  const Icon(Icons.warning_amber_rounded, size: 14, color: TerminalUiPalette.error),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    _shortcutName(sb),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasConflict
                    ? TerminalUiPalette.error.withValues(alpha: 0.15)
                    : isCustom
                        ? TerminalUiPalette.accent.withValues(alpha: 0.15)
                        : TerminalUiPalette.cardBackground,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                sb.effectiveKeys,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasConflict ? TerminalUiPalette.error : isCustom ? TerminalUiPalette.accent : TerminalUiPalette.textPrimary,
                ),
              ),
            ),
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final idx = appState.shortcutBindings.indexWhere((s) => s.id == sb.id);
                if (idx >= 0) {
                  appState.shortcutBindings[idx] = sb.copyWith(customKeys: null);
                  appState.scheduleStateSave();
                  appState.notifyState();
                }
              },
              child: const Icon(Icons.restore, size: 16, color: TerminalUiPalette.warning),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showShortcutEditDialog(appState, sb),
            child: const Icon(Icons.edit, size: 16, color: TerminalUiPalette.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _showShortcutEditDialog(TerminalAppState appState, ShortcutBinding sb) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _ShortcutCaptureDialog(
        title: '${t(context, AppStrings.values.editShortcut)}: ${_shortcutName(sb)}',
        currentKeys: sb.effectiveKeys,
      ),
    );
    if (result == null || !mounted) return;
    final idx = appState.shortcutBindings.indexWhere((s) => s.id == sb.id);
    if (idx < 0) return;

    if (result.isNotEmpty) {
      final conflict = _findConflictingBinding(appState, sb.id, result);
      if (conflict != null) {
        final conflictName = _shortcutName(conflict);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusDialog),
            title: Text(t(context, AppStrings.values.shortcutConflictTitle), style: AppTextStyles.h4),
            content: Text(
              AppStrings.values.shortcutAlreadyUsed.resolve(
                Localizations.localeOf(context).languageCode,
                params: {
                  'key': result,
                  'action': conflictName,
                },
              ),
            ),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(ctx, false),
                label: t(context, AppStrings.values.cancel),
                size: ButtonSize.small,
              ),
              PrimaryButton(
                onPressed: () => Navigator.pop(ctx, true),
                label: AppStrings.values.navigateToAction.resolve(
                  Localizations.localeOf(context).languageCode,
                  params: {'action': conflictName},
                ),
                size: ButtonSize.small,
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;

        if (conflict.customKeys != null) {
          final conflictIdx = appState.shortcutBindings.indexWhere((s) => s.id == conflict.id);
          if (conflictIdx >= 0) {
            appState.shortcutBindings[conflictIdx] = conflict.copyWith(customKeys: null);
          }
        }
        _scrollToBindingId = conflict.id;
      }
    }

    if (result.isEmpty) {
      appState.shortcutBindings[idx] = sb.copyWith(customKeys: null);
    } else {
      appState.shortcutBindings[idx] = sb.copyWith(customKeys: result);
    }
    appState.shortcutConflictToken++;
    appState.scheduleStateSave();
    appState.notifyState();
  }

  void _scrollToBinding(TerminalAppState appState, ScrollController scrollController) {
    final id = _scrollToBindingId;
    if (id == null) return;
    _scrollToBindingId = null;

    final groupOrder = ['clipboard', 'search', 'panes', 'selection', 'sessions', 'scripts', 'files', 'tools', 'settings'];
    double offset = 0;
    for (final group in groupOrder) {
      final groupBindings = appState.shortcutBindings
          .where((sb) => _shortcutBindingGroup[sb.id] == group).toList();
      if (groupBindings.isEmpty) continue;
      offset += 30;
      for (final sb in groupBindings) {
        if (sb.id == id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            scrollController.animateTo(
              offset.clamp(0, scrollController.position.maxScrollExtent),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          });
          return;
        }
        offset += 56;
      }
    }
  }

  void _autoResolveConflicts(TerminalAppState appState) {
    int resolved = 0;
    for (int i = 0; i < appState.shortcutBindings.length; i++) {
      final sb = appState.shortcutBindings[i];
      if (sb.customKeys == null) continue;
      for (final other in appState.shortcutBindings) {
        if (other.id == sb.id) continue;
        if (other.effectiveKeys == sb.customKeys) {
          appState.shortcutBindings[i] = sb.copyWith(customKeys: null);
          resolved++;
          break;
        }
      }
    }
    if (resolved > 0) {
      appState.shortcutConflictToken++;
      appState.scheduleStateSave();
      appState.notifyState();
    }
  }

  void disposeShortcutsFocus() {
    _scriptCaptureFocus.dispose();
  }
}

