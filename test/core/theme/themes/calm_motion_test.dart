import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/shared/calm_motion.dart';

void main() {
  testWidgets('renders child + survives success/error pulses', (tester) async {
    final motion = calmMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: motion.reactionOverlay(
                context,
                controller: controller,
                child: const Text('app'),
              ),
            );
          },
        ),
      ),
    );
    expect(find.text('app'), findsOneWidget);
    controller.fire(
      const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    );
    await tester.pump(const Duration(milliseconds: 100));
    controller.fire(
      const ThemeReaction(
        kind: ThemeReactionKind.clientError,
        statusCode: 404,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    controller.dispose();
  });

  test('A2: calmSpecFor sets blink counts + tints', () {
    const base = Color(0xFF3355FF);
    const error = Color(0xFFFF3333);
    expect(
      calmSpecFor(StatusReactionFlavor.notModified, base, error).blinks,
      2,
    );
    expect(
      calmSpecFor(StatusReactionFlavor.rateLimited, base, error).blinks,
      3,
    );
    expect(
      calmSpecFor(StatusReactionFlavor.rateLimited, base, error).color,
      error,
    );
    expect(
      calmSpecFor(StatusReactionFlavor.unauthorized, base, error).color,
      error,
    );
    expect(calmSpecFor(StatusReactionFlavor.ok, base, error).blinks, 1);
    expect(
      calmSpecFor(StatusReactionFlavor.badCertificate, base, error).color,
      error,
    );
    expect(
      calmSpecFor(StatusReactionFlavor.badCertificate, base, error).blinks,
      2,
    );
  });

  testWidgets('calm overlay survives a bad-certificate reaction', (
    tester,
  ) async {
    final motion = calmMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: motion.reactionOverlay(
              context,
              controller: controller,
              child: const Text('app'),
            ),
          ),
        ),
      ),
    );
    controller.fire(
      const ThemeReaction(
        kind: ThemeReactionKind.networkError,
        transportFailure: TransportFailureKind.badCertificate,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets(
    'A2: calm overlay survives every mapped status code',
    (tester) async {
      final motion = calmMotion(reduceEffects: false);
      final controller = ThemeReactionController();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: motion.reactionOverlay(
                context,
                controller: controller,
                child: const Text('app'),
              ),
            ),
          ),
        ),
      );
      for (final code in [201, 204, 304, 401, 403, 404, 408, 429, 500, 503]) {
        controller.fire(
          ThemeReaction(
            kind: ThemeReaction.kindForStatus(code),
            statusCode: code,
            durationMs: 2500,
          ),
        );
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('app'), findsOneWidget, reason: 'code=$code');
      }
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}
