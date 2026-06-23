// test/core/theme/themes/auris/auris_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';

void main() {
  test('aurisMotion reduceEffects:true is identity AppMotion', () {
    final m = aurisMotion(reduceEffects: true);
    expect(m, equals(const AppMotion()));
  });

  testWidgets(
    'aurisMotion full: overlay renders child and survives reactions',
    (tester) async {
      final controller = ThemeReactionController();
      final m = aurisMotion(reduceEffects: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: m.reactionOverlay(
                context,
                controller: controller,
                child: const Text('CHILD'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('CHILD'), findsOneWidget);

      // success (2xx)
      controller.fire(
        const ThemeReaction(
          kind: ThemeReactionKind.success,
          statusCode: 200,
          durationMs: 120,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('CHILD'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // serverError (5xx)
      controller.fire(
        const ThemeReaction(
          kind: ThemeReactionKind.serverError,
          statusCode: 500,
          durationMs: 4000,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('CHILD'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // networkError — timeout
      controller.fire(
        const ThemeReaction(
          kind: ThemeReactionKind.networkError,
          transportFailure: TransportFailureKind.timeout,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);

      // networkError — badCertificate
      controller.fire(
        const ThemeReaction(
          kind: ThemeReactionKind.networkError,
          transportFailure: TransportFailureKind.badCertificate,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);

      // cancelled — fizzle
      controller.fire(
        const ThemeReaction(kind: ThemeReactionKind.cancelled),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}
