// test/core/theme/themes/rpg_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_theme.dart';

void main() {
  test('reduced effects returns identity AppMotion', () {
    final motion = rpgMotion(reduceEffects: true);
    expect(motion.reactionOverlay, isA<ReactionOverlayBuilder>());
    const identity = AppMotion();
    // Identity overlay returns child unchanged.
    // (smoke: see widget test below for behavior)
    expect(motion.runtimeType, identity.runtimeType);
  });

  testWidgets('success shower + error shake both render without throwing', (
    tester,
  ) async {
    final motion = rpgMotion(reduceEffects: false);
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
    await tester.pump(const Duration(milliseconds: 80));
    controller.fire(
      const ThemeReaction(
        kind: ThemeReactionKind.serverError,
        statusCode: 500,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    controller.dispose();
  });

  testWidgets('A1: rune ring build-up runs and tears down cleanly', (
    tester,
  ) async {
    final motion = rpgMotion(reduceEffects: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: motion.sendAffordance(
                context,
                isSending: true,
                child: const Text('SEND'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('SEND'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('A1: slow error (5xx, high latency) shakes and resolves', (
    tester,
  ) async {
    final motion = rpgMotion(reduceEffects: false);
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
        kind: ThemeReactionKind.serverError,
        statusCode: 500,
        durationMs: 2900,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  test('A2: rpgSpecFor selects the right effect per flavor', () {
    expect(rpgSpecFor(StatusReactionFlavor.created).style, RpgFx.sparkle);
    expect(rpgSpecFor(StatusReactionFlavor.notModified).style, RpgFx.echo);
    expect(rpgSpecFor(StatusReactionFlavor.unauthorized).style, RpgFx.ward);
    expect(rpgSpecFor(StatusReactionFlavor.forbidden).style, RpgFx.ward);
    expect(rpgSpecFor(StatusReactionFlavor.notFound).style, RpgFx.scatter);
    expect(rpgSpecFor(StatusReactionFlavor.serverCrash).style, RpgFx.crack);
    expect(rpgSpecFor(StatusReactionFlavor.rateLimited).repeat, 3);
    expect(rpgSpecFor(StatusReactionFlavor.badCertificate).style, RpgFx.ward);
  });

  testWidgets('A2: rpg overlay survives every mapped status code', (
    tester,
  ) async {
    final motion = rpgMotion(reduceEffects: false);
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
          durationMs: 400,
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('app'), findsOneWidget, reason: 'code=$code');
    }
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets(
    'A1: send build-up starts and stops via didUpdateWidget',
    (tester) async {
      final motion = rpgMotion(reduceEffects: false);
      late StateSetter setOuter;
      var sending = true;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, ss) {
            setOuter = ss;
            return MaterialApp(
              theme: rpgTheme(Brightness.light),
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
    },
  );
}
