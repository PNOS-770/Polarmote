import 'package:flutter_test/flutter_test.dart';
import 'package:Polarmote/events/event_bus.dart';
import 'package:Polarmote/features/terminal/state/terminal_app_state.dart';
import 'package:Polarmote/providers/transfer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransferProvider', () {
    late TerminalAppState appState;
    late EventBus eventBus;
    late TransferProvider provider;

    setUp(() async {
      eventBus = EventBus();
      appState = TerminalAppState();
      appState.suspendStateSave = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider = TransferProvider(appState: appState, eventBus: eventBus);
    });

    tearDown(() async {
      provider.dispose();
      eventBus.dispose();
      appState.suspendStateSave = true;
      appState.dispose();
    });

    test('starts with no active transfers', () {
      expect(provider.hasActiveTransfers, isFalse);
      expect(provider.totalActiveJobs, 0);
    });

    test('notifies on transfer completed', () async {
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      eventBus.fire(TransferCompletedEvent(sessionId: 's1', taskId: 't1'));
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
    });

    test('notifies on transfer error', () async {
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      eventBus.fire(TransferErrorEvent(sessionId: 's1', taskId: 't1', error: 'err'));
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
    });
  });
}
