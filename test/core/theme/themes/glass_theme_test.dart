import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/glass/glass_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('glassTheme', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      for (final c in [false, true]) {
        for (final r in [false, true]) {
          testWidgets(
            'attaches all six extensions (brightness=$b compact=$c reduce=$r)',
            (tester) async {
              final theme = glassTheme(b, isCompact: c, reduceEffects: r);
              expect(theme.extension<AppLayout>(), isNotNull);
              expect(theme.extension<AppPalette>(), isNotNull);
              expect(theme.extension<AppShape>(), isNotNull);
              expect(theme.extension<AppTypography>(), isNotNull);
              expect(theme.extension<AppDecoration>(), isNotNull);
              expect(theme.extension<AppCopy>(), isNotNull);
              expect(theme.extension<AppLayout>()!.isCompact, c);
              expect(theme.brightness, b);
            },
          );
        }
      }
    }

    testWidgets('frost wraps in BackdropFilter when effects are full', (
      tester,
    ) async {
      final theme = glassTheme(Brightness.dark);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (ctx) =>
                ctx.appDecoration.frost(ctx, child: const SizedBox()),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('frost is identity when effects are reduced', (tester) async {
      final theme = glassTheme(Brightness.dark, reduceEffects: true);
      const child = SizedBox(key: ValueKey('c'));
      late Widget result;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (ctx) {
              result = ctx.appDecoration.frost(ctx, child: child);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(identical(result, child), isTrue);
    });

    testWidgets('selected tab is a glass lozenge (gradient + border + glow)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: glassTheme(Brightness.dark),
          home: Builder(
            builder: (ctx) {
              final deco = ctx.appDecoration;
              // Open-request tab strip.
              final active = deco.tabShape(
                ctx,
                active: true,
                hovered: false,
                isFirst: true,
              );
              expect(active.gradient, isNotNull, reason: 'needs a gradient');
              expect(active.border, isNotNull, reason: 'needs a border');
              expect(active.boxShadow, isNotEmpty, reason: 'needs a glow');
              // BrandedTabBar indicator override is wired up.
              expect(deco.brandedTabIndicator, isNotNull);
              final indicator = deco.brandedTabIndicator!(ctx) as BoxDecoration;
              expect(indicator.gradient, isNotNull);
              expect(indicator.border, isNotNull);
              // Inactive tab has no fill (wallpaper shows through).
              final inactive = deco.tabShape(
                ctx,
                active: false,
                hovered: false,
                isFirst: false,
              );
              expect(inactive.gradient, isNull);
              expect(inactive.color, isNull);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('defines an explicit switch theme with a visible thumb', () {
      final theme = glassTheme(Brightness.dark);
      final sw = theme.switchTheme;
      expect(sw.thumbColor, isNotNull, reason: 'thumb must be explicitly set');
      const on = {WidgetState.selected};
      // On = accent track; off = a distinct translucent track (not the same
      // color), so the thumb is always visible.
      final onTrack = sw.trackColor?.resolve(on);
      final offTrack = sw.trackColor?.resolve(const {});
      expect(onTrack, isNotNull);
      expect(offTrack, isNotNull);
      expect(onTrack, isNot(offTrack));
      expect(sw.trackOutlineColor?.resolve(const {}), isNotNull);
    });

    test('every theme defines a switchTheme (switch colors are no longer '
        'hardcoded at call sites)', () {
      for (final id in [
        'brutalist',
        'editorial',
        'rpg',
        'dracula',
        'glass',
        'classic',
      ]) {
        for (final b in [Brightness.light, Brightness.dark]) {
          final theme = resolveTheme(id)(b, isCompact: false);
          final sw = theme.switchTheme;
          final onThumb = sw.thumbColor?.resolve({WidgetState.selected});
          final onTrack = sw.trackColor?.resolve({WidgetState.selected});
          expect(onThumb, isNotNull, reason: '$id/$b needs a selected thumb');
          expect(onTrack, isNotNull, reason: '$id/$b needs a selected track');
          // The thumb must contrast the track so the ON state is visible — the
          // glass bug was thumb == track == accent.
          expect(
            onThumb,
            isNot(onTrack),
            reason: '$id/$b: thumb must differ from track when ON',
          );
        }
      }
    });

    test(
      'non-glass themes keep the null indicator fallback (no regression)',
      () {
        // brutalist/editorial/rpg/dracula must NOT define brandedTabIndicator —
        // BrandedTabBar falls back to its signature solid filled look for them.
        for (final id in [
          'brutalist',
          'editorial',
          'rpg',
          'dracula',
          'classic',
        ]) {
          final theme = resolveTheme(id)(Brightness.dark, isCompact: false);
          final deco = theme.extension<AppDecoration>();
          expect(
            deco?.brandedTabIndicator,
            isNull,
            reason: '$id should keep the default filled indicator',
          );
        }
      },
    );
  });
}
