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
      // Use a plain widget tree without Scaffold so there is no overlay theater
      // that absorbs pointer events before they reach our target widget.
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(
          builder: (ctx) => Align(
            alignment: Alignment.topLeft,
            child: ctx.appDecoration.wrapInteractive(
              child: const SizedBox(width: 40, height: 40, key: ValueKey('target')),
              onTap: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle(); // settle route animation before gestures

      expect(find.byKey(const ValueKey('target')), findsOneWidget);

      // Scope the ScaleTransition search to the Align subtree to avoid
      // matching the MaterialApp page-route ScaleTransition as well.
      final scaleInAlign = find.descendant(
        of: find.byType(Align),
        matching: find.byType(ScaleTransition),
      );
      expect(scaleInAlign, findsOneWidget);

      // Press on the BrutalBounce GestureDetector (HitTestBehavior.opaque), which
      // is the actual hit-test recipient. Pressing the inner SizedBox would trigger
      // a warnIfMissed warning because opaque behavior absorbs the hit at the
      // GestureDetector level before the test framework walks to the SizedBox leaf.
      final gesture = await tester.press(find.byType(GestureDetector));
      await tester.pump(); // let gesture recognizer fire onTapDown
      await tester.pump(const Duration(milliseconds: 50));
      final scaleBefore = tester.widget<ScaleTransition>(scaleInAlign).scale.value;
      expect(scaleBefore, lessThan(1.0));
      await gesture.up();
      await tester.pumpAndSettle();
      final scaleAfter = tester.widget<ScaleTransition>(scaleInAlign).scale.value;
      expect(scaleAfter, 1.0);
    });
  });
}
