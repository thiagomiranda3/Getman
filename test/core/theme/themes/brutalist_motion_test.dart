// test/core/theme/themes/brutalist_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('stamp on success shows the status code text', (tester) async {
    final motion = brutalistMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
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
    controller.fire(
      const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('200'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  test('reduced effects => identity', () {
    final motion = brutalistMotion(reduceEffects: true);
    expect(motion.runtimeType.toString(), 'AppMotion');
  });

  testWidgets('A1: send build-up starts and stops via didUpdateWidget', (
    tester,
  ) async {
    final motion = brutalistMotion(reduceEffects: false);
    late StateSetter setOuter;
    var sending = true;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, ss) {
          setOuter = ss;
          return MaterialApp(
            theme: brutalistTheme(Brightness.light),
            home: Scaffold(
              body: Center(
                child: motion.sendAffordance(
                  context,
                  isSending: sending,
                  child: const Text('SEND'),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('SEND'), findsOneWidget);
    // Flip isSending in place — triggers didUpdateWidget stop/reset path.
    setOuter(() => sending = false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('A1: slow success resolves without throwing', (tester) async {
    final motion = brutalistMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
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
        kind: ThemeReactionKind.success,
        statusCode: 200,
        durationMs: 2800, // high latencyWeight
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  test('A2: stampSpecFor encodes the flavor matrix', () {
    expect(stampSpecFor(StatusReactionFlavor.notModified).doubled, isTrue);
    expect(stampSpecFor(StatusReactionFlavor.rateLimited).thuds, 3);
    expect(stampSpecFor(StatusReactionFlavor.timeout).sag, isTrue);
    expect(
      stampSpecFor(StatusReactionFlavor.serviceUnavailable).flicker,
      isTrue,
    );
    expect(stampSpecFor(StatusReactionFlavor.notFound).scatter, isTrue);
    expect(stampSpecFor(StatusReactionFlavor.unauthorized).barrier, isTrue);
    expect(stampSpecFor(StatusReactionFlavor.forbidden).barrier, isTrue);
    expect(stampSpecFor(StatusReactionFlavor.ok).thuds, 1);
    expect(stampSpecFor(StatusReactionFlavor.badCertificate).barrier, isTrue);
  });

  testWidgets('A2: overlay survives every mapped status code', (tester) async {
    final motion = brutalistMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
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
          durationMs: 500,
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('app'), findsOneWidget, reason: 'code=$code');
    }
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}
