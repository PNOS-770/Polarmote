part of '../terminal_app_state.dart';

const Duration _hostKeyPromptTimeout = Duration(minutes: 3);
const Duration _errorCooldownDuration = Duration(seconds: 5);
const int _maxPreviewScrollOffsets = 240;
const int _previewScrollOffsetCleanup = 40;
const Duration _sessionProbeTimeout = Duration(seconds: 4);
const int _sessionProbeMaxConcurrency = 10;

extension TerminalAppStateOps on TerminalAppState {
  // === State Export/Import ===

  Future<void> exportPortableStateToPath(String path, {String? masterPassword}) async {
    try {
      final data = _buildPortableStateData(includeSecrets: false);
      if (masterPassword != null && masterPassword.isNotEmpty) {
        final secrets = <String, Map<String, dynamic>>{};
        for (final host in hosts) {
          final stored = await readHostSecret(host.id);
          if (stored != null) secrets[host.id] = stored.toJson();
        }
        if (secrets.isNotEmpty) data['encryptedSecrets'] = SecretEncryption.encryptSecrets(secrets: secrets, password: masterPassword);
      }
      await File(path).writeAsString(TerminalAppState._stateJsonEncoder.convert(data));
    } catch (error) { addLog('Export failed: $error'); }
  }

  Future<void> importHostSecretsFromData(Map<String, dynamic> secrets) async {
    for (final entry in secrets.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      try {
        final stored = StoredHostSecret.fromJson(entry.value as Map<String, dynamic>);
        final key = _secureHostSecretKey(entry.key);
        if ((stored.password ?? '').trim().isEmpty && (stored.privateKeyPath ?? '').trim().isEmpty && (stored.privateKeyPassphrase ?? '').trim().isEmpty && (stored.socksProxyPassword ?? '').trim().isEmpty) {
          await _secureStorage.delete(key: key);
        } else {
          await _secureStorage.write(key: key, value: jsonEncode(stored.toJson()));
        }
      } catch (e) { PolarmoteLog.error('ops', '$e'); }
    }
  }

  Future<void> importPortableStateFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      decoded.remove('encryptedSecrets');
      await _loadStateFromData(decoded);
      scheduleStateSave();
      notifyState();
    } catch (error) { addLog('Import failed: $error'); }
  }

  Future<void> createPortableStateSnapshot() async {
    try {
      final base = await getApplicationSupportDirectory();
      final snapshotDir = Directory(p.join(base.path, 'snapshots'));
      if (!await snapshotDir.exists()) await snapshotDir.create(recursive: true);
      final timestamp = DateTime.now();
      final id = 'snap-${timestamp.millisecondsSinceEpoch}';
      final file = File(p.join(snapshotDir.path, '$id.json'));
      final data = _buildPortableStateData(includeSecrets: false);
      await file.writeAsString(TerminalAppState._stateJsonEncoder.convert(data));
      portableStateSnapshots.add(PortableStateSnapshot(id: id, createdAt: timestamp, label: 'Snapshot ${portableStateSnapshots.length + 1}', path: file.path));
      notifyState();
    } catch (e) { PolarmoteLog.error('ops', '$e'); }
  }

  Future<List<PortableStateSnapshot>> refreshPortableStateSnapshots() async {
    try {
      final base = await getApplicationSupportDirectory();
      final snapshotDir = Directory(p.join(base.path, 'snapshots'));
      if (!await snapshotDir.exists()) return [];
      final results = <PortableStateSnapshot>[];
      final files = await snapshotDir.list().toList();
      for (final entry in files) {
        if (entry is File && entry.path.endsWith('.json')) {
          final stat = await entry.stat();
          results.add(PortableStateSnapshot(id: p.basenameWithoutExtension(entry.path), createdAt: stat.modified, label: p.basenameWithoutExtension(entry.path), path: entry.path));
        }
      }
      results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      portableStateSnapshots..clear()..addAll(results);
      await _loadPortableSnapshotMetas();
      notifyState();
      return results;
    } catch (_) { return []; }
  }

  Future<void> rollbackPortableStateSnapshot(String snapshotId) async {
    for (final snap in portableStateSnapshots) {
      if (snap.id == snapshotId && snap.path.isNotEmpty) {
        await importPortableStateFromPath(snap.path);
        return;
      }
    }
  }

  Future<void> deletePortableStateSnapshot(String snapshotId) async {
    for (final snap in portableStateSnapshots.toList()) {
      if (snap.id == snapshotId) {
        if (snap.path.isNotEmpty) { try { await File(snap.path).delete(); } catch (e) { PolarmoteLog.error('ops', '$e'); } }
        portableStateSnapshots.remove(snap);
        notifyState();
        return;
      }
    }
  }

  Future<void> updatePortableStateSnapshotMeta(String snapshotId, {required String label, String? description}) async {
    final snap = portableStateSnapshots.where((s) => s.id == snapshotId).firstOrNull;
    if (snap == null) return;
    snap.label = label;
    if (description != null) snap.description = description;
    await _savePortableSnapshotMeta(snap);
    notifyState();
  }

  Future<void> _savePortableSnapshotMeta(PortableStateSnapshot snap) async {
    try { await File('${snap.path}.meta.json').writeAsString(TerminalAppState._stateJsonEncoder.convert(snap.toJson())); } catch (e) { PolarmoteLog.error('ops', '$e'); }
  }

  Future<void> _loadPortableSnapshotMetas() async {
    for (final snap in portableStateSnapshots) {
      try {
        final metaFile = File('${snap.path}.meta.json');
        if (await metaFile.exists()) {
          final data = const JsonDecoder().convert(await metaFile.readAsString()) as Map<String, dynamic>;
          snap.label = data['label']?.toString() ?? snap.label;
          snap.description = data['description']?.toString();
        }
      } catch (e) { PolarmoteLog.error('ops', '$e'); }
    }
  }

  Map<String, dynamic> _buildPortableStateData({required bool includeSecrets}) {
    final data = _buildStateJson();
    if (!includeSecrets) data.remove('hostSecrets');
    return data;
  }

  // === File Preview ===

  double? filePreviewScrollOffsetForKey(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty) return null;
    final value = filePreviewScrollOffsets[normalized];
    if (value == null) return null;
    if (!value.isFinite || value < 0) return 0;
    return value;
  }

  void setFilePreviewScrollOffsetForKey(String key, double offset) {
    final normalized = key.trim();
    if (normalized.isEmpty) return;
    final safe = offset.isFinite && offset > 0 ? offset : 0.0;
    final existing = filePreviewScrollOffsets[normalized];
    if (existing != null && (existing - safe).abs() < 0.5) return;
    filePreviewScrollOffsets[normalized] = safe;
    if (filePreviewScrollOffsets.length > 240) {
      for (final k in filePreviewScrollOffsets.keys.take(40).toList()) filePreviewScrollOffsets.remove(k);
    }
    scheduleStateSave();
  }

  // === Script Shortcuts ===

  String? scriptIdForShortcut(String shortcut) {
    final key = shortcut.trim();
    return key.isEmpty ? null : scriptShortcutBindings[key];
  }

  String? shortcutForScript(String scriptId) {
    final id = scriptId.trim();
    if (id.isEmpty) return null;
    for (final entry in scriptShortcutBindings.entries) {
      if (entry.value == id) return entry.key;
    }
    return null;
  }

  void bindScriptShortcut({required String scriptId, required String shortcut}) {
    final id = scriptId.trim();
    final key = shortcut.trim();
    if (id.isEmpty || key.isEmpty) return;
    scriptShortcutBindings.removeWhere((existingKey, existingId) => existingId == id || existingKey == key);
    scriptShortcutBindings[key] = id;
    scheduleStateSave();
    notifyState();
  }

  void unbindScriptShortcut(String scriptId) {
    final id = scriptId.trim();
    if (id.isEmpty) return;
    final before = scriptShortcutBindings.length;
    scriptShortcutBindings.removeWhere((_, existingId) => existingId == id);
    if (scriptShortcutBindings.length != before) { scheduleStateSave(); notifyState(); }
  }

  // === Session Probing ===

  SessionProbeState? sessionProbeStateForHost(String hostId) => sessionProbeStates[hostId];

  void ensureSessionProbeRuntime() {
    if (_sessionProbeTimer != null) return;
    _sessionProbeTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tickSessionProbes());
    _tickSessionProbes();
  }

  void _tickSessionProbes() {
    if (hosts.isEmpty) { sessionProbeStates.clear(); _sessionProbeNextAt.clear(); _sessionProbeFailures.clear(); return; }
    final hostIdSet = hosts.map((host) => host.id).toSet();
    sessionProbeStates.removeWhere((id, _) => !hostIdSet.contains(id));
    _sessionProbeNextAt.removeWhere((id, _) => !hostIdSet.contains(id));
    _sessionProbeFailures.removeWhere((id, _) => !hostIdSet.contains(id));
    if (_sessionProbesInFlight.length >= _sessionProbeMaxConcurrency) return;
    final now = DateTime.now();
    final dueHosts = <HostEntry>[];
    for (final host in hosts) {
      if (_shouldSkipProbe(host, now)) continue;
      dueHosts.add(host);
      if (_sessionProbesInFlight.length + dueHosts.length >= _sessionProbeMaxConcurrency) break;
    }
    for (final host in dueHosts) { _probeHost(host); }
  }

  bool _shouldSkipProbe(HostEntry host, DateTime now) {
    if (_sessionProbesInFlight.contains(host.id)) return true;
    if (hostSessionStatus(host.id) == TerminalStatus.connected) return true;
    final nextAt = _sessionProbeNextAt[host.id];
    if (nextAt == null) return false;
    return now.isBefore(nextAt);
  }

  void _probeHost(HostEntry host) {
    final now = DateTime.now();
    _sessionProbesInFlight.add(host.id);
    sessionProbeStates[host.id] = SessionProbeState(status: SessionProbeStatus.probing, lastCheckedAt: now);
    notifyState();
    unawaited(() async {
      final startedAt = DateTime.now();
      try {
        final result = await _probeHostConnectivity(host);
        final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
        _sessionProbeFailures[host.id] = result.reachable ? 0 : (_sessionProbeFailures[host.id] ?? 0) + 1;
        _sessionProbeNextAt[host.id] = _nextProbeAt(host.id, DateTime.now());
        sessionProbeStates[host.id] = SessionProbeState(status: result.reachable ? SessionProbeStatus.reachable : SessionProbeStatus.unreachable, latencyMs: result.reachable ? elapsed : null, lastCheckedAt: DateTime.now(), lastError: result.error);
      } catch (error) {
        _sessionProbeFailures[host.id] = (_sessionProbeFailures[host.id] ?? 0) + 1;
        _sessionProbeNextAt[host.id] = _nextProbeAt(host.id, DateTime.now());
        sessionProbeStates[host.id] = SessionProbeState(status: SessionProbeStatus.unreachable, lastCheckedAt: DateTime.now(), lastError: '$error');
      } finally { _sessionProbesInFlight.remove(host.id); notifyState(); }
    }());
  }

  DateTime _nextProbeAt(String hostId, DateTime now) {
    final failures = _sessionProbeFailures[hostId] ?? 0;
    if (failures == 0) return now.add(const Duration(seconds: 10));
    final backoffSeconds = (10 * (1 << failures.clamp(1, 4))).clamp(10, 120);
    return now.add(Duration(seconds: backoffSeconds));
  }

  Future<_ProbeResult> _probeHostConnectivity(HostEntry host) async {
    switch (host.connectionType) {
      case ConnectionType.local: return _ProbeResult(reachable: true);
      case ConnectionType.serial: return (host.serialPortPath ?? '').trim().isEmpty ? _ProbeResult(reachable: false, error: 'serial-path-empty') : _ProbeResult(reachable: false, error: 'serial-check-unsupported');
      case ConnectionType.ssh: final s = await Socket.connect(host.host, host.port, timeout: _sessionProbeTimeout); s.destroy(); return _ProbeResult(reachable: true);
      case ConnectionType.telnet: final s = await Socket.connect(host.host, host.telnetPort, timeout: _sessionProbeTimeout); s.destroy(); return _ProbeResult(reachable: true);
    }
  }

  // === Host Key Verification ===

  String _hostFingerprintKey(String hostId, String keyType) => '${hostId.trim()}::${normalizeSshHostKeyType(keyType.trim())}';
  String _secureHostSecretKey(String hostId) => 'Polarmote.host.secret.$hostId';

  Map<String, String> _secureStorageOptions() => Platform.isWindows ? const WindowsOptions(useBackwardCompatibility: false).toMap() : const <String, String>{};

  Future<void> _ensureSecureStorageReady() => _secureStorageInit ??= _initializeSecureStorageBackend();

  Future<void> _initializeSecureStorageBackend() async {
    if (!Platform.isWindows) return;
    final current = FlutterSecureStoragePlatform.instance;
    if (current is MethodChannelFlutterSecureStorage) return;
    final options = _secureStorageOptions();
    Map<String, String> legacyData;
    try { legacyData = await current.readAll(options: options); } catch (_) { legacyData = const <String, String>{}; }
    FlutterSecureStoragePlatform.instance = MethodChannelFlutterSecureStorage();
    final target = FlutterSecureStoragePlatform.instance;
    if (legacyData.isNotEmpty) {
      for (final entry in legacyData.entries) {
        try { await target.write(key: entry.key, value: entry.value, options: options); } catch (e) { PolarmoteLog.error('ops', '$e'); }
      }
    }
    try { await current.deleteAll(options: options); } catch (e) { PolarmoteLog.error('ops', '$e'); }
  }

  Future<bool> verifyHostFingerprint({required HostEntry host, required String keyType, required String fingerprint}) async {
    final rawKeyType = keyType.trim().toLowerCase();
    final normalizedKeyType = normalizeSshHostKeyType(rawKeyType);
    final normalizedFingerprint = normalizeFingerprint(fingerprint);
    if (normalizedKeyType.isEmpty || normalizedFingerprint.isEmpty) return false;
    final fingerprintKey = _hostFingerprintKey(host.id, normalizedKeyType);
    final legacyKey = '${host.id.trim()}::$rawKeyType';
    final existed = normalizeFingerprint(knownHostFingerprints[fingerprintKey] ?? knownHostFingerprints[legacyKey] ?? '');
    if (existed == normalizedFingerprint) {
      if (legacyKey != fingerprintKey && knownHostFingerprints.containsKey(legacyKey)) { knownHostFingerprints.remove(legacyKey); knownHostFingerprints[fingerprintKey] = normalizedFingerprint; scheduleStateSave(); }
      return true;
    }
    final knownHostsDecision = await checkOpenSshKnownHostFingerprint(host: host.host, port: host.port, keyType: normalizedKeyType, fingerprint: normalizedFingerprint);
    if (knownHostsDecision.trusted) {
      knownHostFingerprints[fingerprintKey] = normalizedFingerprint;
      scheduleStateSave();
      addStructuredLog(category: TerminalLogCategory.session, message: '[HostKey][$normalizedKeyType] accepted from known_hosts ${host.host}:${host.port}', notifyListeners: false);
      notifyState();
      return true;
    }
    if (knownHostsDecision.mismatched) {
      addStructuredLog(category: TerminalLogCategory.session, level: TerminalLogLevel.warn, message: '[HostKey][$normalizedKeyType] mismatch with known_hosts ${host.host}:${host.port}', notifyListeners: false);
      return false;
    }
    final promptId = 'host-key-${DateTime.now().microsecondsSinceEpoch}';
    pendingHostKeyPrompt = HostKeyVerificationPrompt(id: promptId, hostId: host.id, hostDisplayName: host.name.trim().isEmpty ? host.host : host.name, hostAddress: '${host.host}:${host.port}', keyType: normalizedKeyType, fingerprint: normalizedFingerprint, existedFingerprint: existed, createdAt: DateTime.now());
    hostKeyPromptToken += 1;
    _hostKeyPromptDecision?.complete(false);
    _hostKeyPromptDecision = Completer<bool>();
    _hostKeyPromptRemember = true;
    notifyState();
    var trusted = false;
    try { trusted = await _hostKeyPromptDecision!.future.timeout(const Duration(minutes: 3), onTimeout: () => false); } catch (_) { trusted = false; }
    pendingHostKeyPrompt = null;
    _hostKeyPromptDialogVisible = false;
    _hostKeyPromptDecision = null;
    hostKeyPromptToken += 1;
    if (trusted && _hostKeyPromptRemember) {
      knownHostFingerprints[fingerprintKey] = normalizedFingerprint;
      scheduleStateSave();
      addStructuredLog(category: TerminalLogCategory.session, message: '[HostKey][$normalizedKeyType] trusted ${host.host}:${host.port}', notifyListeners: false);
    } else if (!trusted) {
      addStructuredLog(category: TerminalLogCategory.session, level: TerminalLogLevel.warn, message: '[HostKey][$normalizedKeyType] rejected ${host.host}:${host.port}', notifyListeners: false);
    }
    notifyState();
    return trusted;
  }

  bool beginHostKeyPromptDialog() => !_hostKeyPromptDialogVisible && pendingHostKeyPrompt != null ? (_hostKeyPromptDialogVisible = true) as bool : false;
  void endHostKeyPromptDialog() { _hostKeyPromptDialogVisible = false; }
  void resolveHostKeyPrompt(bool trusted, {bool remember = true}) { final d = _hostKeyPromptDecision; if (d == null || d.isCompleted) return; _hostKeyPromptRemember = remember; d.complete(trusted); }
  bool beginShortcutConflictDialog() => !_shortcutConflictDialogVisible && shortcutConflicts.isNotEmpty ? (_shortcutConflictDialogVisible = true) as bool : false;
  void endShortcutConflictDialog() { _shortcutConflictDialogVisible = false; }

  // === Shortcuts ===

  void _checkShortcutConflicts() {
    shortcutConflicts.clear();
    final Map<String, _ShortcutOwner> owners = {};
    void register(String id, String name, String keys, String type) {
      if (keys.isEmpty) return;
      for (final alt in keys.split('/')) {
        final norm = _normalizeShortcutCombo(alt.trim());
        if (norm.isEmpty) continue;
        if (owners.containsKey(norm)) {
          final existing = owners[norm]!;
          if (existing.id != id) shortcutConflicts.add('$norm → ${existing.name} (${existing.type}) & $name ($type)');
        } else { owners[norm] = _ShortcutOwner(id, name, type); }
      }
    }
    for (final sb in shortcutBindings) { register(sb.id, sb.name, sb.customKeys ?? sb.defaultKeys, 'system'); }
    for (final kb in customKeyBindings) { register(kb.id, kb.name, kb.keys, 'custom'); }
    for (final entry in scriptShortcutBindings.entries) {
      final script = scripts.where((s) => s.id == entry.value).firstOrNull;
      register(entry.key, script?.name ?? entry.value, entry.key, 'script');
    }
    if (shortcutConflicts.isNotEmpty) { shortcutConflictToken++; notifyState(); }
  }

  String _normalizeShortcutCombo(String combo) {
    final parts = combo.split('+').map((p) => p.trim()).toList();
    final mods = <String>[];
    String? key;
    for (final part in parts) {
      switch (part) { case 'Ctrl': case 'Alt': case 'Shift': case 'Meta': mods.add(part); break; default: key = part; }
    }
    if (key == null || key.isEmpty) return '';
    mods.sort();
    return mods.isEmpty ? key : '${mods.join('+')}+$key';
  }

  // === Secure Storage ===

  Future<StoredHostSecret?> readHostSecret(String hostId) async {
    await _ensureSecureStorageReady();
    try {
      final raw = await _secureStorage.read(key: _secureHostSecretKey(hostId), wOptions: Platform.isWindows ? const WindowsOptions(useBackwardCompatibility: false) : null);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is! Map<String, dynamic> ? null : StoredHostSecret.fromJson(decoded);
    } catch (_) { return null; }
  }

  Future<void> _writeHostSecret(HostEntry host) async {
    await _ensureSecureStorageReady();
    try {
      final secret = StoredHostSecret(password: host.password, privateKeyPath: host.privateKeyPath, privateKeyPassphrase: host.privateKeyPassphrase, socksProxyPassword: host.socksProxyPassword);
      final hasSecret = (secret.password ?? '').trim().isNotEmpty || (secret.privateKeyPath ?? '').trim().isNotEmpty || (secret.privateKeyPassphrase ?? '').trim().isNotEmpty || (secret.socksProxyPassword ?? '').trim().isNotEmpty;
      final key = _secureHostSecretKey(host.id);
      if (!hasSecret) { await _secureStorage.delete(key: key, wOptions: Platform.isWindows ? const WindowsOptions(useBackwardCompatibility: false) : null); return; }
      await _secureStorage.write(key: key, value: jsonEncode(secret.toJson()), wOptions: Platform.isWindows ? const WindowsOptions(useBackwardCompatibility: false) : null);
    } catch (e) { PolarmoteLog.error('ops', '$e'); }
  }

  Future<void> _deleteHostSecret(String hostId) async {
    await _ensureSecureStorageReady();
    try { await _secureStorage.delete(key: _secureHostSecretKey(hostId), wOptions: Platform.isWindows ? const WindowsOptions(useBackwardCompatibility: false) : null); } catch (e) { PolarmoteLog.error('ops', '$e'); }
  }


  // === Host Session Lookup ===

  Future<void> _synchronizeHostSecrets() async {}

  TerminalStatus? hostSessionStatus(String hostId) {
    HostEntry? h; for (final e in hosts) { if (e.id == hostId) { h = e; break; } }
    if (h == null) return null;
    final key = _hostConnectionKey(h);
    TerminalStatus? status;
    for (final s in sessions.reversed) {
      if (_hostConnectionKey(s.profile) != key) continue;
      status = s.tab.status;
      if (status == TerminalStatus.connected) break;
    }
    return status;
  }

  String joinRemote(String p, String c) => p.endsWith('/') ? '$p$c' : '$p/$c';

  String parentOf(String path) {
    if (!path.contains('/')) return '/';
    final x = p.dirname(path.replaceAll('\\', '/'));
    return x.isEmpty || x == '.' ? '/' : x;
  }

  HostEntry? resolveHostForVisitedFile(VisitedFileEntry e) {
    for (final h in hosts) {
      if (h.id == e.hostId.trim() ||
          (h.host.trim() == e.host.trim() && h.username.trim() == e.username.trim() && h.connectionType.name == e.connectionType && h.port == e.port)) return h;
    }
    return null;
  }

  List<HostEntry> recentHosts({int limit = 30}) {
    final r = hosts.where((h) => h.lastConnected != null).toList()..sort((a, b) => b.lastConnected!.compareTo(a.lastConnected!));
    return r.isEmpty ? [] : r.take(limit.clamp(1, r.length)).toList();
  }

  List<VisitedFileEntry> recentVisitedFiles({int limit = 30}) =>
    visitedFiles.isEmpty ? [] : visitedFiles.take(limit.clamp(1, visitedFiles.length)).toList();

  void recordVisitedFile(TerminalSession session, FileNode node) {
    if (node.isDirectory) return;
    final path = node.path.trim(); if (path.isEmpty) return;
    final item = VisitedFileEntry(hostId: session.profile.id.trim(), host: session.profile.host.trim(), port: session.profile.port, username: session.profile.username.trim(), connectionType: session.profile.connectionType.name, isLocal: session.profile.isLocal, filePath: path, displayName: node.name.trim().isEmpty ? p.basename(path) : node.name.trim(), fileSize: node.size, fileModifiedAt: node.modified, lastVisitedAt: DateTime.now());
    visitedFiles.removeWhere((x) => x.dedupeKey == item.dedupeKey);
    visitedFiles.insert(0, item);
    if (visitedFiles.length > TerminalAppState.visitedFilesCap) visitedFiles.removeRange(TerminalAppState.visitedFilesCap, visitedFiles.length);
    scheduleStateSave(); notifyState();
  }

  void recordCommandHistory(String hid, String cmd) {
    final normalizedHostId = hid.trim(); final normalizedCommand = cmd.trim();
    if (normalizedHostId.isEmpty || normalizedCommand.isEmpty) return;
    final list = List<String>.from(commandHistoryByHost[normalizedHostId] ?? [], growable: true);
    if (list.isNotEmpty && list.last == normalizedCommand) return;
    list.add(normalizedCommand);
    if (list.length > TerminalAppState.commandHistoryPerHostCap) list.removeRange(0, list.length - TerminalAppState.commandHistoryPerHostCap);
    commandHistoryByHost[normalizedHostId] = list; scheduleStateSave(); notifyState();
  }

  // === Settings & Layout ===

  void triggerKeyboardRecovery({String? reason}) {
    keyboardRecoveryToken++;
    if ((reason ?? '').trim().isEmpty) addStructuredLog(category: TerminalLogCategory.system, message: _l(AppStrings.values.logKeyboardRecoveryTriggered), notifyListeners: false);
    else addStructuredLog(category: TerminalLogCategory.system, message: _l(AppStrings.values.logKeyboardRecoveryTriggeredReasonVar, params: {'reason': reason!}), notifyListeners: false);
    notifyState();
  }

  void setStageBackgroundImage(String stageId, String imageId) {
    final i = terminalStages.indexWhere((s) => s.id == stageId);
    if (i < 0) return;
    terminalStages[i] = terminalStages[i].copyWith(backgroundImageId: imageId);
    stageChangeToken++;
    scheduleStateSave(); notifyState();
  }

  bool isHostPinned(String id) => pinnedHostIds.contains(id);
  void toggleHostPinned(String id) { if (pinnedHostIds.contains(id)) pinnedHostIds.remove(id); else pinnedHostIds.add(id); scheduleStateSave(); notifyState(); }

  TerminalSession? terminalSessionForHost(HostEntry host) {
    final key = _hostConnectionKey(host);
    for (final s in sessions.reversed) { if (_hostConnectionKey(s.profile) == key) return s; }
    return null;
  }

  void clearError() { lastError = null; notifyState(); }
  void setError(String message, {String? detail}) { lastError = message; notifyState(); }
  void setAppError(AppError error) { setError(error.message, detail: error.detail); }
  void setLocale(Locale v) { locale = v; scheduleStateSave(); notifyState(); }
  void toggleLocale() { locale = locale.languageCode == 'zh' ? const Locale('en') : const Locale('zh'); scheduleStateSave(); notifyState(); }
  void setNavSection(NavSection s) { if (navSection == s) return; navSection = s; scheduleStateSave(); notifyState(); }
  void setSessionQuery(String v) { if (sessionQuery == v) return; sessionQuery = v; notifyState(); }
  void setShowHiddenFiles(bool v) { showHiddenFiles = v; scheduleStateSave(); notifyState(); }
  void setAutoReconnect(bool v) { autoReconnect = v; scheduleStateSave(); syncSshForegroundGuardNow(); notifyState(); }
  void setConfirmPaste(bool v) { confirmPaste = v; scheduleStateSave(); notifyState(); }
  void setTerminalSplitViewEnabled(bool v) { if (terminalSplitViewEnabled == v) return; terminalSplitViewEnabled = v; if (v) ensureTerminalSplitPanes(); else maximizedTerminalSplitPaneId = ''; scheduleStateSave(); notifyState(); }
  void setSessionSortMode(SessionSortMode m) { if (sessionSortMode == m) return; sessionSortMode = m; scheduleStateSave(); notifyState(); }
  void setSessionFilterOnlineOnly(bool v) { if (sessionFilterOnlineOnly == v) return; sessionFilterOnlineOnly = v; scheduleStateSave(); notifyState(); }
  void setSessionFilterPinnedOnly(bool v) { if (sessionFilterPinnedOnly == v) return; sessionFilterPinnedOnly = v; scheduleStateSave(); notifyState(); }
  void setSessionGroupFilter(String v) { final n = v.trim(); if (sessionGroupFilter == n) return; sessionGroupFilter = n; scheduleStateSave(); notifyState(); }
  void setReuseSessionForNewPane(bool v) { reuseSessionForNewPane = v; scheduleStateSave(); notifyState(); }
  void setShowThumbnailBackground(bool v) { showThumbnailBackground = v; thumbnailBackgroundVersion++; scheduleStateSave(); notifyState(); }
  void toggleHostSelection(String id, {bool multi = false}) {
    if (multi) { if (selectedHostIds.contains(id)) selectedHostIds.remove(id); else selectedHostIds.add(id); }
    else { selectedHostIds..clear()..add(id); }
    notifyState();
  }
  void addHost(HostEntry h) { hosts.add(h); scheduleStateSave(); notifyState(); eventBus.fire(HostListChangedEvent()); }
  void removeHost(String id) { hosts.removeWhere((e) => e.id == id); scheduleStateSave(); notifyState(); eventBus.fire(HostListChangedEvent()); }
  List<HostEntry> visibleHosts() => hosts.where((h) => true).toList();

  void setMobileSidebarWidth(double v) { mobileSidebarWidth = v.clamp(TerminalAppState.mobileSidebarWidthMin, TerminalAppState.mobileSidebarWidthMax); scheduleStateSave(); notifyState(); }
  void setMobileTerminalColumns(int v) { mobileTerminalColumns = v.clamp(TerminalAppState.mobileTerminalColumnsMin, TerminalAppState.mobileTerminalColumnsMax).toInt(); scheduleStateSave(); notifyState(); }
  void setTerminalHorizontalScrollEnabled(bool v) { terminalHorizontalScrollEnabled = v; scheduleStateSave(); notifyState(); }
  void setTerminalAccessibilitySemanticsEnabled(bool v) { terminalAccessibilitySemanticsEnabled = v; scheduleStateSave(); notifyState(); }
  void setTransferAutoRetryEnabled(bool v) { transferAutoRetryEnabled = v; scheduleStateSave(); notifyState(); }
  void setTransferResumeEnabled(bool v) { transferResumeEnabled = v; scheduleStateSave(); notifyState(); }
  void setTransferRetryPolicy({int? maxAttempts, int? baseDelayMs, int? maxDelayMs}) {}
  void setSettingsTabIndex(int v) { settingsTabIndex = v.clamp(0, 6); notifyState(); }
  void setHomeLayoutMode(HomeLayoutMode v) { if (homeLayoutMode == v) return; homeLayoutMode = v; notifyState(); }
  void setAndroidKeepSshAliveInBackground(bool v) { androidKeepSshAliveInBackground = v; scheduleStateSave(); notifyState(); }
  void applyShortcutPreset(ShortcutPreset preset) { shortcutPresetId = preset.id; for (final sb in preset.bindings) { final i = shortcutBindings.indexWhere((s) => s.id == sb.id); if (i >= 0) shortcutBindings[i] = shortcutBindings[i].copyWith(customKeys: sb.customKeys); } scheduleStateSave(); notifyState(); }
  void renameSessionFolder({required String folderKey, required String newName}) {}
  void toggleSessionFolderExpanded(String k) { if (expandedSessionFolderKeys.contains(k)) expandedSessionFolderKeys.remove(k); else expandedSessionFolderKeys.add(k); scheduleStateSave(); notifyState(); }
  void setActiveTerminalSession(String sessionId) {
    final s = findSessionById(sessionId);
    if (s == null) return;
    final idx = sessions.indexOf(s);
    if (idx >= 0) activeSessionIndexValue = idx;
    scheduleStateSave(); notifyState();
  }

  // === Stage Background ===

  Future<void> addBackgroundImage(String path) async {
    final id = 'bg-$_nextBgImageId'; _nextBgImageId++;
    final base = await getApplicationSupportDirectory();
    final bgDir = Directory(p.join(base.path, 'backgrounds'));
    if (!await bgDir.exists()) await bgDir.create(recursive: true);
    final ext = path.contains('.') ? path.split('.').last : 'png';
    final dest = p.join(bgDir.path, '$id.$ext');
    await File(path).copy(dest);
    terminalBackgroundImages.add(BackgroundImageEntry(id: id, path: dest, name: path.split(Platform.pathSeparator).last));
    scheduleStateSave(); notifyState();
  }

  void removeBackgroundImage(String id) {
    final entry = terminalBackgroundImages.cast<BackgroundImageEntry?>().firstWhere((e) => e!.id == id, orElse: () => null);
    terminalBackgroundImages.removeWhere((e) => e.id == id);
    for (var i = 0; i < terminalStages.length; i++) {
      if (terminalStages[i].backgroundImageId == id) terminalStages[i] = terminalStages[i].copyWith(backgroundImageId: '');
    }
    if (entry != null) {
      final file = File(entry.path);
      if (file.existsSync()) file.deleteSync();
    }
    scheduleStateSave(); notifyState();
  }

  String? backgroundImagePathForActiveStage() {
    if (activeTerminalStageId.isEmpty) return null;
    final stage = _stageById(activeTerminalStageId);
    if (stage == null || stage.backgroundImageId.isEmpty) return null;
    for (final e in terminalBackgroundImages) { if (e.id == stage.backgroundImageId) return e.path; }
    return null;
  }

  Future<ViewerCacheCleanupResult> clearFilePreviewCache() async {
    internalViewerPreparedCache.clear(); internalViewerPreparingCache.clear(); internalViewerStreamingCache.clear();
    final base = await getApplicationSupportDirectory();
    int deleted = 0, failed = 0;
    for (final dirPath in ['external-edit', 'internal-viewer']) {
      final d = Directory(p.join(base.path, dirPath));
      if (!await d.exists()) continue;
      await for (final e in d.list()) { try { await e.delete(recursive: true); deleted++; } catch (_) { failed++; } }
    }
    return ViewerCacheCleanupResult(dirs: [p.join(base.path, 'external-edit'), p.join(base.path, 'internal-viewer')], deleted: deleted, failed: failed);
  }


}

