import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../../shared/logging/asmote_log.dart';
import 'file_node.dart';
import 'host_entry.dart';
import 'osc_parser.dart';
import 'terminal_tab.dart';
import 'transfer_task.dart';
import '../transport/native/native_terminal_pty_bridge.dart';
import '../transport/telnet/telnet_session.dart';
import '../state/terminal_app_state_models.dart';

class TerminalSession {
  TerminalSession({
    required this.id,
    required this.profile,
    required this.tab,
    required this.fileState,
    required this.transferQueue,
    int maxLines = 10000,
  })  : terminal = Terminal(maxLines: maxLines.clamp(1000, 100000)) {
    terminal.onOutput = _handleTerminalOutput;
    terminal.onResize = resizeTerminal;
    terminal.resize(120, 34);
  }

  final String id;
  final HostEntry profile;
  TerminalTab tab;
  final SessionFileState fileState;
  final List<TransferTask> transferQueue;
  final Terminal terminal;
  int activeTransfers = 0;
  int transferBatchTotal = 0;
  int transferBatchDone = 0;
  bool transferPreparing = false;
  String? transferPreparingLabel;
  int transferScanningScanned = 0;
  int transferScanningFiles = 0;
  String? currentTransferBatchId;
  final Map<String, DateTime> transferBatchCreatedAt = {};
  final Map<String, bool> transferBatchPreparing = {};
  final Map<String, String?> transferBatchPreparingLabel = {};
  final Map<String, int> transferBatchScanningScanned = {};
  final Map<String, int> transferBatchScanningFiles = {};
  SessionTransferSummary transferSummary = const SessionTransferSummary(
    preparing: false,
    preparingLabel: null,
    scanningScanned: 0,
    scanningFiles: 0,
    uploadQueues: [],
    downloadQueues: [],
    upload: TransferDirectionSummary(total: 0, done: 0, progress: 0),
    download: TransferDirectionSummary(total: 0, done: 0, progress: 0),
    runningUploadJobs: 0,
    runningDownloadJobs: 0,
    runningTotalJobs: 0,
    nativeBusySessions: 0,
    nativeTotalSessions: 0,
  );
  int transferVersion = 0;
  String? lastTransferId;
  final Set<String> canceledTransferIds = {};
  final Map<String, DateTime> transferLastNotifyAt = {};
  final Map<String, int> transferTaskIndex = {};
  final Set<String> transferRunningTaskIds = {};
  final Set<TransferDirection> pausedTransferDirections = {};
  final Set<String> pausedTransferTaskIds = {};
  bool transferCancelRequested = false;
  Timer? transferCleanupTimer;
  Timer? fileTreeRefreshTimer;
  bool closedByUser = false;
  bool _closedNotified = false;
  void Function()? onSessionClosed;
  void Function(String sessionId, List<int> bytes)? onOutputBytes;
  Timer? metricsTimer;
  double? cpuUsage;
  double? memUsage;
  int? memUsedBytes;
  int? memTotalBytes;
  double? diskUsage;
  double? loadAvg;
  double? netRxRate;
  double? netTxRate;
  double? diskReadRate;
  double? diskWriteRate;
  DateTime? metricsUpdatedAt;
  int? lastCpuTotal;
  int? lastCpuIdle;
  int? lastNetRxBytes;
  int? lastNetTxBytes;
  DateTime? lastNetAt;
  int? lastDiskReadBytes;
  int? lastDiskWriteBytes;
  DateTime? lastDiskAt;

  SSHClient? client;
  SSHSession? session;
  SftpClient? sftp;
  NativeTerminalPtySession? localPtySession;
  TelnetSession? telnetSession;
  void Function(int? exitCode, String? error)? onLocalPtyExit;
  void Function(String sessionId, String data)? onUserInput;
  void Function(String hostId, String command)? onCommandSubmitted;
  final List<SSHClient> auxiliaryClients = <SSHClient>[];
  StreamSubscription<List<int>>? _byteChannelOutputSub;
  void Function(List<int> bytes)? _byteChannelInputWriter;
  void Function()? _byteChannelCloser;
  String _byteChannelInputName = 'transport:stdin';
  final StringBuffer _inputLineBuffer = StringBuffer();

  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  int _byteLogSeq = 0;
  int? _lastResizeCols;
  int? _lastResizeRows;

  static const int _maxLogBytes = 256;
  static const bool _byteLogEnabled = bool.fromEnvironment(
    'ASMOTE_TERMINAL_BYTE_LOG',
  );
  static const bool _resizeLogEnabled = bool.fromEnvironment(
    'ASMOTE_TERMINAL_RESIZE_LOG',
  );
  static const Duration _windowsCmdWelcomeDelay = Duration(milliseconds: 200);
  static final RegExp _ansiEscapeRegExp = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');
  static final RegExp _oscEscapeRegExp = RegExp(
    r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)',
  );
  static final RegExp _controlCharRegExp = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );

  String? _pendingStartupBanner;
  String _startupPromptProbeBuffer = '';
  Timer? _startupBannerDelayTimer;
  DateTime _lastOutputAt = DateTime.now();
  DateTime get outputLastAt => _lastOutputAt;

  final OscParser oscParser = OscParser();

  /// Sends shell integration initialization commands to enable OSC 133 markers.
  void initShellIntegration() {
    final esc = '\x1B';
    sendInput(
      "export PS0='\\[${esc}]133;B\\a\\]'\n"
      "export PROMPT_COMMAND='printf \"${esc}]133;C;\$?\\a${esc}]133;A\\a\"'\n",
      trackForHistory: false,
    );
  }

  void attachSession(SSHSession sshSession) {
    session = sshSession;
    _closedNotified = false;
    _applyPendingResizeToSsh(sshSession);
    _stdoutSub = sshSession.stdout.listen(
      (data) => _onOutputBytes(data, channel: 'ssh:stdout'),
      onDone: _notifyClosed,
    );
    _stderrSub = sshSession.stderr.listen(
      (data) => _onOutputBytes(data, channel: 'ssh:stderr'),
      onDone: _notifyClosed,
    );
  }

  void _onOutputBytes(List<int> data, {required String channel}) {
    if (data.isEmpty) {
      return;
    }
    _lastOutputAt = DateTime.now();
    onOutputBytes?.call(id, data);
    _logBytes(direction: 'OUT', channel: channel, bytes: data);
    _injectStartupBannerBeforePromptIfNeeded(data);
    _writeToTerminal(data);
  }

  void attachLocalPtySession(NativeTerminalPtySession ptySession) {
    localPtySession = ptySession;
    _closedNotified = false;
    _applyPendingResizeToLocalPty(ptySession);
    final cmdLikeLocalShell = _isWindowsCmdLikeLocalSession();
    ptySession.onOutputBytes = (bytes) {
      onOutputBytes?.call(id, bytes);
      _logBytes(direction: 'OUT', channel: 'pty:stdout', bytes: bytes);
      if (cmdLikeLocalShell) {
        _scheduleWindowsCmdDelayedBannerOnFirstOutputIfNeeded();
      } else {
        _injectStartupBannerBeforePromptIfNeeded(bytes);
      }
      _writeToTerminal(bytes);
    };
    ptySession.onOutput = null;
    ptySession.onExit = (exitCode, error) {
      onLocalPtyExit?.call(exitCode, error);
      _notifyClosed();
    };
  }

  void attachByteChannel({
    required Stream<List<int>> output,
    required void Function(List<int> bytes) writeInputBytes,
    void Function()? close,
    String outputChannelName = 'transport:stdout',
    String inputChannelName = 'transport:stdin',
  }) {
    _safeCall(() => _byteChannelOutputSub?.cancel());
    _safeCall(() => _byteChannelCloser?.call());
    _byteChannelInputWriter = writeInputBytes;
    _byteChannelCloser = close;
    _byteChannelInputName = inputChannelName;
    _closedNotified = false;
    _byteChannelOutputSub = output.listen(
      (data) => _onOutputBytes(data, channel: outputChannelName),
      onDone: _notifyClosed,
    );
  }

  bool _isWindowsCmdLikeLocalSession() {
    if (!Platform.isWindows) {
      return false;
    }
    final shellType = profile.localShellType;
    return shellType == LocalShellType.commandPrompt ||
        shellType == LocalShellType.systemDefault;
  }

  void _scheduleWindowsCmdDelayedBannerOnFirstOutputIfNeeded() {
    final pending = _pendingStartupBanner;
    if (pending == null || pending.isEmpty) {
      return;
    }
    if (_startupBannerDelayTimer != null) {
      return;
    }
    _startupBannerDelayTimer = Timer(_windowsCmdWelcomeDelay, () {
      final delayedPending = _pendingStartupBanner;
      if (delayedPending == null || delayedPending.isEmpty) {
        _startupBannerDelayTimer = null;
        return;
      }
      terminal.write(delayedPending);
      final pty = localPtySession;
      if (pty != null) {
        try {
          pty.write('\r');
      } catch (e) {
        AsmoteLog.warn('terminal_session', '[$id] pty write failed: $e');
        localPtySession = null;
      }
      }
      _pendingStartupBanner = null;
      _startupPromptProbeBuffer = '';
      _startupBannerDelayTimer = null;
    });
  }

  void dispose() {
    closeConnection();
    fileState.dispose();
    transferCleanupTimer?.cancel();
    transferCleanupTimer = null;
  }

  void closeConnection() {
    final currentStdoutSub = _stdoutSub;
    final currentStderrSub = _stderrSub;
    final currentSession = session;
    final currentClient = client;
    final currentSftp = sftp;
    final currentLocalPtySession = localPtySession;
    final currentByteChannelOutputSub = _byteChannelOutputSub;
    final currentByteChannelCloser = _byteChannelCloser;
    final currentAuxClients = List<SSHClient>.from(auxiliaryClients);

    _stdoutSub = null;
    _stderrSub = null;
    session = null;
    client = null;
    sftp = null;
    localPtySession = null;
    _byteChannelOutputSub = null;
    _byteChannelInputWriter = null;
    _byteChannelCloser = null;
    _byteChannelInputName = 'transport:stdin';
    onLocalPtyExit = null;
    _pendingStartupBanner = null;
    _startupPromptProbeBuffer = '';
    _startupBannerDelayTimer?.cancel();
    _startupBannerDelayTimer = null;

    _safeCall(() => currentStdoutSub?.cancel());
    _safeCall(() => currentStderrSub?.cancel());
    _safeCall(() => currentSession?.close());
    _safeCall(() => currentClient?.close());
    _safeCall(() => currentSftp?.close());
    _safeCall(() => currentByteChannelOutputSub?.cancel());
    _safeCall(() => currentByteChannelCloser?.call());
    for (final aux in currentAuxClients) {
      _safeCall(() => aux.close());
    }
    auxiliaryClients.clear();
    _safeCall(() => currentLocalPtySession?.dispose());
    final currentTelnetSession = telnetSession;
    telnetSession = null;
    _safeCall(() => currentTelnetSession?.close());
    metricsTimer?.cancel();
    metricsTimer = null;
    fileTreeRefreshTimer?.cancel();
    fileTreeRefreshTimer = null;
    AsmoteLog.info('terminal_session', '[$id] connection closed');
  }

  void _notifyClosed() {
    if (_closedNotified) return;
    _closedNotified = true;
    onSessionClosed?.call();
  }

  void _safeCall(void Function() action) {
    try {
      action();
    } catch (_) {
      // Ignore close errors when transport is already closed.
    }
  }

  void queueStartupBannerBeforePrompt(String banner) {
    final normalized = banner.trim();
    if (normalized.isEmpty) {
      return;
    }
    _pendingStartupBanner = '$banner\r\n';
    _startupPromptProbeBuffer = '';
  }

  void _injectStartupBannerBeforePromptIfNeeded(List<int> data) {
    final pending = _pendingStartupBanner;
    if (pending == null || pending.isEmpty) {
      return;
    }
    final chunk = _decodeOutputBytes(data);
    if (chunk.isEmpty) {
      return;
    }
    _startupPromptProbeBuffer = '$_startupPromptProbeBuffer$chunk';
    const maxProbeChars = 8192;
    if (_startupPromptProbeBuffer.length > maxProbeChars) {
      _startupPromptProbeBuffer = _startupPromptProbeBuffer.substring(
        _startupPromptProbeBuffer.length - maxProbeChars,
      );
    }
    if (!_containsPromptLikeLine(_startupPromptProbeBuffer)) {
      return;
    }
    _startupBannerDelayTimer?.cancel();
    _startupBannerDelayTimer = null;
    _pendingStartupBanner = null;
    _startupPromptProbeBuffer = '';
    terminal.write(pending);
  }

  bool _containsPromptLikeLine(String text) {
    if (text.trim().isEmpty) {
      return false;
    }
    final cleaned = text
        .replaceAll(_oscEscapeRegExp, '')
        .replaceAll(_ansiEscapeRegExp, '')
        .replaceAll(_controlCharRegExp, '');
    final lines = cleaned.split('\n');
    for (final raw in lines) {
      final line = raw.replaceAll('\r', '').trimRight();
      if (line.isEmpty) {
        continue;
      }
      if (line.endsWith(r'$') || line.endsWith('#')) {
        return true;
      }
      if (RegExp(r'(?:^|[\s:~./\\\]])[#$]$').hasMatch(line)) {
        return true;
      }
      if (RegExp(r'^[^@\s]+@[^:\s]+:.*[#$]$').hasMatch(line)) {
        return true;
      }
      if (RegExp(r'^[A-Za-z]:\\.*>$').hasMatch(line)) {
        return true;
      }
      if (RegExp(r'^PS .+>$').hasMatch(line)) {
        return true;
      }
    }
    return false;
  }

  void sendInput(String data, {bool trackForHistory = true}) {
    if (data.isEmpty) {
      return;
    }
    if (trackForHistory) {
      _trackUserInputForHistory(data);
    }
    final bytes = Uint8List.fromList(utf8.encode(data));
    final sshSession = session;
    if (sshSession != null) {
      try {
        _logBytes(direction: 'IN', channel: 'ssh:stdin', bytes: bytes);
        sshSession.write(bytes);
        return;
      } catch (_) {
        session = null;
      }
    }
    final pty = localPtySession;
    if (pty != null) {
      try {
        _logBytes(direction: 'IN', channel: 'pty:stdin', bytes: bytes);
        pty.write(data);
        return;
      } catch (_) {
        localPtySession = null;
      }
    }
    final writer = _byteChannelInputWriter;
    if (writer != null) {
      try {
        _logBytes(
          direction: 'IN',
          channel: _byteChannelInputName,
          bytes: bytes,
        );
        writer(bytes);
      } catch (e) {
        AsmoteLog.warn('terminal_session', '[$id] byte channel write failed: $e');
        _byteChannelInputWriter = null;
        _safeCall(() => _byteChannelCloser?.call());
        _byteChannelCloser = null;
      }
    }
    final telnet = telnetSession;
    if (telnet != null) {
      try {
        _logBytes(direction: 'IN', channel: 'telnet:stdin', bytes: bytes);
        telnet.send(bytes);
        return;
      } catch (e) {
        AsmoteLog.warn('terminal_session', '[$id] telnet write failed: $e');
        telnetSession = null;
      }
    }
  }

  /// Waits until no output bytes have been received for [quietPeriod].
  Future<void> waitForOutputSilence(Duration quietPeriod) async {
    while (true) {
      final cutoff = _lastOutputAt;
      await Future<void>.delayed(quietPeriod);
      if (!identical(_lastOutputAt, cutoff)) continue;
      return;
    }
  }

  /// Waits for output to arrive after [since], then waits for [quietPeriod] of silence.
  /// Returns true if new output was detected, false if [timeout] elapsed with no output.
  Future<bool> waitForOutputSilenceSince(DateTime since, {
    Duration quietPeriod = const Duration(milliseconds: 800),
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    // First, wait for new output to arrive (the shell processing our command)
    while (identical(_lastOutputAt, since)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (DateTime.now().isAfter(deadline)) return false;
    }
    // New output arrived, now wait for silence
    await waitForOutputSilence(quietPeriod);
    return true;
  }

  void _handleTerminalOutput(String data) {
    sendInput(data);
    onUserInput?.call(id, data);
  }

  void _trackUserInputForHistory(String data) {
    if (data.isEmpty || data.contains('\x1B')) {
      return;
    }
    for (final rune in data.runes) {
      if (rune == 0x0D || rune == 0x0A) {
        _submitBufferedCommand();
        continue;
      }
      if (rune == 0x08 || rune == 0x7F) {
        if (_inputLineBuffer.isNotEmpty) {
          final next = _inputLineBuffer.toString();
          _inputLineBuffer
            ..clear()
            ..write(next.substring(0, next.length - 1));
        }
        continue;
      }
      if (rune < 0x20) {
        continue;
      }
      _inputLineBuffer.writeCharCode(rune);
    }
  }

  void _submitBufferedCommand() {
    final command = _inputLineBuffer.toString().trim();
    _inputLineBuffer.clear();
    if (command.isEmpty) {
      return;
    }
    onCommandSubmitted?.call(profile.id, command);
  }

  void _logBytes({
    required String direction,
    required String channel,
    required List<int> bytes,
  }) {
    if (!_byteLogEnabled || bytes.isEmpty) {
      return;
    }
    _byteLogSeq += 1;
    final previewLen = bytes.length > _maxLogBytes
        ? _maxLogBytes
        : bytes.length;
    final preview = bytes.sublist(0, previewLen);
    final hex = preview
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final text = _escapeBytes(preview);
    final more = bytes.length > previewLen
        ? ' ...(+${bytes.length - previewLen} bytes)'
        : '';
    AsmoteLog.debug(
      'terminal_session',
      '[$id][#$_byteLogSeq][$direction][$channel] len=${bytes.length}',
    );
    AsmoteLog.debug(
      'terminal_session',
      '[$id][#$_byteLogSeq][$direction][$channel] hex=$hex$more',
    );
    AsmoteLog.debug(
      'terminal_session',
      '[$id][#$_byteLogSeq][$direction][$channel] txt="$text"$more',
    );
  }

  void _writeToTerminal(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    var text = _decodeOutputBytes(bytes);
    text = oscParser.process(text);
    terminal.write(text);
  }

  void _applyPendingResizeToSsh(SSHSession sshSession) {
    final cols = _lastResizeCols;
    final rows = _lastResizeRows;
    if (cols == null || rows == null) {
      return;
    }
    try {
      sshSession.resizeTerminal(cols, rows, 0, 0);
      } catch (e) {
        AsmoteLog.warn('terminal_session', '[$id] ssh write failed: $e');
        session = null;
      }
  }

  void _applyPendingResizeToLocalPty(NativeTerminalPtySession ptySession) {
    final cols = _lastResizeCols;
    final rows = _lastResizeRows;
    if (cols == null || rows == null) {
      return;
    }
    try {
      ptySession.resize(cols, rows);
    } catch (_) {
      localPtySession = null;
    }
  }

  String _decodeOutputBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  String _escapeBytes(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      switch (b) {
        case 0x1b:
          sb.write(r'\e');
        case 0x0d:
          sb.write(r'\r');
        case 0x0a:
          sb.write(r'\n');
        case 0x09:
          sb.write(r'\t');
        case 0x5c:
          sb.write(r'\\');
        case 0x22:
          sb.write(r'\"');
        default:
          if (b >= 0x20 && b <= 0x7e) {
            sb.writeCharCode(b);
          } else {
            sb.write(r'\x');
            sb.write(b.toRadixString(16).padLeft(2, '0'));
          }
      }
    }
    return sb.toString();
  }

  void resizeTerminal(int cols, int rows, int pixelWidth, int pixelHeight) {
    final safeCols = cols.clamp(1, 500).toInt();
    final safeRows = rows.clamp(1, 500).toInt();
    if (_lastResizeCols == safeCols && _lastResizeRows == safeRows) {
      return;
    }
    _lastResizeCols = safeCols;
    _lastResizeRows = safeRows;
    if (_resizeLogEnabled) {
      AsmoteLog.debug('terminal_session', '[$id] resize cols=$safeCols rows=$safeRows');
    }
    final sshSession = session;
    if (sshSession != null) {
      try {
        sshSession.resizeTerminal(safeCols, safeRows, pixelWidth, pixelHeight);
      } catch (_) {
        session = null;
      }
    }
    final pty = localPtySession;
    if (pty != null) {
      try {
        pty.resize(safeCols, safeRows);
      } catch (_) {
        localPtySession = null;
      }
    }
    telnetSession?.resize(safeCols, safeRows);
  }
}

class SessionFileState {
  SessionFileState({required this.rootPath}) : currentPath = rootPath;

  String rootPath;
  String currentPath;
  String? homePath;
  String? forwardPath;
  final List<String> backStack = [];
  final List<String> forwardStack = [];
  final Map<String, List<FileNode>> directories = {};
  final Map<String, double> scrollOffsets = {};
  final Set<String> expanded = {};
  final Set<String> selected = {};
  final Set<String> loading = {};
  int version = 0;
  final ValueNotifier<int> selectionVersion = ValueNotifier(0);

  void bumpSelection() {
    selectionVersion.value += 1;
  }

  void dispose() {
    selectionVersion.dispose();
  }
}

class ScriptRunRecord {
  const ScriptRunRecord({
    required this.id,
    required this.scriptId,
    required this.scriptName,
    required this.sessionIds,
    required this.createdAt,
    required this.successCount,
    required this.totalCount,
  });

  final String id;
  final String scriptId;
  final String scriptName;
  final List<String> sessionIds;
  final DateTime createdAt;
  final int successCount;
  final int totalCount;
}
