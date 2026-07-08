import 'package:flutter_test/flutter_test.dart';

import 'package:Polarmote/events/event_bus.dart';
import 'package:Polarmote/features/terminal/models/host_entry.dart';
import 'package:Polarmote/features/terminal/state/terminal_app_state.dart';
import 'package:Polarmote/providers/host_book_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostBookProvider', () {
    late TerminalAppState appState;
    late EventBus eventBus;
    late HostBookProvider provider;

    setUp(() async {
      eventBus = EventBus();
      appState = TerminalAppState();
      appState.suspendStateSave = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider = HostBookProvider(appState: appState, eventBus: eventBus);
    });

    tearDown(() async {
      provider.dispose();
      eventBus.dispose();
      appState.suspendStateSave = true;
      appState.dispose();
    });

    test('starts with empty hosts', () {
      expect(provider.hosts, isEmpty);
      expect(provider.visibleHosts, isEmpty);
    });

    test('reflects host additions', () {
      final host = HostEntry(
        id: 'host-1', name: 'Server 1', host: '192.168.1.1',
        port: 22, username: 'admin', group: '', authType: AuthType.password,
      );
      provider.add(host);

      expect(provider.hosts.length, 1);
      expect(provider.visibleHosts.length, 1);
      expect(provider.hosts.first.id, 'host-1');
    });

    test('reflects host removal', () {
      final host = HostEntry(
        id: 'host-1', name: 'Server 1', host: '192.168.1.1',
        port: 22, username: 'admin', group: '', authType: AuthType.password,
      );
      provider.add(host);
      expect(provider.hosts.length, 1);

      provider.remove('host-1');
      expect(provider.hosts, isEmpty);
    });

    test('notifies listeners on HostListChangedEvent', () async {
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      eventBus.fire(HostListChangedEvent());
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
    });
  });
}
