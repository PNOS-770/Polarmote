import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/constants/app_string.dart';
import '../../models/script_entry.dart';
import '../../models/script_folder_entry.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import '../../../../shared/design_system/design_system.dart';

Future<void> showScriptEditorDialog(
  BuildContext context,
  TerminalAppState appState, {
  ScriptEntry? script,
  String? initialFolderId,
}) async {
  final result = await showDialog<ScriptEditorOutput>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ScriptEditorDialog(
      appState: appState,
      script: script,
      initialFolderId: initialFolderId,
    ),
  );

  if (result == null || result.action == ScriptEditorAction.cancel) {
    return;
  }
  if (result.action == ScriptEditorAction.delete) {
    if (script != null) {
      appState.removeScriptEntry(script.id);
    }
    return;
  }
  if (result.action == ScriptEditorAction.saveAsNew || script == null) {
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

enum ScriptEditorAction { cancel, save, saveAsNew, delete }

class ScriptEditorOutput {
  const ScriptEditorOutput({
    required this.action,
    required this.name,
    required this.commands,
    required this.folderId,
    this.stepConfigs,
    this.variables,
  });

  final ScriptEditorAction action;
  final String name;
  final List<String> commands;
  final String folderId;
  final List<ScriptStepConfig?>? stepConfigs;
  final Map<String, String>? variables;
}

class ScriptEditorDialog extends StatefulWidget {
  const ScriptEditorDialog({
    super.key,
    required this.appState,
    required this.script,
    this.initialFolderId,
  });

  final TerminalAppState appState;
  final ScriptEntry? script;
  final String? initialFolderId;

  @override
  State<ScriptEditorDialog> createState() => ScriptEditorDialogState();
}

class HighlightController extends TextEditingController {
  HighlightController(String text) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle();
    final spans = <Match>[];
    final variableRegex = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
    final scriptRefRegex = RegExp(r'@script:([A-Za-z0-9_\-\u4e00-\u9fff]+)');
    for (final match in variableRegex.allMatches(text)) {
      spans.add(Match(match.start, match.end, AppColors.accent));
    }
    for (final match in scriptRefRegex.allMatches(text)) {
      spans.add(Match(match.start, match.end, AppColors.success));
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

class Match {
  const Match(this.start, this.end, this.color);
  final int start;
  final int end;
  final Color color;
}

class StepEditorState {
  StepEditorState(String command, [ScriptStepConfig? config])
      : id = 'step_${_nextId++}',
        commandController = HighlightController(command),
        config = config ?? const ScriptStepConfig();

  static int _nextId = 0;
  final String id;
  final TextEditingController commandController;
  ScriptStepConfig config;

  void dispose() {
    commandController.dispose();
  }
}

class StepSnapshot {
  final String command;
  final ScriptStepConfig config;
  const StepSnapshot(this.command, this.config);
}

class KeyValueEntry {
  KeyValueEntry({String key = '', String value = ''})
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

class ScriptEditorDialogState extends State<ScriptEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _folderController;
  final List<StepEditorState> _steps = <StepEditorState>[];
  final List<List<StepSnapshot>> _undoStack = [];
  final FocusNode _folderFocusNode = FocusNode();
  List<String> _folderSuggestions = [];
  int _selectedSuggestionIndex = -1;
  final List<KeyValueEntry> _variableEntries = [];
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
          .map((s) => StepSnapshot(s.commandController.text, s.config))
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
        _steps.add(StepEditorState(snapshot[_steps.length].command, snapshot[_steps.length].config));
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
      _steps.add(StepEditorState(''));
    } else {
      for (var i = 0; i < initialCommands.length; i++) {
        _steps.add(StepEditorState(
          initialCommands[i],
          i < initialConfigs.length ? initialConfigs[i] : null,
        ));
      }
    }
    final scriptVariables = widget.script?.variables ?? const <String, String>{};
    for (final entry in scriptVariables.entries) {
      _variableEntries.add(KeyValueEntry(key: entry.key, value: entry.value));
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
    final newText = '${text.substring(0, dollarBrace)}\$$varName}${text.substring(cursorPos)}';
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
      _steps.insert(insertIndex, StepEditorState(value));
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
          _steps.add(StepEditorState(command));
        }
        return;
      }
      for (final command in commands) {
        _steps.add(StepEditorState(command));
      }
    });
  }

  Future<void> _showBulkInputDialog() async {
    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkSplitEditor(
        appState: widget.appState,
      ),
    );
    if (result != null && mounted) {
      _appendCommands(result);
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
        ScriptEditorOutput(
          action: ScriptEditorAction.delete,
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
                          _variableEntries.add(KeyValueEntry());
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
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: AppColors.info),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l(appState, AppStrings.values.scriptReferenceHint),
                          style: AppTextStyles.captionSmall.copyWith(color: AppColors.primaryDark),
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
                  onReorderItem: (oldIndex, newIndex) {
                    _pushUndo();
                    setState(() {
                      final step = _steps.removeAt(oldIndex);
                      _steps.insert(newIndex, step);
                    });
                  },
                  children: [
                    for (var index = 0; index < _steps.length; index++)
                      Padding(
                        key: ValueKey('script_step_${_steps[index].id}'),
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
                                      child: Icon(Icons.drag_handle, size: 18, color: AppColors.grey400),
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
            ScriptEditorOutput(
              action: ScriptEditorAction.cancel,
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
            color: AppColors.error,
          ),
        if (script != null)
          SecondaryButton(
            onPressed: () {
              final folderId = _resolveFolderIdFromInput();
              Navigator.pop(
                context,
                ScriptEditorOutput(
                  action: ScriptEditorAction.saveAsNew,
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
              ScriptEditorOutput(
                action: ScriptEditorAction.save,
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

class BulkSplitEditor extends StatefulWidget {
  const BulkSplitEditor({super.key, required this.appState});
  final TerminalAppState appState;
  @override
  State<BulkSplitEditor> createState() => BulkSplitEditorState();
}

class BulkSplitEditorState extends State<BulkSplitEditor> {
  final _controller = TextEditingController();
  final _commandsNotifier = ValueNotifier<List<String>>([]);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateCommands);
  }

  void _updateCommands() {
    _commandsNotifier.value = _parseCommands(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateCommands);
    _controller.dispose();
    _commandsNotifier.dispose();
    super.dispose();
  }

  static List<String> _parseCommands(String text) {
    if (text.isEmpty) return const [];

    final lines = LineSplitter.split(text).toList();
    final commands = <String>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i].trim();

      if (line.isEmpty) {
        i++;
        continue;
      }

      if (line == '---' || line == '===' || line == '>>>') {
        i++;
        final block = <String>[];

        while (i < lines.length) {
          final blockLine = lines[i].trim();

          if (blockLine == '---' || blockLine == '===' || blockLine == '>>>') {
            i++;
            break;
          }

          if (blockLine.isNotEmpty) {
            block.add(blockLine);
          }
          i++;
        }

        if (block.isNotEmpty) {
          commands.add(block.join('\n'));
        }
        continue;
      }

      commands.add(line);
      i++;
    }

    return commands;
  }

  @override
  Widget build(BuildContext context) {
    const l = AppStrings.values;
    final locale = widget.appState.locale.languageCode;

    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.radiusDialog,
      ),
      title: Text(
        l.scriptBulkAppendDialogTitle.resolve(locale),
        style: AppTextStyles.h4,
      ),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: AppRadius.radiusMD,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppColors.primaryDark),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l.scriptBulkDelimiterHint.resolve(locale),
                      style: AppTextStyles.captionSmall.copyWith(color: Colors.blue[800]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.05),
                borderRadius: AppRadius.radiusMD,
                border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 12, color: AppColors.success),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.scriptBulkDelimiterExample.resolve(locale),
                          style: AppTextStyles.captionSmall.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.scriptBulkExampleDemo.resolve(locale),
                          style: AppTextStyles.captionSmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: AppRadius.radiusMD,
                  color: AppColors.background,
                ),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: null,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                    hintText: l.scriptBulkInputPlaceholder.resolve(locale),
                    hintStyle: AppTextStyles.hint,
                  ),
                  style: AppTextStyles.code,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ValueListenableBuilder<List<String>>(
              valueListenable: _commandsNotifier,
              builder: (context, commands, _) {
                if (commands.isEmpty) return const SizedBox.shrink();

                return Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.05),
                    borderRadius: AppRadius.radiusMD,
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, size: 14, color: AppColors.success),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            l.scriptBulkWillAppendVar.resolve(locale, params: {'count': '${commands.length}'}),
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: commands.length,
                          itemBuilder: (context, i) {
                            final cmd = commands[i];
                            final isMultiLine = cmd.contains('\n');
                            final lineCount = isMultiLine ? cmd.split('\n').length : 1;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: AppRadius.radiusXS,
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: AppTextStyles.captionSmall.copyWith(
                                        fontFamily: 'monospace',
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  if (isMultiLine)
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning.withValues(alpha: 0.2),
                                        borderRadius: AppRadius.radiusXS,
                                      ),
                                      child: Text(
                                        l.scriptBulkMultiLineVar.resolve(locale, params: {'count': '$lineCount'}),
                                        style: AppTextStyles.captionSmall.copyWith(
                                          fontSize: 9,
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      isMultiLine ? '${cmd.split('\n').first}...' : cmd,
                                      style: AppTextStyles.captionSmall.copyWith(
                                        fontFamily: 'monospace',
                                        color: AppColors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        SecondaryButton(
          onPressed: () => Navigator.pop(context),
          label: t(context, AppStrings.values.cancel),
          size: ButtonSize.medium,
        ),
        const SizedBox(width: AppSpacing.sm),
        ValueListenableBuilder<List<String>>(
          valueListenable: _commandsNotifier,
          builder: (context, commands, _) {
            return PrimaryButton(
              onPressed: commands.isEmpty ? null : () => Navigator.pop(context, commands),
              label: l.scriptBulkAppend.resolve(locale),
              size: ButtonSize.medium,
            );
          },
        ),
      ],
    );
  }
}

