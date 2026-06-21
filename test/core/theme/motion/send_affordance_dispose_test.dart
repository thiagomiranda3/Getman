// Regression: a loud theme's send affordance can lazily field-initialize its
// in-flight build-up AnimationController (`late final _build = ...`) and only
// touch it while sending (build returns the child early when not sending). If
// the affordance is mounted not-sending and then disposed before ever sending
// (e.g. closing a tab, switching themes), dispose()'s `_build.dispose()` forces
// the lazy initializer to run *inside dispose* — which constructs an
// AnimationController and does a TickerMode inherited-widget lookup on a
// deactivated element: "Looking up a deactivated widget's ancestor is unsafe."
// This flooded the console on AURIS (and rpg).
//
// Fix: initialize those controllers eagerly in initState (the proven pattern in
// AurisWallpaper/AurisPress), so dispose always has a real controller.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Loud themes ship a real (non-identity) sendAffordance with a build-up
  // controller; calm themes use the identity affordance (no controller).
  const loud = ['brutalist', 'rpg', 'glass', 'auris'];

  for (final id in loud) {
    testWidgets('$id sendAffordance disposes cleanly when never sending', (
      tester,
    ) async {
      final theme = appThemes[id]!.builder(Brightness.dark);

      // Mount the affordance in the not-sending state (build returns the child
      // early; the build-up controller is never touched).
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => context.appMotion.sendAffordance(
                context,
                isSending: false,
                child: const Text('SEND'),
              ),
            ),
          ),
        ),
      );

      // Dispose the affordance by replacing the subtree — it never sent.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '$id never-sent dispose');
    });
  }
}
