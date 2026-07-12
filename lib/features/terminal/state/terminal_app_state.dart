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

import '../../../errors/app_error.dart';
import '../../../events/event_bus.dart';
import '../../../shared/constants/app_string.dart';

import '../../../shared/logging/log_controller.dart';
import '../../../shared/logging/log_level.dart';
export '../../../shared/logging/log_level.dart';
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
part 'app/terminal_app_state_memory_monitor.dart';
part 'parts/terminal_app_state_ops.dart';
part 'parts/terminal_app_state_ops2.dart';
part 'parts/terminal_app_state_fix.dart';

class TerminalAppState extends ChangeNotifier {
  static const int commandHistoryPerHostCap = 80;
  static const int scriptRunHistoryCap = 240;
  static const int mobileTerminalColumnsMin = 40;
  static const int mobileTerminalColumnsMax = 2000;
  static const double mobileSidebarWidthMin = 220;
  static const double mobileSidebarWidthMax = 2000;
  static const double mobileSidebarWidthDefault = 304;

  final Set<String> scriptBusySessions = {};
  static const String _explicitAppVersion = String.fromEnvironment('Polarmote_APP_VERSION', defaultValue: '');

  final EventBus eventBus = EventBus();

  TerminalAppState() {
    unawaited(_bootstrapStartupLogs());
    unawaited(_loadState().then((_) {
      _checkShortcutConflicts();
      _cleanupOrphanStages();
      if (stageManagerEnabled && terminalStages.isEmpty) createTerminalStage('Stage 1');
      unawaited(restoreStageSessions());
    }));
    unawaited(refreshPortableStateSnapshots().catchError((_) => const <PortableStateSnapshot>[]));
    unawaited(Future.delayed(const Duration(seconds: 2), () => ServerMonitorService.instance.start(this)));
  }

  void _cleanupOrphanStages() {
    final hostIds = hosts.map((h) => h.id).toSet();
    final validSessionIds = sessions.map((s) => s.id).toSet();
    final before = terminalStages.length;
    terminalStages.removeWhere((st) {
      if (st.connectedHostIds.isEmpty) return true;
      return st.connectedHostIds.every((hid) => !hostIds.contains(hid));
    });
    for (var i = 0; i < terminalStages.length; i++) {
      final st = terminalStages[i];
      final staleIds = st.sessionIds.where((sid) => !validSessionIds.contains(sid)).toList();
      if (staleIds.isEmpty) continue;
      terminalStages[i] = st.copyWith(
        sessionIds: st.sessionIds.where((sid) => validSessionIds.contains(sid)).toList(),
      );
    }
    if (terminalStages.length < before &&
        !terminalStages.any((s) => s.id == activeTerminalStageId)) {
      activeTerminalStageId = terminalStages.isNotEmpty ? terminalStages.first.id : '';
    }
  }

  static HomeLayoutMode _defaultHomeLayoutMode() => (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ? HomeLayoutMode.desktop : HomeLayoutMode.mobile;
  static const JsonEncoder _stateJsonEncoder = JsonEncoder.withIndent('  ');

  NavSection navSection = NavSection.sessions;
  String? lastError;
  final List<HostEntry> hosts = [];
  final Set<String> selectedHostIds = {};
  final Map<String, Image> terminalThumbnailImages = {};
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
  final LogController logController = LogController();
  MemoryMode memoryMode = MemoryMode.medium;
  int customTerminalBufferSize = 5000;
  bool smartMemoryManagement = true;
  Timer? _memoryMonitorTimer;
  DateTime? _lastMemoryWarning;
  MemoryMode? _originalMemoryMode;


  int get terminalBufferSize => switch (memoryMode) { MemoryMode.low => 2000, MemoryMode.medium => 5000, MemoryMode.high => 10000, MemoryMode.custom => customTerminalBufferSize.clamp(1000, 50000) };
  double get estimatedMemoryPerTerminal => (terminalBufferSize * 200) / (1024 * 1024);
  File? stateFile;
  Timer? stateSaveTimer;
  bool suspendStateSave = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  FlutterSecureStorage get secureStorage => _secureStorage;
  Future<void>? _secureStorageInit;
  int transferIdSeed = 0;
  int lastTransferTimestamp = 0;
  int keyboardRecoveryToken = 0;
  int stageChangeToken = 0;
  int stageCardMinWidth = 280;
  double stageCardAspectRatio = 1.45;
  bool showHiddenFiles = true;
  bool autoReconnect = true;
  bool androidKeepSshAliveInBackground = Platform.isAndroid;
  bool confirmPaste = true;
  TerminalAppearanceProfile globalAppearance = const TerminalAppearanceProfile();
  final List<BackgroundImageEntry> terminalBackgroundImages = [];
  int _nextBgImageId = 1;
  double terminalBackgroundOpacity = 0.15;
  bool showThumbnailBackground = true;
  int thumbnailBackgroundVersion = 0;
  bool reuseSessionForNewPane = false;
  bool terminalBlockSelectEnabled = false;
  final List<ShortcutBinding> shortcutBindings = defaultShortcutBindings();
  final List<KeyBinding> customKeyBindings = [];
  String shortcutPresetId = 'default';

  static List<ShortcutBinding> defaultShortcutBindings() => [
    const ShortcutBinding(id: 'copy', name: 'Copy', defaultKeys: 'Ctrl+Shift+C / Ctrl+C'),
    const ShortcutBinding(id: 'paste', name: 'Paste', defaultKeys: 'Ctrl+V / Shift+Insert'),
    const ShortcutBinding(id: 'selectAll', name: 'Select All', defaultKeys: 'Ctrl+A'),
    const ShortcutBinding(id: 'search', name: 'Find in terminal', defaultKeys: 'Ctrl+F'),
    const ShortcutBinding(id: 'blockSelect', name: 'Toggle block selection', defaultKeys: 'Alt+B'),
    const ShortcutBinding(id: 'splitMaximize', name: 'Maximize / Restore pane', defaultKeys: 'Ctrl+Alt+Enter'),
    const ShortcutBinding(id: 'splitBroadcast', name: 'Toggle input broadcast', defaultKeys: 'Ctrl+Alt+B'),
    const ShortcutBinding(id: 'newSession', name: 'New session', defaultKeys: 'Ctrl+N'),
    const ShortcutBinding(id: 'quickConnect', name: 'Quick connect', defaultKeys: 'Ctrl+K'),
    const ShortcutBinding(id: 'closeSession', name: 'Close current workspace', defaultKeys: 'Ctrl+W'),
    const ShortcutBinding(id: 'closeAllSessions', name: 'Close all sessions', defaultKeys: 'Ctrl+Shift+W'),
    const ShortcutBinding(id: 'newScript', name: 'New script', defaultKeys: 'Ctrl+Shift+N'),
    const ShortcutBinding(id: 'runScript', name: 'Run script', defaultKeys: 'Ctrl+Shift+R'),
    const ShortcutBinding(id: 'scriptList', name: 'Script list', defaultKeys: 'Ctrl+Shift+L'),
    const ShortcutBinding(id: 'scriptMonitor', name: 'Script monitor', defaultKeys: 'Ctrl+Shift+M'),
    const ShortcutBinding(id: 'transferManager', name: 'Transfer manager', defaultKeys: 'Ctrl+Shift+T'),
    const ShortcutBinding(id: 'portForwarding', name: 'Port forwarding', defaultKeys: 'Ctrl+Shift+P'),
    const ShortcutBinding(id: 'lanScan', name: 'LAN scan', defaultKeys: 'Ctrl+Shift+A'),
    const ShortcutBinding(id: 'openSettings', name: 'Settings', defaultKeys: 'Ctrl+,'),
    const ShortcutBinding(id: 'logViewer', name: 'Log viewer', defaultKeys: 'Ctrl+Shift+O'),
    const ShortcutBinding(id: 'previousStage', name: 'Previous stage', defaultKeys: 'Alt+Left'),
    const ShortcutBinding(id: 'nextStage', name: 'Next stage', defaultKeys: 'Alt+Right'),
  ];

  HomeLayoutMode homeLayoutMode = _defaultHomeLayoutMode();
  bool terminalSplitViewEnabled = true;
  final List<TerminalSplitPaneConfig> terminalSplitPanes = [];
  String activeTerminalSplitPaneId = '';
  String maximizedTerminalSplitPaneId = '';
  final List<TerminalStage> terminalStages = [];
  String activeTerminalStageId = '';
  int _terminalStageIdSeed = 0;
  bool stageManagerEnabled = true;
  bool restorationInProgress = false;
  bool broadcastEnabled = false;
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
  TerminalPerformanceSettings performanceSettings = TerminalPerformanceSettings();
  Locale locale = const Locale('zh');
  String sessionQuery = '';
  bool sessionFilterOnlineOnly = false;
  bool sessionFilterPinnedOnly = false;
  String sessionGroupFilter = '';
  SessionSortMode sessionSortMode = SessionSortMode.smart;

  String _hostConnectionKey(HostEntry profile) => switch (profile.connectionType) {
    ConnectionType.local => 'local:${profile.localShellType.name}',
    ConnectionType.serial => 'serial:${profile.serialPortPath ?? ''}:${profile.serialBaudRate}:${profile.serialDataBits}:${profile.serialStopBits}:${profile.serialParity.name}',
    ConnectionType.ssh => 'ssh:${profile.username}@${profile.host}:${profile.port}',
    ConnectionType.telnet => 'telnet:${profile.host}:${profile.telnetPort}',
  };

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
  final Map<String, StreamSubscription<FileSystemEvent>> externalEditSubscriptions = {};
  final Map<String, Timer> externalEditDebounceTimers = {};
  final Map<String, InternalViewerPreparationResult> internalViewerPreparedCache = {};
  final Map<String, Future<InternalViewerPreparationResult?>> internalViewerPreparingCache = {};
  final Map<String, InternalViewerStreamPreparationResult> internalViewerStreamingCache = {};
  final Map<String, double> filePreviewScrollOffsets = <String, double>{};
  final List<VisitedFileEntry> visitedFiles = <VisitedFileEntry>[];
  static const int visitedFilesCap = 15;

  int get activeSessionIndex => sessions.isEmpty ? -1 : activeSessionIndexValue.clamp(-1, sessions.length - 1);
  TerminalSession? get activeSession => sessions.isEmpty || activeSessionIndex < 0 ? null : sessions[activeSessionIndex];

  void notifyState() { notifyListeners(); }

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

  @override
  void dispose() {
    disposeMemoryMonitor();
    stateSaveTimer?.cancel();
    _sessionProbeTimer?.cancel();
    _sessionProbesInFlight.clear();
    ServerMonitorService.instance.stop();
    for (final session in sessions) { session.closedByUser = true; session.closeConnection(); }
    disposeSessionRuntimes();
    disposePortForwardRuntime();
    disposeScriptScheduleRuntime();
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
    logController.dispose();
    super.dispose();
  }
}

enum SessionProbeStatus { unknown, probing, reachable, unreachable }

class SessionProbeState {
  const SessionProbeState({required this.status, this.latencyMs, this.lastCheckedAt, this.lastError});
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


