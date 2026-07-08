import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Polarmote/app/Polarmote_app.dart';

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PolarmoteAppBootstrap());

    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('Polarmote'), findsWidgets);
  });
}
