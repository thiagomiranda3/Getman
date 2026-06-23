// test/core/theme/themes/glass_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';

void main() {
  testWidgets('reduced effects => identity overlay', (
    tester,
  ) async {
    final motion = glassMotion(reduceEffects: true);
    final controller = ThemeReactionController();
    const marker = SizedBox(key: ValueKey('m'));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      identical(
        motion.contentTransition(ctx, child: marker, transitionKey: 'x'),
        marker,
      ),
      isTrue,
    );
    controller.dispose();
  });

  testWidgets('full effects: overlay renders child and survives a reaction', (
    tester,
  ) async {
    final motion = glassMotion(reduceEffects: false);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('app'),
      findsOneWidget,
    ); // overlay didn't tear down content
    controller.fire(
      const ThemeReaction(kind: ThemeReactionKind.serverError, statusCode: 500),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1)); // let controllers finish
    controller.dispose();
  });

  testWidgets('A1: slow vs fast success both resolve cleanly', (tester) async {
    final motion = glassMotion(reduceEffects: false);
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
        kind: ThemeReactionKind.success,
        statusCode: 200,
        durationMs: 2900,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  test('A2: glassSpecFor selects the right effect per flavor', () {
    expect(glassSpecFor(StatusReactionFlavor.created).style, GlassFx.ripple);
    expect(glassSpecFor(StatusReactionFlavor.notModified).style, GlassFx.echo);
    expect(
      glassSpecFor(StatusReactionFlavor.unauthorized).style,
      GlassFx.barrier,
    );
    expect(
      glassSpecFor(StatusReactionFlavor.forbidden).style,
      GlassFx.barrier,
    );
    expect(glassSpecFor(StatusReactionFlavor.notFound).style, GlassFx.shards);
    expect(
      glassSpecFor(StatusReactionFlavor.serviceUnavailable).style,
      GlassFx.flicker,
    );
    expect(
      glassSpecFor(StatusReactionFlavor.serverCrash).style,
      GlassFx.crack,
    );
    expect(
      glassSpecFor(StatusReactionFlavor.badCertificate).style,
      GlassFx.barrier,
    );
  });

  testWidgets('A2: glass overlay survives every mapped status code', (
    tester,
  ) async {
    final motion = glassMotion(reduceEffects: false);
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
}
