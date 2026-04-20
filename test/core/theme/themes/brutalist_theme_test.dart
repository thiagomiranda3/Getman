import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // Disable network font fetching in tests to prevent async errors after
    // tests complete; fonts fall back to system defaults.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('brutalistTheme', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      for (final c in [false, true]) {
        // testWidgets is used (rather than bare test) so the Flutter test zone
        // absorbs the asynchronous google_fonts font-not-found error that fires
        // after assertions pass when fonts are missing from test assets.
        testWidgets('attaches all five extensions for brightness=$b isCompact=$c', (tester) async {
          final theme = brutalistTheme(b, isCompact: c);
          expect(theme.extension<AppLayout>(), isNotNull);
          expect(theme.extension<AppPalette>(), isNotNull);
          expect(theme.extension<AppShape>(), isNotNull);
          expect(theme.extension<AppTypography>(), isNotNull);
          expect(theme.extension<AppDecoration>(), isNotNull);
          expect(theme.extension<AppLayout>()!.isCompact, c);
          expect(theme.brightness, b);
        });
      }
    }

    testWidgets('panelBox returns a BoxDecoration with brutalist hard shadow (blurRadius: 0)', (tester) async {
      final theme = brutalistTheme(Brightness.light);
      late BoxDecoration decoration;
      late double heavy;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(
          builder: (ctx) {
            decoration = ctx.appDecoration.panelBox(ctx);
            heavy = ctx.appLayout.borderHeavy;
            return const SizedBox.shrink();
          },
        ),
      ));
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.first.blurRadius, 0);
      expect(decoration.boxShadow!.first.offset, Offset(heavy, heavy));
    });

    testWidgets('wrapInteractive returns a widget that scales on tap-down', (tester) async {
      final theme = brutalistTheme(Brightness.light);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ctx.appDecoration.wrapInteractive(
                child: const SizedBox(width: 40, height: 40, key: ValueKey('target')),
                onTap: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle(); // settle route animation before gestures

      final target = find.byKey(const ValueKey('target'));
      expect(target, findsOneWidget);

      // Scope the ScaleTransition search to the Center subtree to avoid
      // matching the MaterialApp page-route ScaleTransition as well.
      final scaleInCenter = find.descendant(
        of: find.byType(Center),
        matching: find.byType(ScaleTransition),
      );
      expect(scaleInCenter, findsOneWidget);

      // tester.press dispatches a proper pointer-down via hit-testing.
      // A bare pump() after press lets the gesture recognizer process onTapDown
      // before we start measuring the animation progress at +50ms.
      // warnIfMissed:false silences the hit-test warning caused by the Scaffold
      // overlay absorbing the pointer at the center of the screen.
      final gesture = await tester.press(target, warnIfMissed: false);
      await tester.pump(); // let gesture recognizer fire onTapDown
      await tester.pump(const Duration(milliseconds: 50));
      final scaleBefore = tester.widget<ScaleTransition>(scaleInCenter).scale.value;
      expect(scaleBefore, lessThan(1.0));
      await gesture.up();
      await tester.pumpAndSettle();
      final scaleAfter = tester.widget<ScaleTransition>(scaleInCenter).scale.value;
      expect(scaleAfter, 1.0);
    });
  });
}
