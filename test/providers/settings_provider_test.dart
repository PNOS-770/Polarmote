import 'package:flutter_test/flutter_test.dart';
import 'package:Polarmote/features/terminal/state/terminal_app_state.dart';
import 'package:Polarmote/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider', () {
    late TerminalAppState appState;
    late SettingsProvider provider;

    setUp(() async {
      appState = TerminalAppState();
      appState.suspendStateSave = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider = SettingsProvider(appState: appState);
    });

    tearDown(() async {
      provider.dispose();
      appState.suspendStateSave = true;
      appState.dispose();
    });

    test('reflects default settings', () {
      expect(provider.autoReconnect, isTrue);
      expect(provider.confirmPaste, isTrue);
      expect(provider.showHiddenFiles, isTrue);
    });

    test('can toggle auto reconnect', () {
      provider.setAutoReconnect(false);
      expect(provider.autoReconnect, isFalse);
    });

    test('can toggle confirm paste', () {
      provider.setConfirmPaste(false);
      expect(provider.confirmPaste, isFalse);
    });
  });
}
