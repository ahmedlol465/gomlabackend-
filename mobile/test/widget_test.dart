import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App shells render', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('بابا عبدو'))),
    ));
    expect(find.text('بابا عبدو'), findsOneWidget);
  });
}