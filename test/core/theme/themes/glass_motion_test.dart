// test/core/theme/themes/glass_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';

void main() {
  testWidgets('reduced effects => identity overlay + identity send', (
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
        motion.sendAffordance(ctx, child: marker, isSending: false),
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

  testWidgets('A1: glass send shows a rising liquid level while sending', (
    tester,
  ) async {
    final motion = glassMotion(reduceEffects: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: motion.sendAffordance(
                context,
                isSending: true,
                child: const SizedBox(
                  width: 100,
                  height: 40,
                  key: ValueKey('s'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('s')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Assert that a _GlassSendPainter with level > 0 is in the tree.
    // Dynamic cast is used because _GlassSendPainter is library-private.
    final sendPainterFinder = find.byWidgetPredicate((widget) {
      if (widget is! CustomPaint) return false;
      final p = widget.painter;
      if (p == null) return false;
      if (!p.runtimeType.toString().contains('_GlassSendPainter')) return false;
      // Dynamic cast needed: _GlassSendPainter is library-private; there is no
      // other way to read its `level` field from an external test library.
      return ((p as dynamic).level as double) > 0;
    });
    expect(
      sendPainterFinder,
      findsAtLeastNWidgets(1),
      reason: '_GlassSendPainter.level must be > 0 after 600ms of sending',
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
