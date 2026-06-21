// test/core/theme/themes/in_flight_frame_themes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';
import 'package:getman/core/theme/themes/auris/auris_theme.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
import 'package:getman/core/theme/themes/glass/glass_theme.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_theme.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Shared setup
// ---------------------------------------------------------------------------

void _disableGoogleFonts() => GoogleFonts.config.allowRuntimeFetching = false;

// ---------------------------------------------------------------------------
// Helper: pump the frame widget with isSending:true, advance time,
// check child survives, then pump with isSending:false and verify clean
// teardown.
// ---------------------------------------------------------------------------

Future<void> _pumpFrame(
  WidgetTester tester,
  AppMotion motion,
  ThemeData theme,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.inFlightFrame(
            context,
            isSending: true,
            child: const SizedBox(
              key: ValueKey('panes'),
              width: 300,
              height: 300,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  expect(find.byKey(const ValueKey('panes')), findsOneWidget);
  expect(tester.takeException(), isNull);
  // Toggle off — frame must tear down cleanly.
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

// ---------------------------------------------------------------------------
// Helper: assert the effect is PRESENT when isSending:true.
// Counts the number of CustomPaint (rpg/brutalist/auris) or DecoratedBox
// (glass) widgets; isSending:true must produce MORE than isSending:false.
//
// Uses an inline counter closure instead of a typedef to satisfy
// avoid_private_typedef_functions.
// ---------------------------------------------------------------------------

Future<void> _assertEffectPresent({
  required WidgetTester tester,
  required AppMotion motion,
  required ThemeData theme,
  required int Function(WidgetTester) countLayer,
}) async {
  // --- isSending: false ---
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.inFlightFrame(
            context,
            isSending: false,
            child: const SizedBox(
              key: ValueKey('panes'),
              width: 300,
              height: 300,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  final countOff = countLayer(tester);

  // --- isSending: true ---
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.inFlightFrame(
            context,
            isSending: true,
            child: const SizedBox(
              key: ValueKey('panes'),
              width: 300,
              height: 300,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  final countOn = countLayer(tester);

  expect(
    countOn,
    greaterThan(countOff),
    reason:
        'isSending:true should add at least one extra paint/overlay layer '
        'compared to isSending:false. '
        'Got off=$countOff on=$countOn — is inFlightFrame still identity?',
  );

  // Cleanup.
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

// ---------------------------------------------------------------------------
// Survival tests (child present, no exception, toggle off cleanly)
// ---------------------------------------------------------------------------

void main() {
  setUpAll(_disableGoogleFonts);

  testWidgets(
    'glass in-flight frame renders child + survives toggle',
    (t) async {
      await _pumpFrame(
        t,
        glassMotion(reduceEffects: false),
        glassTheme(Brightness.light),
      );
    },
  );
  testWidgets(
    'rpg in-flight frame renders child + survives toggle',
    (t) async {
      await _pumpFrame(
        t,
        rpgMotion(reduceEffects: false),
        rpgTheme(Brightness.light),
      );
    },
  );
  testWidgets(
    'brutalist in-flight frame renders child + survives toggle',
    (t) async {
      await _pumpFrame(
        t,
        brutalistMotion(reduceEffects: false),
        brutalistTheme(Brightness.light),
      );
    },
  );
  testWidgets(
    'auris in-flight frame renders child + survives toggle',
    (t) async {
      await _pumpFrame(
        t,
        aurisMotion(reduceEffects: false),
        aurisTheme(Brightness.light),
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Effect-presence tests — RED before implementation, GREEN after.
  // Each asserts that isSending:true produces MORE painted layers than
  // isSending:false (i.e. the frame widget is NOT identity).
  // ---------------------------------------------------------------------------

  testWidgets(
    'glass in-flight frame effect is PRESENT when sending',
    (t) async {
      await _assertEffectPresent(
        tester: t,
        motion: glassMotion(reduceEffects: false),
        theme: glassTheme(Brightness.light),
        // _GlassInFlightFrame adds a DecoratedBox border layer.
        countLayer: (tester) =>
            tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).length,
      );
    },
  );

  testWidgets(
    'rpg in-flight frame effect is PRESENT when sending',
    (t) async {
      await _assertEffectPresent(
        tester: t,
        motion: rpgMotion(reduceEffects: false),
        theme: rpgTheme(Brightness.light),
        // _RpgInFlightFrame adds a CustomPaint circuit-trace painter.
        countLayer: (tester) =>
            tester.widgetList<CustomPaint>(find.byType(CustomPaint)).length,
      );
    },
  );

  testWidgets(
    'brutalist in-flight frame effect is PRESENT when sending',
    (t) async {
      await _assertEffectPresent(
        tester: t,
        motion: brutalistMotion(reduceEffects: false),
        theme: brutalistTheme(Brightness.light),
        // _BrutalistInFlightFrame adds a CustomPaint marching-bar painter.
        countLayer: (tester) =>
            tester.widgetList<CustomPaint>(find.byType(CustomPaint)).length,
      );
    },
  );

  testWidgets(
    'auris in-flight frame effect is PRESENT when sending',
    (t) async {
      await _assertEffectPresent(
        tester: t,
        motion: aurisMotion(reduceEffects: false),
        theme: aurisTheme(Brightness.light),
        // _AurisInFlightFrame adds a CustomPaint scanline painter.
        countLayer: (tester) =>
            tester.widgetList<CustomPaint>(find.byType(CustomPaint)).length,
      );
    },
  );

  // ---------------------------------------------------------------------------
  // dispose-safety: mount with isSending:false for entire lifetime, then
  // unmount — must NOT crash (lazy-init controller dispose-time vsync crash).
  // ---------------------------------------------------------------------------

  group('dispose with isSending:false never touched', () {
    testWidgets('brutalist dispose is clean', (tester) async {
      final theme = brutalistTheme(Brightness.light);
      final motion = brutalistMotion(reduceEffects: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: motion.inFlightFrame(
                context,
                isSending: false,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'brutalist crashed on dispose',
      );
    });

    testWidgets('rpg dispose is clean', (tester) async {
      final theme = rpgTheme(Brightness.light);
      final motion = rpgMotion(reduceEffects: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: motion.inFlightFrame(
                context,
                isSending: false,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'rpg crashed on dispose',
      );
    });

    testWidgets('glass dispose is clean', (tester) async {
      final theme = glassTheme(Brightness.light);
      final motion = glassMotion(reduceEffects: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: motion.inFlightFrame(
                context,
                isSending: false,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'glass crashed on dispose',
      );
    });

    testWidgets('auris dispose is clean', (tester) async {
      final theme = aurisTheme(Brightness.dark);
      final motion = aurisMotion(reduceEffects: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: motion.inFlightFrame(
                context,
                isSending: false,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'auris crashed on dispose',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // reduceEffects → identity (all four return child unchanged)
  // ---------------------------------------------------------------------------

  testWidgets('reduceEffects keeps inFlightFrame identity', (tester) async {
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
        identical(m.inFlightFrame(ctx, child: marker, isSending: true), marker),
        isTrue,
      );
    }
  });
}
