import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asmote/app/asmote_app.dart';

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const AsmoteAppBootstrap());

    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('Asmote'), findsWidgets);
  });
}
