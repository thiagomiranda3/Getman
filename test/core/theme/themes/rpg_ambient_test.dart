import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'RPG animated background renders child + pumps without throwing',
    (tester) async {
      final theme = resolveThemeData(
        kRpgThemeId,
        Brightness.dark,
        isCompact: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => context.appDecoration.scaffoldBackground(
              context,
              child: const Text('bg'),
            ),
          ),
        ),
      );
      // Pump a few animation frames; the ambient painter must not throw.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('bg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'starfield paints UNDER the app content (background, not overlay)',
    (tester) async {
      final theme = resolveThemeData(
        kRpgThemeId,
        Brightness.dark,
        isCompact: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => context.appDecoration.scaffoldBackground(
              context,
              child: const Text('bg'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // Regression: the starfield CustomPaint must sit BEFORE the child in
      // the ambient Stack's paint order (vignette, starfield, content) — it
      // previously came after the child and drew motes + the shooting comet
      // over every panel, contradicting a scaffold *background*.
      final stack = tester.widget<Stack>(
        find.ancestor(of: find.text('bg'), matching: find.byType(Stack)).first,
      );
      final children = stack.children;
      expect(children, hasLength(3));
      expect(
        children[1],
        isA<Positioned>().having(
          (p) => p.child,
          'child',
          isA<RepaintBoundary>().having(
            (r) => r.child,
            'child',
            isA<CustomPaint>(),
          ),
        ),
        reason: 'starfield painter must be the middle (under-content) layer',
      );
      expect(
        children[2],
        isA<RepaintBoundary>().having((r) => r.child, 'child', isA<Text>()),
        reason: 'the app content must be the topmost layer',
      );
    },
  );
}
