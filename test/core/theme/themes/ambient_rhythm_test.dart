// test/core/theme/themes/ambient_rhythm_test.dart
//
// Verifies that each animated ambient painter subscribes to the provided
// [WorkspacePulseController], reads idleFactor, and unsubscribes on teardown.
//
// The [hasListeners] check is a TDD seam: the painters include [pulse] in their
// `repaint:` listenable only when [hasPulse] is true (i.e. a real provider is
// registered). If a painter ignores the pulse its [hasPulse] will be false and
// the pulse will not be in the merged listenable — [hasListeners] stays false
// and this test goes RED.
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

// Reset C2 debug sentinels before each test.
void _resetSentinels() {
  debugGlassLastIdleFactor = 0;
  debugBrutalistLastIdleFactor = 0;
  debugAurisLastIdleFactor = 0;
  debugRpgLastIdleFactor = 0;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(_resetSentinels);

  // ---------------------------------------------------------------------------
  // Glass
  // ---------------------------------------------------------------------------

  testWidgets(
    'glass animated: subscribes to pulse, idle sentinel active, unsubscribes',
    (tester) async {
      final pulse = WorkspacePulseController();
      await tester.pumpWidget(
        ChangeNotifierProvider<WorkspacePulseController>.value(
          value: pulse,
          child: MaterialApp(
            theme: appThemes[kGlassThemeId]!.builder(Brightness.dark),
            home: Builder(
              builder: (context) => glassScaffoldBackground(
                context,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Painter must have subscribed to the pulse via repaint:.
      expect(
        pulse.debugHasListeners,
        isTrue,
        reason: 'animated glass ambient must subscribe to the pulse for C2',
      );
      // Idle ticks must not throw (exercises idleFactor path in paint()).
      pulse
        ..tick()
        ..tick();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      // After ticks, idleFactor should be non-zero.
      expect(
        debugGlassLastIdleFactor,
        greaterThan(0.0),
        reason: 'paint() must read idleFactor from pulse after tick',
      );
      // Teardown: ambient unsubscribes when removed.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        pulse.debugHasListeners,
        isFalse,
        reason: 'ambient must unsubscribe when torn down',
      );
      pulse.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // Brutalist
  // ---------------------------------------------------------------------------

  testWidgets(
    'brutalist animated: subscribes to pulse, idle sentinel, unsubscribes',
    (tester) async {
      final pulse = WorkspacePulseController();
      await tester.pumpWidget(
        ChangeNotifierProvider<WorkspacePulseController>.value(
          value: pulse,
          child: MaterialApp(
            home: Builder(
              builder: (context) => brutalistScaffoldBackgroundAnimated(
                context,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        pulse.debugHasListeners,
        isTrue,
        reason: 'animated brutalist ambient must subscribe to the pulse for C2',
      );
      pulse
        ..tick()
        ..tick();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(
        debugBrutalistLastIdleFactor,
        greaterThan(0.0),
        reason: 'paint() must read idleFactor from pulse after tick',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        pulse.debugHasListeners,
        isFalse,
        reason: 'ambient must unsubscribe when torn down',
      );
      pulse.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // AURIS
  // ---------------------------------------------------------------------------

  testWidgets(
    'auris animated: subscribes to pulse, idle sentinel active, unsubscribes',
    (tester) async {
      final pulse = WorkspacePulseController();
      await tester.pumpWidget(
        ChangeNotifierProvider<WorkspacePulseController>.value(
          value: pulse,
          child: MaterialApp(
            theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
            home: Builder(
              builder: (context) => aurisScaffoldBackgroundAnimated(
                context,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        pulse.debugHasListeners,
        isTrue,
        reason: 'animated auris ambient must subscribe to the pulse for C2',
      );
      pulse
        ..tick()
        ..tick();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(
        debugAurisLastIdleFactor,
        greaterThan(0.0),
        reason: 'paint() must read idleFactor from pulse after tick',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        pulse.debugHasListeners,
        isFalse,
        reason: 'ambient must unsubscribe when torn down',
      );
      pulse.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // RPG
  // ---------------------------------------------------------------------------

  testWidgets(
    'rpg animated: subscribes to pulse, idle sentinel active, unsubscribes',
    (tester) async {
      final pulse = WorkspacePulseController();
      await tester.pumpWidget(
        ChangeNotifierProvider<WorkspacePulseController>.value(
          value: pulse,
          child: MaterialApp(
            theme: appThemes[kRpgThemeId]!.builder(Brightness.dark),
            home: Builder(
              builder: (context) => rpgScaffoldBackground(
                context,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        pulse.debugHasListeners,
        isTrue,
        reason: 'animated rpg ambient must subscribe to the pulse for C2',
      );
      pulse
        ..tick()
        ..tick();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(
        debugRpgLastIdleFactor,
        greaterThan(0.0),
        reason: 'paint() must read idleFactor from pulse after tick',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        pulse.debugHasListeners,
        isFalse,
        reason: 'ambient must unsubscribe when torn down',
      );
      pulse.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // Static / no-provider paths remain unaffected
  // ---------------------------------------------------------------------------

  testWidgets('glass static: no provider = no throw, no listeners', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
    // Deliberately no ChangeNotifierProvider — static path must be inert.
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
    expect(tester.takeException(), isNull);
    // External pulse never passed in — no listeners.
    expect(pulse.debugHasListeners, isFalse);
  });

  testWidgets('brutalist static: no provider = no throw, no listeners', (
    tester,
  ) async {
    final pulse = WorkspacePulseController();
    addTearDown(pulse.dispose);
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
    expect(tester.takeException(), isNull);
    expect(pulse.debugHasListeners, isFalse);
  });
}
