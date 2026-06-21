import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';

// Sentinel key emitted by each theme's contentTransition overlay widget.
// We look for this to prove the effect layer is present mid-transition.
const _kTransitionOverlayKey = ValueKey<String>('content_transition_overlay');

/// Returns the count of widgets keyed [_kTransitionOverlayKey] — used to
/// detect whether the transition overlay is currently painted.
int _overlayCount(WidgetTester tester) =>
    tester.widgetList(find.byKey(_kTransitionOverlayKey)).length;

Future<void> _swap(
  WidgetTester tester,
  AppMotion motion, {
  ThemeData? theme,
}) async {
  Widget build(String key) => MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) => Scaffold(
        body: motion.contentTransition(
          context,
          transitionKey: key,
          child: const SizedBox(
            key: ValueKey('content'),
            width: 200,
            height: 200,
          ),
        ),
      ),
    ),
  );

  // Initial render — no transition running yet.
  await tester.pumpWidget(build('p1/t1'));
  await tester.pump();
  final baselineCount = _overlayCount(tester);

  // Trigger tab-switch.
  await tester.pumpWidget(build('p1/t2'));
  // Pump a small duration mid-transition.
  await tester.pump(const Duration(milliseconds: 100));

  // STRONG assertion: the overlay must be PRESENT mid-transition (effect
  // widget keyed with _kTransitionOverlayKey — more than the baseline).
  expect(
    _overlayCount(tester),
    greaterThan(baselineCount),
    reason:
        'Expected a themed transition overlay to be visible 100ms into the '
        'tab-switch transition, but none was found (count stayed at '
        '$baselineCount).',
  );

  // Child must survive.
  expect(find.byKey(const ValueKey('content')), findsOneWidget);

  // Settle — overlay must be gone.
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('content')), findsOneWidget);
  expect(tester.takeException(), isNull);

  // Trigger panel-switch.
  await tester.pumpWidget(build('p2/t9'));
  await tester.pump(const Duration(milliseconds: 100));
  // Overlay present mid-transition.
  expect(
    _overlayCount(tester),
    greaterThan(baselineCount),
    reason: 'Expected a themed transition overlay mid-panel-switch.',
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('content')), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('glass content transition plays + keeps child', (t) async {
    await _swap(t, glassMotion(reduceEffects: false));
  });

  testWidgets('rpg content transition plays + keeps child', (t) async {
    await _swap(t, rpgMotion(reduceEffects: false));
  });

  testWidgets('brutalist content transition plays + keeps child', (t) async {
    await _swap(t, brutalistMotion(reduceEffects: false));
  });

  testWidgets('auris content transition plays + keeps child', (t) async {
    // Pumped under the real AURIS ThemeData so AurisScheme is present and the
    // HUD-wipe code path is exercised — not the identity bail-out branch.
    final aurisTheme = appThemes[kAurisThemeId]!.builder(Brightness.dark);
    await _swap(t, aurisMotion(reduceEffects: false), theme: aurisTheme);
  });

  testWidgets('reduceEffects content transition is identity', (tester) async {
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
    for (final m in [
      glassMotion(reduceEffects: true),
      rpgMotion(reduceEffects: true),
      brutalistMotion(reduceEffects: true),
      aurisMotion(reduceEffects: true),
    ]) {
      expect(
        identical(
          m.contentTransition(ctx, child: marker, transitionKey: 'x'),
          marker,
        ),
        isTrue,
      );
    }
  });
}
