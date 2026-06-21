// Tests for editorial_decorations.dart:
//   - editorialPanelBox        → BoxDecoration (border, color)
//   - editorialTabShape        → BoxDecoration, bottom border varies by state
//   - editorialScaffoldBackground → Stack with dot-grid overlay over child

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/editorial/editorial_decorations.dart';
import 'package:getman/core/theme/themes/editorial/editorial_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ── editorialPanelBox ─────────────────────────────────────────────────────

  group('editorialPanelBox', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('returns a BoxDecoration with a border in $brightness mode', (
        tester,
      ) async {
        BoxDecoration? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: editorialTheme(brightness),
            home: Builder(
              builder: (ctx) {
                result = editorialPanelBox(ctx);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(result, isNotNull);
        // Editorial panels are magazine-flat — border present, no hard shadow.
        expect(result!.border, isNotNull);
        expect(result!.boxShadow, anyOf(isNull, isEmpty));
      });

      testWidgets(
        'accepts optional color override in $brightness mode',
        (tester) async {
          BoxDecoration? result;
          await tester.pumpWidget(
            MaterialApp(
              theme: editorialTheme(brightness),
              home: Builder(
                builder: (ctx) {
                  result = editorialPanelBox(ctx, color: Colors.amber);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );
          expect(result!.color, Colors.amber);
        },
      );

      testWidgets(
        'accepts optional borderRadius override in $brightness mode',
        (tester) async {
          BoxDecoration? result;
          const radius = BorderRadius.all(Radius.circular(8));
          await tester.pumpWidget(
            MaterialApp(
              theme: editorialTheme(brightness),
              home: Builder(
                builder: (ctx) {
                  result = editorialPanelBox(ctx, borderRadius: radius);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );
          expect(result!.borderRadius, radius);
        },
      );
    }

    testWidgets(
      'does not throw under reduceEffects=true',
      (tester) async {
        BoxDecoration? deco;
        await tester.pumpWidget(
          MaterialApp(
            theme: editorialTheme(Brightness.light, reduceEffects: true),
            home: Builder(
              builder: (ctx) {
                deco = editorialPanelBox(ctx);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(deco, isNotNull);
        expect(deco!.border, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── editorialTabShape ─────────────────────────────────────────────────────

  group('editorialTabShape', () {
    testWidgets(
      'active tab has a thicker bottom border in light mode',
      (tester) async {
        BoxDecoration? active;
        BoxDecoration? inactive;
        await tester.pumpWidget(
          MaterialApp(
            theme: editorialTheme(Brightness.light),
            home: Builder(
              builder: (ctx) {
                final layout = ctx.appLayout;
                active = editorialTabShape(
                  ctx,
                  active: true,
                  hovered: false,
                  isFirst: false,
                );
                inactive = editorialTabShape(
                  ctx,
                  active: false,
                  hovered: false,
                  isFirst: false,
                );
                // Validate the context is themed correctly.
                expect(layout.borderThick, greaterThan(layout.borderThin));
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        // Active tab → thick bottom border (borderThick).
        final activeBottom = (active!.border as Border?)?.bottom;
        final inactiveBottom = (inactive!.border as Border?)?.bottom;
        expect(activeBottom, isNotNull);
        expect(inactiveBottom, isNotNull);
        expect(activeBottom!.width, greaterThan(inactiveBottom!.width));
      },
    );

    testWidgets('isFirst=true adds a left border, isFirst=false does not', (
      tester,
    ) async {
      BoxDecoration? first;
      BoxDecoration? notFirst;
      await tester.pumpWidget(
        MaterialApp(
          theme: editorialTheme(Brightness.light),
          home: Builder(
            builder: (ctx) {
              first = editorialTabShape(
                ctx,
                active: false,
                hovered: false,
                isFirst: true,
              );
              notFirst = editorialTabShape(
                ctx,
                active: false,
                hovered: false,
                isFirst: false,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // isFirst=true: left border should have a non-zero width.
      final borderFirst = first!.border as Border?;
      final borderNotFirst = notFirst!.border as Border?;
      final leftFirst = borderFirst?.left;
      final leftNotFirst = borderNotFirst?.left;
      expect(leftFirst, isNotNull);
      expect(leftFirst!.width, greaterThan(0));
      // isFirst=false: left border is BorderSide.none (width == 0).
      expect(leftNotFirst?.width ?? 0.0, equals(0.0));
    });

    testWidgets('hovered=true changes the bottom border color vs inactive', (
      tester,
    ) async {
      BoxDecoration? hovered;
      BoxDecoration? idle;
      await tester.pumpWidget(
        MaterialApp(
          theme: editorialTheme(Brightness.light),
          home: Builder(
            builder: (ctx) {
              hovered = editorialTabShape(
                ctx,
                active: false,
                hovered: true,
                isFirst: false,
              );
              idle = editorialTabShape(
                ctx,
                active: false,
                hovered: false,
                isFirst: false,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Hovered has a plain (non-translucent) bottom border.
      // Idle has a semi-transparent border color.
      final hoveredAlpha = (hovered!.border as Border?)?.bottom.color.a ?? 0.0;
      final idleAlpha = (idle!.border as Border?)?.bottom.color.a ?? 0.0;
      // Hovered is fully opaque (or more so) vs idle which is translucent.
      expect(hoveredAlpha, greaterThan(idleAlpha));
    });

    testWidgets('works in dark mode without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: editorialTheme(Brightness.dark),
          home: Builder(
            builder: (ctx) {
              editorialTabShape(
                ctx,
                active: true,
                hovered: false,
                isFirst: true,
              );
              editorialTabShape(
                ctx,
                active: false,
                hovered: true,
                isFirst: false,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── editorialScaffoldBackground ───────────────────────────────────────────

  group('editorialScaffoldBackground', () {
    testWidgets(
      'wraps child in a Stack and renders an IgnorePointer dot-grid overlay',
      (tester) async {
        const child = SizedBox(
          key: ValueKey('bg_child'),
          width: 200,
          height: 200,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: editorialTheme(Brightness.light),
            home: Builder(
              builder: (ctx) => editorialScaffoldBackground(
                ctx,
                child: child,
              ),
            ),
          ),
        );
        // The child must still be present.
        expect(find.byKey(const ValueKey('bg_child')), findsOneWidget);
        // A Stack wraps the content + the dot-grid overlay.
        expect(find.byType(Stack), findsAtLeastNWidgets(1));
        // The grid overlay is in an IgnorePointer so taps pass through.
        expect(find.byType(IgnorePointer), findsAtLeastNWidgets(1));
        // A CustomPaint renders the dots.
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('works in dark mode without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: editorialTheme(Brightness.dark),
          home: Builder(
            builder: (ctx) => editorialScaffoldBackground(
              ctx,
              child: const SizedBox(
                key: ValueKey('bg_child_dark'),
                width: 200,
                height: 200,
              ),
            ),
          ),
        ),
      );
      // The structural contract must hold in dark mode too.
      expect(find.byKey(const ValueKey('bg_child_dark')), findsOneWidget);
      expect(find.byType(Stack), findsAtLeastNWidgets(1));
      expect(find.byType(IgnorePointer), findsAtLeastNWidgets(1));
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('works with reduceEffects=true without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: editorialTheme(Brightness.light, reduceEffects: true),
          home: Builder(
            builder: (ctx) => editorialScaffoldBackground(
              ctx,
              child: const SizedBox(
                key: ValueKey('bg_child_reduce'),
                width: 200,
                height: 200,
              ),
            ),
          ),
        ),
      );
      // Under reduceEffects the structural wrapping (Stack + overlay) must
      // still render correctly — the child must be present.
      expect(find.byKey(const ValueKey('bg_child_reduce')), findsOneWidget);
      expect(find.byType(Stack), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'via context.appDecoration.scaffoldBackground — renders child in Stack',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: editorialTheme(Brightness.light),
            home: Builder(
              builder: (ctx) => ctx.appDecoration.scaffoldBackground(
                ctx,
                child: const SizedBox(
                  key: ValueKey('bg_child_deco'),
                  width: 200,
                  height: 200,
                ),
              ),
            ),
          ),
        );
        // Verify the child is reachable and wrapped in a Stack.
        expect(find.byKey(const ValueKey('bg_child_deco')), findsOneWidget);
        expect(find.byType(Stack), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
