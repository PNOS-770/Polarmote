import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/constants/app_string.dart';
import '../../../shared/utils/secret_encryption.dart';
import '../../../services/server_monitor_service.dart';
import '../transfer/mobile/android_ssh_foreground_bridge.dart';
import '../transfer/mobile/android_transfer_foreground_bridge.dart';
import '../transfer/transport/native/native_transfer_bridge.dart';
import '../models/host_entry.dart';
import '../models/port_forward_entry.dart';
import '../models/script_batch_template.dart';
import '../models/script_entry.dart';
import '../models/script_folder_entry.dart';
import '../models/script_run_session.dart';
import '../models/ssh_connection_pool.dart';
import '../models/script_schedule_entry.dart';
import '../models/script_trigger_entry.dart';
import '../models/script_workflow_entry.dart';
import '../models/file_node.dart';
import '../models/terminal_session.dart';
import '../models/terminal_tab.dart';
import 'app/terminal_app_state_port_forward.dart';
import 'app/terminal_app_state_sessions.dart';
import 'app/terminal_app_state_ssh_foreground.dart';
import 'ssh/ssh_openssh_compat.dart';
import 'terminal_app_state_models.dart';
import 'app/terminal_app_state_scripts.dart';

export 'app/terminal_app_state_external_edit.dart';
export 'app/terminal_app_state_metrics.dart';
export 'app/terminal_app_state_automation.dart';
export 'app/terminal_app_state_ssh_foreground.dart';
export 'app/terminal_app_state_ssh.dart';
export 'app/terminal_app_state_scripts.dart';
export 'app/terminal_app_state_sessions.dart';
export 'app/terminal_app_state_sftp.dart';
export 'app/terminal_app_state_transfers.dart';
export 'app/terminal_app_state_port_forward.dart';

part 'terminal_app_state_types.dart';

class TerminalAppState extends ChangeNotifier {
  static const int commandHistoryPerHostCap = 80;
  static const int scriptRunHistoryCap = 240;
  static const int mobileTerminalColumnsMin = 40;
  static const int mobileTerminalColumnsMax = 2000;
  static const double mobileSidebarWidthMin = 220;
  static const double mobileSidebarWidthMax = 2000;
  static const double mobileSidebarWidthDefault = 304;
  static const String _legacyScriptDefaultFolderId = 'script-folder-default';

  static const String _explicitAppVersion = String.fromEnvironment(
    'ASMOTE_APP_VERSION',
    defaultValue: '',
  );

  TerminalAppState() : navSection = NavSection.sessions {
    unawaited(_bootstrapStartupLogs());
    unawaited(_loadState().then((_) {
      _checkShortcutConflicts();
    }));
    unawaited(
      refreshPortableStateSnapshots().catchError(
        (_) => const <PortableStateSnapshot>[],
      ),
    );
    unawaited(Future.delayed(const Duration(seconds: 2), () {
      ServerMonitorService.instance.start(this);
    }));
  }

  static HomeLayoutMode _defaultHomeLayoutMode() {
    return (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
        ? HomeLayoutMode.desktop
        : HomeLayoutMode.mobile;
  }

  static const JsonEncoder _stateJsonEncoder = JsonEncoder.withIndent('  ');

  NavSection navSection;
  String? lastError;

  final List<HostEntry> hosts = [];
  final Set<String> selectedHostIds = {};

  final List<TerminalSession> sessions = [];
  int activeSessionIndexValue = 0;

  final List<ScriptEntry> scripts = [];
  final List<ScriptFolderEntry> scriptFolders = [];
  final List<ScriptWorkflowEntry> scriptWorkflows = [];
  final List<ScriptBatchTemplate> scriptBatchTemplates = [];
  final List<ScriptTriggerEntry> scriptTriggers = [];
  final List<PortForwardEntry> portForwards = [];
  final List<PortForwardTemplate> portForwardTemplates = [];
  final Map<String, String> knownHostFingerprints = {};
  HostKeyVerificationPrompt? pendingHostKeyPrompt;
  int hostKeyPromptToken = 0;
  int shortcutConflictToken = 0;
  List<String> shortcutConflicts = [];
  bool _shortcutConflictDialogVisible = false;
  bool _hostKeyPromptDialogVisible = false;
  Completer<bool>? _hostKeyPromptDecision;
  bool _hostKeyPromptRemember = true;
  final List<String> logs = [];
  LogVerbosity logVerbosity = LogVerbosity.important;
  final Map<String, DateTime> _errorCooldownUntil = <String, DateTime>{};
  final List<_PendingLogLine> _pendingLogWrites = [];
  IOSink? logSink;
  File? logFile;
  String? _activeLogDateKey;
  Directory? logDirectory;
  DateTime lastLogPrune = DateTime.fromMillisecondsSinceEpoch(0);
  File? stateFile;
  Timer? stateSaveTimer;
  bool suspendStateSave = false;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  FlutterSecureStorage get secureStorage => _secureStorage;
  Future<void>? _secureStorageInit;

  int transferIdSeed = 0;
  int lastTransferTimestamp = 0;
  int keyboardRecoveryToken = 0;
  bool showHiddenFiles = true;
  bool autoReconnect = true;
  bool androidKeepSshAliveInBackground = Platform.isAndroid;
  bool confirmPaste = true;
  TerminalAppearanceProfile globalAppearance = const TerminalAppearanceProfile();
  final List<BackgroundImageEntry> terminalBackgroundImages = [];
  int _nextBgImageId = 1;
  double terminalBackgroundOpacity = 0.15;
  int maxScrollbackLines = 10000;
  bool reuseSessionForNewPane = false;
  bool terminalBlockSelectEnabled = false;
  final List<ShortcutBinding> shortcutBindings = _defaultShortcutBindings();
  final List<KeyBinding> customKeyBindings = [];
  String shortcutPresetId = 'default';

  static List<ShortcutBinding> _defaultShortcutBindings() {
    return [
      const ShortcutBinding(id: 'copy', name: 'Copy', defaultKeys: 'Ctrl+Shift+C / Ctrl+C'),
      const ShortcutBinding(id: 'paste', name: 'Paste', defaultKeys: 'Ctrl+V / Shift+Insert'),
      const ShortcutBinding(id: 'selectAll', name: 'Select All', defaultKeys: 'Ctrl+A'),
      const ShortcutBinding(id: 'search', name: 'Find in terminal', defaultKeys: 'Ctrl+F'),
      const ShortcutBinding(id: 'blockSelect', name: 'Toggle block selection', defaultKeys: 'Alt+B'),
      const ShortcutBinding(id: 'splitMaximize', name: 'Maximize / Restore pane', defaultKeys: 'Ctrl+Alt+Enter'),
      const ShortcutBinding(id: 'splitBroadcast', name: 'Toggle input broadcast', defaultKeys: 'Ctrl+Alt+B'),
      const ShortcutBinding(id: 'splitPrev', name: 'Switch to previous pane', defaultKeys: 'Ctrl+Alt+Left / Ctrl+Alt+Up'),
      const ShortcutBinding(id: 'splitNext', name: 'Switch to next pane', defaultKeys: 'Ctrl+Alt+Right / Ctrl+Alt+Down'),
    ];
  }
  HomeLayoutMode homeLayoutMode = _defaultHomeLayoutMode();
  bool terminalSplitViewEnabled = true;
  TerminalSplitLayout terminalSplitLayout = TerminalSplitLayout.horizontal;
  final List<TerminalSplitPaneConfig> terminalSplitPanes = [];
  TerminalSplitTreeNode? terminalSplitTree;
  int _terminalSplitIdSeed = 0;
  final List<TerminalSplitTemplate> terminalSplitTemplates = [];
  String activeTerminalSplitPaneId = '';
  String maximizedTerminalSplitPaneId = '';


  double terminalSplitPrimaryRatio = 0.5;
  double terminalSplitSecondaryRatio = 0.5;
  double mobileSidebarWidth = mobileSidebarWidthDefault;
  bool terminalHorizontalScrollEnabled = false;
  int mobileTerminalColumns = 132;
  bool terminalAccessibilitySemanticsEnabled = false;
  bool transferAutoRetryEnabled = true;
  bool transferResumeEnabled = true;
  int transferRetryMaxAttempts = 3;
  int transferRetryBaseDelayMs = 800;
  int transferRetryMaxDelayMs = 10 * 1000;
  Locale locale = const Locale('zh');
  String sessionQuery = '';
  bool sessionFilterOnlineOnly = false;
  bool sessionFilterPinnedOnly = false;
  String sessionGroupFilter = '';
  SessionSortMode sessionSortMode = SessionSortMode.smart;
  String _hostConnectionKey(HostEntry profile) {
    return switch (profile.connectionType) {
      ConnectionType.local => 'local:${profile.localShellType.name}',
      ConnectionType.serial =>
        'serial:${profile.serialPortPath ?? ''}:${profile.serialBaudRate}:${profile.serialDataBits}:${profile.serialStopBits}:${profile.serialParity.name}',
      ConnectionType.ssh =>
        'ssh:${profile.username}@${profile.host}:${profile.port}',
      ConnectionType.telnet =>
        'telnet:${profile.host}:${profile.telnetPort}',
    };
  }

  final Set<String> pinnedHostIds = {};
  final Set<String> expandedSessionFolderKeys = {};
  bool sessionFolderExpansionConfigured = false;
  final Map<String, List<String>> commandHistoryByHost = {};
  final List<ScriptScheduleEntry> scriptSchedules = [];
  final List<ScriptHostRunRecord> scriptRunHistory = [];
  final List<ScriptWorkflowRunResult> workflowRunHistory = [];
  final Map<String, ScriptRunSession> activeScriptRuns = {};
  final SshConnectionPool scriptSshPool = SshConnectionPool();
  String? focusedScriptRunId;
  bool showScriptMonitorInline = false;
  final Map<String, String> scriptShortcutBindings = {};
  int scriptMultiSelectToken = 0;
  bool scriptMultiSelectActive = false;
  int settingsTabIndex = 0;  
  final Map<String, SessionProbeState> sessionProbeStates = {};
  final Map<String, DateTime> _sessionProbeNextAt = <String, DateTime>{};
  final Map<String, int> _sessionProbeFailures = <String, int>{};
  final Set<String> _sessionProbesInFlight = <String>{};
  Timer? _sessionProbeTimer;
  final List<PortableStateSnapshot> portableStateSnapshots = [];
  int _nextScriptRunId = 0;

  final Map<String, ExternalEditEntry> externalEdits = {};
  final Map<String, StreamSubscription<FileSystemEvent>>
  externalEditSubscriptions = {};
  final Map<String, Timer> externalEditDebounceTimers = {};
  final Map<String, InternalViewerPreparationResult>
  internalViewerPreparedCache = {};
  final Map<String, Future<InternalViewerPreparationResult?>>
  internalViewerPreparingCache = {};
  final Map<String, InternalViewerStreamPreparationResult>
  internalViewerStreamingCache = {};

  final Map<String, double> filePreviewScrollOffsets = <String, double>{};
  final List<VisitedFileEntry> visitedFiles = <VisitedFileEntry>[];
  static const int visitedFilesCap = 15;

  int get activeSessionIndex => sessions.isEmpty
      ? 0
      : activeSessionIndexValue.clamp(0, sessions.length - 1);
  TerminalSession? get activeSession =>
      sessions.isEmpty ? null : sessions[activeSessionIndex];
  Future<void> exportPortableStateToPath(
    String path, {
    String? masterPassword,
  }) async {
    try {
      final data = _buildPortableStateData(includeSecrets: false);
      if (masterPassword != null && masterPassword.isNotEmpty) {
        final secrets = <String, Map<String, dynamic>>{};
        for (final host in hosts) {
          final stored = await readHostSecret(host.id);
          if (stored != null) {
            secrets[host.id] = stored.toJson();
          }
        }
        if (secrets.isNotEmpty) {
          data['encryptedSecrets'] = SecretEncryption.encryptSecrets(
            secrets: secrets,
            password: masterPassword,
          );
        }
      }
      final file = File(path);
      await file.writeAsString(_stateJsonEncoder.convert(data));
    } catch (error) {
      addLog('Export failed: $error');
    }
  }

  Future<void> importHostSecretsFromData(Map<String, dynamic> secrets) async {
    for (final entry in secrets.entries) {
      final hostId = entry.key;
      final data = entry.value;
      if (data is! Map<String, dynamic>) continue;
      try {
        final stored = StoredHostSecret.fromJson(data);
        final key = _secureHostSecretKey(hostId);
        if ((stored.password ?? '').trim().isEmpty &&
            (stored.privateKeyPath ?? '').trim().isEmpty &&
            (stored.privateKeyPassphrase ?? '').trim().isEmpty &&
            (stored.socksProxyPassword ?? '').trim().isEmpty) {
          await _secureStorage.delete(key: key);
        } else {
          await _secureStorage.write(
            key: key,
            value: jsonEncode(stored.toJson()),
          );
        }
      } catch (_) {
        // Ignore per-host secret write errors.
      }
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
      notifyListeners();
    } catch (error) {
      addLog('Import failed: $error');
    }
  }

  Future<void> createPortableStateSnapshot() async {
    try {
      final base = await getApplicationSupportDirectory();
      final snapshotDir = Directory(p.join(base.path, 'snapshots'));
      if (!await snapshotDir.exists()) {
        await snapshotDir.create(recursive: true);
      }
      final timestamp = DateTime.now();
      final id = 'snap-${timestamp.millisecondsSinceEpoch}';
      final file = File(p.join(snapshotDir.path, '$id.json'));
      final data = _buildPortableStateData(includeSecrets: false);
      await file.writeAsString(_stateJsonEncoder.convert(data));
      portableStateSnapshots.add(
        PortableStateSnapshot(
          id: id,
          createdAt: timestamp,
          label: 'Snapshot ${portableStateSnapshots.length + 1}',
          path: file.path,
        ),
      );
      notifyListeners();
    } catch (_) {}
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
          final id = p.basenameWithoutExtension(entry.path);
          results.add(
            PortableStateSnapshot(
              id: id,
              createdAt: stat.modified,
              label: id,
              path: entry.path,
            ),
          );
        }
      }
      results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      portableStateSnapshots
        ..clear()
        ..addAll(results);
      await _loadPortableSnapshotMetas();
      notifyListeners();
      return results;
    } catch (_) {
      return [];
    }
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
        if (snap.path.isNotEmpty) {
          try {
            final file = File(snap.path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        portableStateSnapshots.remove(snap);
        notifyListeners();
        return;
      }
    }
  }

  Future<void> updatePortableStateSnapshotMeta(
    String snapshotId, {
    required String label,
    String? description,
  }) async {
    final snap = portableStateSnapshots.where((s) => s.id == snapshotId).firstOrNull;
    if (snap == null) return;
    snap.label = label;
    if (description != null) snap.description = description;
    await _savePortableSnapshotMeta(snap);
    notifyListeners();
  }

  Future<void> _savePortableSnapshotMeta(PortableStateSnapshot snap) async {
    try {
      final metaFile = File('${snap.path}.meta.json');
      await metaFile.writeAsString(_stateJsonEncoder.convert(snap.toJson()));
    } catch (_) {}
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
      } catch (_) {}
    }
  }

  Map<String, dynamic> _buildPortableStateData({required bool includeSecrets}) {
    final data = _buildStateJson();
    if (!includeSecrets) {
      data.remove('hostSecrets');
    }
    return data;
  }

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
    if (existing != null && (existing - safe).abs() < 0.5) {
      return;
    }
    filePreviewScrollOffsets[normalized] = safe;
    if (filePreviewScrollOffsets.length > 240) {
      final toRemove = filePreviewScrollOffsets.keys.take(40).toList();
      for (final k in toRemove) {
        filePreviewScrollOffsets.remove(k);
      }
    }
    scheduleStateSave();
  }

  String? scriptIdForShortcut(String shortcut) {
    final key = shortcut.trim();
    if (key.isEmpty) {
      return null;
    }
    return scriptShortcutBindings[key];
  }

  String? shortcutForScript(String scriptId) {
    final id = scriptId.trim();
    if (id.isEmpty) {
      return null;
    }
    for (final entry in scriptShortcutBindings.entries) {
      if (entry.value == id) {
        return entry.key;
      }
    }
    return null;
  }

  void bindScriptShortcut({
    required String scriptId,
    required String shortcut,
  }) {
    final id = scriptId.trim();
    final key = shortcut.trim();
    if (id.isEmpty || key.isEmpty) {
      return;
    }
    scriptShortcutBindings.removeWhere(
      (existingKey, existingId) => existingId == id || existingKey == key,
    );
    scriptShortcutBindings[key] = id;
    scheduleStateSave();
    notifyListeners();
  }

  void unbindScriptShortcut(String scriptId) {
    final id = scriptId.trim();
    if (id.isEmpty) {
      return;
    }
    final before = scriptShortcutBindings.length;
    scriptShortcutBindings.removeWhere((_, existingId) => existingId == id);
    if (scriptShortcutBindings.length != before) {
      scheduleStateSave();
      notifyListeners();
    }
  }

  SessionProbeState? sessionProbeStateForHost(String hostId) {
    return sessionProbeStates[hostId];
  }

  void ensureSessionProbeRuntime() {
    if (_sessionProbeTimer != null) {
      return;
    }
    _sessionProbeTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _tickSessionProbes(),
    );
    _tickSessionProbes();
  }

  void _tickSessionProbes() {
    if (hosts.isEmpty) {
      sessionProbeStates.clear();
      _sessionProbeNextAt.clear();
      _sessionProbeFailures.clear();
      return;
    }
    final hostIdSet = hosts.map((host) => host.id).toSet();
    sessionProbeStates.removeWhere((id, _) => !hostIdSet.contains(id));
    _sessionProbeNextAt.removeWhere((id, _) => !hostIdSet.contains(id));
    _sessionProbeFailures.removeWhere((id, _) => !hostIdSet.contains(id));
    if (_sessionProbesInFlight.length >= _sessionProbeMaxConcurrency) {
      return;
    }
    final now = DateTime.now();
    final dueHosts = <HostEntry>[];
    for (final host in hosts) {
      if (_shouldSkipProbe(host, now)) {
        continue;
      }
      dueHosts.add(host);
      if (_sessionProbesInFlight.length + dueHosts.length >=
          _sessionProbeMaxConcurrency) {
        break;
      }
    }
    for (final host in dueHosts) {
      _probeHost(host);
    }
  }

  bool _shouldSkipProbe(HostEntry host, DateTime now) {
    if (_sessionProbesInFlight.contains(host.id)) {
      return true;
    }
    if (hostSessionStatus(host.id) == TerminalStatus.connected) {
      return true;
    }
    final nextAt = _sessionProbeNextAt[host.id];
    if (nextAt != null && now.isBefore(nextAt)) {
      return true;
    }
    return false;
  }

  static const Duration _sessionProbeBaseInterval = Duration(seconds: 60);
  static const Duration _sessionProbeTimeout = Duration(seconds: 4);
  static const int _sessionProbeMaxConcurrency = 3;

  void _probeHost(HostEntry host) {
    final now = DateTime.now();
    _sessionProbesInFlight.add(host.id);
    sessionProbeStates[host.id] = SessionProbeState(
      status: SessionProbeStatus.probing,
      lastCheckedAt: now,
    );
    notifyState();
    unawaited(() async {
      final startedAt = DateTime.now();
      try {
        final result = await _probeHostConnectivity(host);
        final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
        _sessionProbeFailures[host.id] = result.reachable
            ? 0
            : (_sessionProbeFailures[host.id] ?? 0) + 1;
        final nextAt = _nextProbeAt(host.id, DateTime.now());
        _sessionProbeNextAt[host.id] = nextAt;
        sessionProbeStates[host.id] = SessionProbeState(
          status: result.reachable
              ? SessionProbeStatus.reachable
              : SessionProbeStatus.unreachable,
          latencyMs: result.reachable ? elapsed : null,
          lastCheckedAt: DateTime.now(),
          lastError: result.error,
        );
      } catch (error) {
        _sessionProbeFailures[host.id] =
            (_sessionProbeFailures[host.id] ?? 0) + 1;
        _sessionProbeNextAt[host.id] = _nextProbeAt(host.id, DateTime.now());
        sessionProbeStates[host.id] = SessionProbeState(
          status: SessionProbeStatus.unreachable,
          lastCheckedAt: DateTime.now(),
          lastError: '$error',
        );
      } finally {
        _sessionProbesInFlight.remove(host.id);
        notifyState();
      }
    }());
  }

  DateTime _nextProbeAt(String hostId, DateTime now) {
    final failures = _sessionProbeFailures[hostId] ?? 0;
    final exponent = failures.clamp(0, 4);
    final backoffSeconds =
        _sessionProbeBaseInterval.inSeconds * (1 << exponent);
    final cappedSeconds = backoffSeconds.clamp(60, 15 * 60);
    return now.add(Duration(seconds: cappedSeconds));
  }

  Future<_ProbeResult> _probeHostConnectivity(HostEntry host) async {
    switch (host.connectionType) {
      case ConnectionType.local:
        return _ProbeResult(reachable: true);
      case ConnectionType.serial:
        if ((host.serialPortPath ?? '').trim().isEmpty) {
          return _ProbeResult(reachable: false, error: 'serial-path-empty');
        }
        return _ProbeResult(
          reachable: false,
          error: 'serial-check-unsupported',
        );
      case ConnectionType.ssh:
        final socket = await Socket.connect(
          host.host,
          host.port,
          timeout: _sessionProbeTimeout,
        );
        socket.destroy();
        return _ProbeResult(reachable: true);
      case ConnectionType.telnet:
        final socket = await Socket.connect(
          host.host,
          host.telnetPort,
          timeout: _sessionProbeTimeout,
        );
        socket.destroy();
        return _ProbeResult(reachable: true);
    }
  }

  String _hostFingerprintKey(String hostId, String keyType) {
    final id = hostId.trim();
    final type = normalizeSshHostKeyType(keyType.trim());
    return '$id::$type';
  }

  String _secureHostSecretKey(String hostId) => 'asmote.host.secret.$hostId';

  Map<String, String> _secureStorageOptions() {
    if (Platform.isWindows) {
      return const WindowsOptions(useBackwardCompatibility: false).toMap();
    }
    return const <String, String>{};
  }

  Future<void> _ensureSecureStorageReady() {
    return _secureStorageInit ??= _initializeSecureStorageBackend();
  }

  Future<void> _initializeSecureStorageBackend() async {
    if (!Platform.isWindows) {
      return;
    }
    final current = FlutterSecureStoragePlatform.instance;
    if (current is MethodChannelFlutterSecureStorage) {
      return;
    }

    final options = _secureStorageOptions();
    Map<String, String> legacyData;
    try {
      legacyData = await current.readAll(options: options);
    } catch (_) {
      legacyData = const <String, String>{};
    }

    FlutterSecureStoragePlatform.instance = MethodChannelFlutterSecureStorage();
    final target = FlutterSecureStoragePlatform.instance;

    if (legacyData.isNotEmpty) {
      for (final entry in legacyData.entries) {
        try {
          await target.write(
            key: entry.key,
            value: entry.value,
            options: options,
          );
        } catch (_) {
          // Ignore single-key migration errors.
        }
      }
    }

    try {
      await current.deleteAll(options: options);
    } catch (_) {
      // Ignore legacy cleanup errors.
    }
  }

  Future<bool> verifyHostFingerprint({
    required HostEntry host,
    required String keyType,
    required String fingerprint,
  }) async {
    final rawKeyType = keyType.trim().toLowerCase();
    final normalizedKeyType = normalizeSshHostKeyType(rawKeyType);
    final normalizedFingerprint = normalizeFingerprint(fingerprint);
    if (normalizedKeyType.isEmpty || normalizedFingerprint.isEmpty) {
      return false;
    }
    final fingerprintKey = _hostFingerprintKey(host.id, normalizedKeyType);
    final legacyKey = '${host.id.trim()}::$rawKeyType';
    final existed = normalizeFingerprint(
      knownHostFingerprints[fingerprintKey] ??
          knownHostFingerprints[legacyKey] ??
          '',
    );
    if (existed == normalizedFingerprint) {
      if (legacyKey != fingerprintKey &&
          knownHostFingerprints.containsKey(legacyKey)) {
        knownHostFingerprints.remove(legacyKey);
        knownHostFingerprints[fingerprintKey] = normalizedFingerprint;
        scheduleStateSave();
      }
      return true;
    }

    final knownHostsDecision = await checkOpenSshKnownHostFingerprint(
      host: host.host,
      port: host.port,
      keyType: normalizedKeyType,
      fingerprint: normalizedFingerprint,
    );
    if (knownHostsDecision.trusted) {
      knownHostFingerprints[fingerprintKey] = normalizedFingerprint;
      scheduleStateSave();
      addStructuredLog(
        category: TerminalLogCategory.session,
        message:
            '[HostKey][$normalizedKeyType] accepted from known_hosts ${host.host}:${host.port}',
        notifyListeners: false,
      );
      notifyState();
      return true;
    }
    if (knownHostsDecision.mismatched) {
      addStructuredLog(
        category: TerminalLogCategory.session,
        level: TerminalLogLevel.warn,
        message:
            '[HostKey][$normalizedKeyType] mismatch with known_hosts ${host.host}:${host.port}',
        notifyListeners: false,
      );
      return false;
    }

    final promptId = 'host-key-${DateTime.now().microsecondsSinceEpoch}';
    pendingHostKeyPrompt = HostKeyVerificationPrompt(
      id: promptId,
      hostId: host.id,
      hostDisplayName: host.name.trim().isEmpty ? host.host : host.name,
      hostAddress: '${host.host}:${host.port}',
      keyType: normalizedKeyType,
      fingerprint: normalizedFingerprint,
      existedFingerprint: existed,
      createdAt: DateTime.now(),
    );
    hostKeyPromptToken += 1;
    _hostKeyPromptDecision?.complete(false);
    _hostKeyPromptDecision = Completer<bool>();
    _hostKeyPromptRemember = true;
    notifyState();

    var trusted = false;
    try {
      trusted = await _hostKeyPromptDecision!.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => false,
      );
    } catch (_) {
      trusted = false;
    }

    pendingHostKeyPrompt = null;
    _hostKeyPromptDialogVisible = false;
    _hostKeyPromptDecision = null;
    hostKeyPromptToken += 1;

    if (trusted && _hostKeyPromptRemember) {
      knownHostFingerprints[fingerprintKey] = normalizedFingerprint;
      scheduleStateSave();
      addStructuredLog(
        category: TerminalLogCategory.session,
        message:
            '[HostKey][$normalizedKeyType] trusted ${host.host}:${host.port}',
        notifyListeners: false,
      );
    } else if (!trusted) {
      addStructuredLog(
        category: TerminalLogCategory.session,
        level: TerminalLogLevel.warn,
        message:
            '[HostKey][$normalizedKeyType] rejected ${host.host}:${host.port}',
        notifyListeners: false,
      );
    }
    notifyState();
    return trusted;
  }

  bool beginHostKeyPromptDialog() {
    if (_hostKeyPromptDialogVisible || pendingHostKeyPrompt == null) {
      return false;
    }
    _hostKeyPromptDialogVisible = true;
    return true;
  }

  void endHostKeyPromptDialog() {
    _hostKeyPromptDialogVisible = false;
  }

  void resolveHostKeyPrompt(bool trusted, {bool remember = true}) {
    final decision = _hostKeyPromptDecision;
    if (decision == null || decision.isCompleted) {
      return;
    }
    _hostKeyPromptRemember = remember;
    decision.complete(trusted);
  }

  bool beginShortcutConflictDialog() {
    if (_shortcutConflictDialogVisible || shortcutConflicts.isEmpty) {
      return false;
    }
    _shortcutConflictDialogVisible = true;
    return true;
  }

  void endShortcutConflictDialog() {
    _shortcutConflictDialogVisible = false;
  }

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
          if (existing.id != id) {
            shortcutConflicts.add(
              '$norm → ${existing.name} (${existing.type}) & $name ($type)',
            );
          }
        } else {
          owners[norm] = _ShortcutOwner(id, name, type);
        }
      }
    }
    for (final sb in shortcutBindings) {
      final keys = sb.customKeys ?? sb.defaultKeys;
      register(sb.id, sb.name, keys, 'system');
    }
    for (final kb in customKeyBindings) {
      register(kb.id, kb.name, kb.keys, 'custom');
    }
    for (final entry in scriptShortcutBindings.entries) {
      final script = scripts.where((s) => s.id == entry.value).firstOrNull;
      final name = script?.name ?? entry.value;
      register(entry.key, name, entry.key, 'script');
    }
    if (shortcutConflicts.isNotEmpty) {
      shortcutConflictToken++;
      notifyState();
    }
  }

  String _normalizeShortcutCombo(String combo) {
    final parts = combo.split('+').map((p) => p.trim()).toList();
    final mods = <String>[];
    String? key;
    for (final part in parts) {
      switch (part) {
        case 'Ctrl':
        case 'Alt':
        case 'Shift':
        case 'Meta':
          mods.add(part);
          break;
        default:
          key = part;
      }
    }
    if (key == null || key.isEmpty) return '';
    mods.sort();
    return mods.isEmpty ? key : '${mods.join('+')}+$key';
  }

  Future<StoredHostSecret?> readHostSecret(String hostId) async {
    await _ensureSecureStorageReady();
    try {
      final raw = await _secureStorage.read(
        key: _secureHostSecretKey(hostId),
        wOptions: Platform.isWindows
            ? const WindowsOptions(useBackwardCompatibility: false)
            : null,
      );
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return StoredHostSecret.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeHostSecret(HostEntry host) async {
    await _ensureSecureStorageReady();
    try {
      final secret = StoredHostSecret(
        password: host.password,
        privateKeyPath: host.privateKeyPath,
        privateKeyPassphrase: host.privateKeyPassphrase,
        socksProxyPassword: host.socksProxyPassword,
      );
      final hasSecret =
          (secret.password ?? '').trim().isNotEmpty ||
          (secret.privateKeyPath ?? '').trim().isNotEmpty ||
          (secret.privateKeyPassphrase ?? '').trim().isNotEmpty ||
          (secret.socksProxyPassword ?? '').trim().isNotEmpty;
      final key = _secureHostSecretKey(host.id);
      if (!hasSecret) {
        await _secureStorage.delete(
          key: key,
          wOptions: Platform.isWindows
              ? const WindowsOptions(useBackwardCompatibility: false)
              : null,
        );
        return;
      }
      await _secureStorage.write(
        key: key,
        value: jsonEncode(secret.toJson()),
        wOptions: Platform.isWindows
            ? const WindowsOptions(useBackwardCompatibility: false)
            : null,
      );
    } catch (_) {
      // Ignore secure storage write errors.
    }
  }

  Future<void> _deleteHostSecret(String hostId) async {
    await _ensureSecureStorageReady();
    try {
      await _secureStorage.delete(
        key: _secureHostSecretKey(hostId),
        wOptions: Platform.isWindows
            ? const WindowsOptions(useBackwardCompatibility: false)
            : null,
      );
    } catch (_) {
      // Ignore secure storage delete errors.
    }
  }

  Future<void> _synchronizeHostSecrets() async {
    await _ensureSecureStorageReady();
    for (int i = 0; i < hosts.length; i++) {
      try {
        final host = hosts[i];
        final stored = await readHostSecret(host.id);
        if (stored != null) {
          hosts[i] = host.copyWith(
            password: stored.password,
            privateKeyPath: stored.privateKeyPath,
            privateKeyPassphrase: stored.privateKeyPassphrase,
            socksProxyPassword: stored.socksProxyPassword,
          );
        } else {
          final hasSecrets =
              (host.password ?? '').trim().isNotEmpty ||
              (host.privateKeyPassphrase ?? '').trim().isNotEmpty ||
              (host.socksProxyPassword ?? '').trim().isNotEmpty;
          if (hasSecrets) {
            await _writeHostSecret(host);
          }
        }
      } catch (_) {
        // Ignore per-host secret sync errors.
      }
    }
  }

  void clearError() {
    lastError = null;
    notifyState();
  }

  void setShowHiddenFiles(bool value) {
    showHiddenFiles = value;
    scheduleStateSave();
    notifyState();
  }

  void setAutoReconnect(bool value) {
    autoReconnect = value;
    scheduleStateSave();
    syncSshForegroundGuardNow();
    notifyState();
  }

  void setAndroidKeepSshAliveInBackground(bool value) {
    if (androidKeepSshAliveInBackground == value) return;
    androidKeepSshAliveInBackground = value;
    scheduleStateSave();
    syncSshForegroundGuardNow();
    addStructuredLog(
      category: TerminalLogCategory.session,
      message: value
          ? AppStrings.values.sshForegroundGuardEnabled.resolve(
              locale.languageCode,
            )
          : AppStrings.values.sshForegroundGuardDisabled.resolve(
              locale.languageCode,
            ),
      notifyListeners: false,
    );
    notifyState();
  }

  void setConfirmPaste(bool value) {
    confirmPaste = value;
    scheduleStateSave();
    notifyState();
  }

  void setReuseSessionForNewPane(bool value) {
    reuseSessionForNewPane = value;
    scheduleStateSave();
    notifyState();
  }

  void setHomeLayoutMode(HomeLayoutMode value) {
    if (homeLayoutMode == value) return;
    homeLayoutMode = value;
    scheduleStateSave();
    notifyState();
  }

  void setTerminalSplitViewEnabled(bool value) {
    if (terminalSplitViewEnabled == value) return;
    terminalSplitViewEnabled = value;
    if (value) {
      ensureTerminalSplitPanes();
    } else {
      maximizedTerminalSplitPaneId = '';
    }
    scheduleStateSave();
    notifyState();
  }

  void setTerminalSplitLayout(TerminalSplitLayout value) {
    if (terminalSplitLayout == value) return;
    final preservedSessionIds = [
      for (final pane in terminalSplitPanes) pane.sessionId,
    ];
    terminalSplitLayout = value;
    terminalSplitTree = null;
    terminalSplitPanes.clear();
    final capacity = switch (terminalSplitLayout) {
      TerminalSplitLayout.horizontal || TerminalSplitLayout.vertical => 2,
      TerminalSplitLayout.grid => 4,
    };
    for (var index = 0; index < capacity; index++) {
      final sessionId = index < preservedSessionIds.length
          ? preservedSessionIds[index]
          : '';
      terminalSplitPanes.add(
        TerminalSplitPaneConfig(
          id: 'pane-$index',
          sessionId: sessions.any((session) => session.id == sessionId)
              ? sessionId
              : '',
        ),
      );
    }
    terminalSplitTree = _initialTerminalSplitTree(terminalSplitPanes);
    ensureTerminalSplitPanes();
    scheduleStateSave();
    notifyState();
  }

  int get terminalSplitPaneCapacity {
    if (!terminalSplitViewEnabled) {
      return 1;
    }
    return terminalSplitTree?.paneIds.length ??
        switch (terminalSplitLayout) {
          TerminalSplitLayout.horizontal || TerminalSplitLayout.vertical => 2,
          TerminalSplitLayout.grid => 4,
        };
  }

  TerminalSession? terminalSessionById(String id) {
    if (id.trim().isEmpty) return null;
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  TerminalSession? terminalSessionForHost(HostEntry host) {
    final key = _hostConnectionKey(host);
    for (final session in sessions.reversed) {
      if (_hostConnectionKey(session.profile) == key) return session;
    }
    return null;
  }

  String? backgroundImagePathForPane(String paneId) {
    final pane = _terminalSplitPaneById(paneId);
    if (pane != null && pane.backgroundImageId.isNotEmpty) {
      for (final entry in terminalBackgroundImages) {
        if (entry.id == pane.backgroundImageId) return entry.path;
      }
    }
    return null;
  }

  void addBackgroundImage(String path) {
    final id = 'bg-$_nextBgImageId';
    _nextBgImageId++;
    final name = path.split(Platform.pathSeparator).last;
    terminalBackgroundImages.add(BackgroundImageEntry(id: id, path: path, name: name));
    scheduleStateSave();
    notifyState();
  }

  void removeBackgroundImage(String id) {
    terminalBackgroundImages.removeWhere((e) => e.id == id);
    for (var i = 0; i < terminalSplitPanes.length; i++) {
      if (terminalSplitPanes[i].backgroundImageId == id) {
        terminalSplitPanes[i] = terminalSplitPanes[i].copyWith(backgroundImageId: '');
      }
    }
    scheduleStateSave();
    notifyState();
  }

  void setTerminalSplitPaneBackground(String paneId, String imageId) {
    final index = terminalSplitPanes.indexWhere((pane) => pane.id == paneId);
    if (index < 0) return;
    terminalSplitPanes[index] = terminalSplitPanes[index].copyWith(backgroundImageId: imageId);
    scheduleStateSave();
    notifyState();
  }

  TerminalSession? _firstUnusedTerminalSplitSession() {
    for (final session in sessions) {
      final used = terminalSplitPanes.any(
        (pane) => pane.sessionId == session.id,
      );
      if (!used) return session;
    }
    return null;
  }

  TerminalSplitPaneConfig? _terminalSplitPaneById(String paneId) {
    for (final pane in terminalSplitPanes) {
      if (pane.id == paneId) return pane;
    }
    return null;
  }

  String _newTerminalSplitId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_terminalSplitIdSeed++}';
  }

  TerminalSplitTreeNode _leafTerminalSplitTree(String paneId) {
    return TerminalSplitTreeNode.leaf(
      id: _newTerminalSplitId('split-leaf'),
      paneId: paneId,
    );
  }

  TerminalSplitTreeNode _buildTerminalSplitTreeFromPanes(
    List<TerminalSplitPaneConfig> panes,
  ) {
    if (panes.isEmpty) {
      return _leafTerminalSplitTree('pane-0');
    }
    if (panes.length == 1) {
      return _leafTerminalSplitTree(panes.first.id);
    }
    if (panes.length == 2) {
      return TerminalSplitTreeNode.split(
        id: _newTerminalSplitId('split-node'),
        axis: terminalSplitLayout == TerminalSplitLayout.vertical
            ? TerminalSplitAxis.column
            : TerminalSplitAxis.row,
        ratio: terminalSplitPrimaryRatio.clamp(0.15, 0.85).toDouble(),
        first: _leafTerminalSplitTree(panes[0].id),
        second: _leafTerminalSplitTree(panes[1].id),
      );
    }
    final firstRow = TerminalSplitTreeNode.split(
      id: _newTerminalSplitId('split-node'),
      axis: TerminalSplitAxis.row,
      ratio: terminalSplitSecondaryRatio.clamp(0.15, 0.85).toDouble(),
      first: _leafTerminalSplitTree(panes[0].id),
      second: _leafTerminalSplitTree(panes[1].id),
    );
    final secondRow = TerminalSplitTreeNode.split(
      id: _newTerminalSplitId('split-node'),
      axis: TerminalSplitAxis.row,
      ratio: terminalSplitSecondaryRatio.clamp(0.15, 0.85).toDouble(),
      first: _leafTerminalSplitTree(panes[2].id),
      second: _leafTerminalSplitTree(panes[3].id),
    );
    return TerminalSplitTreeNode.split(
      id: _newTerminalSplitId('split-node'),
      axis: TerminalSplitAxis.column,
      ratio: terminalSplitPrimaryRatio.clamp(0.15, 0.85).toDouble(),
      first: firstRow,
      second: secondRow,
    );
  }

  TerminalSplitTreeNode _initialTerminalSplitTree(
    List<TerminalSplitPaneConfig> panes,
  ) {
    return _buildTerminalSplitTreeFromPanes(panes);
  }

  TerminalSplitTreeNode _sanitizeTerminalSplitTree(
    TerminalSplitTreeNode node,
    Set<String> validPaneIds,
  ) {
    if (node.isLeaf) {
      if (validPaneIds.contains(node.paneId)) return node;
      return _leafTerminalSplitTree(
        validPaneIds.isEmpty ? 'pane-0' : validPaneIds.first,
      );
    }
    final first = node.first;
    final second = node.second;
    if (first == null || second == null) {
      return _leafTerminalSplitTree(
        validPaneIds.isEmpty ? 'pane-0' : validPaneIds.first,
      );
    }
    return node.copyWith(
      ratio: node.ratio.clamp(0.15, 0.85).toDouble(),
      first: _sanitizeTerminalSplitTree(first, validPaneIds),
      second: _sanitizeTerminalSplitTree(second, validPaneIds),
    );
  }

  void ensureTerminalSplitPanes() {
    final hadPanes = terminalSplitPanes.isNotEmpty;
    final existingSessionIds = <String>[];
    for (final pane in terminalSplitPanes) {
      final sessionId = pane.sessionId;
      if (sessionId.isEmpty ||
          sessions.any((session) => session.id == sessionId)) {
        existingSessionIds.add(sessionId);
      }
    }

    final legacyCapacity = switch (terminalSplitLayout) {
      TerminalSplitLayout.horizontal || TerminalSplitLayout.vertical => 2,
      TerminalSplitLayout.grid => 4,
    };
    final existingTreePaneIds =
        terminalSplitTree?.paneIds.toList(growable: false) ?? const <String>[];
    if (terminalSplitPanes.isEmpty && existingTreePaneIds.isNotEmpty) {
      for (var index = 0; index < existingTreePaneIds.length; index++) {
        terminalSplitPanes.add(
          TerminalSplitPaneConfig(
            id: existingTreePaneIds[index],
            sessionId: index < existingSessionIds.length
                ? existingSessionIds[index]
                : '',
          ),
        );
      }
    } else if (terminalSplitPanes.isEmpty) {
      for (var index = 0; index < legacyCapacity; index++) {
        var sessionId = index < existingSessionIds.length
            ? existingSessionIds[index]
            : '';
        if (sessionId.isEmpty && index == 0 && !hadPanes) {
          sessionId = activeSession?.id ?? '';
        } else if (sessionId.isEmpty && index >= existingSessionIds.length) {
          sessionId = _firstUnusedTerminalSplitSession()?.id ?? '';
        }
        terminalSplitPanes.add(
          TerminalSplitPaneConfig(id: 'pane-$index', sessionId: sessionId),
        );
      }
      terminalSplitTree = _initialTerminalSplitTree(terminalSplitPanes);
    } else {
      terminalSplitTree ??= _initialTerminalSplitTree(terminalSplitPanes);
    }

    final paneIds = terminalSplitTree?.paneIds.toSet() ?? <String>{};
    terminalSplitPanes.removeWhere((pane) => !paneIds.contains(pane.id));
    for (final paneId in paneIds) {
      if (!terminalSplitPanes.any((pane) => pane.id == paneId)) {
        terminalSplitPanes.add(TerminalSplitPaneConfig(id: paneId));
      }
    }
    final validPaneIds = terminalSplitPanes.map((pane) => pane.id).toSet();
    final tree = terminalSplitTree;
    if (tree != null) {
      terminalSplitTree = _sanitizeTerminalSplitTree(tree, validPaneIds);
    }
    if (activeTerminalSplitPaneId.isEmpty ||
        !terminalSplitPanes.any(
          (pane) => pane.id == activeTerminalSplitPaneId,
        )) {
      activeTerminalSplitPaneId = terminalSplitPanes.isEmpty
          ? ''
          : terminalSplitPanes.first.id;
    }
    if (maximizedTerminalSplitPaneId.isNotEmpty &&
        !terminalSplitPanes.any(
          (pane) => pane.id == maximizedTerminalSplitPaneId,
        )) {
      maximizedTerminalSplitPaneId = '';
    }
  }

  void setTerminalSplitPaneSession(String paneId, String sessionId) {
    ensureTerminalSplitPanes();
    final index = terminalSplitPanes.indexWhere((pane) => pane.id == paneId);
    if (index < 0) return;
    terminalSplitPanes[index] = terminalSplitPanes[index].copyWith(
      sessionId: sessionId,
    );
    focusTerminalSplitPane(paneId);
    scheduleStateSave();
    notifyState();
  }

  void setActiveTerminalSession(String sessionId) {
    final session = terminalSessionById(sessionId);
    if (session == null) return;
    ensureTerminalSplitPanes();
    final paneId = activeTerminalSplitPaneId.isEmpty
        ? (terminalSplitPanes.isEmpty ? 'pane-0' : terminalSplitPanes.first.id)
        : activeTerminalSplitPaneId;
    final index = terminalSplitPanes.indexWhere((pane) => pane.id == paneId);
    if (index >= 0) {
      terminalSplitPanes[index] = terminalSplitPanes[index].copyWith(
        sessionId: sessionId,
      );
      activeTerminalSplitPaneId = paneId;
    }
    final sessionIndex = sessions.indexOf(session);
    if (sessionIndex >= 0) {
      activeSessionIndexValue = sessionIndex;
    }
    scheduleStateSave();
    notifyState();
  }

  void focusTerminalSplitPane(String paneId) {
    ensureTerminalSplitPanes();
    final pane = _terminalSplitPaneById(paneId);
    if (pane == null) return;
    activeTerminalSplitPaneId = paneId;
    final session = terminalSessionById(pane.sessionId);
    if (session != null) {
      final index = sessions.indexOf(session);
      if (index >= 0) {
        activeSessionIndexValue = index;
      }
    }
    scheduleStateSave();
    notifyState();
  }

  void clearTerminalSplitPane(String paneId) {
    ensureTerminalSplitPanes();
    final index = terminalSplitPanes.indexWhere((pane) => pane.id == paneId);
    if (index < 0) return;
    terminalSplitPanes[index] = terminalSplitPanes[index].copyWith(
      sessionId: '',
    );
    if (maximizedTerminalSplitPaneId == paneId) {
      maximizedTerminalSplitPaneId = '';
    }
    scheduleStateSave();
    notifyState();
  }

  TerminalSplitTreeNode? _replaceTerminalSplitTreeNode(
    TerminalSplitTreeNode? node,
    String targetNodeId,
    TerminalSplitTreeNode Function(TerminalSplitTreeNode node) replace,
  ) {
    if (node == null) return null;
    if (node.id == targetNodeId) return replace(node);
    if (node.isLeaf) return node;
    final first = _replaceTerminalSplitTreeNode(
      node.first,
      targetNodeId,
      replace,
    );
    final second = _replaceTerminalSplitTreeNode(
      node.second,
      targetNodeId,
      replace,
    );
    if (first == null || second == null) return node;
    return node.copyWith(first: first, second: second);
  }

  TerminalSplitTreeNode? _removeTerminalSplitPaneFromTree(
    TerminalSplitTreeNode? node,
    String paneId,
  ) {
    if (node == null) return null;
    if (node.isLeaf) return node.paneId == paneId ? null : node;
    final first = _removeTerminalSplitPaneFromTree(node.first, paneId);
    final second = _removeTerminalSplitPaneFromTree(node.second, paneId);
    if (first == null) return second;
    if (second == null) return first;
    return node.copyWith(first: first, second: second);
  }

  void splitTerminalSplitPane(String paneId, TerminalSplitAxis axis) {
    ensureTerminalSplitPanes();
    final pane = _terminalSplitPaneById(paneId);
    if (pane == null) return;
    final newPaneId = _newTerminalSplitId('pane');
    final nextSession = _firstUnusedTerminalSplitSession()?.id ?? '';
    terminalSplitPanes.add(
      TerminalSplitPaneConfig(id: newPaneId, sessionId: nextSession),
    );
    final leafId = terminalSplitTreeLeafIdForPane(paneId);
    if (leafId == null) {
      terminalSplitPanes.removeWhere((pane) => pane.id == newPaneId);
      return;
    }
    terminalSplitTree = _replaceTerminalSplitTreeNode(
      terminalSplitTree,
      leafId,
      (node) => TerminalSplitTreeNode.split(
        id: _newTerminalSplitId('split-node'),
        axis: axis,
        ratio: 0.5,
        first: node,
        second: _leafTerminalSplitTree(newPaneId),
      ),
    );
    activeTerminalSplitPaneId = newPaneId;
    terminalSplitViewEnabled = true;
    scheduleStateSave();
    notifyState();
  }

  String? terminalSplitTreeLeafIdForPane(String paneId) {
    String? visit(TerminalSplitTreeNode? node) {
      if (node == null) return null;
      if (node.isLeaf) return node.paneId == paneId ? node.id : null;
      return visit(node.first) ?? visit(node.second);
    }

    return visit(terminalSplitTree);
  }

  void removeTerminalSplitPane(String paneId) {
    ensureTerminalSplitPanes();
    if (terminalSplitPanes.length <= 1) {
      clearTerminalSplitPane(paneId);
      return;
    }
    terminalSplitTree = _removeTerminalSplitPaneFromTree(
      terminalSplitTree,
      paneId,
    );
    terminalSplitPanes.removeWhere((pane) => pane.id == paneId);
    if (activeTerminalSplitPaneId == paneId) {
      activeTerminalSplitPaneId = terminalSplitPanes.isEmpty
          ? ''
          : terminalSplitPanes.first.id;
    }
    if (maximizedTerminalSplitPaneId == paneId) {
      maximizedTerminalSplitPaneId = '';
    }
    scheduleStateSave();
    notifyState();
  }

  void setTerminalSplitNodeRatio(
    String nodeId,
    double value, {
    bool persist = true,
  }) {
    final next = value.clamp(0.15, 0.85).toDouble();
    terminalSplitTree = _replaceTerminalSplitTreeNode(
      terminalSplitTree,
      nodeId,
      (node) => node.copyWith(ratio: next),
    );
    if (persist) {
      scheduleStateSave();
    }
    notifyState();
  }

  void adjustTerminalSplitNodeRatio(
    String nodeId,
    double delta, {
    bool persist = true,
  }) {
    var changed = false;
    terminalSplitTree = _replaceTerminalSplitTreeNode(
      terminalSplitTree,
      nodeId,
      (node) {
        final next = (node.ratio + delta).clamp(0.15, 0.85).toDouble();
        if ((node.ratio - next).abs() < 0.0001) {
          return node;
        }
        changed = true;
        return node.copyWith(ratio: next);
      },
    );
    if (!changed) return;
    if (persist) {
      scheduleStateSave();
    }
    notifyState();
  }

  void saveTerminalSplitLayoutState() {
    scheduleStateSave();
  }

  void toggleMaximizedTerminalSplitPane(String paneId) {
    ensureTerminalSplitPanes();
    maximizedTerminalSplitPaneId = maximizedTerminalSplitPaneId == paneId
        ? ''
        : paneId;
    focusTerminalSplitPane(paneId);
  }


  void applyShortcutPreset(ShortcutPreset preset) {
    shortcutPresetId = preset.id;
    for (final sb in preset.bindings) {
      final idx = shortcutBindings.indexWhere((s) => s.id == sb.id);
      if (idx >= 0) {
        shortcutBindings[idx] = shortcutBindings[idx].copyWith(customKeys: sb.customKeys);
      }
    }
    scheduleStateSave();
    notifyState();
  }

  void setTerminalSplitPrimaryRatio(double value) {
    final next = value.clamp(0.2, 0.8).toDouble();
    if ((terminalSplitPrimaryRatio - next).abs() < 0.001) return;
    terminalSplitPrimaryRatio = next;
    scheduleStateSave();
    notifyState();
  }

  void setTerminalSplitSecondaryRatio(double value) {
    final next = value.clamp(0.2, 0.8).toDouble();
    if ((terminalSplitSecondaryRatio - next).abs() < 0.001) return;
    terminalSplitSecondaryRatio = next;
    scheduleStateSave();
    notifyState();
  }

  void saveCurrentTerminalSplitTemplate(String name) {
    ensureTerminalSplitPanes();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    terminalSplitTemplates.removeWhere((template) => template.name == trimmed);
    terminalSplitTemplates.add(
      TerminalSplitTemplate(
        id: 'split-template-${DateTime.now().microsecondsSinceEpoch}',
        name: trimmed,
        layout: terminalSplitLayout,
        panes: terminalSplitPanes.toList(growable: false),
        tree: terminalSplitTree,
        primaryRatio: terminalSplitPrimaryRatio,
        secondaryRatio: terminalSplitSecondaryRatio,
      ),
    );
    scheduleStateSave();
    notifyState();
  }

  void applyTerminalSplitTemplate(TerminalSplitTemplate template) {
    terminalSplitLayout = template.layout;
    terminalSplitPanes
      ..clear()
      ..addAll(template.panes);
    terminalSplitTree = template.tree;
    terminalSplitPrimaryRatio = template.primaryRatio
        .clamp(0.2, 0.8)
        .toDouble();
    terminalSplitSecondaryRatio = template.secondaryRatio
        .clamp(0.2, 0.8)
        .toDouble();
    terminalSplitViewEnabled = true;
    ensureTerminalSplitPanes();
    scheduleStateSave();
    notifyState();
  }

  void setMobileSidebarWidth(double value) {
    final next = value.clamp(mobileSidebarWidthMin, mobileSidebarWidthMax);
    if (mobileSidebarWidth == next) return;
    mobileSidebarWidth = next;
    scheduleStateSave();
    notifyState();
  }

  double mobileSidebarWidthMaxForViewport(double viewportWidth) {
    if (!viewportWidth.isFinite || viewportWidth <= 0) {
      return mobileSidebarWidthMax;
    }
    final maxByViewport = viewportWidth * 0.75;
    final bounded = maxByViewport.clamp(120.0, mobileSidebarWidthMax);
    return bounded.toDouble();
  }

  double mobileSidebarWidthMinForViewport(double viewportWidth) {
    final max = mobileSidebarWidthMaxForViewport(viewportWidth);
    if (max < mobileSidebarWidthMin) {
      return max;
    }
    return mobileSidebarWidthMin;
  }

  double normalizeMobileSidebarWidthForViewport(
    double value,
    double viewportWidth,
  ) {
    final min = mobileSidebarWidthMinForViewport(viewportWidth);
    final max = mobileSidebarWidthMaxForViewport(viewportWidth);
    final normalized = value.clamp(min, max);
    return normalized.toDouble();
  }

  void setMobileSidebarWidthForViewport(double value, double viewportWidth) {
    final next = normalizeMobileSidebarWidthForViewport(value, viewportWidth);
    if (mobileSidebarWidth == next) return;
    mobileSidebarWidth = next;
    scheduleStateSave();
    notifyState();
  }

  void setTerminalHorizontalScrollEnabled(bool value) {
    if (terminalHorizontalScrollEnabled == value) return;
    terminalHorizontalScrollEnabled = value;
    scheduleStateSave();
    notifyState();
  }

  void setMobileTerminalColumns(int value) {
    final next = value
        .clamp(mobileTerminalColumnsMin, mobileTerminalColumnsMax)
        .toInt();
    if (mobileTerminalColumns == next) return;
    mobileTerminalColumns = next;
    scheduleStateSave();
    notifyState();
  }

  void setTerminalAccessibilitySemanticsEnabled(bool value) {
    if (terminalAccessibilitySemanticsEnabled == value) return;
    terminalAccessibilitySemanticsEnabled = value;
    scheduleStateSave();
    notifyState();
  }

  void setTransferAutoRetryEnabled(bool value) {
    if (transferAutoRetryEnabled == value) return;
    transferAutoRetryEnabled = value;
    scheduleStateSave();
    notifyState();
  }

  void setTransferResumeEnabled(bool value) {
    if (transferResumeEnabled == value) return;
    transferResumeEnabled = value;
    scheduleStateSave();
    notifyState();
  }

  void setTransferRetryPolicy({
    int? maxAttempts,
    int? baseDelayMs,
    int? maxDelayMs,
  }) {
    final nextMaxAttempts = (maxAttempts ?? transferRetryMaxAttempts).clamp(
      1,
      12,
    );
    final nextBaseDelay = (baseDelayMs ?? transferRetryBaseDelayMs).clamp(
      100,
      120000,
    );
    final nextMaxDelay = (maxDelayMs ?? transferRetryMaxDelayMs).clamp(
      nextBaseDelay,
      300000,
    );
    if (nextMaxAttempts == transferRetryMaxAttempts &&
        nextBaseDelay == transferRetryBaseDelayMs &&
        nextMaxDelay == transferRetryMaxDelayMs) {
      return;
    }
    transferRetryMaxAttempts = nextMaxAttempts;
    transferRetryBaseDelayMs = nextBaseDelay;
    transferRetryMaxDelayMs = nextMaxDelay;
    scheduleStateSave();
    notifyState();
  }

  void recordCommandHistory(String hostId, String command) {
    final normalizedHostId = hostId.trim();
    final normalizedCommand = command.trim();
    if (normalizedHostId.isEmpty || normalizedCommand.isEmpty) {
      return;
    }
    final existing = commandHistoryByHost[normalizedHostId];
    final list = existing == null
        ? <String>[]
        : List<String>.from(existing, growable: true);
    if (list.isNotEmpty && list.last == normalizedCommand) {
      return;
    }
    list.add(normalizedCommand);
    if (list.length > commandHistoryPerHostCap) {
      list.removeRange(0, list.length - commandHistoryPerHostCap);
    }
    commandHistoryByHost[normalizedHostId] = list;
    scheduleStateSave();
    notifyState();
  }

  List<VisitedFileEntry> recentVisitedFiles({int limit = 30}) {
    if (visitedFiles.isEmpty) {
      return const <VisitedFileEntry>[];
    }
    final safeLimit = limit.clamp(1, visitedFiles.length);
    return List<VisitedFileEntry>.from(
      visitedFiles.take(safeLimit),
      growable: false,
    );
  }

  List<HostEntry> recentHosts({int limit = 30}) {
    final recent =
        hosts
            .where((host) => host.lastConnected != null)
            .toList(growable: false)
          ..sort((a, b) => b.lastConnected!.compareTo(a.lastConnected!));
    if (recent.isEmpty) {
      return const <HostEntry>[];
    }
    final safeLimit = limit.clamp(1, recent.length);
    return List<HostEntry>.from(recent.take(safeLimit), growable: false);
  }

  void recordVisitedFile(TerminalSession session, FileNode node) {
    if (node.isDirectory) {
      return;
    }
    final path = node.path.trim();
    if (path.isEmpty) {
      return;
    }
    final displayName = node.name.trim().isEmpty
        ? p.basename(path)
        : node.name.trim();
    final host = session.profile.host.trim();
    final username = session.profile.username.trim();
    final port = session.profile.port;
    final connectionType = session.profile.connectionType.name;
    final item = VisitedFileEntry(
      hostId: session.profile.id.trim(),
      host: host,
      port: port,
      username: username,
      connectionType: connectionType,
      isLocal: session.profile.isLocal,
      filePath: path,
      displayName: displayName,
      fileSize: node.size,
      fileModifiedAt: node.modified,
      lastVisitedAt: DateTime.now(),
    );
    visitedFiles.removeWhere((entry) => entry.dedupeKey == item.dedupeKey);
    visitedFiles.insert(0, item);
    if (visitedFiles.length > visitedFilesCap) {
      visitedFiles.removeRange(visitedFilesCap, visitedFiles.length);
    }
    scheduleStateSave();
    notifyState();
  }

  HostEntry? resolveHostForVisitedFile(VisitedFileEntry entry) {
    final hostId = entry.hostId.trim();
    if (hostId.isNotEmpty) {
      for (final host in hosts) {
        if (host.id == hostId) {
          return host;
        }
      }
    }
    final normalizedHost = entry.host.trim();
    final normalizedUsername = entry.username.trim();
    final normalizedConnection = entry.connectionType.trim();
    for (final host in hosts) {
      if (host.host.trim() != normalizedHost) {
        continue;
      }
      if (host.username.trim() != normalizedUsername) {
        continue;
      }
      if (host.connectionType.name != normalizedConnection) {
        continue;
      }
      if (host.port != entry.port) {
        continue;
      }
      return host;
    }
    return null;
  }

  TerminalSession? findSessionForHost(String hostId) {
    final normalized = hostId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (var i = sessions.length - 1; i >= 0; i--) {
      final session = sessions[i];
      if (session.profile.id == normalized) {
        return session;
      }
    }
    return null;
  }

  TerminalSession? findConnectedSessionForHost(String hostId) {
    final normalized = hostId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (var i = sessions.length - 1; i >= 0; i--) {
      final session = sessions[i];
      if (session.profile.id != normalized) {
        continue;
      }
      if (session.tab.status == TerminalStatus.connected) {
        return session;
      }
    }
    return null;
  }

  void setLocale(Locale value) {
    locale = value;
    scheduleStateSave();
    notifyState();
  }

  void toggleLocale() {
    locale = locale.languageCode == 'zh'
        ? const Locale('en')
        : const Locale('zh');
    scheduleStateSave();
    notifyState();
  }

  void setNavSection(NavSection section) {
    navSection = section;
    scheduleStateSave();
    notifyState();
  }

  void setSessionQuery(String value) {
    if (sessionQuery == value) return;
    sessionQuery = value;
    notifyState();
  }

  void setSessionFilterOnlineOnly(bool value) {
    if (sessionFilterOnlineOnly == value) return;
    sessionFilterOnlineOnly = value;
    scheduleStateSave();
    notifyState();
  }

  void setSessionFilterPinnedOnly(bool value) {
    if (sessionFilterPinnedOnly == value) return;
    sessionFilterPinnedOnly = value;
    scheduleStateSave();
    notifyState();
  }

  void setSessionGroupFilter(String value) {
    final normalized = value.trim();
    if (sessionGroupFilter == normalized) return;
    sessionGroupFilter = normalized;
    scheduleStateSave();
    notifyState();
  }

  void setSessionSortMode(SessionSortMode mode) {
    if (sessionSortMode == mode) return;
    sessionSortMode = mode;
    scheduleStateSave();
    notifyState();
  }

  TerminalStatus? hostSessionStatus(String hostId) {
    HostEntry? host;
    for (final entry in hosts) {
      if (entry.id == hostId) {
        host = entry;
        break;
      }
    }
    if (host == null) return null;
    final key = _hostConnectionKey(host);
    TerminalStatus? status;
    for (final session in sessions.reversed) {
      if (_hostConnectionKey(session.profile) != key) continue;
      status = session.tab.status;
      if (status == TerminalStatus.connected) {
        break;
      }
    }
    return status;
  }

  List<HostEntry> visibleHosts() {
    final query = sessionQuery.trim().toLowerCase();
    final hasQuery = query.isNotEmpty;
    final groupFilter = sessionGroupFilter;
    final filtered = hosts
        .where((host) {
          final status = hostSessionStatus(host.id);
          if (sessionFilterOnlineOnly && status != TerminalStatus.connected) {
            return false;
          }
          if (sessionFilterPinnedOnly && !isHostPinned(host.id)) {
            return false;
          }
          if (groupFilter.isNotEmpty && host.group.trim() != groupFilter) {
            return false;
          }
          if (!hasQuery) return true;
          final group = host.group.toLowerCase();
          return host.name.toLowerCase().contains(query) ||
              host.host.toLowerCase().contains(query) ||
              host.username.toLowerCase().contains(query) ||
              group.contains(query);
        })
        .toList(growable: false);

    int compareByRecent(HostEntry a, HostEntry b) {
      final left = a.lastConnected;
      final right = b.lastConnected;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    }

    int compareByName(HostEntry a, HostEntry b) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    int compareBySmart(HostEntry a, HostEntry b) {
      final aPinned = isHostPinned(a.id);
      final bPinned = isHostPinned(b.id);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      final aOnline = hostSessionStatus(a.id) == TerminalStatus.connected;
      final bOnline = hostSessionStatus(b.id) == TerminalStatus.connected;
      if (aOnline != bOnline) {
        return aOnline ? -1 : 1;
      }
      final recent = compareByRecent(a, b);
      if (recent != 0) return recent;
      return compareByName(a, b);
    }

    filtered.sort((a, b) {
      final aPinned = isHostPinned(a.id);
      final bPinned = isHostPinned(b.id);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      return switch (sessionSortMode) {
        SessionSortMode.name => compareByName(a, b),
        SessionSortMode.recent => compareByRecent(a, b),
        SessionSortMode.smart => compareBySmart(a, b),
      };
    });
    return filtered;
  }

  void toggleHostSelection(String id, {bool multi = false}) {
    if (multi) {
      if (selectedHostIds.contains(id)) {
        selectedHostIds.remove(id);
      } else {
        selectedHostIds.add(id);
      }
    } else {
      if (selectedHostIds.length == 1 && selectedHostIds.contains(id)) {
        return;
      }
      selectedHostIds
        ..clear()
        ..add(id);
    }
    notifyState();
  }

  void clearHostSelection() {
    if (selectedHostIds.isEmpty) return;
    selectedHostIds.clear();
    notifyState();
  }

  void addHost(HostEntry host) {
    hosts.add(host);
    unawaited(_writeHostSecret(host));
    scheduleStateSave();
    notifyState();
  }

  void updateHost(HostEntry host) {
    final index = hosts.indexWhere((entry) => entry.id == host.id);
    if (index == -1) return;
    hosts[index] = host;
    unawaited(_writeHostSecret(host));
    for (final session in sessions) {
      if (session.profile.id != host.id) continue;
      final currentTitle = session.tab.title;
      if (currentTitle != host.name) {
        session.tab = session.tab.copyWith(title: host.name);
      }
    }
    scheduleStateSave();
    notifyState();
  }

  void removeHost(String id) {
    hosts.removeWhere((entry) => entry.id == id);
    portForwards.removeWhere((entry) => entry.hostId == id);
    unawaited(_deleteHostSecret(id));
    selectedHostIds.remove(id);
    pinnedHostIds.remove(id);
    knownHostFingerprints.removeWhere((key, _) => key.startsWith('$id::'));
    commandHistoryByHost.remove(id);
    _cleanupAutomationCollections();
    scheduleStateSave();
    notifyState();
  }

  void addScript(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now();
    scripts.add(
      ScriptEntry(
        id: 'script-${now.microsecondsSinceEpoch}',
        name: trimmed,
        commands: [trimmed],
        createdAt: now,
        updatedAt: now,
      ),
    );
    scheduleStateSave();
    notifyState();
  }

  void addScriptEntry({
    required String name,
    required List<String> commands,
    String folderId = '',
    List<ScriptStepConfig?>? stepConfigs,
    Map<String, String>? variables,
    Map<String, String>? environment,
  }) {
    final normalizedName = name.trim();
    final normalizedFolderId = folderId.trim();
    final normalizedCommands = commands
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalizedName.isEmpty || normalizedCommands.isEmpty) return;
    final now = DateTime.now();
    scripts.add(
      ScriptEntry(
        id: 'script-${now.microsecondsSinceEpoch}',
        name: normalizedName,
        folderId: normalizedFolderId,
        commands: normalizedCommands,
        createdAt: now,
        updatedAt: now,
        stepConfigs: stepConfigs ?? const <ScriptStepConfig?>[],
        variables: variables ?? const <String, String>{},
        environment: environment ?? const <String, String>{},
      ),
    );
    scheduleStateSave();
    notifyState();
  }

  void updateScriptEntry(
    String id, {
    required String name,
    required List<String> commands,
    String folderId = '',
    List<ScriptStepConfig?>? stepConfigs,
    Map<String, String>? variables,
    Map<String, String>? environment,
  }) {
    final index = scripts.indexWhere((entry) => entry.id == id);
    if (index == -1) return;
    final normalizedName = name.trim();
    final normalizedFolderId = folderId.trim();
    final normalizedCommands = commands
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalizedName.isEmpty || normalizedCommands.isEmpty) return;
    final current = scripts[index];
    scripts[index] = current.copyWith(
      name: normalizedName,
      folderId: normalizedFolderId,
      commands: normalizedCommands,
      updatedAt: DateTime.now(),
      stepConfigs: stepConfigs,
      variables: variables,
      environment: environment,
      lastRunConfig: current.lastRunConfig,
    );
    scheduleStateSave();
    notifyState();
  }

  void removeScriptEntry(String id) {
    scripts.removeWhere((entry) => entry.id == id);
    unbindScriptShortcut(id);
    for (var i = 0; i < scriptWorkflows.length; i++) {
      final workflow = scriptWorkflows[i];
      final nextNodes = workflow.nodes
          .where((node) => node.scriptId != id)
          .toList(growable: false);
      if (nextNodes.length == workflow.nodes.length) {
        continue;
      }
      scriptWorkflows[i] = workflow.copyWith(
        nodes: nextNodes,
        updatedAt: DateTime.now(),
      );
    }
    scriptWorkflows.removeWhere((workflow) => workflow.nodes.isEmpty);
    scriptBatchTemplates.removeWhere((entry) => entry.scriptId == id);
    scriptTriggers.removeWhere((entry) => entry.scriptId == id);
    scriptSchedules.removeWhere((entry) => entry.scriptId == id);
    scriptRunHistory.removeWhere((entry) => entry.scriptId == id);
    scheduleStateSave();
    notifyState();
  }

  void moveScriptEntry(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= scripts.length) return;
    final targetIndex = toIndex.clamp(0, scripts.length);
    if (fromIndex == targetIndex || fromIndex + 1 == targetIndex) return;
    final item = scripts.removeAt(fromIndex);
    final insertAt = targetIndex > fromIndex ? targetIndex - 1 : targetIndex;
    scripts.insert(insertAt, item);
    scheduleStateSave();
    notifyState();
  }

  void renameSessionTab(TerminalSession session, String title) {
    session.tab = session.tab.copyWith(title: title);
    scheduleStateSave();
    notifyState();
  }

  ScriptRunSession? findActiveScriptRun(String runId) {
    return activeScriptRuns[runId];
  }

  void dismissScriptRun(String runId) {
    activeScriptRuns.remove(runId);
    if (focusedScriptRunId == runId) {
      focusedScriptRunId = null;
    }
    notifyState();
  }

  void dismissFinishedScriptRuns() {
    final finished = activeScriptRuns.entries
        .where((e) => e.value.isFinished)
        .map((e) => e.key)
        .toList();
    for (final runId in finished) {
      activeScriptRuns.remove(runId);
      if (focusedScriptRunId == runId) {
        focusedScriptRunId = null;
      }
    }
    if (finished.isNotEmpty) {
      notifyState();
    }
  }

  void cancelScriptRun(String runId) {
    final session = activeScriptRuns[runId];
    if (session == null) return;
    session.cancel();
    notifyScriptRunCancelled(runId, session.scriptId);
    notifyState();
  }

  void toggleScriptMonitorInline() {
    showScriptMonitorInline = !showScriptMonitorInline;
    notifyState();
  }

  String get nextScriptRunId {
    _nextScriptRunId++;
    return 'run-${DateTime.now().microsecondsSinceEpoch}-$_nextScriptRunId';
  }

  void notifyState() {
    notifyListeners();
  }

  void triggerScriptMultiSelect() {
    scriptMultiSelectActive = !scriptMultiSelectActive;
    scriptMultiSelectToken += 1;
    notifyState();
  }

  void setSettingsTabIndex(int value) {
    final next = value.clamp(0, 6);
    if (settingsTabIndex == next) return;
    settingsTabIndex = next;
    notifyState();
  }

  void setError(String message) {
    final now = DateTime.now();
    final compact = _compactLogMessage(message, max: 320);
    if (compact.isEmpty) {
      return;
    }
    final cooldownUntil = _errorCooldownUntil[compact];
    if (cooldownUntil != null && now.isBefore(cooldownUntil)) {
      return;
    }
    _errorCooldownUntil[compact] = now.add(const Duration(seconds: 5));
    lastError = compact;
    addStructuredLog(
      category: TerminalLogCategory.system,
      level: TerminalLogLevel.error,
      message: _l(AppStrings.values.logErrorVar, params: {'message': compact}),
      notifyListeners: false,
    );
    notifyState();
  }

  void triggerKeyboardRecovery({String? reason}) {
    keyboardRecoveryToken += 1;
    final detail = (reason ?? '').trim();
    if (detail.isEmpty) {
      addStructuredLog(
        category: TerminalLogCategory.system,
        message: _l(AppStrings.values.logKeyboardRecoveryTriggered),
        notifyListeners: false,
      );
    } else {
      addStructuredLog(
        category: TerminalLogCategory.system,
        message: _l(
          AppStrings.values.logKeyboardRecoveryTriggeredReasonVar,
          params: {'reason': detail},
        ),
        notifyListeners: false,
      );
    }
    notifyState();
  }

  String joinRemote(String parent, String child) {
    if (parent.endsWith('/')) return '$parent$child';
    return '$parent/$child';
  }

  String parentOf(String path) {
    if (!path.contains('/')) return '/';
    final parent = p.posix.dirname(path.replaceAll('\\', '/'));
    return parent.isEmpty ? '/' : parent;
  }

  TerminalSession? findSessionById(String id) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  Future<Directory> resolveDesktopDirectory() async {
    if (Platform.isWindows) {
      final oneDriveCandidates = <String?>[
        Platform.environment['OneDrive'],
        Platform.environment['OneDriveConsumer'],
        Platform.environment['OneDriveCommercial'],
      ];
      for (final base in oneDriveCandidates) {
        if (base == null || base.isEmpty) continue;
        final desktop = Directory(p.join(base, 'Desktop'));
        if (await desktop.exists()) {
          return desktop;
        }
      }
      final profile =
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOMEPATH'];
      if (profile != null && profile.isNotEmpty) {
        final oneDriveDesktop = Directory(
          p.join(profile, 'OneDrive', 'Desktop'),
        );
        if (await oneDriveDesktop.exists()) {
          return oneDriveDesktop;
        }
        final desktop = Directory(p.join(profile, 'Desktop'));
        if (await desktop.exists()) {
          return desktop;
        }
      }
    } else {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final desktop = Directory(p.join(home, 'Desktop'));
        if (await desktop.exists()) {
          return desktop;
        }
      }
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null && await downloads.exists()) {
      return downloads;
    }
    return getApplicationDocumentsDirectory();
  }

  static const int _maxInMemoryLogLines = 1000;

  void addLog(String message, {bool notifyListeners = true}) {
    final now = DateTime.now();
    final timestamp = _formatLogTimestamp(now);
    final line = '[$timestamp] $message';
    logs.add(line);
    if (logs.length > _maxInMemoryLogLines) {
      logs.removeRange(0, logs.length - _maxInMemoryLogLines);
    }
    _appendLog(line, timestamp: now);
    _maybePruneLogs();
    if (notifyListeners) {
      notifyState();
    }
  }

  String _l(AppText text, {Map<String, String> params = const {}}) {
    return text.resolve(locale.languageCode, params: params);
  }

  String _logCategoryLabel(TerminalLogCategory category) {
    switch (category) {
      case TerminalLogCategory.startup:
        return _l(AppStrings.values.logCategoryStartup);
      case TerminalLogCategory.session:
        return _l(AppStrings.values.logCategorySession);
      case TerminalLogCategory.transfer:
        return _l(AppStrings.values.logCategoryTransfer);
      case TerminalLogCategory.externalEdit:
        return _l(AppStrings.values.logCategoryExternalEdit);
      case TerminalLogCategory.system:
        return _l(AppStrings.values.logCategorySystem);
      case TerminalLogCategory.ui:
        return _l(AppStrings.values.logCategoryUi);
      case TerminalLogCategory.script:
        return _l(AppStrings.values.logCategoryScript);
    }
  }

  String _logLevelPrefix(TerminalLogLevel level) {
    switch (level) {
      case TerminalLogLevel.warn:
        return _l(AppStrings.values.warning);
      case TerminalLogLevel.error:
        return _l(AppStrings.values.error);
      case TerminalLogLevel.info:
      case TerminalLogLevel.begin:
      case TerminalLogLevel.end:
        return '';
    }
  }

  void addStructuredLog({
    required TerminalLogCategory category,
    required String message,
    TerminalLogLevel level = TerminalLogLevel.info,
    bool notifyListeners = true,
  }) {
    if (_shouldSuppressLog(category, message, level)) return;
    final categoryLabel = _logCategoryLabel(category);
    final compact = message.trim();
    final levelPrefix = _logLevelPrefix(level);
    final hasCategoryPrefix =
        compact.isNotEmpty && compact.startsWith(categoryLabel);
    final core = compact.isEmpty
        ? categoryLabel
        : (hasCategoryPrefix ? compact : '$categoryLabel $compact');
    final line = levelPrefix.isEmpty
        ? core
        : (compact.isEmpty
              ? '$categoryLabel $levelPrefix'
              : hasCategoryPrefix
              ? '$categoryLabel $levelPrefix${compact.substring(categoryLabel.length).trimLeft()}'
              : '$categoryLabel $levelPrefix$compact');
    addLog(line, notifyListeners: notifyListeners);
  }

  bool _shouldSuppressLog(TerminalLogCategory category, String message, TerminalLogLevel level) {
    if (logVerbosity == LogVerbosity.all) return false;
    if (logVerbosity == LogVerbosity.errorsOnly) return level != TerminalLogLevel.error;
    // important mode
    if (level == TerminalLogLevel.error || level == TerminalLogLevel.warn) return false;
    if (level == TerminalLogLevel.begin || level == TerminalLogLevel.end) return true;
    // Important info: keep only results, suppress intermediate progress
    final lower = message.toLowerCase();
    final resultKeywords = ['完成', '成功', '失败', 'error', 'failed', 'finish', 'complete',
        'connected', '已连接', '已启动', '已停止', '已断开', 'result', 'summary', 'total',
        '已关闭', '已取消', 'import', 'export', '已导入', '已导出'];
    if (resultKeywords.any((k) => lower.contains(k))) return false;
    // Suppress startup/script/transfer/begin-end info noise
    if (category == TerminalLogCategory.startup) return true;
    if (category == TerminalLogCategory.script) return true;
    if (category == TerminalLogCategory.transfer && !lower.contains('failed') && !lower.contains('complete')) return true;
    return false;
  }

  List<String> get todayLogs {
    final now = DateTime.now();
    return logs
        .where((line) {
          final ts = _parseLogTimestamp(line);
          if (ts == null) return false;
          return ts.year == now.year &&
              ts.month == now.month &&
              ts.day == now.day;
        })
        .toList(growable: false);
  }

  Future<void> openLogFolder() async {
    try {
      if (logDirectory == null) {
        await _initLogs();
      }
      final target = logDirectory;
      if (target == null) return;
      await OpenFilex.open(target.path);
    } catch (_) {
      // Ignore open folder failures.
    }
  }

  Future<void> openStateFolder() async {
    try {
      final file = await ensureStateFile();
      final folder = file.parent;
      await folder.create(recursive: true);
      await OpenFilex.open(folder.path);
    } catch (_) {
      // Ignore open folder failures.
    }
  }

  Future<void> _initLogs() async {
    try {
      final base = await getApplicationSupportDirectory();
      final logDir = Directory(p.join(base.path, 'logs'));
      await logDir.create(recursive: true);
      logDirectory = logDir;
      await _switchLogFile(_dateKeyFor(DateTime.now()), reloadInMemory: true);
      if (_pendingLogWrites.isNotEmpty) {
        final pending = List<_PendingLogLine>.from(_pendingLogWrites);
        _pendingLogWrites.clear();
        for (final entry in pending) {
          _appendLog(entry.line, timestamp: entry.timestamp);
        }
      }
      lastLogPrune = DateTime.now();
      await _pruneLogs();
      notifyState();
    } catch (_) {
      // Ignore log init errors.
    }
  }

  void _appendLog(String line, {required DateTime timestamp}) {
    final targetDateKey = _dateKeyFor(timestamp);
    if (_activeLogDateKey != targetDateKey) {
      _switchLogFileSync(targetDateKey);
    }
    if (logSink != null) {
      logSink!.writeln(line);
    } else {
      _pendingLogWrites.add(_PendingLogLine(line: line, timestamp: timestamp));
    }
  }

  void _maybePruneLogs() {
    final now = DateTime.now();
    if (now.difference(lastLogPrune) < const Duration(hours: 12)) {
      return;
    }
    lastLogPrune = now;
    unawaited(_pruneLogs());
  }

  Future<void> _pruneLogs() async {
    final dir = logDirectory;
    if (dir == null) return;
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      // Keep exactly the most recent 30 calendar days, including today.
      final cutoffDay = todayStart.subtract(const Duration(days: 29));
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final filename = p.basename(entity.path);
        final date = _dateFromLogFilename(filename);
        var shouldDelete = false;
        if (date != null) {
          shouldDelete = date.isBefore(cutoffDay);
        } else if (filename == 'asmote.log') {
          final modified = await entity.lastModified();
          shouldDelete = modified.isBefore(cutoffDay);
        }
        if (!shouldDelete) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
      notifyState();
    } catch (_) {}
  }

  Future<void> _switchLogFile(
    String dateKey, {
    required bool reloadInMemory,
  }) async {
    final dir = logDirectory;
    if (dir == null) return;
    if (_activeLogDateKey == dateKey && logSink != null && logFile != null) {
      return;
    }

    final previousSink = logSink;
    logSink = null;
    if (previousSink != null) {
      await previousSink.flush();
      await previousSink.close();
    }

    final file = File(p.join(dir.path, _logFilenameForDateKey(dateKey)));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    logFile = file;
    _activeLogDateKey = dateKey;
    logSink = file.openWrite(mode: FileMode.append);

    if (reloadInMemory) {
      final lines = await file.readAsLines();
      final pruned = _pruneLogLines(lines);
      logs
        ..clear()
        ..addAll(pruned.length > _maxInMemoryLogLines
            ? pruned.sublist(pruned.length - _maxInMemoryLogLines)
            : pruned);
    }
  }

  void _switchLogFileSync(String dateKey) {
    final dir = logDirectory;
    if (dir == null) {
      return;
    }
    if (_activeLogDateKey == dateKey && logSink != null && logFile != null) {
      return;
    }

    final previousSink = logSink;
    logSink = null;
    if (previousSink != null) {
      unawaited(previousSink.flush());
      unawaited(previousSink.close());
    }

    final file = File(p.join(dir.path, _logFilenameForDateKey(dateKey)));
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    logFile = file;
    _activeLogDateKey = dateKey;
    logSink = file.openWrite(mode: FileMode.append);
  }

  String _logFilenameForDateKey(String dateKey) => 'asmote-$dateKey.log';

  String _dateKeyFor(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  DateTime? _dateFromLogFilename(String filename) {
    final match = RegExp(
      r'^asmote-(\d{4})-(\d{2})-(\d{2})\.log$',
    ).firstMatch(filename);
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  List<String> _pruneLogLines(List<String> lines) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final kept = <String>[];
    for (final line in lines) {
      final ts = _parseLogTimestamp(line);
      if (ts == null || ts.isAfter(cutoff)) {
        kept.add(line);
      }
    }
    return kept;
  }

  DateTime? _parseLogTimestamp(String line) {
    if (!line.startsWith('[')) return null;
    final end = line.indexOf(']');
    if (end <= 1) return null;
    final raw = line.substring(1, end);
    final compactMatch = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$',
    ).firstMatch(raw);
    if (compactMatch != null) {
      final year = int.parse(compactMatch.group(1)!);
      final month = int.parse(compactMatch.group(2)!);
      final day = int.parse(compactMatch.group(3)!);
      final hour = int.parse(compactMatch.group(4)!);
      final minute = int.parse(compactMatch.group(5)!);
      return DateTime(year, month, day, hour, minute);
    }
    return DateTime.tryParse(raw);
  }

  String _formatLogTimestamp(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String _compactLogMessage(String raw, {int max = 280}) {
    var normalized = raw.trim();
    if (normalized.isEmpty) {
      return '';
    }
    final stackStart = normalized.indexOf('\n#0');
    if (stackStart > 0) {
      normalized = normalized.substring(0, stackStart).trim();
    }
    normalized = normalized
        .replaceAll('\r\n', ' | ')
        .replaceAll('\n', ' | ')
        .replaceAll('\r', ' | ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= max) {
      return normalized;
    }
    return '${normalized.substring(0, max)}...';
  }

  Future<void> _bootstrapStartupLogs() async {
    final startupStopwatch = Stopwatch()..start();
    await _restoreLocaleForStartupLogs();
    await _initLogs();
    addStructuredLog(
      category: TerminalLogCategory.startup,
      message: _l(AppStrings.values.startupBegan),
      notifyListeners: false,
    );
    await _runStartupSection(
      AppStrings.values.startupSectionVersionInfo,
      _logStartupVersionInfo,
    );
    await _runStartupSection(
      AppStrings.values.startupSectionTransferProbe,
      _logStartupTransferInfo,
    );
    startupStopwatch.stop();
    addStructuredLog(
      category: TerminalLogCategory.startup,
      message: AppStrings.values.startupFinishedVarMs.resolve(locale.languageCode, params: {'ms': '${startupStopwatch.elapsedMilliseconds}'}),
      notifyListeners: false,
    );
  }

  Future<void> _restoreLocaleForStartupLogs() async {
    try {
      final file = await ensureStateFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final settings = decoded['settings'];
      if (settings is! Map<String, dynamic>) return;
      final localeCode = settings['locale'];
      if (localeCode is String && localeCode.trim().isNotEmpty) {
        locale = Locale(localeCode.trim());
      }
    } catch (_) {
      // Ignore locale bootstrap read errors.
    }
  }

  Future<void> _runStartupSection(
    AppText section,
    Future<void> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      await action();
    } catch (error) {
      stopwatch.stop();
      _addStartupStructuredLog(
        section,
        _l(
          AppStrings.values.startupSectionErrorDurationVarVar,
          params: {
            'error': '$error',
            'elapsedMs': '${stopwatch.elapsedMilliseconds}',
          },
        ),
        level: TerminalLogLevel.error,
      );
    }
  }

  void _addStartupStructuredLog(
    AppText section,
    String message, {
    TerminalLogLevel level = TerminalLogLevel.info,
  }) {
    addStructuredLog(
      category: TerminalLogCategory.startup,
      message: message,
      level: level,
      notifyListeners: false,
    );
  }

  Future<ViewerCacheCleanupResult> clearFilePreviewCache() async {
    internalViewerPreparedCache.clear();
    internalViewerPreparingCache.clear();
    internalViewerStreamingCache.clear();
    final base = await getApplicationSupportDirectory();
    final targets = <Directory>[
      Directory(p.join(base.path, 'external-edit')),
      Directory(p.join(base.path, 'internal-viewer')),
    ];
    final dirs = <String>[];
    var deleted = 0;
    var failed = 0;
    for (final dir in targets) {
      if (!await dir.exists()) {
        continue;
      }
      dirs.add(dir.path);
      await for (final entity in dir.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
          deleted += 1;
        } catch (_) {
          failed += 1;
        }
      }
    }
    return ViewerCacheCleanupResult(
      dirs: dirs,
      deleted: deleted,
      failed: failed,
    );
  }

  Future<void> _logStartupVersionInfo() async {
    final explicit = _explicitAppVersion.trim();
    if (explicit.isNotEmpty) return;
    try {
      await PackageInfo.fromPlatform();
    } catch (error) {
      _addStartupStructuredLog(
        AppStrings.values.startupSectionVersionInfo,
        AppStrings.values.versionReadFailedVar.resolve(locale.languageCode, params: {'error': '$error'}),
        level: TerminalLogLevel.error,
      );
    }
  }

  Future<void> _logStartupTransferInfo() async {
    final bridge = NativeTransferBridge.instance;
    if (!bridge.isSupported) {
      _addStartupStructuredLog(
        AppStrings.values.startupSectionTransferProbe,
        _l(AppStrings.values.transferEngineUnavailable),
      );
      return;
    }
    _addStartupStructuredLog(
      AppStrings.values.startupSectionTransferProbe,
      _l(AppStrings.values.transferEngineReady),
    );
  }

  void scheduleStateSave() {
    if (suspendStateSave) return;
    stateSaveTimer?.cancel();
    stateSaveTimer = Timer(const Duration(milliseconds: 100), () {
      unawaited(_persistState());
    });
  }

  Future<void> _persistState() async {
    try {
      final file = await ensureStateFile();
      final data = buildPortableState(includeSecrets: false);
      // Remove large data from main state file to keep it small
      data.remove('commandHistoryByHost');
      await file.writeAsString('${_stateJsonEncoder.convert(data)}\n');
      await _persistLargeData();
    } catch (_) {
      // Ignore state save errors.
    }
  }

  Future<void> _persistLargeData() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dataFile = File(p.join(base.path, 'asmote_large_data.json'));
      final largeData = <String, dynamic>{
        'commandHistoryByHost': commandHistoryByHost.map(
          (key, value) =>
              MapEntry(key, List<String>.from(value, growable: false)),
        ),
      };
      await dataFile.writeAsString('${_stateJsonEncoder.convert(largeData)}\n');
    } catch (_) {
      // Ignore save errors for large data.
    }
  }

  Future<void> _loadLargeData() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dataFile = File(p.join(base.path, 'asmote_large_data.json'));
      if (!await dataFile.exists()) return;
      final raw = await dataFile.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final history = decoded['commandHistoryByHost'];
      if (history is Map) {
        commandHistoryByHost.clear();
        for (final entry in history.entries) {
          final key = entry.key?.toString().trim() ?? '';
          if (key.isEmpty) continue;
          final list = entry.value;
          if (list is List) {
            final items = list
                .map((e) => e?.toString().trim() ?? '')
                .where((e) => e.isNotEmpty)
                .toList(growable: true);
            if (items.isNotEmpty) {
              commandHistoryByHost[key] = items;
            }
          }
        }
      }
    } catch (_) {
      // Ignore load errors for large data.
    }
  }

  Map<String, dynamic>? settingsOrNull(Map<String, dynamic> data) {
    final settings = data['settings'];
    if (settings is Map<String, dynamic>) return settings;
    if (settings is Map) {
      final map = <String, dynamic>{};
      settings.forEach((key, value) => map['$key'] = value);
      return map;
    }
    return null;
  }

  void disposeExternalEdit(String localPath) {
    externalEditDebounceTimers[localPath]?.cancel();
    externalEditDebounceTimers.remove(localPath);
    externalEditSubscriptions[localPath]?.cancel();
    externalEditSubscriptions.remove(localPath);
    externalEdits.remove(localPath);
  }

  void disposeExternalEditsForSession(String sessionId) {
    final targets = externalEdits.entries
        .where((entry) => entry.value.sessionId == sessionId)
        .map((entry) => entry.key)
        .toList();
    for (final path in targets) {
      disposeExternalEdit(path);
    }
  }

  void disposeAllExternalEdits() {
    for (final path in externalEdits.keys.toList()) {
      disposeExternalEdit(path);
    }
  }

  bool isHostPinned(String hostId) => pinnedHostIds.contains(hostId);

  void toggleHostPinned(String hostId) {
    if (pinnedHostIds.contains(hostId)) {
      pinnedHostIds.remove(hostId);
    } else {
      pinnedHostIds.add(hostId);
    }
    scheduleStateSave();
    notifyListeners();
  }

  void renameSessionFolder({
    required String folderKey,
    required String newName,
  }) {
    for (final host in hosts.where((h) => h.group == folderKey).toList()) {
      hosts.remove(host);
      final renamed = host.copyWith(group: newName);
      hosts.add(renamed);
    }
    if (expandedSessionFolderKeys.remove(folderKey)) {
      expandedSessionFolderKeys.add(newName);
    }
    scheduleStateSave();
    notifyListeners();
  }

  int sessionFolderHostCount(String folderKey) =>
      hosts.where((h) => h.group == folderKey).length;

  void deleteSessionFolder(String folderKey) {
    hosts.removeWhere((h) => h.group == folderKey);
    expandedSessionFolderKeys.remove(folderKey);
    scheduleStateSave();
    notifyListeners();
  }

  bool isSessionFolderExpanded(String folderKey) =>
      expandedSessionFolderKeys.contains(folderKey);

  void toggleSessionFolderExpanded(String folderKey) {
    if (expandedSessionFolderKeys.contains(folderKey)) {
      expandedSessionFolderKeys.remove(folderKey);
    } else {
      expandedSessionFolderKeys.add(folderKey);
      sessionFolderExpansionConfigured = true;
    }
    scheduleStateSave();
    notifyListeners();
  }

  void cleanupAutomationCollections() => _cleanupAutomationCollections();
  void _cleanupAutomationCollections() {
    // Placeholder stub
  }

  Future<void> _loadState() async {
    try {
      final file = await ensureStateFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        await _loadStateFromData(decoded);
      }
    } catch (_) {}
  }

  Future<void> _loadStateFromData(Map<String, dynamic> data) async {
    final settings = settingsOrNull(data);
    if (settings != null) {
      _loadSettings(settings);
    }

    final hostList = data['hosts'];
    if (hostList is List) {
      hosts.clear();
      for (final entry in hostList) {
        if (entry is Map<String, dynamic>) {
          final host = HostEntry.fromJson(entry);
          hosts.add(host);
        }
      }
    }

    final scriptList = data['scripts'];
    if (scriptList is List) {
      scripts.clear();
      for (final entry in scriptList) {
        if (entry is Map<String, dynamic>) {
          scripts.add(ScriptEntry.fromJson(entry));
        }
      }
    }

    final folderList = data['scriptFolders'];
    if (folderList is List) {
      scriptFolders.clear();
      for (final entry in folderList) {
        if (entry is Map<String, dynamic>) {
          scriptFolders.add(ScriptFolderEntry.fromJson(entry));
        }
      }
    }

    final workflowList = data['scriptWorkflows'];
    if (workflowList is List) {
      scriptWorkflows.clear();
      for (final entry in workflowList) {
        if (entry is Map<String, dynamic>) {
          scriptWorkflows.add(ScriptWorkflowEntry.fromJson(entry));
        }
      }
    }

    final batchList = data['scriptBatchTemplates'];
    if (batchList is List) {
      scriptBatchTemplates.clear();
      for (final entry in batchList) {
        if (entry is Map<String, dynamic>) {
          scriptBatchTemplates.add(ScriptBatchTemplate.fromJson(entry));
        }
      }
    }

    final triggerList = data['scriptTriggers'];
    if (triggerList is List) {
      scriptTriggers.clear();
      for (final entry in triggerList) {
        if (entry is Map<String, dynamic>) {
          scriptTriggers.add(ScriptTriggerEntry.fromJson(entry));
        }
      }
    }

    final pfList = data['portForwards'];
    if (pfList is List) {
      portForwards.clear();
      for (final entry in pfList) {
        if (entry is Map<String, dynamic>) {
          portForwards.add(PortForwardEntry.fromJson(entry));
        }
      }
    }

    final pfTemplates = data['portForwardTemplates'];
    if (pfTemplates is List) {
      portForwardTemplates.clear();
      for (final entry in pfTemplates) {
        if (entry is Map<String, dynamic>) {
          portForwardTemplates.add(PortForwardTemplate.fromJson(entry));
        }
      }
    }

    final fingerprints = data['knownHostFingerprints'];
    if (fingerprints is Map) {
      knownHostFingerprints.clear();
      fingerprints.forEach(
        (k, v) => knownHostFingerprints[k.toString()] = v.toString(),
      );
    }

    final pinned = data['pinnedHostIds'];
    if (pinned is List) {
      pinnedHostIds.clear();
      for (final id in pinned) {
        pinnedHostIds.add(id.toString());
      }
    }

    final expanded = data['expandedSessionFolderKeys'];
    if (expanded is List) {
      expandedSessionFolderKeys.clear();
      for (final key in expanded) {
        expandedSessionFolderKeys.add(key.toString());
      }
    }
    sessionFolderExpansionConfigured =
        data['sessionFolderExpansionConfigured'] == true;

    final visited = data['visitedFiles'];
    if (visited is List) {
      visitedFiles.clear();
      for (final entry in visited) {
        if (entry is Map<String, dynamic>) {
          visitedFiles.add(VisitedFileEntry.fromJson(entry));
        }
      }
    }

    final runHistory = data['scriptRunHistory'];
    if (runHistory is List) {
      scriptRunHistory.clear();
      for (final entry in runHistory) {
        if (entry is Map<String, dynamic>) {
          scriptRunHistory.add(ScriptHostRunRecord.fromJson(entry));
        }
      }
    }

    final shortcuts = data['scriptShortcutBindings'];
    if (shortcuts is Map) {
      scriptShortcutBindings.clear();
      shortcuts.forEach(
        (k, v) => scriptShortcutBindings[k.toString()] = v.toString(),
      );
    }

    final schedules = data['scriptSchedules'];
    if (schedules is List) {
      scriptSchedules.clear();
      for (final entry in schedules) {
        if (entry is Map<String, dynamic>) {
          scriptSchedules.add(ScriptScheduleEntry.fromJson(entry));
        }
      }
    }

    await _loadLargeData();
    await _synchronizeHostSecrets();
    startAutoPortForwards();
  }

  void _loadSettings(Map<String, dynamic> settings) {
    autoReconnect = settings['autoReconnect'] as bool? ?? true;
    confirmPaste = settings['confirmPaste'] as bool? ?? true;
    showHiddenFiles = settings['showHiddenFiles'] as bool? ?? true;

    final layoutMode = settings['homeLayoutMode']?.toString();
    if (layoutMode == 'desktop') {
      homeLayoutMode = HomeLayoutMode.desktop;
    } else if (layoutMode == 'mobile') {
      homeLayoutMode = HomeLayoutMode.mobile;
    }

    final loc = settings['locale']?.toString();
    if (loc == 'en') {
      locale = const Locale('en');
    } else if (loc == 'zh') {
      locale = const Locale('zh');
    }

    terminalSplitViewEnabled =
        settings['terminalSplitViewEnabled'] as bool? ?? false;
    final splitLayout = settings['terminalSplitLayout']?.toString();
    if (splitLayout == 'vertical') {
      terminalSplitLayout = TerminalSplitLayout.vertical;
    }
    if (splitLayout == 'grid') {
      terminalSplitLayout = TerminalSplitLayout.grid;
    }
    activeTerminalSplitPaneId =
        settings['activeTerminalSplitPaneId']?.toString() ?? '';
    maximizedTerminalSplitPaneId =
        settings['maximizedTerminalSplitPaneId']?.toString() ?? '';
    terminalSplitPrimaryRatio =
        (_parseDouble(settings['terminalSplitPrimaryRatio']) ?? 0.5)
            .clamp(0.2, 0.8)
            .toDouble();
    terminalSplitSecondaryRatio =
        (_parseDouble(settings['terminalSplitSecondaryRatio']) ?? 0.5)
            .clamp(0.2, 0.8)
            .toDouble();
    final splitPanes = settings['terminalSplitPanes'];
    if (splitPanes is List) {
      terminalSplitPanes
        ..clear()
        ..addAll(
          splitPanes
              .whereType<Map<String, dynamic>>()
              .map(TerminalSplitPaneConfig.fromJson)
              .where((pane) => pane.id.trim().isNotEmpty),
        );
    }
    final splitTree = settings['terminalSplitTree'];
    if (splitTree is Map<String, dynamic>) {
      terminalSplitTree = TerminalSplitTreeNode.fromJson(splitTree);
    }
    final splitTemplates = settings['terminalSplitTemplates'];
    if (splitTemplates is List) {
      terminalSplitTemplates
        ..clear()
        ..addAll(
          splitTemplates
              .whereType<Map<String, dynamic>>()
              .map(TerminalSplitTemplate.fromJson)
              .where((template) => template.id.trim().isNotEmpty),
        );
    }

    mobileSidebarWidth =
        _parseDouble(settings['mobileSidebarWidth']) ??
        mobileSidebarWidthDefault;
    terminalHorizontalScrollEnabled =
        settings['terminalHorizontalScrollEnabled'] as bool? ?? false;
    mobileTerminalColumns =
        int.tryParse(
          settings['mobileTerminalColumns']?.toString() ?? '',
        )?.clamp(mobileTerminalColumnsMin, mobileTerminalColumnsMax) ??
        mobileTerminalColumns;
    terminalAccessibilitySemanticsEnabled =
        settings['terminalAccessibilitySemanticsEnabled'] as bool? ?? false;

    transferAutoRetryEnabled =
        settings['transferAutoRetryEnabled'] as bool? ?? true;
    transferResumeEnabled = settings['transferResumeEnabled'] as bool? ?? true;
    transferRetryMaxAttempts =
        int.tryParse(
          settings['transferRetryMaxAttempts']?.toString() ?? '',
        )?.clamp(1, 20) ??
        3;
    transferRetryBaseDelayMs =
        int.tryParse(
          settings['transferRetryBaseDelayMs']?.toString() ?? '',
        )?.clamp(100, 60000) ??
        800;
    transferRetryMaxDelayMs =
        int.tryParse(
          settings['transferRetryMaxDelayMs']?.toString() ?? '',
        )?.clamp(1000, 120000) ??
        10000;

    androidKeepSshAliveInBackground =
        settings['androidKeepSshAliveInBackground'] as bool? ??
        Platform.isAndroid;

    final sessionQueryVal = settings['sessionQuery']?.toString();
    if (sessionQueryVal != null) sessionQuery = sessionQueryVal;

    final sessionSortVal = settings['sessionSortMode']?.toString();
    if (sessionSortVal == 'name') sessionSortMode = SessionSortMode.name;
    if (sessionSortVal == 'recent') sessionSortMode = SessionSortMode.recent;

    settingsTabIndex =
        int.tryParse(
          settings['settingsTabIndex']?.toString() ?? '',
        )?.clamp(0, 5) ??
        0;
    final appearanceJson = settings['globalAppearance'];
    if (appearanceJson is Map<String, dynamic>) {
      globalAppearance = TerminalAppearanceProfile.fromJson(appearanceJson);
    }
    final bgList = settings['terminalBackgroundImages'];
    if (bgList is List) {
      terminalBackgroundImages.clear();
      for (final entry in bgList) {
        if (entry is Map<String, dynamic>) {
          terminalBackgroundImages.add(BackgroundImageEntry.fromJson(entry));
        }
      }
    }
    final oldPath = settings['terminalBackgroundImagePath']?.toString();
    if (oldPath != null && oldPath.isNotEmpty && terminalBackgroundImages.isEmpty) {
      final id = 'bg-0';
      final name = oldPath.split(Platform.pathSeparator).last;
      terminalBackgroundImages.add(BackgroundImageEntry(id: id, path: oldPath, name: name));
    }
    terminalBackgroundOpacity = _parseDouble(settings['terminalBackgroundOpacity']) ?? 0.15;
    maxScrollbackLines = int.tryParse(
      settings['maxScrollbackLines']?.toString() ?? '',
    )?.clamp(1000, 100000) ?? 10000;
    reuseSessionForNewPane = settings['reuseSessionForNewPane'] as bool? ?? false;
    terminalBlockSelectEnabled = settings['terminalBlockSelectEnabled'] as bool? ?? false;
    logVerbosity = switch (settings['logVerbosity'] as int? ?? 1) {
      0 => LogVerbosity.all,
      2 => LogVerbosity.errorsOnly,
      _ => LogVerbosity.important,
    };
    final shortcutList = settings['shortcutBindings'];
    if (shortcutList is List) {
      for (final entry in shortcutList) {
        if (entry is Map<String, dynamic>) {
          final sb = ShortcutBinding.fromJson(entry);
          final idx = shortcutBindings.indexWhere((s) => s.id == sb.id);
          if (idx >= 0) {
            shortcutBindings[idx] = shortcutBindings[idx].copyWith(customKeys: sb.customKeys);
          }
        }
      }
    }
    final keybindingList = settings['customKeyBindings'];
    if (keybindingList is List) {
      customKeyBindings.clear();
      for (final entry in keybindingList) {
        if (entry is Map<String, dynamic>) {
          customKeyBindings.add(KeyBinding.fromJson(entry));
        }
      }
    }

  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    final value = double.tryParse(v.toString());
    return value?.isFinite == true ? value : null;
  }

  Map<String, dynamic> _buildStateJson() =>
      buildPortableState(includeSecrets: false);

  Future<File> ensureStateFile() async {
    if (stateFile != null) return stateFile!;
    final base = await getApplicationSupportDirectory();
    stateFile = File(p.join(base.path, 'asmote_state.json'));
    return stateFile!;
  }

  Map<String, dynamic> buildPortableState({required bool includeSecrets}) {
    return <String, dynamic>{
      'settings': <String, dynamic>{
        'autoReconnect': autoReconnect,
        'confirmPaste': confirmPaste,
        'showHiddenFiles': showHiddenFiles,
        'homeLayoutMode': homeLayoutMode.name,
        'locale': locale.languageCode,
        'terminalSplitViewEnabled': terminalSplitViewEnabled,
        'terminalSplitLayout': terminalSplitLayout.name,
        'terminalSplitPanes': terminalSplitPanes
            .map((pane) => pane.toJson())
            .toList(),
        'terminalSplitTree': terminalSplitTree?.toJson(),
        'activeTerminalSplitPaneId': activeTerminalSplitPaneId,
        'maximizedTerminalSplitPaneId': maximizedTerminalSplitPaneId,
        'terminalSplitPrimaryRatio': terminalSplitPrimaryRatio,
        'terminalSplitSecondaryRatio': terminalSplitSecondaryRatio,
        'terminalSplitTemplates': terminalSplitTemplates
            .map((template) => template.toJson())
            .toList(),
        'mobileSidebarWidth': mobileSidebarWidth,
        'terminalHorizontalScrollEnabled':
            terminalHorizontalScrollEnabled,
        'mobileTerminalColumns': mobileTerminalColumns,
        'terminalAccessibilitySemanticsEnabled':
            terminalAccessibilitySemanticsEnabled,
        'transferAutoRetryEnabled': transferAutoRetryEnabled,
        'transferResumeEnabled': transferResumeEnabled,
        'transferRetryMaxAttempts': transferRetryMaxAttempts,
        'transferRetryBaseDelayMs': transferRetryBaseDelayMs,
        'transferRetryMaxDelayMs': transferRetryMaxDelayMs,
        'androidKeepSshAliveInBackground': androidKeepSshAliveInBackground,
        'sessionQuery': sessionQuery,
        'sessionSortMode': sessionSortMode.name,
        'settingsTabIndex': settingsTabIndex,
        'globalAppearance': globalAppearance.toJson(),
        'terminalBackgroundImages': terminalBackgroundImages.map((e) => e.toJson()).toList(),
        'terminalBackgroundOpacity': terminalBackgroundOpacity,
        'maxScrollbackLines': maxScrollbackLines,
        'reuseSessionForNewPane': reuseSessionForNewPane,
        'terminalBlockSelectEnabled': terminalBlockSelectEnabled,
        'logVerbosity': logVerbosity.index,
        'customKeyBindings': customKeyBindings.map((k) => k.toJson()).toList(),
        'shortcutBindings': shortcutBindings.map((s) => s.toJson()).toList(),
      },
      'hosts': hosts.map((h) => h.toJson(includeSecrets: includeSecrets)).toList(),
      'scripts': scripts.map((s) => s.toJson()).toList(),
      'scriptFolders': scriptFolders.map((s) => s.toJson()).toList(),
      'scriptWorkflows': scriptWorkflows.map((s) => s.toJson()).toList(),
      'scriptBatchTemplates': scriptBatchTemplates
          .map((s) => s.toJson())
          .toList(),
      'scriptTriggers': scriptTriggers.map((s) => s.toJson()).toList(),
      'portForwards': portForwards.map((p) => p.toJson()).toList(),
      'portForwardTemplates': portForwardTemplates
          .map((p) => p.toJson())
          .toList(),
      'knownHostFingerprints': Map<String, String>.from(knownHostFingerprints),
      'pinnedHostIds': pinnedHostIds.toList(),
      'expandedSessionFolderKeys': expandedSessionFolderKeys.toList(),
      'sessionFolderExpansionConfigured': sessionFolderExpansionConfigured,
      'visitedFiles': visitedFiles.map((v) => v.toJson()).toList(),
      'scriptRunHistory': <Map<String, dynamic>>[],
      'scriptShortcutBindings': Map<String, String>.from(
        scriptShortcutBindings,
      ),
      'scriptSchedules': scriptSchedules.map((s) => s.toJson()).toList(),
      'commandHistoryByHost': commandHistoryByHost,
      if (includeSecrets) 'hostSecrets': <String, dynamic>{},
    };
  }

  @override
  void dispose() {
    stateSaveTimer?.cancel();
    _sessionProbeTimer?.cancel();
    _sessionProbesInFlight.clear();
    ServerMonitorService.instance.stop();
    for (final session in sessions) {
      session.closedByUser = true;
      session.closeConnection();
    }
    disposeSessionRuntimes();
    disposePortForwardRuntime();
    TerminalAppStateScripts(this).disposeScriptScheduleRuntime();
    scriptSshPool.dispose();
    _hostKeyPromptDecision?.complete(false);
    _hostKeyPromptDecision = null;
    pendingHostKeyPrompt = null;
    disposeAllExternalEdits();
    disposeSshForegroundGuardRuntime();
    if (Platform.isAndroid) {
      unawaited(AndroidSshForegroundBridge.stop().catchError((_) {}));
      unawaited(AndroidTransferForegroundBridge.stop().catchError((_) {}));
    }
    logSink?.close();
    super.dispose();
  }
}

enum SessionProbeStatus { unknown, probing, reachable, unreachable }

class SessionProbeState {
  const SessionProbeState({
    required this.status,
    this.latencyMs,
    this.lastCheckedAt,
    this.lastError,
  });

  final SessionProbeStatus status;
  final int? latencyMs;
  final DateTime? lastCheckedAt;
  final String? lastError;
}

class _ProbeResult {
  const _ProbeResult({required this.reachable, this.error});

  final bool reachable;
  final String? error;
}
