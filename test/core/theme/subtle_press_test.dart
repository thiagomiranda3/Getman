import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/shared/subtle_press.dart';

void main() {
  testWidgets('SubtlePress scales to ~0.99 on press, not a 0.95 bounce', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SubtlePress(
              onTap: () => tapped = true,
              child: const SizedBox(
                width: 50,
                height: 50,
                key: ValueKey('press_child'),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('press_child'))),
    );
    await tester.pump(const Duration(milliseconds: 120));
    final scaleT = tester
        .widget<AnimatedScale>(find.byType(AnimatedScale))
        .scale;
    expect(scaleT, closeTo(0.99, 0.001)); // subtle, NOT 0.95
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('animate:false is a plain tap target (no AnimatedScale)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SubtlePress(
          animate: false,
          child: SizedBox(width: 10, height: 10),
        ),
      ),
    );
    expect(find.byType(AnimatedScale), findsNothing);
  });
}
