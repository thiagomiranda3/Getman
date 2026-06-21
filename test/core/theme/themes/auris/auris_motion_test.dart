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

  testWidgets(
    'aurisMotion full: sendAffordance — restart guard + child always present',
    (tester) async {
      final m = aurisMotion(reduceEffects: false);

      // pump with isSending: false
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: m.sendAffordance(
                  context,
                  isSending: false,
                  child: const SizedBox(
                    key: ValueKey('send_child'),
                    width: 100,
                    height: 40,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('send_child')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // rebuild with isSending: true — exercises forward(from:0) restart guard
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: m.sendAffordance(
                  context,
                  isSending: true,
                  child: const SizedBox(
                    key: ValueKey('send_child'),
                    width: 100,
                    height: 40,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('send_child')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // back to isSending: false — exercises stop()+reset()
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: m.sendAffordance(
                  context,
                  isSending: false,
                  child: const SizedBox(
                    key: ValueKey('send_child'),
                    width: 100,
                    height: 40,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('send_child')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
