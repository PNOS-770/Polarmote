import 'package:asmote/features/terminal/models/host_entry.dart';
import 'package:asmote/features/terminal/models/terminal_session.dart';
import 'package:asmote/features/terminal/models/terminal_tab.dart';
import 'package:asmote/features/terminal/models/transfer_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TerminalSession buildSession() {
    return TerminalSession(
      id: 'session-1',
      profile: const HostEntry(
        id: 'host-1',
        name: 'Host',
        host: '127.0.0.1',
        port: 22,
        username: 'tester',
        group: '',
        authType: AuthType.password,
      ),
      tab: const TerminalTab(
        id: 'tab-1',
        title: 'Host',
        status: TerminalStatus.connected,
      ),
      fileState: SessionFileState(rootPath: '/'),
      transferQueue: const [],
    );
  }

  test('pausedTransferDirections toggles by direction independently', () {
    final session = buildSession();
    addTearDown(session.dispose);

    expect(session.pausedTransferDirections, isEmpty);

    session.pausedTransferDirections.add(TransferDirection.upload);
    expect(
      session.pausedTransferDirections.contains(TransferDirection.upload),
      isTrue,
    );
    expect(
      session.pausedTransferDirections.contains(TransferDirection.download),
      isFalse,
    );

    session.pausedTransferDirections.add(TransferDirection.download);
    expect(session.pausedTransferDirections.length, 2);

    session.pausedTransferDirections.remove(TransferDirection.upload);
    expect(
      session.pausedTransferDirections.contains(TransferDirection.upload),
      isFalse,
    );
    expect(
      session.pausedTransferDirections.contains(TransferDirection.download),
      isTrue,
    );
  });

  test('pausedTransferTaskIds tracks single-task pause state', () {
    final session = buildSession();
    addTearDown(session.dispose);

    expect(session.pausedTransferTaskIds, isEmpty);

    session.pausedTransferTaskIds.add('task-1');
    expect(session.pausedTransferTaskIds.contains('task-1'), isTrue);
    expect(session.pausedTransferTaskIds.contains('task-2'), isFalse);

    session.pausedTransferTaskIds.add('task-2');
    expect(session.pausedTransferTaskIds.length, 2);

    session.pausedTransferTaskIds.remove('task-1');
    expect(session.pausedTransferTaskIds.contains('task-1'), isFalse);
    expect(session.pausedTransferTaskIds.contains('task-2'), isTrue);
  });
}
