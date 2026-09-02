import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter widget test harness renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('CareLink')));

    expect(find.text('CareLink'), findsOneWidget);
  });
}
