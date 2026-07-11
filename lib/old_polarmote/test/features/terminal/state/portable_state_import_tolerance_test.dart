import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:asmote/features/terminal/state/terminal_app_state.dart';

Future<TerminalAppState> _newCleanState() async {
  final state = TerminalAppState();
  state.suspendStateSave = true;
  await Future<void>.delayed(const Duration(milliseconds: 220));
  state.hosts.clear();
  state.scripts.clear();
  state.scriptSchedules.clear();
  state.scriptRunHistory.clear();
  state.portForwards.clear();
  state.commandHistoryByHost.clear();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('import tolerates partial/corrupted sections and keeps valid entries', () async {
    final appState = await _newCleanState();
    addTearDown(appState.dispose);

    final tempDir = await Directory.systemTemp.createTemp(
      'asmote-import-tolerance',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final importFile = File('${tempDir.path}/config.json');
    await importFile.writeAsString('''
{
  "settings": {
    "showHiddenFiles": false,
    "scriptRunHistoryLimit": "bad-value"
  },
  "hosts": [
    {
      "id": "host-1",
      "name": "host-a",
      "host": "127.0.0.1",
      "port": 22,
      "username": "root",
      "group": "",
      "authType": "password"
    },
    "invalid-host-item"
  ],
  "scripts": [
    {
      "id": "script-1",
      "name": "demo",
      "commands": ["echo hello"]
    },
    {"id": "", "name": "", "commands": []}
  ],
  "scriptSchedules": [
    {
      "id": "sched-1",
      "scriptId": "script-1",
      "cronExpression": "*/5 * * * *",
      "enabled": true
    },
    "bad-schedule"
  ],
  "scriptRunHistory": [
    {
      "id": "run-1",
      "runId": "rid-1",
      "scriptId": "script-1",
      "scriptName": "demo",
      "hostId": "host-1",
      "hostName": "host-a",
      "success": true,
      "detail": "ok"
    }
  ]
}
''');

    await appState.importPortableStateFromPath(importFile.path);

    expect(appState.hosts.any((item) => item.id == 'host-1'), isTrue);
    expect(appState.scripts.any((item) => item.id == 'script-1'), isTrue);
    expect(
      appState.scriptSchedules.any((item) => item.scriptId == 'script-1'),
      isTrue,
    );
    expect(
      appState.scriptRunHistory.any((item) => item.scriptId == 'script-1'),
      isTrue,
    );
  });

  test('import malformed json reports invalid import json', () async {
    final appState = await _newCleanState();
    addTearDown(appState.dispose);

    final tempDir = await Directory.systemTemp.createTemp(
      'asmote-import-malformed',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final importFile = File('${tempDir.path}/broken.json');
    await importFile.writeAsString('{ this-is-not-json');

    expect(
      () => appState.importPortableStateFromPath(importFile.path),
      throwsA(isA<StateError>()),
    );
  });
}
