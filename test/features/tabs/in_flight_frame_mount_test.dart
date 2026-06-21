import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

void main() {
  testWidgets('inFlightFrame hook receives isSending and wraps the child', (
    tester,
  ) async {
    bool? sawSending;
    final motion = const AppMotion().copyWith(
      inFlightFrame: (context, {required child, required isSending}) {
        sawSending = isSending;
        return DecoratedBox(
          key: const ValueKey('frame'),
          decoration: const BoxDecoration(),
          child: child,
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => motion.inFlightFrame(
            context,
            isSending: true,
            child: const Text('panes'),
          ),
        ),
      ),
    );
    expect(sawSending, isTrue);
    expect(find.byKey(const ValueKey('frame')), findsOneWidget);
    expect(find.text('panes'), findsOneWidget);
  });
}
