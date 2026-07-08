part of '../terminal_home_panels.dart';

const int _maxBatchConcurrency = 10;

String _stripAnsi(String text) {
  return text.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
}

enum _ScriptFolderAction { newScript, edit, delete }

class _ScriptTreeBuildResult {
  const _ScriptTreeBuildResult({required this.widgets, required this.hasMatch});

  final List<Widget> widgets;
  final bool hasMatch;
}

class _ScriptsPanel extends StatefulWidget {
  const _ScriptsPanel({required this.appState, required this.isCompact});

  final TerminalAppState appState;
  final bool isCompact;

  @override
  State<_ScriptsPanel> createState() => _ScriptsPanelState();
}

class _ScriptsPanelState extends State<_ScriptsPanel> {
  String _scriptKeyword = '';
  String _selectedScriptFolderId = '';
  final Set<String> _expandedScriptFolderIds = <String>{};
  final Set<String> _expandedMonitorTargets = <String>{};
  String? _copyFeedbackKey;
  Timer? _copyFeedbackTimer;
  final Set<String> _selectedScriptIds = <String>{};
  bool _selectionMode = false;
  int _lastMultiSelectToken = 0;
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'scripts-shortcuts',
  );
  bool _registeredShortcutHandler = false;

  String _scriptSearchHint(TerminalAppState appState) {
    return l(appState, AppStrings.values.searchScriptName);
  }

  @override
  void initState() {
    super.initState();
    _registerGlobalShortcutHandler();
  }

  void _registerGlobalShortcutHandler() {
    if (_registeredShortcutHandler) return;
    HardwareKeyboard.instance.addHandler(_handleGlobalShortcut);
    _registeredShortcutHandler = true;
  }

  void _unregisterGlobalShortcutHandler() {
    if (!_registeredShortcutHandler) return;
    HardwareKeyboard.instance.removeHandler(_handleGlobalShortcut);
    _registeredShortcutHandler = false;
  }

  bool _handleGlobalShortcut(KeyEvent event) {
    final appState = widget.appState;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }
    final shortcut = _formatShortcut(event, appState);
    if (shortcut == null) {
      return false;
    }
    final scriptId = appState.scriptIdForShortcut(shortcut);
    if (scriptId == null) {
      return false;
    }
    final script = appState.findScriptById(scriptId);
    if (script == null) {
      return false;
    }
    unawaited(_runScriptByShortcut(context, appState, script));
    return true;
  }

  @override
  void dispose() {
    _unregisterGlobalShortcutHandler();
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  bool _scriptInFolder(
    ScriptEntry script,
    String selectedFolderId,
    Map<String, ScriptFolderEntry> foldersById,
  ) {
    final target = selectedFolderId.trim();
    if (target.isEmpty) {
      return true;
    }
    var cursor = script.folderId.trim();
    if (cursor.isEmpty) {
      return false;
    }
    final visited = <String>{};
    while (cursor.isNotEmpty && visited.add(cursor)) {
      if (cursor == target) {
        return true;
      }
      cursor = foldersById[cursor]?.parentId.trim() ?? '';
    }
    return false;
  }

  List<ScriptEntry> _filteredScripts(
    List<ScriptEntry> source, {
    required String keyword,
    required String selectedFolderId,
    required Map<String, ScriptFolderEntry> foldersById,
  }) {
    return source
        .where((script) {
          if (!_scriptInFolder(script, selectedFolderId, foldersById)) {
            return false;
          }
          if (keyword.isEmpty) {
            return true;
          }
          return script.name.toLowerCase().contains(keyword);
        })
        .toList(growable: false);
  }

  List<PopupMenuEntry<_ScriptItemAction>> _scriptMenuItems(
    BuildContext context,
    TerminalAppState appState,
    ScriptEntry script,
  ) {
    final shortcut = appState.shortcutForScript(script.id);
    return [
      compactMenuItem(
        value: _ScriptItemAction.run,
        label: l(appState, AppStrings.values.run),
      ),
      compactMenuItem(
        value: _ScriptItemAction.edit,
        label: t(context, AppStrings.values.edit),
      ),
      compactMenuItem(
        value: _ScriptItemAction.bindShortcut,
        label: l(appState, AppStrings.values.bindShortcut),
      ),
      if (shortcut != null)
        compactMenuItem(
          value: _ScriptItemAction.removeShortcut,
          label: l(appState, AppStrings.values.removeShortcut),
        ),
      compactMenuItem(
        value: _ScriptItemAction.delete,
        label: t(context, AppStrings.values.delete),
      ),
    ];
  }

  void _handleScriptAction(
    BuildContext context,
    TerminalAppState appState,
    ScriptEntry script,
    _ScriptItemAction action,
  ) {
    switch (action) {
      case _ScriptItemAction.run:
        _showRunScriptDialog(context, appState, script);
      case _ScriptItemAction.edit:
        showScriptEditorDialog(context, appState, script: script);
      case _ScriptItemAction.bindShortcut:
        _showBindShortcutDialog(context, appState, script);
      case _ScriptItemAction.removeShortcut:
        appState.unbindScriptShortcut(script.id);
      case _ScriptItemAction.delete:
        appState.removeScriptEntry(script.id);
    }
  }

  Future<void> _showScriptItemMenu(
    BuildContext context,
    TerminalAppState appState,
    ScriptEntry script,
    Offset position,
  ) async {
    final action = await showCompactMenu<_ScriptItemAction>(
      context: context,
      position: position,
      items: _scriptMenuItems(context, appState, script),
    );
    if (!context.mounted || action == null) {
      return;
    }
    _handleScriptAction(context, appState, script, action);
  }

  KeyEventResult _handleShortcutKeyEvent(
    BuildContext context,
    TerminalAppState appState,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shortcut = _formatShortcut(event, appState);
    if (shortcut == null) {
      return KeyEventResult.ignored;
    }
    final scriptId = appState.scriptIdForShortcut(shortcut);
    if (scriptId == null) {
      return KeyEventResult.ignored;
    }
    final script = appState.findScriptById(scriptId);
    if (script == null) {
      return KeyEventResult.ignored;
    }
    unawaited(_runScriptByShortcut(context, appState, script));
    return KeyEventResult.handled;
  }

  String? _formatShortcut(KeyEvent event, TerminalAppState appState) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      return null;
    }
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!ctrl && !meta && !alt && !shift) {
      return null;
    }
    final parts = <String>[];
    if (ctrl) parts.add(l(appState, AppStrings.values.scriptModifierCtrl));
    if (meta) parts.add(l(appState, AppStrings.values.scriptModifierMeta));
    if (alt) parts.add(l(appState, AppStrings.values.scriptModifierAlt));
    if (shift) parts.add(l(appState, AppStrings.values.scriptModifierShift));
    final label = key.keyLabel.isNotEmpty ? key.keyLabel : key.debugName ?? '';
    if (label.isEmpty) {
      return null;
    }
    parts.add(label.toUpperCase());
    return parts.join('+');
  }

  Future<void> _runScriptByShortcut(
    BuildContext context,
    TerminalAppState appState,
    ScriptEntry script,
  ) async {
    final last = script.lastRunConfig;
    if (last == null ||
        (last.hostIds.isEmpty && last.localShellTypes.isEmpty)) {
      _showRunScriptDialog(context, appState, script);
      return;
    }
    await appState.runScriptOnTargets(
      scriptId: script.id,
      hostIds: last.hostIds,
      localShellTypes: last.localShellTypes,
      silentExecution: false,
      notifyEnabled: last.notifyEnabled,
      failurePolicy: last.failurePolicy,
      retryPerHost: last.retryPerHost,
      templateArgs: last.templateArgs,
      environmentOverrides: last.environmentOverrides,
      maxConcurrency: last.maxConcurrency,
    );
  }

  Future<void> _showBindShortcutDialog(
    BuildContext context,
    TerminalAppState appState,
    ScriptEntry script,
  ) async {
    var shortcut = appState.shortcutForScript(script.id);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final conflictId = shortcut == null
                ? null
                : appState.scriptIdForShortcut(shortcut!);
            final conflictScript = conflictId == null || conflictId == script.id
                ? null
                : appState.findScriptById(conflictId);
            return AlertDialog(
              title: Text(l(appState, AppStrings.values.bindShortcut)),
              content: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  final formatted = _formatShortcut(event, appState);
                  if (formatted == null) {
                    return KeyEventResult.handled;
                  }
                  setState(() => shortcut = formatted);
                  return KeyEventResult.handled;
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l(appState, AppStrings.values.pressShortcut)),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: l(appState, AppStrings.values.shortcut),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        shortcut ?? '',
                        style: TextStyle(
                          color: shortcut == null
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (conflictScript != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l(
                            appState,
                            AppStrings.values.shortcutAlreadyBoundVar,
                            params: {'name': conflictScript.name},
                          ),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                AppTextButton(
                  onPressed: () => setState(() => shortcut = null),
                  label: l(appState, AppStrings.values.clear),
                  size: ButtonSize.small,
                ),
                SecondaryButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  label: t(dialogContext, AppStrings.values.cancel),
                  size: ButtonSize.small,
                ),
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  onPressed: shortcut == null
                      ? null
                      : () {
                          appState.bindScriptShortcut(
                            scriptId: script.id,
                            shortcut: shortcut!,
                          );
                          Navigator.pop(dialogContext);
                        },
                  label: t(dialogContext, AppStrings.values.save),
                  size: ButtonSize.small,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _renameScriptFolder(
    TerminalAppState appState,
    ScriptFolderEntry folder,
  ) async {
    final newName = await showInputDialog(
      context,
      title: l(appState, AppStrings.values.renameFolder),
      initialValue: folder.name,
      hint: l(appState, AppStrings.values.folderName),
      confirmText: l(appState, AppStrings.values.save),
      cancelText: t(context, AppStrings.values.cancel),
      validator: (v) => v == null || v.trim().isEmpty ? '' : null,
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    appState.upsertScriptFolder(
      folder.copyWith(name: newName.trim(), updatedAt: DateTime.now()),
    );
  }

  Future<void> _deleteScriptFolder(
    TerminalAppState appState,
    ScriptFolderEntry folder,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t(context, AppStrings.values.confirm),
      message: l(
        appState,
        AppStrings.values.deleteScriptFolderConfirmVar,
        params: {'name': folder.name},
      ),
      confirmText: t(context, AppStrings.values.delete),
      cancelText: t(context, AppStrings.values.cancel),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    appState.removeScriptFolder(folder.id);
    if (_selectedScriptFolderId == folder.id) {
      setState(() {
        _selectedScriptFolderId = '';
      });
    }
  }

  Future<void> _showScriptFolderMenu(
    BuildContext context,
    TerminalAppState appState,
    ScriptFolderEntry folder,
    Offset position,
  ) async {
    final action = await showCompactMenu<_ScriptFolderAction>(
      context: context,
      position: position,
      items: [
        compactMenuItem(
          value: _ScriptFolderAction.newScript,
          label: l(appState, AppStrings.values.addScript),
        ),
        compactMenuItem(
          value: _ScriptFolderAction.edit,
          label: t(context, AppStrings.values.edit),
        ),
        compactMenuItem(
          value: _ScriptFolderAction.delete,
          label: t(context, AppStrings.values.delete),
        ),
      ],
    );
    if (!context.mounted || action == null) {
      return;
    }
    switch (action) {
      case _ScriptFolderAction.newScript:
        await showScriptEditorDialog(
          context,
          appState,
          initialFolderId: folder.id,
        );
      case _ScriptFolderAction.edit:
        await _renameScriptFolder(appState, folder);
      case _ScriptFolderAction.delete:
        await _deleteScriptFolder(appState, folder);
    }
  }

  String _scriptTooltipPreview(ScriptEntry script) {
    final commands = script.commands
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final lines = commands.take(5).toList(growable: false);
    if (lines.isEmpty) {
      return script.name;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final normalized = lines[i].replaceAll('\n', ' ');
      final text = normalized.length > 120
          ? '${normalized.substring(0, 120)}...'
          : normalized;
      if (i > 0) {
        buffer.write('\n');
      }
      buffer.write('${i + 1}. $text');
    }
    if (commands.length > 5) {
      buffer.write('\n...');
    }
    return buffer.toString();
  }

  Widget _buildScriptLeafNode(
    BuildContext context,
    TerminalAppState appState,
    ScriptEntry script,
    int depth,
    String keyword,
  ) {
    final preview = _scriptTooltipPreview(script);
    final status = appState.scriptRunStatus(script.id);
    final statusColor = _scriptStatusColor(status);
    final statusBackground = _scriptStatusBackground(status);
    final isSelected = _selectedScriptIds.contains(script.id);
    return InkWell(
      onTap: () {
        if (_selectionMode) {
          _toggleScriptSelection(script.id);
          return;
        }
        showScriptEditorDialog(context, appState, script: script);
      },
      onLongPress: () {
        if (_selectionMode) {
          return;
        }
        setState(() {
          _selectionMode = true;
          _selectedScriptIds.add(script.id);
        });
      },
      onSecondaryTapDown: (details) => unawaited(
        _showScriptItemMenu(context, appState, script, details.globalPosition),
      ),
      child: Container(
        height: 30,
        padding: EdgeInsets.only(left: 10 + depth * 14.0, right: 8),
        color: statusBackground,
        child: Row(
          children: [
            if (_selectionMode)
              SizedBox(
                width: 20,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleScriptSelection(script.id),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                ),
              )
            else
              const SizedBox(width: 20),
            Icon(Icons.description_outlined, size: 16, color: statusColor),
            const SizedBox(width: 6),
            Expanded(
              child: Tooltip(
                message: preview,
                child: Text.rich(
                  AppTextStyles.highlightSpan(
                    text: script.name,
                    query: keyword,
                    baseStyle: TextStyle(
                      fontSize: 12,
                      color: statusColor ?? AppColors.textPrimary,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              tooltip: l(appState, AppStrings.values.run),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              onPressed: () => _showRunScriptDialog(context, appState, script),
            ),
            CompactMoreMenuButton(
              tooltip: l(appState, AppStrings.values.more),
              iconSize: 16,
              padding: 0,
              onTapDown: (details) => unawaited(
                _showScriptItemMenu(
                  context,
                  appState,
                  script,
                  details.globalPosition,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleScriptSelection(String scriptId) {
    setState(() {
      if (_selectedScriptIds.contains(scriptId)) {
        _selectedScriptIds.remove(scriptId);
      } else {
        _selectedScriptIds.add(scriptId);
      }
      if (_selectedScriptIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _setSelectionMode(bool enabled) {
    setState(() {
      _selectionMode = enabled;
      if (!enabled) {
        _selectedScriptIds.clear();
      }
    });
  }

  Widget _buildSelectionFloatingBar(TerminalAppState appState) {
    final selectedCount = _selectedScriptIds.length;
    final allScriptIds = appState.scripts
        .map((script) => script.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    final allSelected =
        allScriptIds.isNotEmpty && selectedCount == allScriptIds.length;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x1A000000)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l(
                  appState,
                  AppStrings.values.selectedCountVar,
                  params: {'count': '$selectedCount'},
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              AppTextButton(
                onPressed: allScriptIds.isEmpty
                    ? null
                    : () {
                        setState(() {
                          if (allSelected) {
                            _selectedScriptIds.clear();
                          } else {
                            _selectedScriptIds
                              ..clear()
                              ..addAll(allScriptIds);
                          }
                        });
                      },
                label: allSelected
                    ? l(appState, AppStrings.values.clearAll)
                    : l(appState, AppStrings.values.selectAll),
              ),
              const SizedBox(width: 4),
              PrimaryButton(
                onPressed: selectedCount == 0
                    ? null
                    : () {
                        final ids = _selectedScriptIds.toList(growable: false);
                        _setSelectionMode(false);
                        unawaited(
                          _runSelectedScriptsWithSavedConfig(appState, ids),
                        );
                      },
                label: l(appState, AppStrings.values.run),
                size: ButtonSize.medium,
              ),
              SecondaryButton(
                onPressed: () => _setSelectionMode(false),
                label: l(appState, AppStrings.values.cancel),
                size: ButtonSize.medium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runSelectedScriptsWithSavedConfig(
    TerminalAppState appState,
    List<String> scriptIds,
  ) async {
    if (scriptIds.isEmpty) return;
    final futures = <Future<void>>[];
    for (final scriptId in scriptIds) {
      final script = appState.findScriptById(scriptId);
      if (script == null) {
        appState.addStructuredLog(
          category: TerminalLogCategory.script,
          level: TerminalLogLevel.warn,
          message: l(appState, AppStrings.values.scriptNotFoundOnHost, params: {'id': scriptId}),
          notifyListeners: false,
        );
        continue;
      }
      final last = script.lastRunConfig;
      if (last == null ||
          (last.hostIds.isEmpty && last.localShellTypes.isEmpty)) {
        appState.addStructuredLog(
          category: TerminalLogCategory.script,
          level: TerminalLogLevel.warn,
          message: l(appState, AppStrings.values.scriptNoSavedConfigVar, params: {'name': script.name}),
          notifyListeners: false,
        );
        continue;
      }
      futures.add(appState.runScriptOnTargets(
        scriptId: script.id,
        hostIds: last.hostIds,
        localShellTypes: last.localShellTypes,
        silentExecution: false,
        notifyEnabled: last.notifyEnabled,
        failurePolicy: last.failurePolicy,
        retryPerHost: last.retryPerHost,
        templateArgs: last.templateArgs,
        environmentOverrides: last.environmentOverrides,
        maxConcurrency: last.maxConcurrency,
      ));
    }
    for (var i = 0; i < futures.length; i += _maxBatchConcurrency) {
      final batch = futures.sublist(
        i,
        (i + _maxBatchConcurrency).clamp(0, futures.length),
      );
      await Future.wait(batch);
    }
  }

  Color? _scriptStatusColor(ScriptRunStatus status) {
    switch (status) {
      case ScriptRunStatus.running:
        return TerminalUiPalette.info;
      case ScriptRunStatus.success:
        return TerminalUiPalette.success;
      case ScriptRunStatus.failed:
        return TerminalUiPalette.error;
      case ScriptRunStatus.idle:
        return null;
    }
  }

  Color? _scriptStatusBackground(ScriptRunStatus status) {
    switch (status) {
      case ScriptRunStatus.running:
        return TerminalUiPalette.infoSoft;
      case ScriptRunStatus.success:
        return TerminalUiPalette.successSoft;
      case ScriptRunStatus.failed:
        return TerminalUiPalette.errorSoft;
      case ScriptRunStatus.idle:
        return null;
    }
  }

  _ScriptTreeBuildResult _buildScriptTreeNodes(
    BuildContext context, {
    required TerminalAppState appState,
    required String parentId,
    required int depth,
    required Map<String, List<ScriptFolderEntry>> foldersByParent,
    required Map<String, List<ScriptEntry>> scriptsByFolder,
    required Set<String> visibleScriptIds,
    required String keyword,
    required Set<String> forceExpandFolderIds,
  }) {
    final widgets = <Widget>[];
    var hasMatch = false;
    final childFolders =
        foldersByParent[parentId] ?? const <ScriptFolderEntry>[];

    for (final folder in childFolders) {
      final childResult = _buildScriptTreeNodes(
        context,
        appState: appState,
        parentId: folder.id,
        depth: depth + 1,
        foldersByParent: foldersByParent,
        scriptsByFolder: scriptsByFolder,
        visibleScriptIds: visibleScriptIds,
        keyword: keyword,
        forceExpandFolderIds: forceExpandFolderIds,
      );
      final folderMatch =
          keyword.isNotEmpty && folder.name.toLowerCase().contains(keyword);
      final showFolder = keyword.isEmpty || folderMatch || childResult.hasMatch;
      if (!showFolder) {
        continue;
      }
      hasMatch = true;
      final hasChildren =
          (foldersByParent[folder.id]?.isNotEmpty ?? false) ||
          (scriptsByFolder[folder.id]?.isNotEmpty ?? false);
      final autoExpanded =
          keyword.isNotEmpty && (folderMatch || childResult.hasMatch);
      final expanded =
          autoExpanded ||
          forceExpandFolderIds.contains(folder.id) ||
          _expandedScriptFolderIds.contains(folder.id);
      final selected = _selectedScriptFolderId == folder.id;

      widgets.add(
        InkWell(
          onTap: () {
            setState(() {
              _selectedScriptFolderId = folder.id;
              if (hasChildren && keyword.isEmpty) {
                if (_expandedScriptFolderIds.contains(folder.id)) {
                  _expandedScriptFolderIds.remove(folder.id);
                } else {
                  _expandedScriptFolderIds.add(folder.id);
                }
              }
            });
          },
          onSecondaryTapDown: (details) => unawaited(
            _showScriptFolderMenu(
              context,
              appState,
              folder,
              details.globalPosition,
            ),
          ),
          onLongPress: () {
            final box = context.findRenderObject() as RenderBox?;
            final position = box == null
                ? Offset.zero
                : box.localToGlobal(box.size.center(Offset.zero));
            unawaited(
              _showScriptFolderMenu(context, appState, folder, position),
            );
          },
          child: Container(
            color: selected ? const Color(0xFFE0E7FF) : null,
            height: 30,
            padding: EdgeInsets.only(left: 10 + depth * 14.0, right: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: hasChildren
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          splashRadius: 14,
                          icon: Icon(
                            expanded ? Icons.expand_more : Icons.chevron_right,
                            size: 16,
                          ),
                          onPressed: () {
                            setState(() {
                              if (expanded) {
                                _expandedScriptFolderIds.remove(folder.id);
                              } else {
                                _expandedScriptFolderIds.add(folder.id);
                              }
                            });
                          },
                        )
                      : const SizedBox.shrink(),
                ),
                const Icon(Icons.folder_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    AppTextStyles.highlightSpan(
                      text: folder.name,
                      query: keyword,
                      baseStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (hasChildren && expanded) {
        widgets.addAll(childResult.widgets);
      }
    }

    final scripts = scriptsByFolder[parentId] ?? const <ScriptEntry>[];
    final visibleScripts = keyword.isEmpty
        ? scripts
        : scripts
              .where((script) => visibleScriptIds.contains(script.id))
              .toList(growable: false);
    if (visibleScripts.isNotEmpty) {
      hasMatch = true;
      for (final script in visibleScripts) {
        widgets.add(
          _buildScriptLeafNode(context, appState, script, depth, keyword),
        );
      }
    }

    return _ScriptTreeBuildResult(widgets: widgets, hasMatch: hasMatch);
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    // 不在页面 build 时启动定时调度，避免脚本自动执行
    // 定时调度改为在 upsertScriptScheduleEntry 中按需启动

    if (appState.showScriptMonitorInline) {
      return _buildInlineMonitor(appState);
    }
    if (appState.scriptMultiSelectToken != _lastMultiSelectToken) {
      _lastMultiSelectToken = appState.scriptMultiSelectToken;
      _setSelectionMode(appState.scriptMultiSelectActive);
    }
    if (_selectedScriptFolderId.isNotEmpty &&
        appState.findScriptFolderById(_selectedScriptFolderId) == null) {
      _selectedScriptFolderId = '';
    }
    final sortedScripts = List<ScriptEntry>.from(
      appState.scripts,
      growable: false,
    )..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final foldersById = <String, ScriptFolderEntry>{
      for (final folder in appState.scriptFolders) folder.id: folder,
    };
    final keyword = _scriptKeyword.trim().toLowerCase();
    final scriptsByFolder = <String, List<ScriptEntry>>{};
    for (final script in sortedScripts) {
      final folderId = script.folderId.trim();
      (scriptsByFolder[folderId] ??= <ScriptEntry>[]).add(script);
    }
    for (final list in scriptsByFolder.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    final foldersByParent = <String, List<ScriptFolderEntry>>{};
    for (final folder in appState.scriptFolders) {
      final parentId = folder.parentId.trim();
      (foldersByParent[parentId] ??= <ScriptFolderEntry>[]).add(folder);
    }
    for (final list in foldersByParent.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    final visibleScripts = _filteredScripts(
      sortedScripts,
      keyword: keyword,
      selectedFolderId: '',
      foldersById: foldersById,
    );
    final visibleScriptIds = visibleScripts.map((script) => script.id).toSet();
    final forceExpandFolderIds = <String>{};
    var cursor = _selectedScriptFolderId.trim();
    while (cursor.isNotEmpty) {
      final folder = foldersById[cursor];
      if (folder == null) {
        break;
      }
      final parentId = folder.parentId.trim();
      if (parentId.isEmpty) {
        break;
      }
      forceExpandFolderIds.add(parentId);
      cursor = parentId;
    }
    final scriptTreeResult = _buildScriptTreeNodes(
      context,
      appState: appState,
      parentId: '',
      depth: 0,
      foldersByParent: foldersByParent,
      scriptsByFolder: scriptsByFolder,
      visibleScriptIds: visibleScriptIds,
      keyword: keyword,
      forceExpandFolderIds: forceExpandFolderIds,
    );
    final isSearchActive = keyword.isNotEmpty;
    final emptySearchText = l(appState, AppStrings.values.noMatchingScripts);
    if (!_shortcutFocusNode.hasFocus &&
        FocusManager.instance.primaryFocus == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_shortcutFocusNode.hasFocus) {
          return;
        }
        if (FocusManager.instance.primaryFocus != null) {
          return;
        }
        _shortcutFocusNode.requestFocus();
      });
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _shortcutFocusNode.requestFocus(),
      child: Focus(
        focusNode: _shortcutFocusNode,
        onKeyEvent: (node, event) =>
            _handleShortcutKeyEvent(context, appState, event),
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    widget.isCompact ? 12 : 8,
                    12,
                    8,
                  ),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: _scriptSearchHint(appState),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _scriptKeyword.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  tooltip: l(appState, AppStrings.values.clear),
                                  onPressed: () {
                                    setState(() {
                                      _scriptKeyword = '';
                                    });
                                  },
                                ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _scriptKeyword = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child:
                      (sortedScripts.isEmpty && appState.scriptFolders.isEmpty)
                      ? Center(
                          child: Text(
                            t(context, AppStrings.values.noData),
                            style: AppTextStyles.secondarySmall,
                          ),
                        )
                      : scriptTreeResult.widgets.isEmpty
                      ? Center(
                          child: Text(
                            isSearchActive
                                ? emptySearchText
                                : t(context, AppStrings.values.noData),
                            style: AppTextStyles.secondarySmall,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: scriptTreeResult.widgets,
                        ),
                ),
              ],
            ),
            if (_selectionMode)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _buildSelectionFloatingBar(appState),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineMonitor(TerminalAppState appState) {
    final runs = appState.activeScriptRuns.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final workflowResults = List<ScriptWorkflowRunResult>.from(
      appState.workflowRunHistory.reversed,
    );

    if (runs.isEmpty && workflowResults.isEmpty) {
      return Center(
        child: Text(
          l(appState, AppStrings.values.scriptMonitorNoRunning),
          style: TextStyle(color: TerminalUiPalette.textSecondary),
        ),
      );
    }

    final runningCount = runs.where((r) => !r.isFinished).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                l(
                  appState,
                  AppStrings.values.scriptMonitorRunningCountVar,
                  params: {'count': '$runningCount'},
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              if (runs.any((r) => r.isFinished))
                GestureDetector(
                  onTap: () => appState.dismissFinishedScriptRuns(),
                  child: Text(
                    l(appState, AppStrings.values.scriptMonitorDismissFinished),
                    style: TextStyle(
                      fontSize: 11,
                      color: TerminalUiPalette.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (runs.length > _maxBatchConcurrency)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              l(
                appState,
                AppStrings.values.scriptMonitorBatchHintVar,
                params: {'max': '$_maxBatchConcurrency'},
              ),
              style: TextStyle(
                fontSize: 11,
                color: TerminalUiPalette.textSecondary,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: runs.length + workflowResults.length,
            itemBuilder: (context, index) {
              if (index < workflowResults.length) {
                return _buildWorkflowResultTile(appState, workflowResults[index]);
              }
              final run = runs[index - workflowResults.length];
              return _buildInlineRunTile(appState, run, key: ValueKey(run.runId));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowResultTile(TerminalAppState appState, ScriptWorkflowRunResult result) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: BaseCard(
        padding: EdgeInsets.zero,
        border: true,
        radius: AppRadius.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 4),
              child: Row(
                children: [
                  Icon(
                    result.failedSteps > 0 ? Icons.error : Icons.check_circle,
                    size: 16,
                    color: result.failedSteps > 0
                        ? TerminalUiPalette.error
                        : TerminalUiPalette.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      result.workflowName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (result.nodeResults.isNotEmpty) ...[
                    Text(
                      l(appState, AppStrings.values.workflowResultSummary, params: {
                        'attempted': '${result.attemptedSteps}',
                        'succeeded': '${result.succeededSteps}',
                        'failed': '${result.failedSteps}',
                      }),
                      style: TextStyle(
                        fontSize: 11,
                        color: result.failedSteps > 0
                            ? TerminalUiPalette.error
                            : TerminalUiPalette.success,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (result.nodeResults.isNotEmpty)
              ...result.nodeResults.map((nr) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      nr.passed ? Icons.check_circle : Icons.error,
                      size: 12,
                      color: nr.passed
                          ? TerminalUiPalette.success
                          : TerminalUiPalette.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      nr.detail,
                      style: TextStyle(
                        fontSize: 11,
                        color: nr.passed
                            ? TerminalUiPalette.textSecondary
                            : TerminalUiPalette.error,
                      ),
                    ),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineRunTile(TerminalAppState appState, ScriptRunSession run, {Key? key}) {
    final progress = run.progress;
    final failedCount = run.failedTargets;

    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: BaseCard(
        padding: EdgeInsets.zero,
        border: true,
        radius: AppRadius.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 4),
            child: Row(
              children: [
                Icon(
                  run.isCancelled
                      ? Icons.cancel
                      : run.isFinished
                          ? (run.failedTargets > 0
                              ? Icons.error
                              : Icons.check_circle)
                          : Icons.play_circle,
                  size: 16,
                  color: run.isCancelled
                      ? TerminalUiPalette.textSecondary
                      : run.isFinished
                          ? (run.failedTargets > 0
                              ? TerminalUiPalette.error
                              : TerminalUiPalette.success)
                          : TerminalUiPalette.info,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          run.scriptName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: run.silent
                              ? TerminalUiPalette.info.withValues(alpha: 0.15)
                              : TerminalUiPalette.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          run.silent
                              ? l(appState, AppStrings.values.runSilent)
                              : l(appState, AppStrings.values.runVisible),
                          style: TextStyle(
                            fontSize: 10,
                            color: run.silent
                                ? TerminalUiPalette.info
                                : TerminalUiPalette.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!run.isFinished)
                  AppTextButton(
                    onPressed: () {
                      final cancelTitle = l(appState, AppStrings.values.cancelExecution);
                      final cancelConfirm = l(
                        appState,
                        AppStrings.values.cancelExecutionConfirmVar,
                        params: {'name': run.scriptName},
                      );
                      final cancelBack = l(appState, AppStrings.values.back);
                      final cancelAction = l(appState, AppStrings.values.cancel);
                      final confirmed = showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => AlertDialog(
                          title: Text(cancelTitle),
                          content: Text(cancelConfirm),
                          actions: [
                            SecondaryButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              label: cancelBack,
                              size: ButtonSize.medium,
                            ),
                            PrimaryButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              label: cancelAction,
                              size: ButtonSize.medium,
                            ),
                          ],
                        ),
                      );
                      confirmed.then((v) {
                        if (v == true) appState.cancelScriptRun(run.runId);
                      });
                    },
                    label: l(appState, AppStrings.values.cancel),
                    color: TerminalUiPalette.error,
                    size: ButtonSize.small,
                  ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: TerminalUiPalette.border,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 8, 6),
            child: Row(
              children: [
                Text(
                  '${run.completedTargets}/${run.targetCount}',
                  style: TextStyle(
                    fontSize: 11,
                    color: TerminalUiPalette.textSecondary,
                  ),
                ),
                if (failedCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                      l(appState, AppStrings.values.scriptFailureCountVar, params: {'count': '$failedCount'}),
                    style: TextStyle(
                      fontSize: 11,
                      color: TerminalUiPalette.error,
                    ),
                  ),
                ],
                if (run.isCancelled) ...[
                  const SizedBox(width: 8),
                  Text(
                    l(appState, AppStrings.values.scriptCancelledCountVar, params: {'count': '${run.cancelledTargets}'}),
                    style: TextStyle(
                      fontSize: 11,
                      color: TerminalUiPalette.textSecondary,
                    ),
                  ),
                ],
                const Spacer(),
                if (run.isFinished) ...[
                  AppTextButton(
                    onPressed: () => appState.dismissScriptRun(run.runId),
                    label: l(appState, AppStrings.values.close),
                    color: TerminalUiPalette.textSecondary,
                    size: ButtonSize.small,
                  ),
                ],
              ],
            ),
          ),
          ...run.targets.values.map((target) {
            final key = '${run.runId}:${target.targetId}';
            final expanded = _expandedMonitorTargets.contains(key);
            final tStatus = target.status;
            final statusColor = switch (tStatus) {
              ScriptTargetRunStatus.success => TerminalUiPalette.success,
              ScriptTargetRunStatus.failed => TerminalUiPalette.error,
              ScriptTargetRunStatus.cancelled => TerminalUiPalette.textSecondary,
              ScriptTargetRunStatus.running => TerminalUiPalette.info,
              ScriptTargetRunStatus.pending => TerminalUiPalette.textSecondary,
            };
            final statusIcon = switch (tStatus) {
              ScriptTargetRunStatus.success => Icons.check_circle,
              ScriptTargetRunStatus.failed => Icons.error,
              ScriptTargetRunStatus.cancelled => Icons.cancel,
              ScriptTargetRunStatus.running => Icons.play_circle,
              ScriptTargetRunStatus.pending => Icons.hourglass_empty,
            };

            return Column(
              children: [
                const Divider(height: 1, indent: 10, endIndent: 10),
                InkWell(
                  onTap: () {
                    setState(() {
                      if (expanded) {
                        _expandedMonitorTargets.remove(key);
                      } else {
                        _expandedMonitorTargets.add(key);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            target.targetName,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${target.currentStep}/${target.totalSteps}',
                          style: TextStyle(
                            fontSize: 11,
                            color: TerminalUiPalette.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: TerminalUiPalette.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (expanded) ...[
                  for (final step in target.steps)
                    _buildMonitorStepTile(step, target: target, runId: run.runId),
                ],
              ],
            );
          }),
        ],
      ),
    ),
  );
  }

  Widget _buildMonitorStepTile(ScriptRunStepState step, {required ScriptRunTargetState target, required String runId}) {
    final sStatus = step.status;
    final statusColor = switch (sStatus) {
      ScriptTargetRunStatus.success => TerminalUiPalette.success,
      ScriptTargetRunStatus.failed => TerminalUiPalette.error,
      ScriptTargetRunStatus.cancelled => TerminalUiPalette.textSecondary,
      ScriptTargetRunStatus.running => TerminalUiPalette.info,
      ScriptTargetRunStatus.pending => TerminalUiPalette.textSecondary,
    };
    final statusIcon = switch (sStatus) {
      ScriptTargetRunStatus.success => Icons.check_circle_outline,
      ScriptTargetRunStatus.failed => Icons.error_outline,
      ScriptTargetRunStatus.cancelled => Icons.cancel,
      ScriptTargetRunStatus.running => Icons.play_circle_outline,
      ScriptTargetRunStatus.pending => Icons.circle_outlined,
    };
    final stepKey = '$runId:${target.targetId}:${step.index}';
    final showingCopied = _copyFeedbackKey == stepKey;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: TerminalUiPalette.cardBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 12, color: statusColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  step.command,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (step.exitCode != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    l(widget.appState, AppStrings.values.scriptExitCodeVar, params: {'code': '${step.exitCode}'}),
                    style: TextStyle(
                      fontSize: 10,
                      color: step.exitCode == 0
                          ? TerminalUiPalette.success
                          : TerminalUiPalette.error,
                    ),
                  ),
                ),
              if (step.lines.isNotEmpty) ...[
                GestureDetector(
                  onTap: () {
                    final text = step.lines.map((l) => l.text).join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                    _copyFeedbackTimer?.cancel();
                    _copyFeedbackKey = stepKey;
                    _copyFeedbackTimer = Timer(
                      const Duration(milliseconds: 500),
                      () {
                        if (mounted) {
                          setState(() => _copyFeedbackKey = null);
                        }
                      },
                    );
                    setState(() {});
                  },
                  child: Tooltip(
                    message: showingCopied
                        ? l(widget.appState, AppStrings.values.scriptCopied)
                        : l(widget.appState, AppStrings.values.scriptCopyOutput),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        showingCopied ? Icons.check : Icons.copy,
                        size: 14,
                        color: showingCopied ? TerminalUiPalette.success : TerminalUiPalette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (step.lines.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: SelectableText(
                step.lines.map((l) => _stripAnsi(l.text)).join('\n'),
                key: ValueKey('${step.index}:${step.lines.length}'),
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: TerminalUiPalette.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _ScriptItemAction {
  run,
  edit,
  bindShortcut,
  removeShortcut,
  delete,
}



