import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../../../../events/event_bus.dart';
import '../../../../shared/constants/app_string.dart';

import '../../models/host_entry.dart';
import '../../models/session_file_state.dart';
import '../../models/terminal_session.dart';
import '../../models/terminal_tab.dart';
import '../../transport/native/native_terminal_pty_bridge.dart';
import '../../transport/telnet/telnet_session.dart';
import '../ssh/ssh_openssh_compat.dart';
import '../terminal_app_state.dart';

part 'terminal_app_state_sessions_reconnect.dart';

final Set<String> _connectedLogSessionIds = <String>{};
final Map<String, Timer> _autoReconnectTimers = <String, Timer>{};
final Set<String> _reconnectingSessionIds = <String>{};
const Duration _autoReconnectInterval = Duration(seconds: 2);

extension TerminalAppStateSessions on TerminalAppState {
  Future<void> connectToHost(
    HostEntry host, {
    bool remember = true,
    bool background = false,
  }) async {
    final effectiveHost = host.isSsh
        ? await applyOpenSshConfigToHost(host)
        : host;
    final session = _createSession(effectiveHost, activate: !background);
    if (remember && !hosts.any((entry) => entry.id == host.id)) {
      hosts.add(host);
      scheduleStateSave();
    }
    await _connectSession(session, background: background);
  }

  Future<void> quickConnect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final entry = HostEntry(
      id: 'quick-${DateTime.now().microsecondsSinceEpoch}',
      name: host,
      host: host,
      port: port,
      username: username,
      group: AppStrings.values.quickConnect.resolve(locale.languageCode),
      authType: AuthType.password,
      password: password,
    );
    final session = _createSession(entry);
    await _connectSession(session);
  }

  Future<void> reconnectSession(
    TerminalSession session, {
    bool background = false,
  }) async {
    if (!sessions.contains(session)) return;
    if (session.closedByUser) return;
    if (_reconnectingSessionIds.contains(session.id)) return;
    _stopAutoReconnectLoop(session.id);
    _reconnectingSessionIds.add(session.id);
    session.closedByUser = true;
    session.closeConnection();
    if (!sessions.contains(session)) {
      _reconnectingSessionIds.remove(session.id);
      return;
    }
    session.closedByUser = false;
    session.tab = session.tab.copyWith(status: TerminalStatus.reconnecting);
    notifyState();
    syncSshForegroundGuardNow();
    try {
      await _connectSession(session, background: background);
    } finally {
      _reconnectingSessionIds.remove(session.id);
    }
  }

  TerminalSession _createSession(HostEntry host, {bool activate = true}) {
    final sessionId = 'sess-${DateTime.now().microsecondsSinceEpoch}';
    final tab = TerminalTab(
      id: sessionId,
      title: host.name,
      status: TerminalStatus.connecting,
    );

    final session = TerminalSession(
      id: sessionId,
      profile: host,
      tab: tab,
      fileState: SessionFileState(rootPath: '/'),
      transferQueue: [],
      maxLines: terminalBufferSize, // 使用动态的 buffer 大小
      adaptiveThrottleEnabled: performanceSettings.adaptiveThrottleEnabled,
    );
    session.onCommandSubmitted = (hostId, command) {
      recordCommandHistory(hostId, command);
      unawaited(runScriptTriggersForCommandSubmitted(session, command));
    };
    session.onSessionClosed = () => _handleSessionClosed(session);

    sessions.add(session);
    if (activate) {
      activeSessionIndexValue = sessions.length - 1;
      var stageIndex = terminalStages.indexWhere(
        (s) => s.id == activeTerminalStageId,
      );
      if (stageIndex >= 0) {
        if (Platform.isAndroid || Platform.isIOS) {
          terminalStages[stageIndex] = terminalStages[stageIndex].copyWith(
            sessionIds: [...terminalStages[stageIndex].sessionIds, session.id],
            connectedHostIds: [...terminalStages[stageIndex].connectedHostIds, host.id],
          );
          switchTerminalStage(terminalStages[stageIndex].id);
        } else if (terminalStages[stageIndex].sessionIds.isEmpty) {
          terminalStages[stageIndex] = terminalStages[stageIndex].copyWith(
            sessionIds: [session.id],
            connectedHostIds: [host.id],
          );
          switchTerminalStage(terminalStages[stageIndex].id);
        } else {
          createTerminalStage(host.name, sessionIds: [session.id], connectedHostIds: [host.id]);
        }
      } else {
        createTerminalStage(host.name, sessionIds: [session.id], connectedHostIds: [host.id]);
      }
      ensureTerminalSplitPanes();
      final paneId = activeTerminalSplitPaneId.isEmpty
          ? (terminalSplitPanes.isEmpty ? 'pane-0' : terminalSplitPanes.first.id)
          : activeTerminalSplitPaneId;
      final paneIndex = terminalSplitPanes.indexWhere(
        (pane) => pane.id == paneId,
      );
      if (paneIndex >= 0) {
        terminalSplitPanes[paneIndex] = terminalSplitPanes[paneIndex].copyWith(
          sessionId: session.id,
        );
        activeTerminalSplitPaneId = paneId;
      }
    }
    if (activate) {
      // Only notify when activating (session is visible in UI).
      // Background sessions (activate=false) don't need to trigger rebuild
      // until _connectSession sets their status.
      notifyState();
      syncSshForegroundGuardNow();
    }
    return session;
  }

  Future<void> _connectSession(
    TerminalSession session, {
    bool background = false,
  }) async {
    if (!sessions.contains(session) || session.closedByUser) return;
    session.tab = session.tab.copyWith(status: TerminalStatus.connecting);
    if (!background) {
      notifyState();
    }
    syncSshForegroundGuardNow();
    try {
      if (!sessions.contains(session) || session.closedByUser) return;
      if (session.profile.isLocal) {
        await _connectLocalSession(session, background: background);
        return;
      }
      if (session.profile.isSerial) {
        await _connectSerialSession(session, background: background);
        return;
      }
      if (session.profile.isTelnet) {
        await _connectTelnetSession(session, background: background);
        return;
      }
      addStructuredLog(
        category: TerminalLogCategory.session,
        message: AppStrings.values.connectingToVarVar.resolve(
          locale.languageCode,
          params: {
            'host': session.profile.host,
            'port': '${session.profile.port}',
          },
        ),
        notifyListeners: false,
      );
      final auxiliaryClients = <SSHClient>[];
      final client = await connectSshClientForHost(
        session.profile,
        auxiliaryClients: auxiliaryClients,
      );
      if (!sessions.contains(session) || session.closedByUser) {
        client.close();
        for (final auxiliaryClient in auxiliaryClients) {
          auxiliaryClient.close();
        }
        return;
      }
      session.client = client;
      session.auxiliaryClients
        ..clear()
        ..addAll(auxiliaryClients);

      final sshSession = await client
          .shell(pty: const SSHPtyConfig(type: 'xterm-256color'))
          .timeout(const Duration(seconds: 15));
      if (!sessions.contains(session) || session.closedByUser) {
        sshSession.close();
        client.close();
        for (final auxiliaryClient in auxiliaryClients) {
          auxiliaryClient.close();
        }
        return;
      }

      _queuePolarmoteTerminalWelcome(session);
      session.attachSession(sshSession);
      session.closedByUser = false;
      unawaited(
        client.done.catchError((_) {}).then((_) {
          if (!sessions.contains(session) || session.closedByUser) return;
          if (session.tab.status == TerminalStatus.disconnected) return;
          _handleSessionClosed(session);
        }),
      );

      session.tab = session.tab.copyWith(status: TerminalStatus.connected);
      _stopAutoReconnectLoop(session.id);
      eventBus.fire(SessionConnectedEvent(sessionId: session.id));
      _updateHostLastConnected(session.profile.id);
      if (!_connectedLogSessionIds.contains(session.id)) {
        _connectedLogSessionIds.add(session.id);
        addStructuredLog(
          category: TerminalLogCategory.session,
          message: AppStrings.values.connectedVar.resolve(
            locale.languageCode,
            params: {'host': session.profile.host},
          ),
          notifyListeners: false,
        );
      }
      startMetricsPolling(session);
      unawaited(runScriptTriggersForSessionConnected(session));
      if (!background) {
        notifyState();
        syncSshForegroundGuardNow();
      }
    } catch (e) {
      if (!sessions.contains(session) || session.closedByUser) {
        return;
      }
      final failure = _classifySshConnectionFailure(
        appState: this,
        host: session.profile,
        error: e,
      );
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      session.closedByUser = true;
      session.closeConnection();
      session.closedByUser = false;
      setError(failure.userMessage);
      addStructuredLog(
        category: TerminalLogCategory.session,
        level: TerminalLogLevel.warn,
        message: failure.logMessage,
        notifyListeners: false,
      );
      if (failure.allowAutoReconnect &&
          autoReconnect &&
          sessions.contains(session) &&
          session.profile.isSsh) {
        _startAutoReconnectLoop(session);
      }
      syncSshForegroundGuardNow();
    }
  }

  Future<void> _connectSerialSession(
    TerminalSession session, {
    bool background = false,
  }) async {
    
    if (!_isSerialSupportedOnPlatform()) {
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      setError(
        AppStrings.values.serialUnsupportedOnPlatform.resolve(
          locale.languageCode,
        ),
      );
      return;
    }
    final portPath = session.profile.serialPortPath?.trim() ?? '';
    if (portPath.isEmpty) {
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      setError(
        AppStrings.values.serialPortRequired.resolve(locale.languageCode),
      );
      return;
    }

    SerialPort? serialPort;
    SerialPortReader? serialReader;
    try {
      serialPort = SerialPort(portPath);
      if (!serialPort.openReadWrite()) {
        throw SerialPort.lastError ??
            StateError('Failed to open serial port $portPath');
      }
      final config = serialPort.config;
      config.baudRate = session.profile.serialBaudRate;
      config.bits = session.profile.serialDataBits;
      config.stopBits = session.profile.serialStopBits;
      config.parity = _mapSerialParity(session.profile.serialParity);
      config.setFlowControl(SerialPortFlowControl.none);
      serialPort.config = config;
      serialPort.flush();

      serialReader = SerialPortReader(serialPort, timeout: 200);
      session.attachByteChannel(
        output: serialReader.stream,
        writeInputBytes: (bytes) {
          serialPort?.write(Uint8List.fromList(bytes));
        },
        close: () {
          try {
            serialReader?.close();
          } catch (_) {}
          try {
            serialPort?.close();
          } catch (_) {}
          try {
            serialPort?.dispose();
          } catch (_) {}
          serialReader = null;
          serialPort = null;
        },
        outputChannelName: 'serial:rx',
        inputChannelName: 'serial:tx',
      );
      session.closedByUser = false;
      session.tab = session.tab.copyWith(status: TerminalStatus.connected);
      _stopAutoReconnectLoop(session.id);
      _updateHostLastConnected(session.profile.id);
      if (!_connectedLogSessionIds.contains(session.id)) {
        _connectedLogSessionIds.add(session.id);
        addStructuredLog(
          category: TerminalLogCategory.session,
          message: AppStrings.values.connectedVar.resolve(
            locale.languageCode,
            params: {'host': portPath},
          ),
          notifyListeners: false,
        );
      }
      unawaited(runScriptTriggersForSessionConnected(session));
      if (!background) {
        notifyState();
        syncSshForegroundGuardNow();
      }
    } catch (e) {
      
      session.closeConnection();
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      try {
        serialReader?.close();
      } catch (_) {}
      try {
        serialPort?.close();
      } catch (_) {}
      try {
        serialPort?.dispose();
      } catch (_) {}
      setError(
        AppStrings.values.serialConnectFailedVar.resolve(
          locale.languageCode,
          params: {'error': '$e'},
        ),
      );
      syncSshForegroundGuardNow();
    }
  }

  Future<void> _connectTelnetSession(
    TerminalSession session, {
    bool background = false,
  }) async {
    if (!sessions.contains(session) || session.closedByUser) return;
    final telnetPort = session.profile.telnetPort;
    final host = session.profile.host;
    
    addStructuredLog(
      category: TerminalLogCategory.session,
      message: AppStrings.values.connectingToVarVar.resolve(
        locale.languageCode,
        params: {'host': host, 'port': '$telnetPort'},
      ),
      notifyListeners: false,
    );
    try {
      final telnetSession = TelnetSession(
        session: session,
        host: host,
        port: telnetPort,
      );
      await telnetSession.connect();
      if (!sessions.contains(session) || session.closedByUser) {
        await telnetSession.close();
        return;
      }
      session.telnetSession = telnetSession;
      session.closedByUser = false;
      session.tab = session.tab.copyWith(status: TerminalStatus.connected);
      _stopAutoReconnectLoop(session.id);
      _updateHostLastConnected(session.profile.id);
      if (!_connectedLogSessionIds.contains(session.id)) {
        _connectedLogSessionIds.add(session.id);
        addStructuredLog(
          category: TerminalLogCategory.session,
          message: AppStrings.values.connectedVar.resolve(
            locale.languageCode,
            params: {'host': host},
          ),
          notifyListeners: false,
        );
      }
      unawaited(runScriptTriggersForSessionConnected(session));
      if (!background) {
        notifyState();
        syncSshForegroundGuardNow();
      }
    } catch (e) {
      
      session.closeConnection();
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      setError(
        AppStrings.values.connectionFailedVar.resolve(
          locale.languageCode,
          params: {'error': '$e'},
        ),
      );
      addStructuredLog(
        category: TerminalLogCategory.session,
        level: TerminalLogLevel.warn,
        message: AppStrings.values.logErrorVar.resolve(
          locale.languageCode,
          params: {'message': 'telnet $host:$telnetPort $e'},
        ),
        notifyListeners: false,
      );
      syncSshForegroundGuardNow();
    }
  }

  Future<void> _connectLocalSession(
    TerminalSession session, {
    bool background = false,
  }) async {
    
    if (Platform.isWindows &&
        session.profile.localShellType == LocalShellType.powershellAdmin &&
        !_isWindowsProcessElevated()) {
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      setError(
        AppStrings.values.localTerminalAdminRequiresElevation.resolve(
          locale.languageCode,
        ),
      );
      return;
    }
    final shellSpec = _resolveLocalShellSpec(session.profile);
    if (shellSpec == null) {
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      setError(
        AppStrings.values.localTerminalUnsupportedOnPlatform.resolve(
          locale.languageCode,
        ),
      );
      return;
    }
    final bridge = NativeTerminalPtyBridge.instance;
    if (!bridge.isSupported) {
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      setError(
        AppStrings.values.localTerminalUnsupportedOnPlatform.resolve(
          locale.languageCode,
        ),
      );
      return;
    }
    final (program, args) = shellSpec;
    try {
      final ptySession = _spawnLocalPtyWithFallback(
        bridge: bridge,
        primaryProgram: program,
        primaryArgs: args,
        cwd: _resolveLocalWorkingDirectory(),
        cols: session.terminal.viewWidth,
        rows: session.terminal.viewHeight,
      );
      session.attachLocalPtySession(ptySession);
      session.onLocalPtyExit = (exitCode, error) {
        if (session.closedByUser) {
          return;
        }
        if (!sessions.contains(session)) {
          return;
        }
        if (exitCode == null || exitCode == 0) {
          return;
        }
        final rawDetail = error?.trim() ?? '';
        final detail = rawDetail.isNotEmpty ? rawDetail : 'exitCode=$exitCode';
        setError(
          AppStrings.values.localTerminalStartFailedVar.resolve(
            locale.languageCode,
            params: {'error': detail},
          ),
        );
      };
      session.closedByUser = false;
      session.tab = session.tab.copyWith(status: TerminalStatus.connected);
      _stopAutoReconnectLoop(session.id);
      _updateHostLastConnected(session.profile.id);
      if (!_connectedLogSessionIds.contains(session.id)) {
        _connectedLogSessionIds.add(session.id);
        addStructuredLog(
          category: TerminalLogCategory.session,
          message: AppStrings.values.connectedVar.resolve(
            locale.languageCode,
            params: {'host': session.profile.name},
          ),
          notifyListeners: false,
        );
      }
      startMetricsPolling(session);
      unawaited(runScriptTriggersForSessionConnected(session));
      if (!background) {
        notifyState();
        syncSshForegroundGuardNow();
      }
    } catch (e) {
      
      session.closeConnection();
      session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
      setError(
        AppStrings.values.localTerminalStartFailedVar.resolve(
          locale.languageCode,
          params: {'error': '$e'},
        ),
      );
      syncSshForegroundGuardNow();
    }
  }

  NativeTerminalPtySession _spawnLocalPtyWithFallback({
    required NativeTerminalPtyBridge bridge,
    required String primaryProgram,
    required List<String> primaryArgs,
    required String cwd,
    required int cols,
    required int rows,
  }) {
    NativeTerminalPtySession trySpawn(
      String program,
      List<String> args, {
      String? workingDirectory,
    }) {
      return bridge.spawn(
        NativeTerminalPtySpawnConfig(
          program: program,
          args: args,
          cwd: workingDirectory,
          env: {
            'TERM': 'xterm-256color', // 设置终端类型，启用替代屏幕缓冲区等高级特性
            'COLORTERM': 'truecolor', // 支持真彩色
          },
          cols: cols.clamp(1, 500).toInt(),
          rows: rows.clamp(1, 500).toInt(),
        ),
      );
    }

    Object? firstError;
    try {
      return trySpawn(primaryProgram, primaryArgs, workingDirectory: cwd);
    } catch (error) {
      firstError = error;
    }

    try {
      return trySpawn(primaryProgram, primaryArgs);
    } catch (error) {
      if (Platform.isWindows) {
        try {
          return trySpawn('cmd.exe', const <String>[
            '/Q',
            '/D',
            '/K',
            'chcp 65001>nul',
          ]);
        } catch (_) {
          // Keep original failure context below.
        }
      }
      throw StateError('primary=$firstError, fallback=$error');
    }
  }

  bool _isWindowsProcessElevated() {
    if (!Platform.isWindows) return false;
    try {
      final result = Process.runSync('powershell.exe', const [
        '-NoProfile',
        '-Command',
        '[bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
      ]);
      if (result.exitCode != 0) return false;
      final output = result.stdout?.toString().trim().toLowerCase() ?? '';
      return output == 'true';
    } catch (_) {
      return false;
    }
  }

  (String, List<String>)? _resolveLocalShellSpec(HostEntry profile) {
    String? firstExisting(List<String> candidates) {
      for (final candidate in candidates) {
        if (candidate.trim().isEmpty) continue;
        try {
          if (File(candidate).existsSync()) return candidate;
        } catch (_) {
          // Ignore inaccessible candidate and continue fallback probing.
        }
      }
      return null;
    }

    if (Platform.isWindows) {
      switch (profile.localShellType) {
        case LocalShellType.powershell:
        case LocalShellType.powershellAdmin:
          final shell =
              firstExisting([
                '${Platform.environment['ProgramFiles']}\\PowerShell\\7\\pwsh.exe',
                '${Platform.environment['ProgramW6432']}\\PowerShell\\7\\pwsh.exe',
                '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
              ]) ??
              'powershell.exe';
          return (shell, const <String>['-NoLogo', '-NoExit']);
        case LocalShellType.commandPrompt:
        case LocalShellType.systemDefault:
          final cmdShell =
              firstExisting([
                Platform.environment['ComSpec'] ?? '',
                '${Platform.environment['SystemRoot']}\\System32\\cmd.exe',
              ]) ??
              'cmd.exe';
          return (cmdShell, const <String>['/Q', '/D', '/K', 'chcp 65001>nul']);
        case LocalShellType.wsl:
          return ('wsl.exe', const <String>[]);
        case LocalShellType.bash:
          final bashPath =
              firstExisting([
                '${Platform.environment['ProgramFiles']}\\Git\\bin\\bash.exe',
                '${Platform.environment['ProgramFiles(x86)']}\\Git\\bin\\bash.exe',
              ]) ??
              'bash.exe';
          return (bashPath, const <String>['--login', '-i']);
      }
    }
    if (Platform.isAndroid) {
      final androidShell = File('/system/bin/sh');
      if (androidShell.existsSync()) {
        return (androidShell.path, const <String>['-i']);
      }
      return ('sh', const <String>['-i']);
    }
    if (Platform.isIOS) {
      return null;
    }
    if (profile.localShellType == LocalShellType.bash) {
      final shellEnv = Platform.environment['SHELL']?.trim() ?? '';
      if (shellEnv.isNotEmpty && shellEnv.contains('bash')) {
        return (shellEnv, const <String>['-i']);
      }
      return ('/bin/bash', const <String>['-i']);
    }
    final shellEnv = Platform.environment['SHELL']?.trim();
    if (shellEnv != null && shellEnv.isNotEmpty) {
      return (shellEnv, const <String>['-i']);
    }
    return ('/bin/sh', const <String>['-i']);
  }

  String _resolveLocalWorkingDirectory() {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE']?.trim();
      if (userProfile != null && userProfile.isNotEmpty) {
        return userProfile;
      }
      final homePath = Platform.environment['HOMEPATH']?.trim();
      if (homePath != null && homePath.isNotEmpty) {
        final drive = Platform.environment['HOMEDRIVE']?.trim() ?? '';
        return '$drive$homePath';
      }
    } else {
      final home = Platform.environment['HOME']?.trim();
      if (home != null && home.isNotEmpty) {
        return home;
      }
    }
    return Directory.current.path;
  }

  void _updateHostLastConnected(String hostId) {
    final index = hosts.indexWhere((entry) => entry.id == hostId);
    if (index == -1) return;
    hosts[index] = hosts[index].copyWith(lastConnected: DateTime.now());
    scheduleStateSave();
  }

  void _queuePolarmoteTerminalWelcome(TerminalSession session) {
    if (!sessions.contains(session)) {
      return;
    }
    session.queueStartupBannerBeforePrompt(
      _buildPolarmoteTerminalWelcome(session),
    );
  }

  String _buildPolarmoteTerminalWelcome(TerminalSession session) {
    const accent = '\x1B[38;5;81m';
    const secondary = '\x1B[38;5;111m';
    const emailAccent = '\x1B[38;5;220m';
    const border = '\x1B[38;5;67m';
    const neutral = '\x1B[38;5;250m';
    const reset = '\x1B[0m';
    final now = DateTime.now().toLocal().toIso8601String().replaceFirst(
      'T',
      ' ',
    );
    final title = session.tab.title.trim().isEmpty
        ? (session.profile.name.trim().isEmpty
              ? AppStrings.values.session.resolve(locale.languageCode)
              : session.profile.name.trim())
        : session.tab.title.trim();
    final mode = switch (session.profile.connectionType) {
      ConnectionType.local => 'LOCAL',
      ConnectionType.serial => 'SERIAL',
      ConnectionType.ssh => 'SSH',
      ConnectionType.telnet => 'TELNET',
    };
    return [
      '\r\n',
      accent,
      '██████╗  ██████╗ ██╗      █████╗ ██████╗ ███╗   ███╗ ██████╗ ████████╗███████╗',
      '\r\n',
      '██╔══██╗██╔═══██╗██║     ██╔══██╗██╔══██╗████╗ ████║██╔═══██╗╚══██╔══╝██╔════╝',
      '\r\n',
      '██████╔╝██║   ██║██║     ███████║██████╔╝██╔████╔██║██║   ██║   ██║   █████╗  ',
      '\r\n',
      '██╔═══╝ ██║   ██║██║     ██╔══██║██╔══██╗██║╚██╔╝██║██║   ██║   ██║   ██╔══╝  ',
      '\r\n',
      '██║     ╚██████╔╝███████╗██║  ██║██║  ██║██║ ╚═╝ ██║╚██████╔╝   ██║   ███████╗',
      '\r\n',
      '╚═╝      ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝    ╚═╝   ╚══════╝',
      '\r\n',
      border,
      '  ------------------------------------------------------------',
      '\r\n',
      secondary,
      '  ${AppStrings.values.PolarmoteTerminalReady.resolve(locale.languageCode)}',
      '\r\n',
      neutral,
      '  ${AppStrings.values.sessionLabel.resolve(locale.languageCode)} $title',
      '\r\n',
      '  ${AppStrings.values.modeLabel.resolve(locale.languageCode)} $mode',
      '\r\n',
      '  ${AppStrings.values.timeLabel.resolve(locale.languageCode)} $now',
      '\r\n',
      neutral,
      '  ${AppStrings.values.contactLabel.resolve(locale.languageCode)} ',
      emailAccent,
      AppStrings.values.contactEmail.resolve(locale.languageCode),
      neutral,
      '\r\n',
      '  ${AppStrings.values.contactQuestion.resolve(locale.languageCode)}',
      '\r\n',
      '  ${AppStrings.values.thanksForUsing.resolve(locale.languageCode)}',
      '\r\n',
      border,
      '  ------------------------------------------------------------',
      '\r\n',
      reset,
    ].join();
  }

  Future<void> disconnectSession(String id) async {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index == -1) return;
    final session = sessions[index];
    _stopAutoReconnectLoop(id);
    session.closedByUser = true;
    session.fileTreeRefreshTimer?.cancel();
    session.fileTreeRefreshTimer = null;
    stopMetricsPolling(session);
    session.closeConnection();
    session.tab = session.tab.copyWith(status: TerminalStatus.disconnected);
    _connectedLogSessionIds.remove(session.id);
    notifyState();
    syncSshForegroundGuardNow();
  }

  Future<void> closeSession(String id) async {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index == -1) {
      // session 已不在 sessions 中，只清理 stage 里残留的 session ID
      for (var si = 0; si < terminalStages.length; si++) {
        final st = terminalStages[si];
        if (st.sessionIds.contains(id)) {
          terminalStages[si] = st.copyWith(
            sessionIds: st.sessionIds.where((sid) => sid != id).toList(),
          );
        }
      }
      notifyState(); return;
    }
    final session = sessions[index];
    // 先从 stage 移除 hostId，再移除 sessionId（顺序重要，否则 sessionIds 被清除后找不到 stage）
    for (var si = 0; si < terminalStages.length; si++) {
      final st = terminalStages[si];
      if (st.sessionIds.contains(id)) {
        terminalStages[si] = st.copyWith(
          sessionIds: st.sessionIds.where((sid) => sid != id).toList(),
          connectedHostIds: st.connectedHostIds.where((hid) => hid != session.profile.id).toList(),
        );
      }
    }
    _stopAutoReconnectLoop(id);
    session.closedByUser = true;
    session.fileTreeRefreshTimer?.cancel();
    session.fileTreeRefreshTimer = null;
    stopMetricsPolling(session);
    disposeExternalEditsForSession(session.id);
    cleanupTransfersForSession(session);
    session.dispose();
    _connectedLogSessionIds.remove(session.id);

    // Clean up thumbnail Image to prevent memory leak
    terminalThumbnailImages[session.id]?.dispose();
    terminalThumbnailImages.remove(session.id);

    sessions.removeAt(index);
    for (
      var paneIndex = 0;
      paneIndex < terminalSplitPanes.length;
      paneIndex++
    ) {
      if (terminalSplitPanes[paneIndex].sessionId == id) {
        terminalSplitPanes[paneIndex] = terminalSplitPanes[paneIndex].copyWith(
          sessionId: '',
        );
      }
    }
    if (activeSessionIndexValue >= sessions.length) {
      activeSessionIndexValue = sessions.isEmpty ? -1 : sessions.length - 1;
    }
    // 如果当前 Stage 已无会话，停留在空 Stage 上，不跳转到其他 Stage
    final activeStage = terminalStages.where((s) => s.id == activeTerminalStageId).firstOrNull;
    if (activeStage != null && activeStage.sessionIds.isEmpty) {
      activeSessionIndexValue = -1;
      notifyState();
      syncSshForegroundGuardNow();
      return;
    }
    if (sessions.isNotEmpty && activeSession != null) {
      setActiveTerminalSession(activeSession!.id);
      syncSshForegroundGuardNow();
      return;
    }
    notifyState();
    syncSshForegroundGuardNow();
  }

  void setActiveSession(int index) {
    if (index < 0 || index >= sessions.length) return;
    setActiveTerminalSession(sessions[index].id);
  }

  bool _isSerialSupportedOnPlatform() {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  int _mapSerialParity(SerialParity parity) {
    return switch (parity) {
      SerialParity.none => SerialPortParity.none,
      SerialParity.odd => SerialPortParity.odd,
      SerialParity.even => SerialPortParity.even,
    };
  }

  void disposeSessionRuntimes() {
    for (final timer in _autoReconnectTimers.values) {
      timer.cancel();
    }
    _autoReconnectTimers.clear();
    _reconnectingSessionIds.clear();
    _connectedLogSessionIds.clear();
  }
}

class _SshConnectionFailureInfo {
  const _SshConnectionFailureInfo({
    required this.userMessage,
    required this.logMessage,
    required this.allowAutoReconnect,
  });

  final String userMessage;
  final String logMessage;
  final bool allowAutoReconnect;
}

_SshConnectionFailureInfo _classifySshConnectionFailure({
  required TerminalAppState appState,
  required HostEntry host,
  required Object error,
}) {
  final localeCode = appState.locale.languageCode;
  final raw = '$error'.trim();
  final lower = raw.toLowerCase();
  final target = '${host.host}:${host.port}';

  String buildUserMessage(String detail) {
    return AppStrings.values.connectionFailedVar.resolve(
      localeCode,
      params: {'error': detail},
    );
  }

  String buildLogMessage(String summary) {
    final prefix = AppStrings.values.connectionFailed.resolve(localeCode);
    return '$prefix $target · $summary · raw=$raw';
  }

  if (error is TimeoutException ||
      lower.contains('timed out') ||
      lower.contains('timeout')) {
    final detail = AppStrings.values.connectionTimedOutDesc.resolve(localeCode);
    return _SshConnectionFailureInfo(
      userMessage: buildUserMessage(detail),
      logMessage: buildLogMessage(detail),
      allowAutoReconnect: true,
    );
  }

  if (error is SocketException) {
    if (lower.contains('failed host lookup') ||
        lower.contains('name or service not known') ||
        lower.contains('no address associated with hostname') ||
        lower.contains('getaddrinfo')) {
      final detail = AppStrings.values.hostLookupFailedDesc.resolve(localeCode);
      return _SshConnectionFailureInfo(
        userMessage: buildUserMessage(detail),
        logMessage: buildLogMessage(detail),
        allowAutoReconnect: false,
      );
    }
    if (lower.contains('connection refused') ||
        lower.contains('actively refused')) {
      final detail = AppStrings.values.connectionRefusedDesc.resolve(localeCode);
      return _SshConnectionFailureInfo(
        userMessage: buildUserMessage(detail),
        logMessage: buildLogMessage(detail),
        allowAutoReconnect: true,
      );
    }
    if (lower.contains('network is unreachable') ||
        lower.contains('no route to host') ||
        lower.contains('host is down') ||
        lower.contains('host unreachable')) {
      final detail = AppStrings.values.networkUnreachableDesc.resolve(localeCode);
      return _SshConnectionFailureInfo(
        userMessage: buildUserMessage(detail),
        logMessage: buildLogMessage(detail),
        allowAutoReconnect: true,
      );
    }
  }

  if (lower.contains('permission denied') ||
      lower.contains('authentication failed') ||
      lower.contains('unable to authenticate') ||
      lower.contains('auth fail') ||
      lower.contains('no supported authentication methods')) {
    final detail = AppStrings.values.authFailedDesc.resolve(localeCode);
    return _SshConnectionFailureInfo(
      userMessage: buildUserMessage(detail),
      logMessage: buildLogMessage(detail),
      allowAutoReconnect: false,
    );
  }

  if (lower.contains('host key') ||
      lower.contains('fingerprint') ||
      lower.contains('known_hosts')) {
    final detail = AppStrings.values.hostKeyFailedDesc.resolve(localeCode);
    return _SshConnectionFailureInfo(
      userMessage: buildUserMessage(detail),
      logMessage: buildLogMessage(detail),
      allowAutoReconnect: false,
    );
  }

  if (lower.contains('private key') ||
      lower.contains('passphrase') ||
      lower.contains('identity file') ||
      lower.contains('identity') ||
      raw.contains('私钥')) {
    final detail = AppStrings.values.privateKeyInvalidDesc.resolve(localeCode);
    return _SshConnectionFailureInfo(
      userMessage: buildUserMessage(detail),
      logMessage: buildLogMessage(detail),
      allowAutoReconnect: false,
    );
  }

  if (lower.contains('proxyjump') ||
      lower.contains('jump host') ||
      lower.contains('socks') ||
      lower.contains('proxy')) {
    final detail = AppStrings.values.proxyInvalidDesc.resolve(localeCode);
    return _SshConnectionFailureInfo(
      userMessage: buildUserMessage(detail),
      logMessage: buildLogMessage(detail),
      allowAutoReconnect: false,
    );
  }

  final detail = AppStrings.values.unknownErrorSeeLogs.resolve(localeCode);
  return _SshConnectionFailureInfo(
    userMessage: buildUserMessage(detail),
    logMessage: buildLogMessage(detail),
    allowAutoReconnect: true,
  );
}


