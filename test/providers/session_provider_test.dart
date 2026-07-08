import 'package:flutter_test/flutter_test.dart';
import 'package:Polarmote/events/event_bus.dart';
import 'package:Polarmote/features/terminal/state/terminal_app_state.dart';
import 'package:Polarmote/providers/session_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionProvider', () {
    late TerminalAppState appState;
    late EventBus eventBus;
    late SessionProvider provider;

    setUp(() async {
      eventBus = EventBus();
      appState = TerminalAppState();
      appState.suspendStateSave = true;
      // Allow async constructor work to settle
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider = SessionProvider(appState: appState, eventBus: eventBus);
    });

    tearDown(() async {
      provider.dispose();
      eventBus.dispose();
      // Cancel pending async work before dispose
      appState.suspendStateSave = true;
      appState.dispose();
    });

    test('starts with empty sessions', () {
      expect(provider.sessions, isEmpty);
      expect(provider.activeSession, isNull);
      expect(provider.hasActiveSession, isFalse);
    });

    test('notifies listeners when session connects', () async {
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      eventBus.fire(SessionConnectedEvent(sessionId: 'test-session'));
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
    });
  });
}
