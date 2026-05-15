import 'package:bt_signal_meter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots and shows scan button', (tester) async {
    await tester.pumpWidget(const BtSignalApp());
    expect(find.text('BT Signal Meter'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
