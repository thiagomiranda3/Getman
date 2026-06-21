import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';

/// Builds a widget with the motion's tabChipTransition at a fixed animation
/// value, but WITHOUT the routing machinery of [MaterialApp] that injects its
/// own [FadeTransition] / [ScaleTransition] into the tree and confounds
/// assertions.
Widget _buildChip(
  AppMotion motion, {
  double animationValue = 0.5,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => _IdentityWrapper(
          motion: motion,
          animationValue: animationValue,
        ),
      ),
    ),
  );
}

/// Wraps the chip result in a plain [Column] so any transition widgets added
/// by tabChipTransition appear as *descendants* of [_IdentityWrapper], not as
/// ancestors. The [Column] itself adds nothing special.
class _IdentityWrapper extends StatelessWidget {
  const _IdentityWrapper({
    required this.motion,
    required this.animationValue,
  });

  final AppMotion motion;
  final double animationValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        motion.tabChipTransition(
          context,
          animation: AlwaysStoppedAnimation<double>(animationValue),
          child: const Text('chip'),
        ),
      ],
    );
  }
}

// ── Finder helpers ──────────────────────────────────────────────────────────

/// Finds [FadeTransition] widgets that are descendants of [_IdentityWrapper].
Finder get _fadeFinder => find.descendant(
  of: find.byType(_IdentityWrapper),
  matching: find.byType(FadeTransition),
);

/// Finds [ScaleTransition] widgets that are descendants of [_IdentityWrapper].
Finder get _scaleFinder => find.descendant(
  of: find.byType(_IdentityWrapper),
  matching: find.byType(ScaleTransition),
);

void main() {
  // ── child presence + no-throw (all loud themes) ─────────────────────────
  for (final entry in {
    'glass': glassMotion,
    'rpg': rpgMotion,
    'brutalist': brutalistMotion,
    'auris': aurisMotion,
  }.entries) {
    testWidgets('${entry.key} tabChipTransition wraps + renders child', (
      t,
    ) async {
      final motion = entry.value(reduceEffects: false);
      await t.pumpWidget(_buildChip(motion));
      expect(find.text('chip'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  // ── entrance EFFECT is present at mid-animation (loud themes) ────────────

  testWidgets(
    'glass tabChipTransition has FadeTransition + ScaleTransition at 0.5',
    (t) async {
      final motion = glassMotion(reduceEffects: false);
      await t.pumpWidget(_buildChip(motion));
      expect(
        _fadeFinder,
        findsWidgets,
        reason: 'glass entrance should wrap with FadeTransition',
      );
      expect(
        _scaleFinder,
        findsWidgets,
        reason: 'glass entrance should wrap with ScaleTransition',
      );
      expect(find.text('chip'), findsOneWidget);
    },
  );

  testWidgets('rpg tabChipTransition has FadeTransition at 0.5', (t) async {
    final motion = rpgMotion(reduceEffects: false);
    await t.pumpWidget(_buildChip(motion));
    expect(
      _fadeFinder,
      findsWidgets,
      reason: 'rpg entrance should use FadeTransition',
    );
    expect(find.text('chip'), findsOneWidget);
  });

  testWidgets('brutalist tabChipTransition has FadeTransition at 0.5', (
    t,
  ) async {
    final motion = brutalistMotion(reduceEffects: false);
    await t.pumpWidget(_buildChip(motion));
    expect(
      _fadeFinder,
      findsWidgets,
      reason: 'brutalist entrance should use FadeTransition',
    );
    expect(find.text('chip'), findsOneWidget);
  });

  testWidgets('auris tabChipTransition has FadeTransition at 0.5', (t) async {
    final motion = aurisMotion(reduceEffects: false);
    await t.pumpWidget(_buildChip(motion));
    expect(
      _fadeFinder,
      findsWidgets,
      reason: 'auris entrance should use FadeTransition',
    );
    expect(find.text('chip'), findsOneWidget);
  });

  // ── identity / calm themes: NO entrance widgets inside the wrapper ────────

  testWidgets('identity (calm) tabChipTransition returns child unchanged', (
    t,
  ) async {
    const motion = AppMotion(); // default identity
    await t.pumpWidget(_buildChip(motion));
    expect(find.text('chip'), findsOneWidget);
    // Identity returns child directly — no FadeTransition inside our wrapper.
    expect(
      _fadeFinder,
      findsNothing,
      reason: 'identity should not wrap with FadeTransition',
    );
    expect(
      _scaleFinder,
      findsNothing,
      reason: 'identity should not wrap with ScaleTransition',
    );
  });

  testWidgets('reduceEffects=true returns identity (no entrance widgets)', (
    t,
  ) async {
    for (final builder in [
      glassMotion,
      rpgMotion,
      brutalistMotion,
      aurisMotion,
    ]) {
      final motion = builder(reduceEffects: true);
      await t.pumpWidget(_buildChip(motion));
      expect(find.text('chip'), findsOneWidget);
      expect(
        _fadeFinder,
        findsNothing,
        reason: 'reduceEffects should produce identity — no FadeTransition',
      );
      expect(
        _scaleFinder,
        findsNothing,
        reason: 'reduceEffects should produce identity — no ScaleTransition',
      );
    }
  });
}
