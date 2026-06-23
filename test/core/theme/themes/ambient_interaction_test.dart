// test/core/theme/themes/ambient_interaction_test.dart
//
// Task 3 — Remove per-click background ripple: the click ripple was deleted
// from all four animated ambients. What remains on pointer-down is the
// `_pulse?.touch()` call (idle-reset), which keeps the session-rhythm pulse
// awake. These tests assert that REAL consequence:
//
//   • Animated mode: a pointer-down resets the pulse's idleFactor to 0 (proves
//     the Listener → touch() wiring survives). We first tick() the pulse so
//     idleFactor > 0, since touch() early-returns when idle is already 0.
//   • Static / reduced-effects mode: a pointer-down leaves idleFactor UNCHANGED
//     (proves static mode wires NO Listener, so touch() never fires).
//
// The ambient drift animation never settles, so we use pump(Duration), never
// pumpAndSettle. Each animated test provides the controller via Provider, since
// the widgets resolve it with Provider.of(listen: false).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/auris/auris_ambient.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_ambient.dart';
import 'package:getman/core/theme/themes/glass/glass_decorations.dart';
import 'package:getman/core/theme/themes/rpg/rpg_decorations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// Pumps [ambient] under a Provider exposing [pulse], wrapped in a
  /// MaterialApp using [theme] (null = default). The painted surface fills the
  /// screen so a centre pointer-down always lands inside it.
  Future<void> pumpAmbient(
    WidgetTester tester, {
    required WorkspacePulseController pulse,
    required Widget ambient,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkspacePulseController>.value(
        value: pulse,
        child: MaterialApp(
          theme: theme,
          home: Builder(builder: (_) => ambient),
        ),
      ),
    );
    // One frame so the ambient's didChangeDependencies resolves the provider.
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Fires a mouse pointer-down + up at the screen centre, then one frame.
  Future<void> clickCentre(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MaterialApp)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    // pump (NOT pumpAndSettle): the ambient drift animation never settles.
    await tester.pump(const Duration(milliseconds: 16));
  }

  // ---------------------------------------------------------------------------
  // Glass
  // ---------------------------------------------------------------------------

  testWidgets('glass animated: pointer-down resets the pulse (touch fired)', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
    pulse.tick(); // idleFactor now > 0
    expect(pulse.idleFactor, greaterThan(0));

    await pumpAmbient(
      tester,
      pulse: pulse,
      theme: appThemes[kGlassThemeId]!.builder(Brightness.dark),
      ambient: Builder(
        builder: (context) =>
            glassScaffoldBackground(context, child: const SizedBox.expand()),
      ),
    );
    await clickCentre(tester);

    expect(tester.takeException(), isNull);
    expect(
      pulse.idleFactor,
      0,
      reason: 'animated glass must call touch() on pointer-down (idle reset)',
    );
  });

  testWidgets('glass static: pointer-down does NOT touch the pulse', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
    pulse.tick(); // idleFactor now > 0
    final before = pulse.idleFactor;
    expect(before, greaterThan(0));

    await pumpAmbient(
      tester,
      pulse: pulse,
      theme: appThemes[kGlassThemeId]!.builder(Brightness.dark),
      ambient: Builder(
        builder: (context) => glassStaticScaffoldBackground(
          context,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await clickCentre(tester);

    expect(tester.takeException(), isNull);
    expect(
      pulse.idleFactor,
      before,
      reason: 'static glass wires no Listener — touch() must not fire',
    );
  });

  // ---------------------------------------------------------------------------
  // Brutalist
  // ---------------------------------------------------------------------------

  testWidgets(
    'brutalist animated: pointer-down resets the pulse (touch fired)',
    (tester) async {
      final pulse = WorkspacePulseController();
      addTearDown(pulse.dispose);
      pulse.tick();
      expect(pulse.idleFactor, greaterThan(0));

      await pumpAmbient(
        tester,
        pulse: pulse,
        ambient: Builder(
          builder: (context) => brutalistScaffoldBackgroundAnimated(
            context,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await clickCentre(tester);

      expect(tester.takeException(), isNull);
      expect(
        pulse.idleFactor,
        0,
        reason:
            'animated brutalist must call touch() on pointer-down (idle reset)',
      );
    },
  );

  testWidgets('brutalist static: pointer-down does NOT touch the pulse', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
    pulse.tick();
    final before = pulse.idleFactor;
    expect(before, greaterThan(0));

    await pumpAmbient(
      tester,
      pulse: pulse,
      ambient: Builder(
        builder: (context) => brutalistStaticScaffoldBackground(
          context,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await clickCentre(tester);

    expect(tester.takeException(), isNull);
    expect(
      pulse.idleFactor,
      before,
      reason: 'static brutalist wires no Listener — touch() must not fire',
    );
  });

  // ---------------------------------------------------------------------------
  // AURIS
  // ---------------------------------------------------------------------------

  testWidgets('auris animated: pointer-down resets the pulse (touch fired)', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
    pulse.tick();
    expect(pulse.idleFactor, greaterThan(0));

    await pumpAmbient(
      tester,
      pulse: pulse,
      theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
      ambient: Builder(
        builder: (context) => aurisScaffoldBackgroundAnimated(
          context,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await clickCentre(tester);

    expect(tester.takeException(), isNull);
    expect(
      pulse.idleFactor,
      0,
      reason: 'animated auris must call touch() on pointer-down (idle reset)',
    );
  });

  testWidgets('auris static: pointer-down does NOT touch the pulse', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
    pulse.tick();
    final before = pulse.idleFactor;
    expect(before, greaterThan(0));

    await pumpAmbient(
      tester,
      pulse: pulse,
      theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
      ambient: Builder(
        builder: (context) => aurisStaticScaffoldBackground(
          context,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await clickCentre(tester);

    expect(tester.takeException(), isNull);
    expect(
      pulse.idleFactor,
      before,
      reason: 'static auris wires no Listener — touch() must not fire',
    );
  });

  // ---------------------------------------------------------------------------
  // RPG
  // ---------------------------------------------------------------------------

  testWidgets('rpg animated: pointer-down resets the pulse (touch fired)', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
    pulse.tick();
    expect(pulse.idleFactor, greaterThan(0));

    await pumpAmbient(
      tester,
      pulse: pulse,
      theme: appThemes[kRpgThemeId]!.builder(Brightness.dark),
      ambient: Builder(
        builder: (context) =>
            rpgScaffoldBackground(context, child: const SizedBox.expand()),
      ),
    );
    await clickCentre(tester);

    expect(tester.takeException(), isNull);
    expect(
      pulse.idleFactor,
      0,
      reason: 'animated rpg must call touch() on pointer-down (idle reset)',
    );
  });

  testWidgets('rpg static: pointer-down does NOT touch the pulse', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
    pulse.tick();
    final before = pulse.idleFactor;
    expect(before, greaterThan(0));

    await pumpAmbient(
      tester,
      pulse: pulse,
      theme: appThemes[kRpgThemeId]!.builder(Brightness.dark),
      ambient: Builder(
        builder: (context) => rpgStaticScaffoldBackground(
          context,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await clickCentre(tester);

    expect(tester.takeException(), isNull);
    expect(
      pulse.idleFactor,
      before,
      reason: 'static rpg wires no Listener — touch() must not fire',
    );
  });
}
