// test/core/theme/themes/auris/auris_ambient_test.dart
//
// Task 12: the new AURIS HUD ambient (scanning grid + radar sweep), the C1/C2
// foundation. Pumped UNDER the AURIS theme so `AurisScheme` is present and the
// scheme-coloured HUD path is exercised (NOT the null-scheme graceful bail).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/auris/auris_ambient.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Harness for toggle-safety tests
//
// Drives `didUpdateWidget` on the SAME `_AurisAmbient` element by rebuilding a
// `_AnimateToggleHarness` with a new `animate` value. Because the harness
// renders the same widget type (`_AurisAmbient`, via the two public wrappers)
// at the same element slot Flutter diffs the tree and calls `didUpdateWidget`
// rather than unmounting+remounting — exactly the ticker-recreation crash path
// we guard against.
// ---------------------------------------------------------------------------
class _AnimateToggleHarness extends StatelessWidget {
  const _AnimateToggleHarness({required this.animate, required this.child});
  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) => animate
      ? aurisScaffoldBackgroundAnimated(context, child: child)
      : aurisStaticScaffoldBackground(context, child: child);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('animated auris ambient paints under AURIS theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) => aurisScaffoldBackgroundAnimated(
            context,
            child: const Text('app'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('app'), findsOneWidget);
    // The animated ambient paints a HUD layer (a CustomPaint with a painter)
    // behind the child — proves the ambient is mounted, not just the child.
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter != null,
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    // Survives teardown (controller/notifier disposal) with no exception.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('static auris ambient paints one frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) =>
              aurisStaticScaffoldBackground(context, child: const Text('app')),
        ),
      ),
    );
    // No pump beyond build: the static variant must render its single frame
    // immediately (no controller driving subsequent frames).
    expect(find.text('app'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter != null,
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  // -------------------------------------------------------------------------
  // Toggle-safety tests: regression net for the "multiple tickers" crash.
  // The controller is created ONCE in initState and started/stopped via
  // didUpdateWidget — never recreated. These tests drive that path by pumping
  // the SAME _AurisAmbient element with a flipped `animate` bool.
  // -------------------------------------------------------------------------

  testWidgets(
    'animate true→false→true round-trip: no ticker-recreation crash',
    (tester) async {
      // Start animated.
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: const _AnimateToggleHarness(
            animate: true,
            child: Text('app'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);

      // Flip to static (didUpdateWidget: animate=true→false).
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: const _AnimateToggleHarness(
            animate: false,
            child: Text('app'),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Flip back to animated (didUpdateWidget: animate=false→true).
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: const _AnimateToggleHarness(
            animate: true,
            child: Text('app'),
          ),
        ),
      );
      // Use a bounded pump — pumpAndSettle would loop forever because the
      // animated controller repeats indefinitely.
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'animate false→true→false round-trip: no ticker-recreation crash',
    (tester) async {
      // Start static.
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: const _AnimateToggleHarness(
            animate: false,
            child: Text('app'),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Flip to animated (didUpdateWidget: animate=false→true).
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: const _AnimateToggleHarness(
            animate: true,
            child: Text('app'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);

      // Flip back to static (didUpdateWidget: animate=true→false).
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
          home: const _AnimateToggleHarness(
            animate: false,
            child: Text('app'),
          ),
        ),
      );
      // Controller is stopped in this branch — a single pump is sufficient and
      // safe (no infinite animation to settle).
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
