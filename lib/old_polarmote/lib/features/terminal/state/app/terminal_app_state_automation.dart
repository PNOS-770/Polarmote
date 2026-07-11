import 'dart:async';

import '../../../../shared/constants/app_string.dart';
import '../../models/host_entry.dart';
import '../../models/script_batch_template.dart';
import '../../models/script_folder_entry.dart';
import '../../models/script_trigger_entry.dart';
import '../../models/script_workflow_entry.dart';
import '../../models/terminal_session.dart';
import '../terminal_app_state.dart';

final Expando<Map<String, DateTime>> _scriptTriggerCooldownStore =
    Expando<Map<String, DateTime>>('script-trigger-cooldown');

extension TerminalAppStateAutomation on TerminalAppState {
  List<ScriptFolderEntry> scriptFoldersByParent(String parentId) {
    final normalizedParentId = parentId.trim();
    final children =
        scriptFolders
            .where((item) => item.parentId.trim() == normalizedParentId)
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return children;
  }

  ScriptFolderEntry? findScriptFolderById(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final folder in scriptFolders) {
      if (folder.id == normalized) {
        return folder;
      }
    }
    return null;
  }

  void upsertScriptFolder(ScriptFolderEntry folder) {
    final id = folder.id.trim();
    final name = folder.name.trim();
    var parentId = folder.parentId.trim();
    if (id.isEmpty || name.isEmpty) {
      return;
    }
    if (parentId == id || !scriptFolders.any((item) => item.id == parentId)) {
      parentId = '';
    }
    final now = DateTime.now();
    final normalized = folder.copyWith(
      id: id,
      name: name,
      parentId: parentId,
      updatedAt: now,
    );
    final index = scriptFolders.indexWhere((item) => item.id == id);
    if (index >= 0) {
      scriptFolders[index] = normalized;
    } else {
      scriptFolders.add(normalized);
    }
    cleanupAutomationCollections();
    scheduleStateSave();
    notifyState();
  }

  void removeScriptFolder(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return;
    }
    final removedIds = _collectScriptFolderSubtree(normalized);
    if (removedIds.isEmpty) {
      return;
    }
    scriptFolders.removeWhere((item) => removedIds.contains(item.id));
    for (var i = 0; i < scripts.length; i++) {
      final script = scripts[i];
      if (!removedIds.contains(script.folderId)) {
        continue;
      }
      scripts[i] = script.copyWith(folderId: '', updatedAt: DateTime.now());
    }
    for (var i = 0; i < scriptWorkflows.length; i++) {
      final workflow = scriptWorkflows[i];
      if (!removedIds.contains(workflow.folderId)) {
        continue;
      }
      scriptWorkflows[i] = workflow.copyWith(
        folderId: '',
        updatedAt: DateTime.now(),
      );
    }
    cleanupAutomationCollections();
    scheduleStateSave();
    notifyState();
  }

  Set<String> _collectScriptFolderSubtree(String rootId) {
    final result = <String>{};
    final pending = <String>[rootId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!result.add(current)) {
        continue;
      }
      for (final folder in scriptFolders) {
        if (folder.parentId == current) {
          pending.add(folder.id);
        }
      }
    }
    return result;
  }

  List<ScriptWorkflowEntry> scriptWorkflowsForFolder(String folderId) {
    final normalized = folderId.trim();
    return scriptWorkflows
        .where((item) => item.folderId.trim() == normalized)
        .toList(growable: false);
  }

  ScriptWorkflowEntry? findScriptWorkflowById(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final workflow in scriptWorkflows) {
      if (workflow.id == normalized) {
        return workflow;
      }
    }
    return null;
  }

  void upsertScriptWorkflow(ScriptWorkflowEntry workflow) {
    final id = workflow.id.trim();
    final name = workflow.name.trim();
    var folderId = workflow.folderId.trim();
    if (id.isEmpty || name.isEmpty || workflow.nodes.isEmpty) {
      return;
    }
    final validScriptIds = scripts
        .map((item) => item.id.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final filteredNodes = workflow.nodes
        .where((n) => validScriptIds.contains(n.scriptId.trim()))
        .toList(growable: false);
    if (filteredNodes.isEmpty) {
      return;
    }
    if (folderId.isNotEmpty &&
        !scriptFolders.any((item) => item.id == folderId)) {
      folderId = '';
    }
    final now = DateTime.now();
    final normalized = workflow.copyWith(
      id: id,
      name: name,
      folderId: folderId,
      nodes: filteredNodes,
      updatedAt: now,
    );
    final index = scriptWorkflows.indexWhere((item) => item.id == id);
    if (index >= 0) {
      scriptWorkflows[index] = normalized;
    } else {
      scriptWorkflows.add(normalized);
    }
    cleanupAutomationCollections();
    scheduleStateSave();
    notifyState();
  }

  void removeScriptWorkflow(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return;
    }
    scriptWorkflows.removeWhere((item) => item.id == normalized);
    scheduleStateSave();
    notifyState();
  }

  List<ScriptBatchTemplate> scriptBatchTemplatesForScript(String scriptId) {
    final normalized = scriptId.trim();
    if (normalized.isEmpty) {
      return const <ScriptBatchTemplate>[];
    }
    return scriptBatchTemplates
        .where((item) => item.scriptId == normalized)
        .toList(growable: false);
  }

  void upsertScriptBatchTemplate(ScriptBatchTemplate template) {
    final scriptId = template.scriptId.trim();
    final name = template.name.trim();
    if (scriptId.isEmpty || name.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final normalized = template.copyWith(
      scriptId: scriptId,
      name: name,
      hostIds: template.hostIds
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false),
      retryPerHost: template.retryPerHost.clamp(1, 6),
      maxConcurrency: template.maxConcurrency.clamp(1, 8),
      updatedAt: now,
    );
    final index = scriptBatchTemplates.indexWhere(
      (item) => item.id == normalized.id,
    );
    if (index >= 0) {
      scriptBatchTemplates[index] = normalized;
    } else {
      scriptBatchTemplates.add(normalized);
    }
    scheduleStateSave();
    notifyState();
  }

  void removeScriptBatchTemplate(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return;
    }
    scriptBatchTemplates.removeWhere((item) => item.id == normalized);
    scheduleStateSave();
    notifyState();
  }

  List<ScriptTriggerEntry> scriptTriggersForScript(String scriptId) {
    final normalized = scriptId.trim();
    if (normalized.isEmpty) {
      return const <ScriptTriggerEntry>[];
    }
    return scriptTriggers
        .where((item) => item.scriptId == normalized)
        .toList(growable: false);
  }

  void upsertScriptTrigger(ScriptTriggerEntry trigger) {
    final scriptId = trigger.scriptId.trim();
    final name = trigger.name.trim();
    if (scriptId.isEmpty || name.isEmpty) {
      return;
    }
    final pattern = trigger.commandPattern.trim();
    final now = DateTime.now();
    final normalized = trigger.copyWith(
      scriptId: scriptId,
      name: name,
      commandPattern: pattern,
      hostIds: trigger.hostIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      retryPerHost: trigger.retryPerHost.clamp(1, 6),
      maxConcurrency: trigger.maxConcurrency.clamp(1, 8),
      cooldownSeconds: trigger.cooldownSeconds.clamp(0, 3600),
      updatedAt: now,
    );
    final index = scriptTriggers.indexWhere((item) => item.id == normalized.id);
    if (index >= 0) {
      scriptTriggers[index] = normalized;
    } else {
      scriptTriggers.add(normalized);
    }
    scheduleStateSave();
    notifyState();
  }

  void removeScriptTrigger(String triggerId) {
    final normalized = triggerId.trim();
    if (normalized.isEmpty) {
      return;
    }
    scriptTriggers.removeWhere((item) => item.id == normalized);
    scheduleStateSave();
    notifyState();
  }

  Future<void> runScriptTriggersForSessionConnected(
    TerminalSession session,
  ) async {
    await _runScriptTriggers(
      session: session,
      eventType: ScriptTriggerEventType.sessionConnected,
      command: null,
    );
  }

  Future<void> runScriptTriggersForCommandSubmitted(
    TerminalSession session,
    String command,
  ) async {
    await _runScriptTriggers(
      session: session,
      eventType: ScriptTriggerEventType.commandSubmitted,
      command: command,
    );
  }

  Future<void> _runScriptTriggers({
    required TerminalSession session,
    required ScriptTriggerEventType eventType,
    String? command,
  }) async {
    if (!sessions.contains(session)) {
      return;
    }
    if (scriptTriggers.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final triggerPool = scriptTriggers
        .where((trigger) {
          if (!trigger.enabled || trigger.eventType != eventType) {
            return false;
          }
          if (trigger.hostIds.isNotEmpty &&
              !trigger.hostIds.contains(session.profile.id)) {
            return false;
          }
          if (eventType == ScriptTriggerEventType.commandSubmitted) {
            return _matchTriggerCommand(trigger, command ?? '');
          }
          return true;
        })
        .toList(growable: false);
    if (triggerPool.isEmpty) {
      return;
    }
    final cooldownStore = _scriptTriggerCooldownStore[this] ??=
        <String, DateTime>{};
    for (final trigger in triggerPool) {
      final cooldownKey = '${trigger.id}::${session.id}';
      final lastAt = cooldownStore[cooldownKey];
      if (lastAt != null &&
          now.difference(lastAt).inSeconds < trigger.cooldownSeconds) {
        continue;
      }
      _logScriptTriggerHit(
        trigger: trigger,
        session: session,
        eventType: eventType,
        command: command,
      );
      await _executeScriptTrigger(trigger, session);
      cooldownStore[cooldownKey] = DateTime.now();
    }
  }

  bool _matchTriggerCommand(ScriptTriggerEntry trigger, String command) {
    final pattern = trigger.commandPattern.trim();
    final normalizedCommand = command.trim();
    if (pattern.isEmpty || normalizedCommand.isEmpty) {
      return false;
    }
    switch (trigger.matchType) {
      case ScriptTriggerMatchType.contains:
        return normalizedCommand.toLowerCase().contains(pattern.toLowerCase());
      case ScriptTriggerMatchType.regex:
        try {
          return RegExp(
            pattern,
            caseSensitive: false,
          ).hasMatch(normalizedCommand);
        } catch (_) {
          return false;
        }
    }
  }

  Future<void> _executeScriptTrigger(
    ScriptTriggerEntry trigger,
    TerminalSession session,
  ) async {
    if (trigger.executeAsMacro || session.profile.isSerial) {
      await runScriptAsMacroOnSession(
        scriptId: trigger.scriptId,
        session: session,
      );
      return;
    }
    if (session.profile.isLocal) {
      await runScriptOnTargets(
        scriptId: trigger.scriptId,
        hostIds: const <String>[],
        localShellTypes: <LocalShellType>[session.profile.localShellType],
        silentExecution: trigger.silentExecution,
        failurePolicy: trigger.failurePolicy,
        retryPerHost: trigger.retryPerHost,
        maxConcurrency: trigger.maxConcurrency,
      );
      return;
    }
    if (session.profile.isSsh) {
      await runScriptOnTargets(
        scriptId: trigger.scriptId,
        hostIds: <String>[session.profile.id],
        localShellTypes: const <LocalShellType>[],
        silentExecution: trigger.silentExecution,
        failurePolicy: trigger.failurePolicy,
        retryPerHost: trigger.retryPerHost,
        maxConcurrency: trigger.maxConcurrency,
      );
      return;
    }
    setError(
      AppStrings.values.scriptExecutionFailedVarVar.resolve(
        locale.languageCode,
        params: {'name': trigger.name, 'detail': 'Unsupported connection type'},
      ),
    );
  }

  void _logScriptTriggerHit({
    required ScriptTriggerEntry trigger,
    required TerminalSession session,
    required ScriptTriggerEventType eventType,
    String? command,
  }) {
    final eventLabel = eventType == ScriptTriggerEventType.sessionConnected
        ? AppStrings.values.scriptTriggerOnConnect.resolve(locale.languageCode)
        : AppStrings.values.scriptTriggerOnCommand.resolve(locale.languageCode);
    final scriptName = findScriptById(trigger.scriptId)?.name ?? trigger.name;
    final hostName = session.profile.name.trim().isEmpty
        ? session.profile.id
        : session.profile.name.trim();
    final commandSnippet = (command ?? '').trim();
    final commandDetail = commandSnippet.isEmpty
        ? ''
        : ' command="${commandSnippet.substring(0, commandSnippet.length.clamp(0, 80).toInt())}"';
    addStructuredLog(
      category: TerminalLogCategory.script,
      message:
          '[TriggerHit] trigger=${trigger.name} script=$scriptName event=$eventLabel host=$hostName$commandDetail',
      notifyListeners: false,
    );
  }
}
