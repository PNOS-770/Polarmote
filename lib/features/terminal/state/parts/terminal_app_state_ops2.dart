part of '../terminal_app_state.dart';

const Duration _stateSaveDebounce = Duration(milliseconds: 100);

extension TerminalAppStateOps2 on TerminalAppState {
  // === Logging ===

  String _l(AppText text, {Map<String, String> params = const {}}) => text.resolve(locale.languageCode, params: params);

  String _logCategoryLabel(TerminalLogCategory category) => switch (category) {
    TerminalLogCategory.startup => _l(AppStrings.values.logCategoryStartup),
    TerminalLogCategory.session => _l(AppStrings.values.logCategorySession),
    TerminalLogCategory.transfer => _l(AppStrings.values.logCategoryTransfer),
    TerminalLogCategory.externalEdit => _l(AppStrings.values.logCategoryExternalEdit),
    TerminalLogCategory.system => _l(AppStrings.values.logCategorySystem),
    TerminalLogCategory.ui => _l(AppStrings.values.logCategoryUi),
    TerminalLogCategory.script => _l(AppStrings.values.logCategoryScript),
  };

  String _logLevelPrefix(TerminalLogLevel level) => switch (level) { TerminalLogLevel.warn => _l(AppStrings.values.warning), TerminalLogLevel.error => _l(AppStrings.values.error), _ => '' };

  void addLog(String message, {bool notifyListeners = true}) {
    logController.addLog(message, notify: notifyListeners);
    if (notifyListeners) notifyState();
  }

  void addStructuredLog({required TerminalLogCategory category, required String message, TerminalLogLevel level = TerminalLogLevel.info, bool notifyListeners = true}) {
    if (_shouldSuppressLog(category, message, level)) return;
    final cl = _logCategoryLabel(category); final m = message.trim(); final lp = _logLevelPrefix(level);
    final p = m.isNotEmpty && m.startsWith(cl); final core = m.isEmpty ? cl : (p ? m : '$cl $m');
    final line = lp.isEmpty ? core : (m.isEmpty ? '$cl $lp' : (p ? '$cl $lp${m.substring(cl.length).trimLeft()}' : '$cl $lp$m'));
    addLog(line, notifyListeners: notifyListeners);
  }

  bool _shouldSuppressLog(TerminalLogCategory category, String message, TerminalLogLevel level) { return false; }

  List<String> get todayLogs => logController.todayLogs;

  Future<void> openLogFolder() => logController.openLogFolder();

  Future<void> openStateFolder() async { try { final f = await ensureStateFile(); await f.parent.create(recursive: true); await OpenFilex.open(f.parent.path); } catch (e) { PolarmoteLog.error('ops2', '$e'); } }

  Future<void> _initLogs() => logController.initialize();

  DateTime? _parseLogTimestamp(String line) {
    if (!line.startsWith('[')) return null;
    final end = line.indexOf(']'); if (end <= 1) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$').firstMatch(line.substring(1, end));
    if (m != null) return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), int.parse(m.group(4)!), int.parse(m.group(5)!));
    return DateTime.tryParse(line.substring(1, end));
  }

  String _formatLogTimestamp(DateTime v) => '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')} ${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
  String _compactLogMessage(String raw, {int max = 280}) { var n = raw.trim(); if (n.isEmpty) return ''; final s = n.indexOf('\n#0'); if (s > 0) n = n.substring(0, s).trim(); n = n.replaceAll('\r\n', ' | ').replaceAll('\n', ' | ').replaceAll('\r', ' | ').replaceAll(RegExp(r'\s+'), ' ').trim(); return n.length <= max ? n : '${n.substring(0, max)}...'; }

  // === Persistence ===
  void scheduleStateSave() { if (suspendStateSave) return; stateSaveTimer?.cancel(); stateSaveTimer = Timer(const Duration(milliseconds: 100), () => unawaited(_persistState())); }

  Future<void> _persistState() async {
    try { final f = await ensureStateFile(); final d = buildPortableState(includeSecrets: false); d.remove('commandHistoryByHost'); await f.writeAsString('${TerminalAppState._stateJsonEncoder.convert(d)}\n'); await _persistLargeData(); } catch (e) { PolarmoteLog.error('ops2', '$e'); }
  }

  Future<void> _persistLargeData() async {
    try { final b = await getApplicationSupportDirectory(); await File(p.join(b.path, 'Polarmote_large_data.json')).writeAsString('${TerminalAppState._stateJsonEncoder.convert({'commandHistoryByHost': commandHistoryByHost.map((k, v) => MapEntry(k, List<String>.from(v)))})}\n'); } catch (e) { PolarmoteLog.error('ops2', '$e'); }
  }

  Future<void> _loadLargeData() async {
    try {
      final f = File(p.join((await getApplicationSupportDirectory()).path, 'Polarmote_large_data.json'));
      if (!await f.exists()) return;
      final d = jsonDecode(await f.readAsString());
      if (d is! Map<String, dynamic>) return;
      final h = d['commandHistoryByHost'];
      if (h is Map) { commandHistoryByHost.clear(); for (final e in h.entries) { final k = e.key?.toString().trim() ?? ''; if (k.isEmpty || e.value is! List) continue; final items = (e.value as List).map((x) => x?.toString().trim() ?? '').where((x) => x.isNotEmpty).toList(); if (items.isNotEmpty) commandHistoryByHost[k] = items; } }
    } catch (e) { PolarmoteLog.error('ops2', '$e'); }
  }

  Map<String, dynamic>? settingsOrNull(Map<String, dynamic> data) { final s = data['settings']; if (s is Map<String, dynamic>) return s; if (s is Map) { final m = <String, dynamic>{}; s.forEach((k, v) => m['$k'] = v); return m; } return null; }

  Future<void> _loadState() async {
    try { final f = await ensureStateFile(); if (!await f.exists()) return; final raw = await f.readAsString(); if (raw.trim().isEmpty) return; final d = jsonDecode(raw); if (d is Map<String, dynamic>) await _loadStateFromData(d); } catch (e) { PolarmoteLog.error('ops2', '$e'); }
  }

  Future<void> _loadStateFromData(Map<String, dynamic> data) async {
    final settings = settingsOrNull(data);
    if (settings != null) _loadSettings(settings);
    if (data['hosts'] is List) { hosts.clear(); for (final e in data['hosts'] as List) { if (e is Map<String, dynamic>) hosts.add(HostEntry.fromJson(e)); } }
    if (data['scripts'] is List) { scripts.clear(); for (final e in data['scripts'] as List) { if (e is Map<String, dynamic>) scripts.add(ScriptEntry.fromJson(e)); } }
    if (data['scriptFolders'] is List) { scriptFolders.clear(); for (final e in data['scriptFolders'] as List) { if (e is Map<String, dynamic>) scriptFolders.add(ScriptFolderEntry.fromJson(e)); } }
    if (data['scriptWorkflows'] is List) { scriptWorkflows.clear(); for (final e in data['scriptWorkflows'] as List) { if (e is Map<String, dynamic>) scriptWorkflows.add(ScriptWorkflowEntry.fromJson(e)); } }
    if (data['scriptBatchTemplates'] is List) { scriptBatchTemplates.clear(); for (final e in data['scriptBatchTemplates'] as List) { if (e is Map<String, dynamic>) scriptBatchTemplates.add(ScriptBatchTemplate.fromJson(e)); } }
    if (data['scriptTriggers'] is List) { scriptTriggers.clear(); for (final e in data['scriptTriggers'] as List) { if (e is Map<String, dynamic>) scriptTriggers.add(ScriptTriggerEntry.fromJson(e)); } }
    if (data['portForwards'] is List) { portForwards.clear(); for (final e in data['portForwards'] as List) { if (e is Map<String, dynamic>) portForwards.add(PortForwardEntry.fromJson(e)); } }
    if (data['portForwardTemplates'] is List) { portForwardTemplates.clear(); for (final e in data['portForwardTemplates'] as List) { if (e is Map<String, dynamic>) portForwardTemplates.add(PortForwardTemplate.fromJson(e)); } }
    if (data['knownHostFingerprints'] is Map) { knownHostFingerprints.clear(); (data['knownHostFingerprints'] as Map).forEach((k, v) => knownHostFingerprints[k.toString()] = v.toString()); }
    if (data['pinnedHostIds'] is List) { pinnedHostIds.clear(); for (final id in data['pinnedHostIds'] as List) pinnedHostIds.add(id.toString()); }
    expandedSessionFolderKeys.clear(); sessionFolderExpansionConfigured = false;
    if (data['visitedFiles'] is List) { visitedFiles.clear(); for (final e in data['visitedFiles'] as List) { if (e is Map<String, dynamic>) visitedFiles.add(VisitedFileEntry.fromJson(e)); } }
    if (data['scriptRunHistory'] is List) { scriptRunHistory.clear(); for (final e in data['scriptRunHistory'] as List) { if (e is Map<String, dynamic>) scriptRunHistory.add(ScriptHostRunRecord.fromJson(e)); } }
    if (data['scriptShortcutBindings'] is Map) { scriptShortcutBindings.clear(); (data['scriptShortcutBindings'] as Map).forEach((k, v) => scriptShortcutBindings[k.toString()] = v.toString()); }
    if (data['scriptSchedules'] is List) { scriptSchedules.clear(); for (final e in data['scriptSchedules'] as List) { if (e is Map<String, dynamic>) scriptSchedules.add(ScriptScheduleEntry.fromJson(e)); } }
    await _loadLargeData(); await _synchronizeHostSecrets(); startAutoPortForwards();
  }

  void _loadSettings(Map<String, dynamic> settings) {
    autoReconnect = settings['autoReconnect'] as bool? ?? true;
    confirmPaste = settings['confirmPaste'] as bool? ?? true;
    showHiddenFiles = settings['showHiddenFiles'] as bool? ?? true;
    terminalSplitViewEnabled = settings['terminalSplitViewEnabled'] as bool? ?? false;
    terminalSplitPrimaryRatio = (_parseDouble(settings['terminalSplitPrimaryRatio']) ?? 0.5).clamp(0.2, 0.8).toDouble();
    terminalSplitSecondaryRatio = (_parseDouble(settings['terminalSplitSecondaryRatio']) ?? 0.5).clamp(0.2, 0.8).toDouble();
    transferAutoRetryEnabled = settings['transferAutoRetryEnabled'] as bool? ?? true;
    transferResumeEnabled = settings['transferResumeEnabled'] as bool? ?? true;
    transferRetryMaxAttempts = int.tryParse(settings['transferRetryMaxAttempts']?.toString() ?? '')?.clamp(1, 20) ?? 3;
    transferRetryBaseDelayMs = int.tryParse(settings['transferRetryBaseDelayMs']?.toString() ?? '')?.clamp(100, 60000) ?? 800;
    transferRetryMaxDelayMs = int.tryParse(settings['transferRetryMaxDelayMs']?.toString() ?? '')?.clamp(1000, 120000) ?? 10000;
    logVerbosity = switch (settings['logVerbosity'] as int? ?? 1) { 0 => LogVerbosity.all, 2 => LogVerbosity.errorsOnly, _ => LogVerbosity.important };
    memoryMode = switch (settings['memoryMode'] as int? ?? 1) { 0 => MemoryMode.low, 1 => MemoryMode.medium, 2 => MemoryMode.high, 3 => MemoryMode.custom, _ => MemoryMode.medium };
    smartMemoryManagement = settings['smartMemoryManagement'] as bool? ?? true;
    stageManagerEnabled = true;

    if (settings['globalAppearance'] is Map) {
      globalAppearance = TerminalAppearanceProfile.fromJson(
        settings['globalAppearance'] as Map<String, dynamic>,
      );
    }
    if (settings['terminalBackgroundImages'] is List) {
      terminalBackgroundImages.clear();
      for (final e in settings['terminalBackgroundImages'] as List) {
        if (e is Map<String, dynamic>) {
          terminalBackgroundImages.add(BackgroundImageEntry.fromJson(e));
        }
      }
    }
    terminalBackgroundOpacity = _parseDouble(settings['terminalBackgroundOpacity']) ?? 0.15;
    showThumbnailBackground = settings['showThumbnailBackground'] as bool? ?? true;
    activeTerminalStageId = settings['activeTerminalStageId']?.toString() ?? '';
    if (settings['terminalStages'] is List) {
      terminalStages.clear();
      for (final e in settings['terminalStages'] as List) {
        if (e is Map<String, dynamic>) {
          terminalStages.add(TerminalStage.fromJson(e));
        }
      }
    }
    if (settings['terminalSplitPanes'] is List) {
      terminalSplitPanes.clear();
      for (final e in settings['terminalSplitPanes'] as List) {
        if (e is Map<String, dynamic>) {
          terminalSplitPanes.add(TerminalSplitPaneConfig.fromJson(e));
        }
      }
    }
    activeTerminalSplitPaneId = settings['activeTerminalSplitPaneId']?.toString() ?? '';
    maximizedTerminalSplitPaneId = settings['maximizedTerminalSplitPaneId']?.toString() ?? '';
    final localeCode = settings['locale']?.toString();
    if (localeCode != null && localeCode.trim().isNotEmpty) {
      locale = Locale(localeCode.trim());
    }
    mobileSidebarWidth = _parseDouble(settings['mobileSidebarWidth']) ?? TerminalAppState.mobileSidebarWidthDefault;
    terminalHorizontalScrollEnabled = settings['terminalHorizontalScrollEnabled'] as bool? ?? false;
    mobileTerminalColumns = int.tryParse(settings['mobileTerminalColumns']?.toString() ?? '')?.clamp(
      TerminalAppState.mobileTerminalColumnsMin, TerminalAppState.mobileTerminalColumnsMax,
    ) ?? TerminalAppState.mobileTerminalColumnsMin;
    terminalAccessibilitySemanticsEnabled = settings['terminalAccessibilitySemanticsEnabled'] as bool? ?? false;
    reuseSessionForNewPane = settings['reuseSessionForNewPane'] as bool? ?? false;
    terminalBlockSelectEnabled = settings['terminalBlockSelectEnabled'] as bool? ?? false;
    if (settings['performanceSettings'] is Map) {
      performanceSettings = TerminalPerformanceSettings.fromJson(
        settings['performanceSettings'] as Map<String, dynamic>,
      );
    }
    androidKeepSshAliveInBackground = settings['androidKeepSshAliveInBackground'] as bool? ?? Platform.isAndroid;
    sessionQuery = settings['sessionQuery']?.toString() ?? '';
    sessionSortMode = SessionSortMode.values.firstWhere(
      (e) => e.name == settings['sessionSortMode']?.toString(),
      orElse: () => SessionSortMode.smart,
    );
    settingsTabIndex = int.tryParse(settings['settingsTabIndex']?.toString() ?? '') ?? 0;
    customTerminalBufferSize = int.tryParse(settings['customTerminalBufferSize']?.toString() ?? '')?.clamp(1000, 50000) ?? 5000;
    if (settings['customKeyBindings'] is List) {
      customKeyBindings.clear();
      for (final e in settings['customKeyBindings'] as List) {
        if (e is Map<String, dynamic>) {
          customKeyBindings.add(KeyBinding.fromJson(e));
        }
      }
    }
    if (settings['shortcutBindings'] is List) {
      final loaded = <ShortcutBinding>[];
      for (final e in settings['shortcutBindings'] as List) {
        if (e is Map<String, dynamic>) {
          loaded.add(ShortcutBinding.fromJson(e));
        }
      }
      if (loaded.isNotEmpty) {
        shortcutBindings.clear();
        shortcutBindings.addAll(loaded);
      }
    }
  }

  double? _parseDouble(dynamic v) { if (v == null) return null; final d = double.tryParse(v.toString()); return d?.isFinite == true ? d : null; }
  Map<String, dynamic> _buildStateJson() => buildPortableState(includeSecrets: false);

  Future<File> ensureStateFile() async { if (stateFile != null) return stateFile!; final base = await getApplicationSupportDirectory(); stateFile = File(p.join(base.path, 'Polarmote_state.json')); return stateFile!; }

  Map<String, dynamic> buildPortableState({required bool includeSecrets}) => {
    'settings': <String, dynamic>{
      'autoReconnect': autoReconnect, 'confirmPaste': confirmPaste, 'showHiddenFiles': showHiddenFiles,
      'locale': locale.languageCode,
      'terminalSplitViewEnabled': terminalSplitViewEnabled, 'terminalSplitPanes': terminalSplitPanes.map((p) => p.toJson()).toList(),
      'activeTerminalSplitPaneId': activeTerminalSplitPaneId, 'maximizedTerminalSplitPaneId': maximizedTerminalSplitPaneId,
      'terminalSplitPrimaryRatio': terminalSplitPrimaryRatio, 'terminalSplitSecondaryRatio': terminalSplitSecondaryRatio,
      'mobileSidebarWidth': mobileSidebarWidth, 'terminalHorizontalScrollEnabled': terminalHorizontalScrollEnabled,
      'mobileTerminalColumns': mobileTerminalColumns, 'terminalAccessibilitySemanticsEnabled': terminalAccessibilitySemanticsEnabled,
      'transferAutoRetryEnabled': transferAutoRetryEnabled, 'transferResumeEnabled': transferResumeEnabled,
      'transferRetryMaxAttempts': transferRetryMaxAttempts, 'transferRetryBaseDelayMs': transferRetryBaseDelayMs,
      'transferRetryMaxDelayMs': transferRetryMaxDelayMs, 'performanceSettings': performanceSettings.toJson(),
      'androidKeepSshAliveInBackground': androidKeepSshAliveInBackground,
      'sessionQuery': sessionQuery, 'sessionSortMode': sessionSortMode.name, 'settingsTabIndex': settingsTabIndex,
      'globalAppearance': globalAppearance.toJson(), 'terminalBackgroundImages': terminalBackgroundImages.map((e) => e.toJson()).toList(),
      'terminalBackgroundOpacity': terminalBackgroundOpacity, 'showThumbnailBackground': showThumbnailBackground, 'reuseSessionForNewPane': reuseSessionForNewPane,
      'terminalBlockSelectEnabled': terminalBlockSelectEnabled, 'logVerbosity': logVerbosity.index,
      'memoryMode': memoryMode.index, 'customTerminalBufferSize': customTerminalBufferSize,
      'smartMemoryManagement': smartMemoryManagement, 'customKeyBindings': customKeyBindings.map((k) => k.toJson()).toList(),
      'shortcutBindings': shortcutBindings.map((s) => s.toJson()).toList(),
      'activeTerminalStageId': activeTerminalStageId, 'terminalStages': terminalStages.map((s) => s.toJson()).toList(),
    },
    'hosts': hosts.map((h) => h.toJson(includeSecrets: includeSecrets)).toList(),
    'scripts': scripts.map((s) => s.toJson()).toList(), 'scriptFolders': scriptFolders.map((s) => s.toJson()).toList(),
    'scriptWorkflows': scriptWorkflows.map((s) => s.toJson()).toList(), 'scriptBatchTemplates': scriptBatchTemplates.map((s) => s.toJson()).toList(),
    'scriptTriggers': scriptTriggers.map((s) => s.toJson()).toList(), 'portForwards': portForwards.map((p) => p.toJson()).toList(),
    'portForwardTemplates': portForwardTemplates.map((p) => p.toJson()).toList(),
    'knownHostFingerprints': Map<String, String>.from(knownHostFingerprints), 'pinnedHostIds': pinnedHostIds.toList(),
    'visitedFiles': visitedFiles.map((v) => v.toJson()).toList(), 'scriptRunHistory': <Map<String, dynamic>>[],
    'scriptShortcutBindings': Map<String, String>.from(scriptShortcutBindings),
    'scriptSchedules': scriptSchedules.map((s) => s.toJson()).toList(), 'commandHistoryByHost': commandHistoryByHost,
    if (includeSecrets) 'hostSecrets': <String, dynamic>{},
  };

  // === Startup ===
  Future<void> _bootstrapStartupLogs() async {
    final sw = Stopwatch()..start();
    await _restoreLocaleForStartupLogs();
    await _initLogs();
    addStructuredLog(category: TerminalLogCategory.startup, message: _l(AppStrings.values.startupBegan), notifyListeners: false);
    await _runStartupSection(AppStrings.values.startupSectionVersionInfo, _logStartupVersionInfo);
    await _runStartupSection(AppStrings.values.startupSectionTransferProbe, _logStartupTransferInfo);
    sw.stop();
    addStructuredLog(category: TerminalLogCategory.startup, message: AppStrings.values.startupFinishedVarMs.resolve(locale.languageCode, params: {'ms': '${sw.elapsedMilliseconds}'}), notifyListeners: false);
    startMemoryMonitoring();
  }

  Future<void> _restoreLocaleForStartupLogs() async {
    try { final f = await ensureStateFile(); if (!await f.exists()) return; final d = jsonDecode(await f.readAsString()); if (d is Map<String, dynamic> && d['settings'] is Map<String, dynamic>) { final lc = (d['settings'] as Map<String, dynamic>)['locale']?.toString(); if (lc != null && lc.trim().isNotEmpty) locale = Locale(lc.trim()); } } catch (e) { PolarmoteLog.error('ops2', '$e'); }
  }

  Future<void> _runStartupSection(AppText section, Future<void> Function() action) async {
    final sw = Stopwatch()..start();
    try { await action(); } catch (error) { sw.stop(); try { _addStartupStructuredLog(section, _l(AppStrings.values.startupSectionErrorDurationVarVar, params: {'error': '$error', 'elapsedMs': '${sw.elapsedMilliseconds}'}), level: TerminalLogLevel.error); } catch (e) { PolarmoteLog.error('ops2', '$e'); } }
  }

  void _addStartupStructuredLog(AppText section, String msg, {TerminalLogLevel level = TerminalLogLevel.info}) { try { addStructuredLog(category: TerminalLogCategory.startup, message: msg, level: level, notifyListeners: false); } catch (e) { PolarmoteLog.error('ops2', '$e'); } }

  Future<void> _logStartupVersionInfo() async {
    if (TerminalAppState._explicitAppVersion.trim().isNotEmpty) return;
    try { await PackageInfo.fromPlatform(); } catch (error) { _addStartupStructuredLog(AppStrings.values.startupSectionVersionInfo, AppStrings.values.versionReadFailedVar.resolve(locale.languageCode, params: {'error': '$error'}), level: TerminalLogLevel.error); }
  }

  Future<void> _logStartupTransferInfo() async {
    final bridge = NativeTransferBridge.instance;
    if (!bridge.isSupported) { _addStartupStructuredLog(AppStrings.values.startupSectionTransferProbe, _l(AppStrings.values.transferEngineUnavailable)); return; }
    _addStartupStructuredLog(AppStrings.values.startupSectionTransferProbe, _l(AppStrings.values.transferEngineReady));
  }
}

