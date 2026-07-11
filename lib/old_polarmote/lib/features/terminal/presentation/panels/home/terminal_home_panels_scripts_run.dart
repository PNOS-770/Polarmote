part of '../terminal_home_panels.dart';

Future<void> showScriptEditorDialog(
  BuildContext context,
  TerminalAppState appState, {
  ScriptEntry? script,
  String? initialFolderId,
}) async {
  final result = await showDialog<_ScriptEditorOutput>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ScriptEditorDialog(
      appState: appState,
      script: script,
      initialFolderId: initialFolderId,
    ),
  );

  if (result == null || result.action == _ScriptEditorAction.cancel) {
    return;
  }
  if (result.action == _ScriptEditorAction.delete) {
    if (script != null) {
      appState.removeScriptEntry(script.id);
    }
    return;
  }
  if (result.action == _ScriptEditorAction.saveAsNew || script == null) {
    appState.addScriptEntry(
      name: result.name,
      commands: result.commands,
      folderId: result.folderId,
      stepConfigs: result.stepConfigs,
      variables: result.variables,
    );
  } else {
    appState.updateScriptEntry(
      script.id,
      name: result.name,
      commands: result.commands,
      folderId: result.folderId,
      stepConfigs: result.stepConfigs,
      variables: result.variables,
    );
  }
}

enum _ScriptEditorAction { cancel, save, saveAsNew, delete }

class _ScriptEditorOutput {
  const _ScriptEditorOutput({
    required this.action,
    required this.name,
    required this.commands,
    required this.folderId,
    this.stepConfigs,
    this.variables,
  });

  final _ScriptEditorAction action;
  final String name;
  final List<String> commands;
  final String folderId;
  final List<ScriptStepConfig?>? stepConfigs;
  final Map<String, String>? variables;
}

class _ScriptEditorDialog extends StatefulWidget {
  const _ScriptEditorDialog({
    required this.appState,
    required this.script,
    this.initialFolderId,
  });

  final TerminalAppState appState;
  final ScriptEntry? script;
  final String? initialFolderId;

  @override
  State<_ScriptEditorDialog> createState() => _ScriptEditorDialogState();
}

class _HighlightController extends TextEditingController {
  _HighlightController(String text) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle();
    final spans = <_Match>[];
    final variableRegex = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
    final scriptRefRegex = RegExp(r'@script:([A-Za-z0-9_\-\u4e00-\u9fff]+)');
    for (final match in variableRegex.allMatches(text)) {
      spans.add(_Match(match.start, match.end, AppColors.accent));
    }
    for (final match in scriptRefRegex.allMatches(text)) {
      spans.add(_Match(match.start, match.end, AppColors.success));
    }
    spans.sort((a, b) => a.start.compareTo(b.start));
    final result = <TextSpan>[];
    var pos = 0;
    for (final m in spans) {
      if (m.start > pos) {
        result.add(TextSpan(text: text.substring(pos, m.start), style: baseStyle));
      }
      if (m.start < pos) continue;
      result.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: baseStyle.copyWith(color: m.color, fontWeight: FontWeight.w600),
      ));
      pos = m.end;
    }
    if (pos < text.length) {
      result.add(TextSpan(text: text.substring(pos), style: baseStyle));
    }
    return TextSpan(children: result, style: baseStyle);
  }
}

class _Match {
  const _Match(this.start, this.end, this.color);
  final int start;
  final int end;
  final Color color;
}

class _StepEditorState {
  _StepEditorState(String command, [ScriptStepConfig? config])
      : commandController = _HighlightController(command),
        config = config ?? const ScriptStepConfig();

  final TextEditingController commandController;
  ScriptStepConfig config;

  void dispose() {
    commandController.dispose();
  }
}

class _StepSnapshot {
  final String command;
  final ScriptStepConfig config;
  const _StepSnapshot(this.command, this.config);
}

class _KeyValueEntry {
  _KeyValueEntry({String key = '', String value = ''})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }

  String get key => keyController.text.trim();
  String get value => valueController.text.trim();
}

class _ScriptEditorDialogState extends State<_ScriptEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _folderController;
  final List<_StepEditorState> _steps = <_StepEditorState>[];
  final List<List<_StepSnapshot>> _undoStack = [];
  final FocusNode _folderFocusNode = FocusNode();
  List<String> _folderSuggestions = [];
  int _selectedSuggestionIndex = -1;
  final List<_KeyValueEntry> _variableEntries = [];
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  var _autocompleteStepIndex = -1;
  String _autocompletePrefix = '';
  int _selectedAutocompleteIndex = -1;

  List<String> _allFolderPaths() {
    final appState = widget.appState;
    final paths = <String>{};
    for (final folder in appState.scriptFolders) {
      final path = _folderPathById(folder.id);
      if (path.isNotEmpty) paths.add(path);
    }
    return paths.toList()..sort();
  }

  void _updateFolderSuggestions(String text) {
    final query = text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _folderSuggestions = [];
        _selectedSuggestionIndex = -1;
      } else {
        _folderSuggestions = _allFolderPaths()
            .where((p) => p.toLowerCase().contains(query))
            .take(20)
            .toList();
        _selectedSuggestionIndex = -1;
      }
    });
  }

  void _pushUndo() {
    _undoStack.add(
      _steps
          .map((s) => _StepSnapshot(s.commandController.text, s.config))
          .toList(growable: false),
    );
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final snapshot = _undoStack.removeLast();
    setState(() {
      var i = 0;
      while (i < snapshot.length && i < _steps.length) {
        _steps[i].commandController.text = snapshot[i].command;
        _steps[i].config = snapshot[i].config;
        i++;
      }
      while (_steps.length > snapshot.length) {
        _steps.removeLast().dispose();
      }
      while (_steps.length < snapshot.length) {
        _steps.add(_StepEditorState(snapshot[_steps.length].command, snapshot[_steps.length].config));
      }
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyZ &&
        HardwareKeyboard.instance.isControlPressed) {
      _undo();
      return true;
    }
    if (event is! KeyDownEvent) return false;
    if (_folderSuggestions.isEmpty) return false;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedSuggestionIndex = (_selectedSuggestionIndex + 1)
            .clamp(0, _folderSuggestions.length - 1);
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedSuggestionIndex = (_selectedSuggestionIndex - 1)
            .clamp(0, _folderSuggestions.length - 1);
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _selectedSuggestionIndex >= 0) {
      _selectFolderSuggestion(
          _folderSuggestions[_selectedSuggestionIndex]);
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _undoStack.clear();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _nameController = TextEditingController(text: widget.script?.name ?? '');
    _folderController = TextEditingController(
      text: _folderPathById(widget.script?.folderId ?? widget.initialFolderId),
    );
    _folderController.addListener(_onFolderChanged);
    final initialCommands = widget.script?.commands ?? const <String>[];
    final initialConfigs = widget.script?.stepConfigs ?? const <ScriptStepConfig?>[];
    if (initialCommands.isEmpty) {
      _steps.add(_StepEditorState(''));
    } else {
      for (var i = 0; i < initialCommands.length; i++) {
        _steps.add(_StepEditorState(
          initialCommands[i],
          i < initialConfigs.length ? initialConfigs[i] : null,
        ));
      }
    }
    final scriptVariables = widget.script?.variables ?? const <String, String>{};
    for (final entry in scriptVariables.entries) {
      _variableEntries.add(_KeyValueEntry(key: entry.key, value: entry.value));
    }

  }

  void _onFolderChanged() {
    _updateFolderSuggestions(_folderController.text);
  }

  void _selectFolderSuggestion(String path) {
    _folderController.text = path;
    _folderController.selection = TextSelection.collapsed(offset: path.length);
    _folderSuggestions = [];
    _selectedSuggestionIndex = -1;
  }

  Map<String, String> _collectVariables() {
    final result = <String, String>{};
    for (final entry in _variableEntries) {
      final key = entry.key;
      final value = entry.value;
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }

  Widget _buildAutocompleteList(TerminalAppState appState, int stepIndex) {
    final varNames = _availableVariableNames();
    final filtered = _autocompletePrefix.isEmpty
        ? varNames
        : varNames.where((n) => n.toLowerCase().contains(_autocompletePrefix.toLowerCase())).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 2, left: 32),
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.radiusSM,
        boxShadow: [
          BoxShadow(color: AppColors.overlayLight, blurRadius: 4),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final name = filtered[i];
          final isSelected = i == _selectedAutocompleteIndex;
          return InkWell(
            onTap: () => _insertVariableAutocomplete(stepIndex, name),
            onHover: (v) {
              if (v) setState(() => _selectedAutocompleteIndex = i);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: isSelected ? AppColors.primaryLight.withValues(alpha: 0.15) : null,
              child: Row(
                children: [
                  Icon(Icons.code, size: 14, color: AppColors.grey500),
                  const SizedBox(width: 6),
                  Text(
                    r'$' + name,
                    style: isSelected ? AppTextStyles.label : AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<String> _availableVariableNames() {
    final names = <String>{};
    for (final entry in _variableEntries) {
      final key = entry.key;
      if (key.isNotEmpty) names.add(key);
    }
    return names.toList()..sort();
  }

  void _onCommandChanged(int index, String text) {
    final controller = _steps[index].commandController;
    final cursorPos = controller.selection.baseOffset;
    if (cursorPos < 0) {
      _clearAutocomplete();
      return;
    }
    final beforeCursor = text.substring(0, cursorPos);
    final dollarBrace = beforeCursor.lastIndexOf(r'${');
    final closeBrace = beforeCursor.lastIndexOf('}');
    if (dollarBrace >= 0 && dollarBrace > closeBrace) {
      _clearAutocomplete();
      return;
    }
    _clearAutocomplete();
  }

  void _clearAutocomplete() {
    if (_autocompleteStepIndex >= 0) {
      setState(() {
        _autocompleteStepIndex = -1;
        _autocompletePrefix = '';
        _selectedAutocompleteIndex = -1;
      });
    }
  }

  void _insertVariableAutocomplete(int stepIndex, String varName) {
    final controller = _steps[stepIndex].commandController;
    final cursorPos = controller.selection.baseOffset;
    if (cursorPos < 0) return;
    final text = controller.text;
    final beforeCursor = text.substring(0, cursorPos);
    final dollarBrace = beforeCursor.lastIndexOf(r'${');
    if (dollarBrace < 0) return;
    final newText = '${text.substring(0, dollarBrace)}\$\{${varName}}${text.substring(cursorPos)}';
    controller.text = newText;
    final newPos = dollarBrace + varName.length + 2;
    controller.selection = TextSelection.collapsed(offset: newPos);
    _clearAutocomplete();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _nameController.dispose();
    _folderController.removeListener(_onFolderChanged);
    _folderController.dispose();
    _folderFocusNode.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    for (final entry in _variableEntries) {
      entry.dispose();
    }
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  List<String> _collectCommands() {
    return _steps
        .map((step) => step.commandController.text.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<ScriptStepConfig?> _collectStepConfigs() {
    return _steps.map((step) {
      final text = step.commandController.text.trim();
      if (text.isEmpty) return null;
      if (step.config.condition == ScriptStepCondition.always &&
          step.config.failurePolicy == ScriptStepFailurePolicy.continueOnFailure &&
          !step.config.captureOutput &&
          step.config.retryCount <= 1) {
        return null;
      }
      return step.config;
    }).toList(growable: false);
  }

  String _folderPathById(String? folderId) {
    final normalizedId = (folderId ?? '').trim();
    if (normalizedId.isEmpty) {
      return '';
    }
    final appState = widget.appState;
    final folderById = <String, ScriptFolderEntry>{
      for (final folder in appState.scriptFolders) folder.id: folder,
    };
    final parts = <String>[];
    final visited = <String>{};
    var cursor = normalizedId;
    while (cursor.isNotEmpty && visited.add(cursor)) {
      final folder = folderById[cursor];
      if (folder == null) {
        break;
      }
      final name = folder.name.trim();
      if (name.isNotEmpty) {
        parts.add(name);
      }
      cursor = folder.parentId.trim();
    }
    if (parts.isEmpty) {
      return '';
    }
    return parts.reversed.join('/');
  }

  String _resolveFolderIdFromInput() {
    final appState = widget.appState;
    final segments = _folderController.text
        .replaceAll('\\', '/')
        .split('/')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return '';
    }
    var parentId = '';
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      ScriptFolderEntry? existing;
      for (final folder in appState.scriptFolders) {
        if (folder.parentId.trim() != parentId) {
          continue;
        }
        if (folder.name.trim() == segment) {
          existing = folder;
          break;
        }
      }
      if (existing != null) {
        parentId = existing.id;
        continue;
      }
      final now = DateTime.now();
      final created = ScriptFolderEntry(
        id: 'script-folder-${now.microsecondsSinceEpoch}-$index',
        name: segment,
        parentId: parentId,
        createdAt: now,
        updatedAt: now,
      );
      appState.upsertScriptFolder(created);
      parentId = created.id;
    }
    return parentId;
  }

  void _insertCommandField(int index, [String value = '']) {
    _pushUndo();
    final insertIndex = index.clamp(0, _steps.length);
    setState(() {
      _steps.insert(insertIndex, _StepEditorState(value));
    });
  }

  void _removeCommandField(int index) {
    if (index < 0 || index >= _steps.length) {
      return;
    }
    _pushUndo();
    setState(() {
      if (_steps.length == 1) {
        _steps.first.commandController.clear();
        _steps.first.config = const ScriptStepConfig();
        return;
      }
      _steps[index].dispose();
      _steps.removeAt(index);
    });
  }

  List<String> _parseBulkCommands(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  void _appendCommands(List<String> commands) {
    if (commands.isEmpty) {
      return;
    }
    _pushUndo();
    setState(() {
      if (_steps.length == 1 &&
          _steps.first.commandController.text.trim().isEmpty) {
        _steps.first.commandController.text = commands.first;
        for (final command in commands.skip(1)) {
          _steps.add(_StepEditorState(command));
        }
        return;
      }
      for (final command in commands) {
        _steps.add(_StepEditorState(command));
      }
    });
  }

  Future<void> _showBulkInputDialog() async {
    final controller = TextEditingController();
    final delimiterController = TextEditingController(text: '');
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.radiusDialog,
            ),
            title: Text(
              l(widget.appState, AppStrings.values.scriptBulkAppendDialogTitle),
              style: AppTextStyles.h4,
            ),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 8,
                    maxLines: 18,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: l(
                        widget.appState,
                        AppStrings.values.scriptBulkInputHint,
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: delimiterController,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l(widget.appState, AppStrings.values.scriptBulkDelimiter),
                      hintText: l(widget.appState, AppStrings.values.scriptBulkDelimiterHint),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
                actionsPadding: const EdgeInsets.all(AppSpacing.lg),
                actions: [
                  SecondaryButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    label: t(dialogContext, AppStrings.values.cancel),
                    size: ButtonSize.medium,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PrimaryButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    label: l(widget.appState, AppStrings.values.append),
                    size: ButtonSize.medium,
                  ),
                ],
              );
            },
          );
      if (confirmed != true || !mounted) {
        return;
      }
      final delimiter = delimiterController.text.trim();
      final rawText = controller.text;
      if (delimiter.isEmpty) {
        _appendCommands(_parseBulkCommands(rawText));
      } else {
        final lines = rawText
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList(growable: false);
        if (lines.isNotEmpty) {
          _appendCommands([lines.join(delimiter)]);
        }
      }
    } finally {
      controller.dispose();
      delimiterController.dispose();
    }
  }

  Future<void> _confirmDelete() async {
    final script = widget.script;
    if (script == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: t(context, AppStrings.values.confirm),
      message: l(
        widget.appState,
        AppStrings.values.deleteVar,
        params: {'name': script.name},
      ),
      confirmText: t(context, AppStrings.values.ok),
      cancelText: t(context, AppStrings.values.cancel),
      destructive: true,
    );
    if (confirmed == true && mounted) {
      Navigator.pop(
        context,
        _ScriptEditorOutput(
          action: _ScriptEditorAction.delete,
          name: _nameController.text,
          commands: _collectCommands(),
          folderId: widget.script?.folderId ?? '',
          variables: _collectVariables(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final script = widget.script;
    return AlertDialog(
      title: Text(
        script == null
            ? l(appState, AppStrings.values.addScript)
            : l(appState, AppStrings.values.edit),
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l(appState, AppStrings.values.scriptName),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _folderController,
                  focusNode: _folderFocusNode,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l(
                      appState,
                      AppStrings.values.scriptFolderInputLabel,
                    ),
                    hintText: l(
                      appState,
                      AppStrings.values.scriptFolderInputHint,
                    ),
                  ),
                ),
                if (_folderSuggestions.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _folderSuggestions.length,
                      itemBuilder: (context, index) {
                        final path = _folderSuggestions[index];
                        final isSelected = index == _selectedSuggestionIndex;
                        return InkWell(
                          onTap: () => _selectFolderSuggestion(path),
                          onHighlightChanged: (highlighted) {
                            if (highlighted) {
                              setState(() {
                                _selectedSuggestionIndex = index;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : null,
                            child: Text(
                              path,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l(appState, AppStrings.values.commandsOnePerLine),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(_showBulkInputDialog()),
                      icon: const Icon(Icons.playlist_add, size: 16),
                      label: Text(
                        l(appState, AppStrings.values.scriptBulkAppend),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      l(appState, AppStrings.values.scriptVariableTitle),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 14),
                      label: Text(
                        l(appState, AppStrings.values.scriptVariableAdd),
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () {
                        setState(() {
                          _variableEntries.add(_KeyValueEntry());
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (_variableEntries.isNotEmpty)
                  ..._variableEntries.asMap().entries.map((e) {
                    final i = e.key;
                    final entry = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: entry.keyController,
                              hint: l(appState, AppStrings.values.scriptVariableName),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: AppTextField(
                              controller: entry.valueController,
                              hint: l(appState, AppStrings.values.scriptVariableValue),
                            ),
                          ),
                          StepIconButton(
                            icon: Icons.delete_outline,
                            onPressed: () {
                              setState(() {
                                entry.dispose();
                                _variableEntries.removeAt(i);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _findController,
                        hint: l(appState, AppStrings.values.scriptFindText),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AppTextField(
                        controller: _replaceController,
                        hint: l(appState, AppStrings.values.scriptReplaceText),
                      ),
                    ),
                    const SizedBox(width: 6),
                    StepIconButton(
                      icon: Icons.find_replace,
                      onPressed: () {
                        final find = _findController.text;
                        final replace = _replaceController.text;
                        if (find.isEmpty) return;
                        _pushUndo();
                        for (final step in _steps) {
                          final text = step.commandController.text;
                          if (text.contains(find)) {
                            step.commandController.text = text.replaceAll(find, replace);
                          }
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.blue[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l(appState, AppStrings.values.scriptReferenceHint),
                          style: TextStyle(fontSize: 11, color: Colors.blue[800]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    _pushUndo();
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final step = _steps.removeAt(oldIndex);
                      _steps.insert(newIndex, step);
                    });
                  },
                  children: [
                    for (var index = 0; index < _steps.length; index++)
                      Padding(
                        key: ValueKey('step_$index'),
                        padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Icon(Icons.drag_handle, size: 18, color: Colors.grey[500]),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 24,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text('${index + 1}.', style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  Expanded(
                                    child: AppTextField(
                                      controller: _steps[index].commandController,
                                      minLines: 2,
                                      maxLines: 6,
                                      hint: l(appState, AppStrings.values.command),
                                      onChanged: (value) => _onCommandChanged(index, value),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      StepIconButton(
                                        icon: Icons.arrow_upward,
                                        onPressed: () => _insertCommandField(index - 1),
                                      ),
                                      const SizedBox(width: 2),
                                      StepIconButton(
                                        icon: Icons.arrow_downward,
                                        onPressed: () => _insertCommandField(index + 1),
                                      ),
                                      const SizedBox(width: 2),
                                      StepIconButton(
                                        icon: Icons.delete_outline,
                                        onPressed: () => _removeCommandField(index),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (index == _autocompleteStepIndex)
                                _buildAutocompleteList(appState, index),
                            ],
                          ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        SecondaryButton(
          onPressed: () => Navigator.pop(
            context,
            _ScriptEditorOutput(
              action: _ScriptEditorAction.cancel,
              name: '',
              commands: <String>[],
              folderId: '',
            ),
          ),
          label: t(context, AppStrings.values.cancel),
          size: ButtonSize.medium,
        ),
        if (script != null)
          AppTextButton(
            onPressed: _confirmDelete,
            label: t(context, AppStrings.values.delete),
            color: Colors.red[700]!,
          ),
        if (script != null)
          SecondaryButton(
            onPressed: () {
              final folderId = _resolveFolderIdFromInput();
              Navigator.pop(
                context,
                _ScriptEditorOutput(
                  action: _ScriptEditorAction.saveAsNew,
                  name: _nameController.text,
                  commands: _collectCommands(),
                  folderId: folderId,
                  stepConfigs: _collectStepConfigs(),
                  variables: _collectVariables(),
                ),
              );
            },
            label: l(appState, AppStrings.values.saveAsNewScript),
            size: ButtonSize.medium,
          ),
        PrimaryButton(
          onPressed: () {
            final folderId = _resolveFolderIdFromInput();
            Navigator.pop(
              context,
              _ScriptEditorOutput(
                action: _ScriptEditorAction.save,
                name: _nameController.text,
                commands: _collectCommands(),
                folderId: folderId,
                stepConfigs: _collectStepConfigs(),
                variables: _collectVariables(),
              ),
            );
          },
          label: t(context, AppStrings.values.save),
          size: ButtonSize.medium,
        ),
      ],
    );
  }
}

Future<void> _showRunScriptDialog(
  BuildContext context,
  TerminalAppState appState,
  ScriptEntry script,
) async {
  final hosts = appState.availableScriptHosts();
  final localShellOptions = _scriptLocalShellOptions();
  if (hosts.isEmpty && localShellOptions.isEmpty) {
    appState.setError(l(appState, AppStrings.values.noSessions));
    return;
  }
  final lastConfig = script.lastRunConfig;
  final hostIdSet = hosts.map((host) => host.id).toSet();
  final selectedHostIds = (lastConfig == null)
      ? <String>{}
      : lastConfig.hostIds.where(hostIdSet.contains).toSet();
  final selectedLocalShells = (lastConfig == null)
      ? <LocalShellType>{}
      : lastConfig.localShellTypes.where(localShellOptions.contains).toSet();
  var hostQuery = '';
  var notifyEnabled = lastConfig?.notifyEnabled ?? true;
  var silentExecution = lastConfig?.silentExecution ?? false;
  var failurePolicy =
      lastConfig?.failurePolicy ?? ScriptFailurePolicy.continueOnFailure;
  var retryPerHost = lastConfig?.retryPerHost ?? 1;
  var maxConcurrency = (lastConfig?.maxConcurrency ?? script.maxConcurrency)
      .clamp(1, 8);
  final scriptVariableKeys = script.variables.keys.toList(growable: false)
    ..sort();
  final scriptTemplateArgs = <String, String>{
    ...script.variables,
    ...?lastConfig?.templateArgs,
  };
  final environmentOverrides = <String, String>{
    ...?lastConfig?.environmentOverrides,
  };
  final templateControllers = <String, TextEditingController>{};
  for (final key in scriptVariableKeys) {
    templateControllers[key] = TextEditingController(
      text: scriptTemplateArgs[key] ?? '',
    );
  }
  var showSelectionError = false;

  bool? confirmed;
  try {
    confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final normalizedQuery = hostQuery.trim().toLowerCase();
            final filteredHosts = hosts
                .where((host) {
                  if (normalizedQuery.isEmpty) {
                    return true;
                  }
                  final group = host.group.toLowerCase();
                  return host.name.toLowerCase().contains(normalizedQuery) ||
                      host.host.toLowerCase().contains(normalizedQuery) ||
                      host.username.toLowerCase().contains(normalizedQuery) ||
                      group.contains(normalizedQuery);
                })
                .toList(growable: false);

            return AlertDialog(
              title: Text(
                l(
                  appState,
                  AppStrings.values.runScriptVar,
                  params: {'name': script.name},
                ),
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l(appState, AppStrings.values.runTargetsSavedSessions),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (hosts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            l(appState, AppStrings.values.noSessions),
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        )
                      else ...[
                        TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l(appState, AppStrings.values.search),
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: hostQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: l(
                                      appState,
                                      AppStrings.values.clear,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        hostQuery = '';
                                      });
                                    },
                                  ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              hostQuery = value;
                            });
                          },
                        ),
                        const SizedBox(height: 6),
                        if (filteredHosts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              l(appState, AppStrings.values.noMatchingSessions),
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        else
                          ...filteredHosts.map(
                            (host) => CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: selectedHostIds.contains(host.id),
                              onChanged: (value) {
                                setState(() {
                                  showSelectionError = false;
                                  if (value == true) {
                                    selectedHostIds.add(host.id);
                                  } else {
                                    selectedHostIds.remove(host.id);
                                  }
                                });
                              },
                              title: Text(host.name),
                              subtitle: Text(
                                _hostScriptStatusLabel(appState, host.id),
                              ),
                            ),
                          ),
                      ],
                      const Divider(height: 22),
                      Text(
                        l(appState, AppStrings.values.runTargetsLocalSessions),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: localShellOptions
                            .map((shell) {
                              final selected = selectedLocalShells.contains(
                                shell,
                              );
                              return FilterChip(
                                selected: selected,
                                label: Text(
                                  _scriptLocalShellLabel(appState, shell),
                                ),
                                onSelected: (value) {
                                  setState(() {
                                    showSelectionError = false;
                                    if (value) {
                                      selectedLocalShells.add(shell);
                                    } else {
                                      selectedLocalShells.remove(shell);
                                    }
                                  });
                                },
                              );
                            })
                            .toList(growable: false),
                      ),
                      if (scriptVariableKeys.isNotEmpty) ...[
                        const Divider(height: 22),
                        Text(
                          l(appState, AppStrings.values.scriptTemplateArgs),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...scriptVariableKeys.map((key) {
                          final controller = templateControllers[key]!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: key,
                              ),
                              onChanged: (value) {
                                scriptTemplateArgs[key] = value;
                              },
                            ),
                          );
                        }),
                      ],
                      const Divider(height: 22),
                      Row(
                        children: [
                          Text(
                            l(appState, AppStrings.values.scriptMaxConcurrency),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$maxConcurrency',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(width: 4),
                                CompactMoreMenuButton(
                                  tooltip: l(
                                    appState,
                                    AppStrings.values.scriptMaxConcurrency,
                                  ),
                                  icon: Icons.arrow_drop_down,
                                  iconSize: 18,
                                  padding: 0,
                                  onTapDown: (details) => unawaited(() async {
                                    final value = await showCompactMenu<int>(
                                      context: context,
                                      position: details.globalPosition,
                                      items: List<PopupMenuEntry<int>>.generate(
                                        8,
                                        (index) => compactMenuItem(
                                          value: index + 1,
                                          label: '${index + 1}',
                                        ),
                                      ),
                                    );
                                    if (!context.mounted || value == null) {
                                      return;
                                    }
                                    setState(() {
                                      maxConcurrency = value;
                                    });
                                  }()),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l(appState, AppStrings.values.runOptionNotify),
                        ),
                        value: notifyEnabled,
                        onChanged: (value) =>
                            setState(() => notifyEnabled = value),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l(appState, AppStrings.values.runOptionSilent),
                        ),
                        subtitle: Text(
                          silentExecution
                              ? l(
                                  appState,
                                  AppStrings.values.runSilentExecutionHint,
                                )
                              : l(
                                  appState,
                                  AppStrings.values.runInteractiveExecutionHint,
                                ),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        value: silentExecution,
                        onChanged: (value) =>
                            setState(() => silentExecution = value),
                      ),
                      AppDropdownButtonFormField<ScriptFailurePolicy>(
                        value: failurePolicy,
                        label: l(appState, AppStrings.values.scriptFailurePolicy),
                        items: ScriptFailurePolicy.values
                            .map(
                              (policy) => DropdownMenuItem(
                                value: policy,
                                child: Text(
                                  _scriptFailurePolicyLabel(appState, policy),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => failurePolicy = value);
                        },
                      ),
                      if (failurePolicy == ScriptFailurePolicy.retryHost)
                        Row(
                          children: [
                            Text(
                              l(appState, AppStrings.values.scriptRetryPerHost),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$retryPerHost'),
                                  const SizedBox(width: 4),
                                  CompactMoreMenuButton(
                                    tooltip: l(
                                      appState,
                                      AppStrings.values.scriptRetryPerHost,
                                    ),
                                    icon: Icons.arrow_drop_down,
                                    iconSize: 18,
                                    padding: 0,
                                    onTapDown: (details) => unawaited(() async {
                                      final value = await showCompactMenu<int>(
                                        context: context,
                                        position: details.globalPosition,
                                        items:
                                            List<PopupMenuEntry<int>>.generate(
                                              6,
                                              (index) => compactMenuItem(
                                                value: index + 1,
                                                label: '${index + 1}',
                                              ),
                                            ),
                                      );
                                      if (!context.mounted || value == null) {
                                        return;
}

                                      setState(() => retryPerHost = value);
                                    }()),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (showSelectionError)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l(appState, AppStrings.values.runNoTargetSelected),
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                AppTextButton(
                  onPressed: () {
                    for (final entry in templateControllers.entries) {
                      scriptTemplateArgs[entry.key] = entry.value.text;
                    }
                    appState.updateScriptLastRunConfig(
                      scriptId: script.id,
                      hostIds: selectedHostIds.toList(growable: false),
                      localShellTypes: selectedLocalShells.toList(growable: false),
                      notifyEnabled: notifyEnabled,
                      silentExecution: silentExecution,
                      failurePolicy: failurePolicy,
                      retryPerHost: retryPerHost,
                      templateArgs: scriptTemplateArgs,
                      environmentOverrides: environmentOverrides,
                      maxConcurrency: maxConcurrency,
                    );
                    appState.scheduleStateSave();
                    if (context.mounted) Navigator.pop(context, false);
                  },
                  label: l(appState, AppStrings.values.saveRunConfig),
                ),
                SecondaryButton(
                  onPressed: () => Navigator.pop(context, false),
                  label: t(context, AppStrings.values.cancel),
                  size: ButtonSize.medium,
                ),
                PrimaryButton(
                  onPressed: () {
                    if (selectedHostIds.isEmpty &&
                        selectedLocalShells.isEmpty) {
                      setState(() => showSelectionError = true);
                      return;
                    }
                    for (final entry in templateControllers.entries) {
                      scriptTemplateArgs[entry.key] = entry.value.text;
                    }
                    Navigator.pop(context, true);
                  },
                  label: l(appState, AppStrings.values.run),
                  size: ButtonSize.medium,
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    for (final controller in templateControllers.values) {
      controller.dispose();
    }
  }
  if (confirmed != true) return;
  appState.updateScriptLastRunConfig(
    scriptId: script.id,
    hostIds: selectedHostIds.toList(growable: false),
    localShellTypes: selectedLocalShells.toList(growable: false),
    notifyEnabled: notifyEnabled,
    silentExecution: silentExecution,
    failurePolicy: failurePolicy,
    retryPerHost: retryPerHost,
    templateArgs: scriptTemplateArgs,
    environmentOverrides: environmentOverrides,
    maxConcurrency: maxConcurrency,
  );

  // Fire-and-forget execution
  unawaited(appState.runScriptOnTargets(
    scriptId: script.id,
    hostIds: selectedHostIds.toList(growable: false),
    localShellTypes: selectedLocalShells.toList(growable: false),
    silentExecution: silentExecution,
    notifyEnabled: notifyEnabled,
    failurePolicy: failurePolicy,
    retryPerHost: retryPerHost,
    templateArgs: scriptTemplateArgs,
    environmentOverrides: environmentOverrides,
    maxConcurrency: maxConcurrency,
  ));

  // Switch sidebar to monitor view
  appState.showScriptMonitorInline = true;
  appState.navSection = NavSection.scripts;
  appState.notifyState();
}

Future<void> showRunScriptsBatchDialogWithSelection(
  BuildContext context,
  TerminalAppState appState,
  List<String> presetScriptIds,
) async {
  await _showRunScriptsBatchDialog(
    context,
    appState,
    presetScriptIds: presetScriptIds,
    lockScriptSelection: true,
  );
}

Future<void> _showRunScriptsBatchDialog(
  BuildContext context,
  TerminalAppState appState, {
  List<String>? presetScriptIds,
  bool lockScriptSelection = false,
}) async {
  final scripts = List<ScriptEntry>.from(appState.scripts, growable: false)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (scripts.isEmpty) {
    appState.setError(l(appState, AppStrings.values.noData));
    return;
  }
  final hosts = appState.availableScriptHosts();
  final localShellOptions = _scriptLocalShellOptions();
  if (hosts.isEmpty && localShellOptions.isEmpty) {
    appState.setError(l(appState, AppStrings.values.noSessions));
    return;
  }

  final hostIdSet = hosts.map((host) => host.id).toSet();
  ScriptLastRunConfig? seedConfig;
  for (final script in List<ScriptEntry>.from(
    appState.scripts,
    growable: false,
  )..sort((a, b) => b.updatedAt.compareTo(a.updatedAt))) {
    if (script.lastRunConfig != null) {
      seedConfig = script.lastRunConfig;
      break;
    }
  }

  final selectedScriptIds = <String>{};
  if (presetScriptIds != null && presetScriptIds.isNotEmpty) {
    final valid = presetScriptIds
        .where((id) => scripts.any((script) => script.id == id))
        .toList(growable: false);
    selectedScriptIds.addAll(valid);
  }
  final selectedHostIds = (seedConfig == null)
      ? <String>{}
      : seedConfig.hostIds.where(hostIdSet.contains).toSet();
  final selectedLocalShells = (seedConfig == null)
      ? <LocalShellType>{}
      : seedConfig.localShellTypes.where(localShellOptions.contains).toSet();
  var scriptQuery = '';
  var hostQuery = '';
  var notifyEnabled = seedConfig?.notifyEnabled ?? true;
  var silentExecution = seedConfig?.silentExecution ?? false;
  var failurePolicy =
      seedConfig?.failurePolicy ?? ScriptFailurePolicy.continueOnFailure;
  var retryPerHost = seedConfig?.retryPerHost ?? 1;
  var maxConcurrency = (seedConfig?.maxConcurrency ?? 1).clamp(1, 8);
  var showScriptSelectionError = false;
  var showTargetSelectionError = false;

  bool? confirmed;
  confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final normalizedScriptQuery = scriptQuery.trim().toLowerCase();
          final filteredScripts = scripts
              .where((script) {
                if (normalizedScriptQuery.isEmpty) {
                  return true;
                }
                return script.name.toLowerCase().contains(
                  normalizedScriptQuery,
                );
              })
              .toList(growable: false);
          final normalizedHostQuery = hostQuery.trim().toLowerCase();
          final filteredHosts = hosts
              .where((host) {
                if (normalizedHostQuery.isEmpty) {
                  return true;
                }
                final group = host.group.toLowerCase();
                return host.name.toLowerCase().contains(normalizedHostQuery) ||
                    host.host.toLowerCase().contains(normalizedHostQuery) ||
                    host.username.toLowerCase().contains(normalizedHostQuery) ||
                    group.contains(normalizedHostQuery);
              })
              .toList(growable: false);
          final allScriptsSelected = selectedScriptIds.length == scripts.length;

          return AlertDialog(
            title: Text(l(appState, AppStrings.values.batchRunScripts)),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!lockScriptSelection) ...[
                      Row(
                        children: [
                          Text(
                            l(appState, AppStrings.values.scripts),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          AppTextButton(
                            onPressed: () {
                              setState(() {
                                if (allScriptsSelected) {
                                  selectedScriptIds.clear();
                                } else {
                                  selectedScriptIds
                                    ..clear()
                                    ..addAll(scripts.map((item) => item.id));
                                }
                                showScriptSelectionError = false;
                              });
                            },
                            label: allScriptsSelected
                                ? l(appState, AppStrings.values.clearAll)
                                : l(appState, AppStrings.values.selectAll),
                          ),
                        ],
                      ),
                      TextField(
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l(appState, AppStrings.values.searchScripts),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: scriptQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      scriptQuery = '';
                                    });
                                  },
                                ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            scriptQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 210),
                        child: filteredScripts.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  l(appState, AppStrings.values.noData),
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: filteredScripts
                                    .map(
                                      (script) => CheckboxListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        value: selectedScriptIds.contains(
                                          script.id,
                                        ),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              selectedScriptIds.add(script.id);
                                            } else {
                                              selectedScriptIds.remove(
                                                script.id,
                                              );
                                            }
                                            showScriptSelectionError = false;
                                          });
                                        },
                                        title: Text(
                                          script.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          l(
                                            appState,
                                            AppStrings
                                                .values
                                                .scriptCommandsCountVar,
                                            params: {
                                              'count':
                                                  '${script.commands.length}',
                                            },
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                      if (showScriptSelectionError)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l(
                              appState,
                              AppStrings.values.selectAtLeastOneScript,
                            ),
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ] else ...[
                      Text(
                        l(
                          appState,
                          AppStrings.values.selectedCountVar,
                          params: {'count': '${selectedScriptIds.length}'},
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Divider(height: 22),
                    Text(
                      l(appState, AppStrings.values.runTargetsSavedSessions),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (hosts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l(appState, AppStrings.values.noSessions),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    else ...[
                      TextField(
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l(appState, AppStrings.values.search),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: hostQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      hostQuery = '';
                                    });
                                  },
                                ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            hostQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      if (filteredHosts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l(appState, AppStrings.values.noMatchingSessions),
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        )
                      else
                        ...filteredHosts.map(
                          (host) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selectedHostIds.contains(host.id),
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  selectedHostIds.add(host.id);
                                } else {
                                  selectedHostIds.remove(host.id);
                                }
                                showTargetSelectionError = false;
                              });
                            },
                            title: Text(host.name),
                            subtitle: Text(
                              _hostScriptStatusLabel(appState, host.id),
                            ),
                          ),
                        ),
                    ],
                    const Divider(height: 22),
                    Text(
                      l(appState, AppStrings.values.runTargetsLocalSessions),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: localShellOptions
                          .map((shell) {
                            final selected = selectedLocalShells.contains(
                              shell,
                            );
                            return FilterChip(
                              selected: selected,
                              label: Text(
                                _scriptLocalShellLabel(appState, shell),
                              ),
                              onSelected: (value) {
                                setState(() {
                                  if (value) {
                                    selectedLocalShells.add(shell);
                                  } else {
                                    selectedLocalShells.remove(shell);
                                  }
                                  showTargetSelectionError = false;
                                });
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                    const Divider(height: 22),
                    Row(
                      children: [
                        Text(
                          l(appState, AppStrings.values.scriptMaxConcurrency),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$maxConcurrency',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(width: 4),
                              CompactMoreMenuButton(
                                tooltip: l(
                                  appState,
                                  AppStrings.values.scriptMaxConcurrency,
                                ),
                                icon: Icons.arrow_drop_down,
                                iconSize: 18,
                                padding: 0,
                                onTapDown: (details) => unawaited(() async {
                                  final value = await showCompactMenu<int>(
                                    context: context,
                                    position: details.globalPosition,
                                    items: List<PopupMenuEntry<int>>.generate(
                                      8,
                                      (index) => compactMenuItem(
                                        value: index + 1,
                                        label: '${index + 1}',
                                      ),
                                    ),
                                  );
                                  if (!context.mounted || value == null) {
                                    return;
                                  }
                                  setState(() => maxConcurrency = value);
                                }()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l(appState, AppStrings.values.runOptionNotify),
                      ),
                      value: notifyEnabled,
                      onChanged: (value) =>
                          setState(() => notifyEnabled = value),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l(appState, AppStrings.values.runOptionSilent),
                      ),
                      subtitle: Text(
                        silentExecution
                            ? l(
                                appState,
                                AppStrings.values.runSilentExecutionHint,
                              )
                            : l(
                                appState,
                                AppStrings.values.runInteractiveExecutionHint,
                              ),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      value: silentExecution,
                      onChanged: (value) =>
                          setState(() => silentExecution = value),
                    ),
                    AppDropdownButtonFormField<ScriptFailurePolicy>(
                      value: failurePolicy,
                      label: l(appState, AppStrings.values.scriptFailurePolicy),
                      items: ScriptFailurePolicy.values
                          .map(
                            (policy) => DropdownMenuItem(
                              value: policy,
                              child: Text(
                                _scriptFailurePolicyLabel(appState, policy),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => failurePolicy = value);
                      },
                    ),
                    if (failurePolicy == ScriptFailurePolicy.retryHost)
                      Row(
                        children: [
                          Text(
                            l(appState, AppStrings.values.scriptRetryPerHost),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$retryPerHost'),
                                const SizedBox(width: 4),
                                CompactMoreMenuButton(
                                  tooltip: l(
                                    appState,
                                    AppStrings.values.scriptRetryPerHost,
                                  ),
                                  icon: Icons.arrow_drop_down,
                                  iconSize: 18,
                                  padding: 0,
                                  onTapDown: (details) => unawaited(() async {
                                    final value = await showCompactMenu<int>(
                                      context: context,
                                      position: details.globalPosition,
                                      items: List<PopupMenuEntry<int>>.generate(
                                        6,
                                        (index) => compactMenuItem(
                                          value: index + 1,
                                          label: '${index + 1}',
                                        ),
                                      ),
                                    );
                                    if (!context.mounted || value == null) {
                                      return;
                                    }
                                    setState(() => retryPerHost = value);
                                  }()),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    if (showTargetSelectionError)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l(appState, AppStrings.values.runNoTargetSelected),
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              AppTextButton(
                onPressed: () {
                  setState(() {
                    selectedScriptIds.clear();
                    selectedHostIds.clear();
                    selectedLocalShells.clear();
                    scriptQuery = '';
                    hostQuery = '';
                    notifyEnabled = true;
                    silentExecution = false;
                    failurePolicy = ScriptFailurePolicy.continueOnFailure;
                    retryPerHost = 1;
                    maxConcurrency = 1;
                    showScriptSelectionError = false;
                    showTargetSelectionError = false;
                  });
                },
                label: l(appState, AppStrings.values.reset),
                size: ButtonSize.small,
              ),
              SecondaryButton(
                onPressed: () => Navigator.pop(context, false),
                label: t(context, AppStrings.values.cancel),
                size: ButtonSize.small,
              ),
              const SizedBox(width: AppSpacing.sm),
              PrimaryButton(
                onPressed: () {
                  var hasError = false;
                  if (selectedScriptIds.isEmpty) {
                    showScriptSelectionError = true;
                    hasError = true;
                  }
                  if (selectedHostIds.isEmpty && selectedLocalShells.isEmpty) {
                    showTargetSelectionError = true;
                    hasError = true;
                  }
                  if (hasError) {
                    setState(() {});
                    return;
                  }
                  Navigator.pop(context, true);
                },
                label: l(appState, AppStrings.values.run),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  final selectedScripts = scripts
      .where((script) => selectedScriptIds.contains(script.id))
      .toList(growable: false);
  if (selectedScripts.isEmpty) {
    return;
  }

  var totalAttempted = 0;
  var totalExecuted = 0;
  var totalFailed = 0;
  final batchFutures = <Future<void>>[];
  for (final script in selectedScripts) {
    final scriptLastConfig = script.lastRunConfig;
    final templateArgs = <String, String>{
      ...script.variables,
      ...?scriptLastConfig?.templateArgs,
    };
    final scriptEnvOverrides = <String, String>{
      ...?scriptLastConfig?.environmentOverrides,
    };
    appState.updateScriptLastRunConfig(
      scriptId: script.id,
      hostIds: selectedHostIds.toList(growable: false),
      localShellTypes: selectedLocalShells.toList(growable: false),
      notifyEnabled: notifyEnabled,
      silentExecution: silentExecution,
      failurePolicy: failurePolicy,
      retryPerHost: retryPerHost,
      templateArgs: templateArgs,
      environmentOverrides: scriptEnvOverrides,
      maxConcurrency: maxConcurrency,
    );
    batchFutures.add(
      appState.runScriptOnTargets(
        scriptId: script.id,
        hostIds: selectedHostIds.toList(growable: false),
        localShellTypes: selectedLocalShells.toList(growable: false),
        silentExecution: silentExecution,
        notifyEnabled: false,
        failurePolicy: failurePolicy,
        retryPerHost: retryPerHost,
        templateArgs: templateArgs,
        environmentOverrides: scriptEnvOverrides,
        maxConcurrency: maxConcurrency,
      ).then((result) {
        totalAttempted += result.attempted;
        totalExecuted += result.executed;
        totalFailed += result.failed;
      }),
    );
  }
  for (var i = 0; i < batchFutures.length; i += _maxBatchConcurrency) {
    final batch = batchFutures.sublist(
      i,
      (i + _maxBatchConcurrency).clamp(0, batchFutures.length),
    );
    await Future.wait(batch);
  }

  if (!context.mounted || !notifyEnabled) {
    return;
  }
  if (totalExecuted <= 0 && totalFailed <= 0) {
    return;
  }
  final summary = l(
    appState,
    AppStrings.values.runSummaryVarVar,
    params: {'success': '$totalExecuted', 'failed': '$totalFailed'},
  );
  final detail = l(
    appState,
    AppStrings.values.runBatchSummaryVarVarVar,
    params: {
      'summary': summary,
      'scripts': '${selectedScripts.length}',
      'targets': '$totalAttempted',
    },
  );
  showBannerAndLog(
    appState,
    BannerData(
      id: 'script-batch-run-${DateTime.now().microsecondsSinceEpoch}',
      type: totalFailed > 0 ? BannerType.error : BannerType.success,
      title: totalFailed > 0
          ? l(appState, AppStrings.values.failed)
          : l(appState, AppStrings.values.done),
      message: detail,
    ),
  );
}
