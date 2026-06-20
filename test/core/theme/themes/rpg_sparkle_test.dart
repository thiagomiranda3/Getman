import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/rpg/rpg_sparkle.dart';

void main() {
  // The sparkle burst rides on a raw pointer-down (a Listener), not on the
  // outer tap recognizer. The regression: when it rode on
  // GestureDetector.onTapDown, a quick tap on a child that itself consumes the
  // tap (an IconButton, an inner GestureDetector, …) let the inner recognizer
  // win the gesture arena before the outer's deferred onTapDown deadline — so
  // onTapDown never fired and the sparkle was silently dropped. It only showed
  // on slow/held presses.
  Finder sparkleLayers() => find.descendant(
    of: find.byType(RpgSparkle),
    matching: find.byType(CustomPaint),
  );

  testWidgets(
    'a quick tap emits a sparkle even when an inner consumer wins the arena',
    (tester) async {
      var innerTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RpgSparkle(
                // An opaque inner consumer (like an IconButton's InkResponse):
                // it is hit-tested and wins the tap arena on a quick tap.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => innerTaps++,
                  child: const SizedBox(width: 80, height: 40),
                ),
              ),
            ),
          ),
        ),
      );

      // Nothing sparkling before interaction.
      expect(sparkleLayers(), findsNothing);

      // tester.tap is a *quick* down+up — the inner GestureDetector wins the
      // tap arena, yet the sparkle must still fire.
      await tester.tap(find.byType(RpgSparkle));
      await tester.pump();

      expect(innerTaps, 1);
      expect(sparkleLayers(), findsWidgets);

      // Let the 650ms burst finish so its controller disposes cleanly.
      await tester.pumpAndSettle();
    },
  );

  testWidgets('no sparkle burst is emitted when sparkle is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RpgSparkle(
              sparkle: false,
              onTap: () {},
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(RpgSparkle));
    await tester.pump();

    expect(sparkleLayers(), findsNothing);
  });
}
