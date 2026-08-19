// test/core/theme/motion/theme_switch_transition_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_switch_transition.dart';

void main() {
  testWidgets('plays an overlay on themeId change, then settles', (
    tester,
  ) async {
    var id = 'a';
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return ThemeSwitchTransition(
              themeId: id,
              reduceEffects: false,
              child: const Text('content', textDirection: TextDirection.ltr),
            );
          },
        ),
      ),
    );
    expect(find.text('content'), findsOneWidget);

    setOuter(() => id = 'b');
    await tester.pump(); // start transition
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600)); // finish
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets(
    'sweep accent resolves colorScheme.primary, never ThemeData.primaryColor',
    (tester) async {
      // Mimics AURIS dark: the composed kit leaves ThemeData.primaryColor at
      // the framework default (near-black) while colorScheme.primary carries
      // the real accent — a primaryColor sweep reads as an off-brand flash.
      const kitPrimary = Color(0xFF12E0B0);
      final theme = ThemeData(
        colorScheme: const ColorScheme.dark(primary: kitPrimary),
        primaryColor: const Color(0xFF101010),
      );
      late Color accent;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              accent = themeSwitchSweepAccent(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(accent, kitPrimary);
      expect(accent, isNot(theme.primaryColor));
    },
  );

  testWidgets('overlay painter is built once, not re-allocated per frame', (
    tester,
  ) async {
    var id = 'a';
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return ThemeSwitchTransition(
              themeId: id,
              reduceEffects: false,
              child: const Text('content', textDirection: TextDirection.ltr),
            );
          },
        ),
      ),
    );
    setOuter(() => id = 'b');
    await tester.pump(); // start transition

    CustomPainter? overlayPainter() => tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('theme_switch_overlay')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter;

    await tester.pump(const Duration(milliseconds: 100));
    final first = overlayPainter();
    await tester.pump(const Duration(milliseconds: 100));
    final second = overlayPainter();
    expect(first, isNotNull);
    expect(
      identical(first, second),
      isTrue,
      reason:
          'the sweep painter (and its Paint) must be reused across '
          'frames — repaint is driven by the controller, not per-frame '
          'painter allocation',
    );

    await tester.pump(const Duration(milliseconds: 600)); // finish
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsNothing);
  });

  testWidgets('reduced effects: no overlay on change', (tester) async {
    var id = 'a';
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return ThemeSwitchTransition(
              themeId: id,
              reduceEffects: true,
              child: const Text('content', textDirection: TextDirection.ltr),
            );
          },
        ),
      ),
    );
    setOuter(() => id = 'b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsNothing);
  });
}
