import 'package:flutter_test/flutter_test.dart';

import 'package:asmote/features/terminal/models/host_entry.dart';
import 'package:asmote/features/terminal/models/port_forward_entry.dart';
import 'package:asmote/features/terminal/models/terminal_session.dart';
import 'package:asmote/features/terminal/models/terminal_tab.dart';
import 'package:asmote/features/terminal/state/terminal_app_state.dart';

Future<TerminalAppState> _newCleanState() async {
  final state = TerminalAppState();
  state.suspendStateSave = true;
  await Future<void>.delayed(const Duration(milliseconds: 220));
  state.hosts.clear();
  state.sessions.clear();
  state.portForwards.clear();
  state.scripts.clear();
  state.scriptSchedules.clear();
  state.scriptRunHistory.clear();
  state.commandHistoryByHost.clear();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connection lifecycle: failed ssh connect then close session', () async {
    final appState = await _newCleanState();
    addTearDown(appState.dispose);

    final host = HostEntry(
      id: 'host-fail',
      name: 'unreachable',
      host: '127.0.0.1',
      port: 1,
      username: 'root',
      group: '',
      authType: AuthType.password,
      password: 'x',
    );

    await appState.connectToHost(host, remember: false);
    expect(appState.sessions, isNotEmpty);
    expect(
      appState.sessions.last.tab.status,
      TerminalStatus.disconnected,
    );

    final sessionId = appState.sessions.last.id;
    await appState.closeSession(sessionId);
    expect(appState.sessions.where((item) => item.id == sessionId), isEmpty);
  });

  test('sftp lifecycle: local session can initialize file tree', () async {
    final appState = await _newCleanState();
    addTearDown(appState.dispose);

    final localHost = HostEntry(
      id: 'local-host',
      name: 'local',
      host: 'local',
      port: 0,
      username: 'local',
      group: '',
      authType: AuthType.password,
      connectionType: ConnectionType.local,
    );
    final session = TerminalSession(
      id: 'sess-local',
      profile: localHost,
      tab: const TerminalTab(
        id: 'sess-local',
        title: 'local',
        status: TerminalStatus.connected,
      ),
      fileState: SessionFileState(rootPath: '/'),
      transferQueue: const [],
    );
    appState.sessions.add(session);

    await appState.ensureSftpReady(session);

    expect(session.fileState.currentPath, isNotEmpty);
    expect(session.fileState.directories.keys, isNotEmpty);
  });

  test('port-forward lifecycle: start error then stop', () async {
    final appState = await _newCleanState();
    addTearDown(appState.dispose);

    final host = HostEntry(
      id: 'ssh-host',
      name: 'ssh-unreachable',
      host: '127.0.0.1',
      port: 1,
      username: 'root',
      group: '',
      authType: AuthType.password,
      password: 'x',
    );
    appState.addHost(host);
    final entry = PortForwardEntry(
      id: 'pf-test',
      name: 'pf',
      hostId: host.id,
      localHost: '127.0.0.1',
      localPort: 0,
      remoteHost: '127.0.0.1',
      remotePort: 22,
      createdAt: DateTime.now(),
    );
    appState.upsertPortForwardEntry(entry);

    await appState.startPortForward(entry.id);
    final afterStart = appState.portForwardViews().firstWhere(
      (item) => item.entry.id == entry.id,
    );
    expect(afterStart.status, PortForwardRuntimeStatus.error);

    await appState.stopPortForward(entry.id);
    final afterStop = appState.portForwardViews().firstWhere(
      (item) => item.entry.id == entry.id,
    );
    expect(afterStop.status, PortForwardRuntimeStatus.stopped);
  });
}
