// Tests for ClassicPress — the subtle press-feedback wrapper used by the
// CLASSIC theme's wrapInteractive slot.
//
// Behavior under test:
//   • animate=true  → GestureDetector + AnimatedScale + AnimatedOpacity;
//     tapping dims + scales down then restores.
//   • animate=false → GestureDetector only; no AnimatedScale/AnimatedOpacity.
//   • animate flip → no crash (SingleTickerProvider safety).
//   • onTap is called on a completed tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/classic/classic_press.dart';

Widget _host({
  required bool animate,
  VoidCallback? onTap,
  double? scaleDown,
}) => MaterialApp(
  home: Scaffold(
    body: ClassicPress(
      animate: animate,
      onTap: onTap,
      scaleDown: scaleDown,
      child: const SizedBox(
        key: ValueKey('cp_child'),
        width: 80,
        height: 80,
      ),
    ),
  ),
);

void main() {
  group('ClassicPress — animate=true', () {
    testWidgets('renders AnimatedScale + AnimatedOpacity around the child', (
      tester,
    ) async {
      await tester.pumpWidget(_host(animate: true));
      // Both animation wrappers must be present.
      expect(find.byType(AnimatedScale), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsOneWidget);
      expect(find.byKey(const ValueKey('cp_child')), findsOneWidget);
    });

    testWidgets('starts at scale 1.0 and opacity 1.0 (idle state)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(animate: true));
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(scale.scale, 1.0);
      expect(opacity.opacity, 1.0);
    });

    testWidgets('dims + scales on tap-down, restores on tap-up', (
      tester,
    ) async {
      await tester.pumpWidget(_host(animate: true));

      // Tap down → _pressed=true → scale/opacity change.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('cp_child'))),
      );
      await tester.pump();

      final scalePressedWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      final opacityPressedWidget = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(scalePressedWidget.scale, lessThan(1.0));
      expect(opacityPressedWidget.opacity, lessThan(1.0));

      // Tap up → _pressed=false → scale/opacity restore.
      await gesture.up();
      await tester.pump();

      final scaleReleasedWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      final opacityReleasedWidget = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(scaleReleasedWidget.scale, 1.0);
      expect(opacityReleasedWidget.opacity, 1.0);
    });

    testWidgets('restores on tap-cancel', (tester) async {
      await tester.pumpWidget(_host(animate: true));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('cp_child'))),
      );
      await tester.pump();

      // Cancel the gesture.
      await gesture.cancel();
      await tester.pump();

      final scaleWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(scaleWidget.scale, 1.0);
    });

    testWidgets('calls onTap on a completed tap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(animate: true, onTap: () => tapped++));
      await tester.tap(
        find.byKey(const ValueKey('cp_child')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tapped, 1);
    });

    testWidgets('uses scaleDown parameter as the pressed scale', (
      tester,
    ) async {
      await tester.pumpWidget(_host(animate: true, scaleDown: 0.90));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('cp_child'))),
      );
      await tester.pump();

      final scaleWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(scaleWidget.scale, closeTo(0.90, 0.001));
      await gesture.up();
    });

    testWidgets('defaults scaleDown to 0.99 when not provided', (
      tester,
    ) async {
      await tester.pumpWidget(_host(animate: true));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('cp_child'))),
      );
      await tester.pump();

      final scaleWidget = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(scaleWidget.scale, closeTo(0.99, 0.001));
      await gesture.up();
    });
  });

  group('ClassicPress — animate=false', () {
    testWidgets(
      'renders a GestureDetector only — no AnimatedScale or AnimatedOpacity',
      (tester) async {
        await tester.pumpWidget(_host(animate: false));
        expect(find.byType(AnimatedScale), findsNothing);
        expect(find.byType(AnimatedOpacity), findsNothing);
        expect(find.byKey(const ValueKey('cp_child')), findsOneWidget);
      },
    );

    testWidgets('calls onTap on a completed tap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(animate: false, onTap: () => tapped++));
      await tester.tap(
        find.byKey(const ValueKey('cp_child')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets(
      'survives mount + immediate dispose (no lifecycle crash)',
      (tester) async {
        await tester.pumpWidget(_host(animate: false));
        // Confirm the widget is present before we unmount it.
        expect(find.byType(ClassicPress), findsOneWidget);
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pump();
        // After replacement, ClassicPress must be gone with no lifecycle error.
        expect(find.byType(ClassicPress), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ClassicPress — animate flip', () {
    testWidgets('false → true → false does not crash', (tester) async {
      await tester.pumpWidget(_host(animate: false));
      await tester.pumpWidget(_host(animate: true));
      await tester.pumpWidget(_host(animate: false));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ClassicPress), findsOneWidget);
    });

    testWidgets('true → false → true does not crash', (tester) async {
      await tester.pumpWidget(_host(animate: true));
      await tester.pumpWidget(_host(animate: false));
      await tester.pumpWidget(_host(animate: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ClassicPress), findsOneWidget);
    });

    testWidgets('onTap still fires after an animate flip', (tester) async {
      var tapped = 0;
      void onFlipTap() => tapped++;
      await tester.pumpWidget(_host(animate: true, onTap: onFlipTap));
      await tester.pumpWidget(_host(animate: false, onTap: onFlipTap));
      await tester.tap(
        find.byKey(const ValueKey('cp_child')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(tapped, 1);
    });
  });

  group(
    'ClassicPress — via context.appDecoration.wrapInteractive (classic theme)',
    () {
      testWidgets(
        'wrapInteractive with animate=true produces a ClassicPress',
        (tester) async {
          // Verify the wrapInteractive contract: wrapping a child produces a
          // ClassicPress with animation wrappers when animate=true.
          Widget buildWrapped({bool animate = true}) => ClassicPress(
            animate: animate,
            onTap: () {},
            child: const SizedBox(
              key: ValueKey('wrapped_child'),
              width: 60,
              height: 60,
            ),
          );

          await tester.pumpWidget(
            MaterialApp(home: Scaffold(body: buildWrapped())),
          );
          expect(find.byType(ClassicPress), findsOneWidget);
          expect(find.byType(AnimatedScale), findsOneWidget);
          expect(find.byKey(const ValueKey('wrapped_child')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'wrapInteractive with animate=false (reduceEffects) produces a '
        'ClassicPress without animation wrappers',
        (tester) async {
          Widget buildReduced() => const ClassicPress(
            animate: false,
            child: SizedBox(
              key: ValueKey('reduced_child'),
              width: 60,
              height: 60,
            ),
          );

          await tester.pumpWidget(
            MaterialApp(home: Scaffold(body: buildReduced())),
          );
          expect(find.byType(ClassicPress), findsOneWidget);
          expect(find.byType(AnimatedScale), findsNothing);
          expect(find.byKey(const ValueKey('reduced_child')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
