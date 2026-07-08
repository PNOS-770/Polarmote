import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Polarmote/features/terminal/presentation/dialogs/terminal_dialogs.dart';
import 'package:Polarmote/features/terminal/state/terminal_app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings panel does not overflow on narrow width and long text', (
    WidgetTester tester,
  ) async {
    final appState = TerminalAppState();
    appState.suspendStateSave = true;
    addTearDown(appState.dispose);

    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    appState.portableStateSnapshots
      ..clear()
      ..addAll([
        PortableStateSnapshot(
          id: 'snapshot-a',
          createdAt: DateTime.now(),
          label:
              'snapshot-with-a-very-very-very-very-long-name-for-overflow-regression-check',
          path: '/tmp/snapshot-a.json',
        ),
      ]);
    appState.setLocale(const Locale('zh'));

    await tester.pumpWidget(
      ChangeNotifierProvider<TerminalAppState>.value(
        value: appState,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 720,
              child: TerminalSettingsPanel(appState: appState, embedded: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    appState.setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
