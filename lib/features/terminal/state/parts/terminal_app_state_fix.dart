part of '../terminal_app_state.dart';

extension TerminalAppStateFix on TerminalAppState {
  void updateHost(HostEntry host) {
    final i = hosts.indexWhere((e) => e.id == host.id);
    if (i == -1) return; hosts[i] = host;
    unawaited(_writeHostSecret(host));
    scheduleStateSave(); notifyState();
  }

  void renameSessionTab(TerminalSession s, String title) { s.tab = s.tab.copyWith(title: title); scheduleStateSave(); notifyState(); }
  void removeVisitedFile(VisitedFileEntry e) { visitedFiles.removeWhere((x) => x.dedupeKey == e.dedupeKey); scheduleStateSave(); notifyState(); }
  void clearVisitedFiles() { visitedFiles.clear(); scheduleStateSave(); notifyState(); }

  void removeScriptEntry(String id) {
    scripts.removeWhere((e) => e.id == id);
    unbindScriptShortcut(id);
    scriptWorkflows.removeWhere((w) => w.nodes.any((n) => n.scriptId == id));
    scheduleStateSave(); notifyState();
  }
  void dismissFinishedScriptRuns() {
    final f = activeScriptRuns.entries.where((e) => e.value.isFinished).map((e) => e.key).toList();
    for (final id in f) { activeScriptRuns.remove(id); if (focusedScriptRunId == id) focusedScriptRunId = null; }
    if (f.isNotEmpty) notifyState();
  }
  void cancelScriptRun(String runId) { final s = activeScriptRuns[runId]; if (s == null) return; s.cancel(); activeScriptRuns.remove(runId); notifyState(); }
  void dismissScriptRun(String runId) { activeScriptRuns.remove(runId); if (focusedScriptRunId == runId) focusedScriptRunId = null; notifyState(); }
  void toggleScriptMonitorInline() { showScriptMonitorInline = !showScriptMonitorInline; notifyState(); }
  void triggerScriptMultiSelect() { scriptMultiSelectActive = !scriptMultiSelectActive; scriptMultiSelectToken++; notifyState(); }

  TerminalSession? terminalSessionById(String id) { for (final s in sessions) { if (s.id == id) return s; } return null; }
  TerminalSession? findSessionById(String id) { for (final s in sessions) { if (s.id == id) return s; } return null; }
  bool isSessionFolderExpanded(String k) => expandedSessionFolderKeys.contains(k);
  int sessionFolderHostCount(String k) => hosts.where((h) => h.group == k).length;
  void deleteSessionFolder(String k) { hosts.removeWhere((h) => h.group == k); expandedSessionFolderKeys.remove(k); scheduleStateSave(); notifyState(); }
  void clearHostSelection() { if (selectedHostIds.isEmpty) return; selectedHostIds.clear(); notifyState(); }

  void disposeExternalEdit(String p) {
    externalEditDebounceTimers[p]?.cancel(); externalEditDebounceTimers.remove(p);
    externalEditSubscriptions[p]?.cancel(); externalEditSubscriptions.remove(p);
    externalEdits.remove(p);
  }
  void disposeExternalEditsForSession(String sid) { for (final p in externalEdits.entries.where((e) => e.value.sessionId == sid).map((e) => e.key).toList()) { disposeExternalEdit(p); } }
  void disposeAllExternalEdits() { for (final p in externalEdits.keys.toList()) { disposeExternalEdit(p); } }

  // === Stage Manager ===
  void ensureTerminalSplitPanes() {
    if (terminalSplitPanes.isNotEmpty) return;
    terminalSplitPanes.add(TerminalSplitPaneConfig(id: 'pane-0', sessionId: activeSession?.id ?? ''));
    activeTerminalSplitPaneId = 'pane-0';
  }
  String _newTerminalStageId() => 'stage-${_terminalStageIdSeed++}';

  void createTerminalStage(String name, {List<String>? sessionIds, List<String>? connectedHostIds}) {
    String id; do { id = _newTerminalStageId(); } while (_stageById(id) != null);
    terminalStages.add(TerminalStage(id: id, name: name, sessionIds: sessionIds ?? const [], connectedHostIds: connectedHostIds ?? const [], createdAt: DateTime.now()));
    switchTerminalStage(id);
  }

  void switchTerminalStage(String stageId) {
    final stage = _stageById(stageId);
    if (stage == null || activeTerminalStageId == stageId) return;
    activeTerminalStageId = stageId;
    activeSessionIndexValue = -1;
    for (final sid in stage.sessionIds) { final i = sessions.indexWhere((s) => s.id == sid); if (i >= 0) { activeSessionIndexValue = i; break; } }
    scheduleStateSave(); notifyState();
  }

  void removeStageById(String stageId) {
    if (terminalStages.length <= 1) return;
    final i = terminalStages.indexWhere((s) => s.id == stageId);
    if (i < 0) return;
    for (final sid in terminalStages[i].sessionIds.toList()) { closeSession(sid); }
    terminalStages.removeAt(i);
    if (activeTerminalStageId == stageId) activeTerminalStageId = terminalStages.isNotEmpty ? terminalStages.first.id : '';
    scheduleStateSave(); notifyState();
  }

  void renameStage(String stageId, String newName) {
    final i = terminalStages.indexWhere((s) => s.id == stageId);
    if (i < 0) return;
    terminalStages[i] = terminalStages[i].copyWith(name: newName);
    stageChangeToken++; scheduleStateSave(); notifyState();
  }

  void toggleStageManager() { stageManagerEnabled = !stageManagerEnabled; scheduleStateSave(); notifyState(); }
  void setBroadcastEnabled(bool v) { broadcastEnabled = v; scheduleStateSave(); notifyState(); }
  void toggleBroadcast() { broadcastEnabled = !broadcastEnabled; notifyState(); }

  void toggleMaximizedTerminalSplitPane(String pId) {
    ensureTerminalSplitPanes();
    maximizedTerminalSplitPaneId = maximizedTerminalSplitPaneId == pId ? '' : pId;
  }

  void setTerminalSplitPaneSession(String pId, String sId) {
    ensureTerminalSplitPanes();
    final i = terminalSplitPanes.indexWhere((p) => p.id == pId);
    if (i < 0) return;
    terminalSplitPanes[i] = terminalSplitPanes[i].copyWith(sessionId: sId);
    scheduleStateSave(); notifyState();
  }

  void clearTerminalSplitPane(String pId) {
    ensureTerminalSplitPanes();
    final i = terminalSplitPanes.indexWhere((p) => p.id == pId);
    if (i < 0) return;
    terminalSplitPanes[i] = terminalSplitPanes[i].copyWith(sessionId: '');
    scheduleStateSave(); notifyState();
  }

  void removeTerminalSplitPane(String pId) {
    ensureTerminalSplitPanes();
    if (terminalSplitPanes.length <= 1) { clearTerminalSplitPane(pId); return; }
    terminalSplitPanes.removeWhere((p) => p.id == pId);
    if (activeTerminalSplitPaneId == pId) activeTerminalSplitPaneId = terminalSplitPanes.isEmpty ? '' : terminalSplitPanes.first.id;
    scheduleStateSave(); notifyState();
  }

  TerminalStage? _stageById(String id) { try { return terminalStages.firstWhere((s) => s.id == id); } catch (_) { return null; } }

  // === Script ===
  void addScript(String value) {
    final t = value.trim(); if (t.isEmpty) return;
    final now = DateTime.now();
    scripts.add(ScriptEntry(id: 'script-${now.microsecondsSinceEpoch}', name: t, commands: [t], createdAt: now, updatedAt: now));
    scheduleStateSave(); notifyState();
  }

  void addScriptEntry({required String name, required List<String> commands, String folderId = '', List? stepConfigs, Map<String, String>? variables, Map<String, String>? environment}) {
    final nn = name.trim(); final nc = commands.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    if (nn.isEmpty || nc.isEmpty) return;
    final now = DateTime.now();
    scripts.add(ScriptEntry(id: 'script-${now.microsecondsSinceEpoch}', name: nn, folderId: folderId.trim(), commands: nc, createdAt: now, updatedAt: now));
    scheduleStateSave(); notifyState();
  }

  void updateScriptEntry(String id, {required String name, required List<String> commands, String folderId = '', List? stepConfigs, Map<String, String>? variables, Map<String, String>? environment}) {
    final i = scripts.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final nn = name.trim(); final nc = commands.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    if (nn.isEmpty || nc.isEmpty) return;
    scripts[i] = scripts[i].copyWith(name: nn, folderId: folderId.trim(), commands: nc, updatedAt: DateTime.now());
    scheduleStateSave(); notifyState();
  }

  void moveScriptEntry(int from, int to) {
    if (from < 0 || from >= scripts.length) return;
    final target = to.clamp(0, scripts.length);
    if (from == target || from + 1 == target) return;
    final item = scripts.removeAt(from);
    scripts.insert(target > from ? target - 1 : target, item);
    scheduleStateSave(); notifyState();
  }

  String get nextScriptRunId { _nextScriptRunId++; return 'run-${DateTime.now().microsecondsSinceEpoch}-$_nextScriptRunId'; }
}

