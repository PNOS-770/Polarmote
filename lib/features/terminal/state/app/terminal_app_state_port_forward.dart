import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../../../shared/constants/app_string.dart';
import '../../models/host_entry.dart';
import '../../models/port_forward_entry.dart';
import '../terminal_app_state.dart';
part 'terminal_app_state_port_forward_types.dart';
part 'terminal_app_state_port_forward_templates.dart';

final Expando<Map<String, _ActivePortForwardRuntime>>
_portForwardRuntimeByState = Expando<Map<String, _ActivePortForwardRuntime>>(
  'port-forward-runtime',
);
final Expando<Timer> _portForwardHealthTimerByState = Expando<Timer>(
  'port-forward-health-timer',
);

enum PortForwardRuntimeStatus { stopped, starting, running, error }

class PortForwardRuntimeView {
  const PortForwardRuntimeView({
    required this.entry,
    required this.status,
    required this.boundPort,
    required this.lastError,
    required this.diagnosticHint,
    required this.activeLocalConnections,
    required this.activeTunnelChannels,
    required this.lastActivityAt,
    required this.startedAt,
  });

  final PortForwardEntry entry;
  final PortForwardRuntimeStatus status;
  final int? boundPort;
  final String? lastError;
  final String? diagnosticHint;
  final int activeLocalConnections;
  final int activeTunnelChannels;
  final DateTime? lastActivityAt;
  final DateTime? startedAt;
}

extension TerminalAppStatePortForward on TerminalAppState {
  Map<String, _ActivePortForwardRuntime> _portForwardRuntimeMap() {
    return _portForwardRuntimeByState[this] ??=
        <String, _ActivePortForwardRuntime>{};
  }

  void _ensurePortForwardHealthMonitor() {
    final existing = _portForwardHealthTimerByState[this];
    if (existing?.isActive ?? false) {
      return;
    }
    _portForwardHealthTimerByState[this] = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _runPortForwardHealthCheck(),
    );
  }

  void _stopPortForwardHealthMonitorIfIdle() {
    final hasActiveRuntime = _portForwardRuntimeMap().values.any(
      (runtime) =>
          runtime.status == PortForwardRuntimeStatus.running ||
          runtime.status == PortForwardRuntimeStatus.starting,
    );
    if (hasActiveRuntime) {
      return;
    }
    _portForwardHealthTimerByState[this]?.cancel();
  }

  void _runPortForwardHealthCheck() {
    final runtimeMap = _portForwardRuntimeMap();
    var changed = false;
    final now = DateTime.now();
    for (final runtime in runtimeMap.values) {
      final status = runtime.status;
      if (status != PortForwardRuntimeStatus.running &&
          status != PortForwardRuntimeStatus.starting) {
        continue;
      }

      runtime.lastHealthCheckAt = now;
      if (status == PortForwardRuntimeStatus.starting) {
        final startedAt = runtime.startedAt;
        if (startedAt != null &&
            now.difference(startedAt) >= const Duration(seconds: 20)) {
          runtime.status = PortForwardRuntimeStatus.error;
          runtime.lastError = AppStrings.values.portForwardErrorStartTimeout
              .resolve(locale.languageCode);
          runtime.boundPort = null;
          unawaited(runtime.dispose());
          changed = true;
        }
        continue;
      }

      final client = runtime.client;
      if (client == null || client.isClosed) {
        runtime.status = PortForwardRuntimeStatus.error;
        runtime.lastError = AppStrings.values.portForwardErrorSshClosed.resolve(
          locale.languageCode,
        );
        runtime.boundPort = null;
        unawaited(runtime.dispose());
        changed = true;
        continue;
      }

      switch (runtime.type) {
        case PortForwardType.local:
        case PortForwardType.socks:
          if (runtime.server == null) {
            runtime.status = PortForwardRuntimeStatus.error;
            runtime.lastError = AppStrings
                .values
                .portForwardErrorLocalListenerClosed
                .resolve(locale.languageCode);
            runtime.boundPort = null;
            unawaited(runtime.dispose());
            changed = true;
          } else {
            runtime.boundPort = runtime.server!.port;
          }
          break;
        case PortForwardType.reverse:
          if (runtime.remoteForward == null) {
            runtime.status = PortForwardRuntimeStatus.error;
            runtime.lastError = AppStrings
                .values
                .portForwardErrorRemoteListenerClosed
                .resolve(locale.languageCode);
            runtime.boundPort = null;
            unawaited(runtime.dispose());
            changed = true;
          } else {
            runtime.boundPort = runtime.remoteForward!.port;
          }
          break;
      }
    }
    if (changed) {
      notifyState();
    }
    _stopPortForwardHealthMonitorIfIdle();
  }

  void _touchRuntimeActivity(_ActivePortForwardRuntime runtime) {
    runtime.lastActivityAt = DateTime.now();
    notifyState();
  }

  void _watchRuntimeClientDone(
    String entryId,
    _ActivePortForwardRuntime runtime,
    SSHClient client,
  ) {
    final lifecycleToken = runtime.lifecycleToken;
    unawaited(
      client.done.catchError((_) {}).whenComplete(() async {
        final active = _portForwardRuntimeMap()[entryId];
        if (!identical(active, runtime) ||
            runtime.lifecycleToken != lifecycleToken) {
          return;
        }
        if (runtime.status == PortForwardRuntimeStatus.stopped) {
          return;
        }
        runtime.status = PortForwardRuntimeStatus.error;
        runtime.lastError = AppStrings.values.portForwardErrorSshClosed.resolve(
          locale.languageCode,
        );
        runtime.boundPort = null;
        await runtime.dispose();
        notifyState();
      }),
    );
  }

  List<HostEntry> availablePortForwardHosts() {
    return hosts.where((host) => host.isSsh).toList(growable: false);
  }

  List<PortForwardRuntimeView> portForwardViews() {
    final runtimeMap = _portForwardRuntimeMap();
    return portForwards
        .map((entry) {
          final runtime = runtimeMap[entry.id];
          return PortForwardRuntimeView(
            entry: entry,
            status: runtime?.status ?? PortForwardRuntimeStatus.stopped,
            boundPort: runtime?.boundPort,
            lastError: runtime?.lastError,
            diagnosticHint: runtime?.diagnosticHint,
            activeLocalConnections: runtime?.activeLocalSockets.length ?? 0,
            activeTunnelChannels: runtime?.activeChannels.length ?? 0,
            lastActivityAt: runtime?.lastActivityAt,
            startedAt: runtime?.startedAt,
          );
        })
        .toList(growable: false);
  }

  void upsertPortForwardEntry(PortForwardEntry entry) {
    final index = portForwards.indexWhere((it) => it.id == entry.id);
    if (index >= 0) {
      final previous = portForwards[index];
      portForwards[index] = entry;
      final runtime = _portForwardRuntimeMap()[entry.id];
      final running = runtime?.status == PortForwardRuntimeStatus.running;
      final needsRestart =
          previous.type != entry.type ||
          previous.hostId != entry.hostId ||
          previous.localHost != entry.localHost ||
          previous.localPort != entry.localPort ||
          previous.remoteHost != entry.remoteHost ||
          previous.remotePort != entry.remotePort;
      if (running && needsRestart) {
        unawaited(() async {
          await stopPortForward(entry.id);
          await startPortForward(entry.id);
        }());
      }
    } else {
      portForwards.add(entry);
      if (entry.autoStart) {
        unawaited(startPortForward(entry.id));
      }
    }
    scheduleStateSave();
    notifyState();
  }

  Future<void> removePortForwardEntry(String entryId) async {
    await stopPortForward(entryId);
    portForwards.removeWhere((entry) => entry.id == entryId);
    scheduleStateSave();
    notifyState();
  }

  Future<void> restartPortForward(String entryId) async {
    await stopPortForward(entryId);
    await startPortForward(entryId);
  }

  Future<void> startPortForward(String entryId) async {
    PortForwardEntry? entry;
    for (final item in portForwards) {
      if (item.id == entryId) {
        entry = item;
        break;
      }
    }
    if (entry == null) {
      setError('Port forward not found: $entryId');
      return;
    }
    HostEntry? host;
    for (final item in hosts) {
      if (item.id == entry.hostId) {
        host = item;
        break;
      }
    }
    if (host == null || !host.isSsh) {
      setError('Invalid SSH host for port forward: ${entry.hostId}');
      return;
    }
    final sshHost = host;
    final forwardEntry = entry;
    final runtimeMap = _portForwardRuntimeMap();
    final runtime = runtimeMap.putIfAbsent(
      entry.id,
      _ActivePortForwardRuntime.new,
    );
    if (runtime.status == PortForwardRuntimeStatus.running ||
        runtime.status == PortForwardRuntimeStatus.starting) {
      return;
    }
    await runtime.dispose();

    runtime.status = PortForwardRuntimeStatus.starting;
    runtime.lastError = null;
    runtime.diagnosticHint = null;
    runtime.boundPort = null;
    runtime.serverAddress = sshHost.host;
    runtime.type = forwardEntry.type;
    runtime.startedAt = DateTime.now();
    runtime.lastActivityAt = runtime.startedAt;
    runtime.lifecycleToken += 1;
    _ensurePortForwardHealthMonitor();
    notifyState();

    SSHClient? client;
    final auxiliaryClients = <SSHClient>[];
    try {
      client = await connectSshClientForHost(
        sshHost,
        auxiliaryClients: auxiliaryClients,
      );

      runtime.client = client;
      runtime.auxiliaryClients
        ..clear()
        ..addAll(auxiliaryClients);
      _watchRuntimeClientDone(forwardEntry.id, runtime, client);

      switch (forwardEntry.type) {
        case PortForwardType.local:
          await _startLocalPortForward(runtime: runtime, entry: forwardEntry);
        case PortForwardType.reverse:
          await _startReversePortForward(runtime: runtime, entry: forwardEntry);
        case PortForwardType.socks:
          await _startSocksPortForward(runtime: runtime, entry: forwardEntry);
      }

      runtime.status = PortForwardRuntimeStatus.running;
      runtime.lastError = null;
      runtime.lastActivityAt = DateTime.now();
      addStructuredLog(
        category: TerminalLogCategory.session,
        message:
            '[PortForward] started ${_portForwardSummary(forwardEntry, runtime)}',
        notifyListeners: false,
      );
      notifyState();
    } catch (error) {
      runtime.status = PortForwardRuntimeStatus.error;
      runtime.lastError = '$error';
      runtime.boundPort = null;
      runtime.lastActivityAt = DateTime.now();
      await runtime.dispose();
      setError('Port forward start failed: $error');
      notifyState();
    }
  }

  String _portForwardSummary(
    PortForwardEntry entry,
    _ActivePortForwardRuntime runtime,
  ) {
    final boundPort = runtime.boundPort ?? entry.localPort;
    switch (entry.type) {
      case PortForwardType.local:
        return '[local] ${entry.localHost}:$boundPort -> '
            '${entry.remoteHost}:${entry.remotePort}';
      case PortForwardType.reverse:
        return '[reverse] ${entry.remoteHost}:${runtime.boundPort ?? entry.remotePort} -> '
            '${entry.localHost}:${entry.localPort}';
      case PortForwardType.socks:
        return '[socks] ${entry.localHost}:$boundPort';
    }
  }

  Future<void> _startLocalPortForward({
    required _ActivePortForwardRuntime runtime,
    required PortForwardEntry entry,
  }) async {
    final bindHost = _resolveLocalBindHost(entry.localHost);
    final server = await ServerSocket.bind(bindHost, entry.localPort);
    runtime.server = server;
    runtime.boundPort = server.port;
    runtime.serverSubscription = server.listen(
      (localSocket) {
        _touchRuntimeActivity(runtime);
        unawaited(
          _bridgePortForwardSocket(
            runtime: runtime,
            localSocket: localSocket,
            entry: entry,
          ),
        );
      },
      onError: (error) {
        runtime.status = PortForwardRuntimeStatus.error;
        runtime.lastError = '$error';
        runtime.boundPort = null;
        runtime.lastActivityAt = DateTime.now();
        unawaited(runtime.dispose());
        notifyState();
      },
      onDone: () {
        if (runtime.status == PortForwardRuntimeStatus.stopped) {
          return;
        }
        runtime.status = PortForwardRuntimeStatus.error;
        runtime.lastError = AppStrings
            .values
            .portForwardErrorLocalListenerClosed
            .resolve(locale.languageCode);
        runtime.boundPort = null;
        runtime.lastActivityAt = DateTime.now();
        unawaited(runtime.dispose());
        notifyState();
      },
    );
  }

  Future<void> _startReversePortForward({
    required _ActivePortForwardRuntime runtime,
    required PortForwardEntry entry,
  }) async {
    final client = runtime.client;
    if (client == null) {
      throw StateError('SSH client not available');
    }
    final remoteBindHost = entry.remoteHost.trim().isEmpty
        ? '127.0.0.1'
        : entry.remoteHost.trim();
    final remoteForward = await client.forwardRemote(
      host: remoteBindHost,
      port: entry.remotePort <= 0 ? null : entry.remotePort,
    );
    if (remoteForward == null) {
      throw StateError('remote forward request rejected');
    }
    runtime.remoteForward = remoteForward;
    runtime.boundPort = remoteForward.port;
    runtime.remoteForwardSubscription = remoteForward.connections.listen(
      (incoming) {
        _touchRuntimeActivity(runtime);
        unawaited(
          _bridgeReverseForwardChannel(
            runtime: runtime,
            incoming: incoming,
            localTargetHost: entry.localHost,
            localTargetPort: entry.localPort,
          ),
        );
      },
      onError: (error) {
        runtime.status = PortForwardRuntimeStatus.error;
        runtime.lastError = '$error';
        runtime.boundPort = null;
        runtime.lastActivityAt = DateTime.now();
        unawaited(runtime.dispose());
        notifyState();
      },
      onDone: () {
        if (runtime.status == PortForwardRuntimeStatus.stopped) {
          return;
        }
        runtime.status = PortForwardRuntimeStatus.error;
        runtime.lastError = AppStrings
            .values
            .portForwardErrorRemoteListenerClosed
            .resolve(locale.languageCode);
        runtime.boundPort = null;
        runtime.lastActivityAt = DateTime.now();
        unawaited(runtime.dispose());
        notifyState();
      },
    );
  }

  Future<void> _startSocksPortForward({
    required _ActivePortForwardRuntime runtime,
    required PortForwardEntry entry,
  }) async {
    final client = runtime.client;
    if (client == null) {
      throw StateError('SSH client not available');
    }
    final bindHost = _resolveLocalBindHost(entry.localHost);
    final server = await ServerSocket.bind(bindHost, entry.localPort);
    runtime.server = server;
    runtime.boundPort = server.port;
    runtime.serverSubscription = server.listen(
      (localSocket) {
        _touchRuntimeActivity(runtime);
        unawaited(
          _handleDynamicSocksClient(
            runtime: runtime,
            localSocket: localSocket,
            client: client,
          ),
        );
      },
      onError: (error) {
        runtime.status = PortForwardRuntimeStatus.error;
        runtime.lastError = '$error';
        runtime.boundPort = null;
        runtime.lastActivityAt = DateTime.now();
        unawaited(runtime.dispose());
        notifyState();
      },
      onDone: () {
        if (runtime.status == PortForwardRuntimeStatus.stopped) {
          return;
        }
        runtime.status = PortForwardRuntimeStatus.error;
        runtime.lastError = AppStrings
            .values
            .portForwardErrorSocksListenerClosed
            .resolve(locale.languageCode);
        runtime.boundPort = null;
        runtime.lastActivityAt = DateTime.now();
        unawaited(runtime.dispose());
        notifyState();
      },
    );
  }

  String _resolveLocalBindHost(String rawHost) {
    final host = rawHost.trim();
    if (host.isEmpty) {
      return '127.0.0.1';
    }
    if (host == '*') {
      return '0.0.0.0';
    }
    if (host == '[::]') {
      return '::';
    }
    return host;
  }

  Future<void> _bridgePortForwardSocket({
    required _ActivePortForwardRuntime runtime,
    required Socket localSocket,
    required PortForwardEntry entry,
  }) async {
    final client = runtime.client;
    if (client == null) {
      localSocket.destroy();
      return;
    }
    SSHForwardChannel? remote;
    StreamSubscription<List<int>>? localSub;
    StreamSubscription<List<int>>? remoteSub;
    runtime.activeLocalSockets.add(localSocket);
    _touchRuntimeActivity(runtime);
    try {
      remote = await client.forwardLocal(
        entry.remoteHost,
        entry.remotePort,
        localHost: localSocket.address.address,
        localPort: localSocket.port,
      );
      runtime.activeChannels.add(remote);
      _touchRuntimeActivity(runtime);
      localSub = localSocket.listen(
        (data) => remote?.sink.add(data),
        onDone: () {
          unawaited(remote?.sink.close());
        },
        onError: (_) {
          remote?.destroy();
        },
      );
      remoteSub = remote.stream.listen(
        localSocket.add,
        onDone: () => localSocket.destroy(),
        onError: (_) => localSocket.destroy(),
      );
      await remote.done;
    } catch (error) {
      runtime.lastError = '$error';
      runtime.lastActivityAt = DateTime.now();
      notifyState();
    } finally {
      await localSub?.cancel();
      await remoteSub?.cancel();
      runtime.activeLocalSockets.remove(localSocket);
      localSocket.destroy();
      runtime.activeChannels.remove(remote);
      _touchRuntimeActivity(runtime);
      try {
        await remote?.close();
      } catch (_) {}
    }
  }

  Future<void> _bridgeReverseForwardChannel({
    required _ActivePortForwardRuntime runtime,
    required SSHForwardChannel incoming,
    required String localTargetHost,
    required int localTargetPort,
  }) async {
    Socket? localSocket;
    StreamSubscription<List<int>>? localSub;
    StreamSubscription<List<int>>? remoteSub;
    runtime.activeChannels.add(incoming);
    _touchRuntimeActivity(runtime);
    try {
      final host = localTargetHost.trim().isEmpty
          ? '127.0.0.1'
          : localTargetHost.trim();
      localSocket = await Socket.connect(host, localTargetPort);
      runtime.activeLocalSockets.add(localSocket);
      _touchRuntimeActivity(runtime);
      localSub = localSocket.listen(
        incoming.sink.add,
        onDone: () => unawaited(incoming.sink.close()),
        onError: (_) => incoming.destroy(),
      );
      remoteSub = incoming.stream.listen(
        localSocket.add,
        onDone: () => localSocket?.destroy(),
        onError: (_) => localSocket?.destroy(),
      );
      await incoming.done;
    } catch (error) {
      runtime.lastError = '$error';
      runtime.lastActivityAt = DateTime.now();
      notifyState();
    } finally {
      await localSub?.cancel();
      await remoteSub?.cancel();
      if (localSocket != null) {
        runtime.activeLocalSockets.remove(localSocket);
        localSocket.destroy();
      }
      runtime.activeChannels.remove(incoming);
      _touchRuntimeActivity(runtime);
      try {
        await incoming.close();
      } catch (_) {}
    }
  }

  Future<void> _handleDynamicSocksClient({
    required _ActivePortForwardRuntime runtime,
    required Socket localSocket,
    required SSHClient client,
  }) async {
    final iterator = StreamIterator<List<int>>(localSocket);
    final reader = _SocketChunkReader(iterator);
    SSHForwardChannel? remote;
    StreamSubscription<List<int>>? remoteToLocalSub;
    runtime.activeLocalSockets.add(localSocket);
    _touchRuntimeActivity(runtime);
    try {
      final hello = await reader.readExact(2);
      if (hello[0] != 0x05) {
        return;
      }
      final methodCount = hello[1];
      final methods = await reader.readExact(methodCount);
      final supportsNoAuth = methods.contains(0x00);
      localSocket.add(<int>[0x05, supportsNoAuth ? 0x00 : 0xFF]);
      if (!supportsNoAuth) {
        return;
      }

      final requestHead = await reader.readExact(4);
      if (requestHead[0] != 0x05) {
        return;
      }
      final cmd = requestHead[1];
      final atyp = requestHead[3];
      if (cmd != 0x01) {
        _sendSocksReply(localSocket, 0x07);
        return;
      }

      final destinationHost = await _readSocksDestinationHost(reader, atyp);
      final portBytes = await reader.readExact(2);
      final destinationPort = (portBytes[0] << 8) | portBytes[1];
      if (destinationHost.isEmpty || destinationPort <= 0) {
        _sendSocksReply(localSocket, 0x08);
        return;
      }

      remote = await client.forwardLocal(
        destinationHost,
        destinationPort,
        localHost: localSocket.address.address,
        localPort: localSocket.port,
      );
      runtime.activeChannels.add(remote);
      _touchRuntimeActivity(runtime);
      _sendSocksReply(localSocket, 0x00);

      remoteToLocalSub = remote.stream.listen(
        localSocket.add,
        onDone: () => localSocket.destroy(),
        onError: (_) => localSocket.destroy(),
      );
      await reader.pumpToSink(remote.sink);
      await remote.sink.close();
      await remote.done;
    } catch (error) {
      runtime.lastError = '$error';
      runtime.lastActivityAt = DateTime.now();
      notifyState();
      if (remote == null) {
        _sendSocksReply(localSocket, 0x01);
      }
    } finally {
      await remoteToLocalSub?.cancel();
      runtime.activeChannels.remove(remote);
      runtime.activeLocalSockets.remove(localSocket);
      _touchRuntimeActivity(runtime);
      try {
        await remote?.close();
      } catch (_) {}
      await reader.cancel();
      localSocket.destroy();
    }
  }

  Future<String> _readSocksDestinationHost(
    _SocketChunkReader reader,
    int atyp,
  ) async {
    switch (atyp) {
      case 0x01:
        final bytes = await reader.readExact(4);
        return '${bytes[0]}.${bytes[1]}.${bytes[2]}.${bytes[3]}';
      case 0x03:
        final length = await reader.readExact(1);
        final host = await reader.readExact(length[0]);
        return utf8.decode(host, allowMalformed: true).trim();
      case 0x04:
        final bytes = await reader.readExact(16);
        return InternetAddress.fromRawAddress(
          Uint8List.fromList(bytes),
        ).address;
      default:
        return '';
    }
  }

  void _sendSocksReply(Socket socket, int replyCode) {
    socket.add(<int>[0x05, replyCode, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
  }

  Future<void> stopPortForward(String entryId) async {
    final runtimeMap = _portForwardRuntimeMap();
    final runtime = runtimeMap.remove(entryId);
    if (runtime == null) {
      _stopPortForwardHealthMonitorIfIdle();
      return;
    }
    final wasRunning = runtime.status == PortForwardRuntimeStatus.running;
    runtime.status = PortForwardRuntimeStatus.stopped;
    runtime.boundPort = null;
    runtime.lifecycleToken += 1;
    runtime.lastActivityAt = DateTime.now();
    await runtime.dispose();
    if (wasRunning) {
      addStructuredLog(
        category: TerminalLogCategory.session,
        message: '[PortForward] stopped $entryId',
        notifyListeners: false,
      );
    }
    _stopPortForwardHealthMonitorIfIdle();
    notifyState();
  }

  Future<void> startAllPortForwards() async {
    for (final entry in portForwards) {
      await startPortForward(entry.id);
    }
  }

  Future<void> stopAllPortForwards() async {
    final ids = _portForwardRuntimeMap().keys.toList(growable: false);
    for (final id in ids) {
      await stopPortForward(id);
    }
  }

  Future<void> stopPortForwardsByHost(String hostId) async {
    final host = hostId.trim();
    if (host.isEmpty) {
      return;
    }
    final ids = portForwards
        .where((item) => item.hostId == host)
        .map((item) => item.id)
        .toList(growable: false);
    for (final id in ids) {
      await stopPortForward(id);
    }
  }

  Future<String?> testReverseForwardConnectivity(String entryId) async {
    final runtimeMap = _portForwardRuntimeMap();
    final runtime = runtimeMap[entryId];
    if (runtime == null ||
        runtime.type != PortForwardType.reverse ||
        runtime.status != PortForwardRuntimeStatus.running) {
      return AppStrings.values.portForwardErrorSshClosed
          .resolve(locale.languageCode);
    }
    final client = runtime.client;
    final remoteForward = runtime.remoteForward;
    if (client == null || client.isClosed || remoteForward == null) {
      return AppStrings.values.portForwardErrorSshClosed
          .resolve(locale.languageCode);
    }
    final serverAddr = runtime.serverAddress;
    if (serverAddr == null || serverAddr.trim().isEmpty) {
      return AppStrings.values.portForwardConnectivityTestSkipped
          .resolve(locale.languageCode);
    }
    final port = remoteForward.port;
    if (port <= 0) {
      return 'invalid bound port: $port';
    }
    try {
      final channel = await client.forwardLocal(serverAddr, port);
      await channel.close();
      runtime.diagnosticHint = null;
      notifyState();
      return null;
    } catch (_) {
      runtime.diagnosticHint = AppStrings
          .values
          .portForwardConnectivityTestFailed
          .resolve(locale.languageCode);
      notifyState();
      return AppStrings.values.portForwardConnectivityTestFailed
          .resolve(locale.languageCode);
    }
  }

  Future<String?> enableGatewayPorts(String entryId) async {
    final runtimeMap = _portForwardRuntimeMap();
    final runtime = runtimeMap[entryId];
    if (runtime == null ||
        runtime.type != PortForwardType.reverse ||
        runtime.status != PortForwardRuntimeStatus.running) {
      return AppStrings.values.portForwardErrorSshClosed
          .resolve(locale.languageCode);
    }
    final client = runtime.client;
    if (client == null || client.isClosed) {
      return AppStrings.values.portForwardErrorSshClosed
          .resolve(locale.languageCode);
    }
    final localeCode = locale.languageCode;
    const timeout_ = Duration(seconds: 10);

    try {
      var session = await client.execute(
        r"if grep -qs '^GatewayPorts.*clientspecified' /etc/ssh/sshd_config; then "
        r'  echo "ALREADY_SET"; '
        r'else '
        r"  sudo sed -i -E 's/^[#[:space:]]*GatewayPorts.*/GatewayPorts clientspecified/' /etc/ssh/sshd_config; "
        r"  if grep -qs '^GatewayPorts' /etc/ssh/sshd_config; then "
        r'    true; '
        r'  else '
        r"    echo 'GatewayPorts clientspecified' | sudo tee -a /etc/ssh/sshd_config > /dev/null; "
        r'  fi && '
        r'  (nohup sh -c "sleep 2 && sudo reboot" > /dev/null 2>&1 &) && '
        r'  echo "SUCCESS" || echo "FAILED"; '
        r'fi',
      ).timeout(timeout_);
      var output = await session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(timeout_);
      await session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(timeout_);
      output = output.trim();
      if (output == 'ALREADY_SET') {
        runtime.diagnosticHint = null;
        notifyState();
        return AppStrings.values.portForwardGatewayPortsAlreadyEnabled
            .resolve(localeCode);
      }
      if (output == 'SUCCESS') {
        runtime.diagnosticHint = null;
        notifyState();
        return AppStrings.values.portForwardGatewayPortsSuccess
            .resolve(localeCode);
      }
      if (output == 'FAILED') {
        return AppStrings.values.portForwardGatewayPortsFailedSudo
            .resolve(localeCode);
      }
      return AppStrings.values.portForwardGatewayPortsFailedSudo
          .resolve(localeCode);
    } on TimeoutException {
      return AppStrings.values.portForwardGatewayPortsFailedTimeout
          .resolve(localeCode);
    } catch (_) {
      return AppStrings.values.portForwardGatewayPortsFailedSudo
          .resolve(localeCode);
    }
  }

  void startAutoPortForwards() {
    _ensurePortForwardHealthMonitor();
    for (final entry in portForwards.where((item) => item.autoStart)) {
      unawaited(startPortForward(entry.id));
    }
  }

  void disposePortForwardRuntime() {
    _portForwardHealthTimerByState[this]?.cancel();
    final runtimeMap = _portForwardRuntimeMap();
    for (final runtime in runtimeMap.values) {
      runtime.status = PortForwardRuntimeStatus.stopped;
      runtime.lifecycleToken += 1;
      runtime.boundPort = null;
      unawaited(runtime.dispose());
    }
    runtimeMap.clear();
  }
}


