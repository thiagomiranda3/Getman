import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/presentation/update_gate_stub.dart';

void main() {
  testWidgets('stub gate renders nothing', (t) async {
    await t.pumpWidget(const MaterialApp(home: UpdateGate()));
    expect(find.byType(SizedBox), findsWidgets);
  });
}
