// test/core/theme/themes/ambient_interaction_test.dart
//
// Task 13 — C1 (cursor force + click ripple): verifies that a mouse click
// registers an impulse in each animated ambient, and that the static/reduced-
// effects path never registers one.
//
// The [debugXxxImpulseCount] top-level variables are @visibleForTesting
// sentinels written by each ambient State in [_addImpulse]; they let the test
// inspect the impulse count without accessing private State classes.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/auris/auris_ambient.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_ambient.dart';
import 'package:getman/core/theme/themes/glass/glass_decorations.dart';
import 'package:getman/core/theme/themes/rpg/rpg_decorations.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    // Reset all debug counters before each test so tests are independent.
    debugBrutalistImpulseCount = 0;
    debugAurisImpulseCount = 0;
    debugRpgImpulseCount = 0;
    debugGlassImpulseCount = 0;
  });

  // ---------------------------------------------------------------------------
  // Glass
  // ---------------------------------------------------------------------------

  testWidgets('glass animated: mouse click registers an impulse', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kGlassThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) =>
              glassScaffoldBackground(context, child: const SizedBox.expand()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(200, 200));
    addTearDown(gesture.removePointer);
    await gesture.down(const Offset(200, 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(
      debugGlassImpulseCount,
      greaterThan(0),
      reason: 'mouse click must register an impulse in the glass wallpaper',
    );
  });

  testWidgets('glass static: click registers no impulse', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kGlassThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) => glassStaticScaffoldBackground(
            context,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(200, 200));
    addTearDown(gesture.removePointer);
    await gesture.down(const Offset(200, 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(
      debugGlassImpulseCount,
      equals(0),
      reason: 'static/reduced-effects path must not register impulses',
    );
  });

  // ---------------------------------------------------------------------------
  // Brutalist
  // ---------------------------------------------------------------------------

  testWidgets('brutalist animated: mouse click registers an impulse', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => brutalistScaffoldBackgroundAnimated(
            context,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(150, 150));
    addTearDown(gesture.removePointer);
    await gesture.down(const Offset(150, 150));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(
      debugBrutalistImpulseCount,
      greaterThan(0),
      reason: 'mouse click must register an impulse in the brutalist ambient',
    );
  });

  testWidgets('brutalist static: click registers no impulse', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => brutalistStaticScaffoldBackground(
            context,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(150, 150));
    addTearDown(gesture.removePointer);
    await gesture.down(const Offset(150, 150));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(
      debugBrutalistImpulseCount,
      equals(0),
      reason: 'static brutalist path must not register impulses',
    );
  });

  // ---------------------------------------------------------------------------
  // AURIS
  // ---------------------------------------------------------------------------

  testWidgets('auris animated: mouse click registers an impulse', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) => aurisScaffoldBackgroundAnimated(
            context,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(200, 200));
    addTearDown(gesture.removePointer);
    await gesture.down(const Offset(200, 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(
      debugAurisImpulseCount,
      greaterThan(0),
      reason: 'mouse click must register an impulse in the auris ambient',
    );
  });

  testWidgets('auris static: click registers no impulse', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) => aurisStaticScaffoldBackground(
            context,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(200, 200));
    addTearDown(gesture.removePointer);
    await gesture.down(const Offset(200, 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(
      debugAurisImpulseCount,
      equals(0),
      reason: 'static auris path must not register impulses',
    );
  });

  // ---------------------------------------------------------------------------
  // RPG
  // ---------------------------------------------------------------------------

  testWidgets('rpg animated: mouse click registers an impulse', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kRpgThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) =>
              rpgScaffoldBackground(context, child: const SizedBox.expand()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(200, 200));
    addTearDown(gesture.removePointer);
    await gesture.down(const Offset(200, 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(
      debugRpgImpulseCount,
      greaterThan(0),
      reason: 'mouse click must register an impulse in the rpg ambient',
    );
  });

  testWidgets('rpg static: click registers no impulse', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kRpgThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) => rpgStaticScaffoldBackground(
            context,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: const Offset(200, 200));
    addTearDown(gesture.removePointer);
    await gesture.down(const Offset(200, 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(
      debugRpgImpulseCount,
      equals(0),
      reason: 'static rpg path must not register impulses',
    );
  });
}
