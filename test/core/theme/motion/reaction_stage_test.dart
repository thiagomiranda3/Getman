// test/core/theme/motion/reaction_stage_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

void main() {
  testWidgets('calls onReaction once per controller seq change', (
    tester,
  ) async {
    final controller = ThemeReactionController();
    final seen = <ThemeReactionKind>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ReactionStage(
          controller: controller,
          onReaction: (r) => seen.add(r.kind),
          child: const SizedBox(),
        ),
      ),
    );

    controller.fire(const ThemeReaction(kind: ThemeReactionKind.success));
    await tester.pump();
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.serverError));
    await tester.pump();
    expect(seen, [ThemeReactionKind.success, ThemeReactionKind.serverError]);
    controller.dispose();
  });

  testWidgets('disabled never reacts', (tester) async {
    final controller = ThemeReactionController();
    final seen = <ThemeReactionKind>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ReactionStage(
          controller: controller,
          enabled: false,
          onReaction: (r) => seen.add(r.kind),
          child: const SizedBox(),
        ),
      ),
    );
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.success));
    await tester.pump();
    expect(seen, isEmpty);
    controller.dispose();
  });
}
