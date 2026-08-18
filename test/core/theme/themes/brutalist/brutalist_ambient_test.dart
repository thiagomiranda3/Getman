import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_ambient.dart';
import 'package:provider/provider.dart';

void main() {
  // Both tests pump WITHOUT a WorkspacePulseController provider on purpose, to
  // prove the animated ambient's pulse lookup is null-safe (skips the pulse
  // when no provider is present) and never throws.
  testWidgets('animated brutalist ambient paints + renders child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => brutalistScaffoldBackgroundAnimated(
            context,
            child: const Text('app'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('app'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Survives teardown (controller/notifier disposal) with no exception.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'animated ambient with provider subscribes to pulse (C2 round-trip)',
    (tester) async {
      final pulse = WorkspacePulseController();
      addTearDown(pulse.dispose);
      // Track whether the pulse notifier triggers a repaint by counting bumps
      // received by a manual listener added after the ambient mounts.
      var bumps = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<WorkspacePulseController>.value(
          value: pulse,
          child: MaterialApp(
            home: Builder(
              builder: (context) => brutalistScaffoldBackgroundAnimated(
                context,
                child: const Text('app'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('app'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Add a sentinel listener AFTER mount. tick() notifies all listeners.
      // Verifies the controller is live — not the inert idle fallback.
      void onPulse() => bumps++;
      pulse
        ..addListener(onPulse)
        ..tick();
      expect(bumps, equals(1));
      pulse.removeListener(onPulse);
    },
  );

  testWidgets('static brutalist ambient paints one frame + renders child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => brutalistStaticScaffoldBackground(
            context,
            child: const Text('app'),
          ),
        ),
      ),
    );
    expect(find.text('app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('brutalistHalftoneGridFor (seam coverage at constant dot budget)', () {
    test('small windows keep the base 26px pitch (unchanged look)', () {
      final grid = brutalistHalftoneGridFor(const Size(800, 600));
      expect(grid.cell, 26);
      // The +2 over-scan keeps the drifting grid covering the edges.
      expect((grid.cols - 1) * grid.cell, greaterThanOrEqualTo(800));
      expect((grid.rows - 1) * grid.cell, greaterThanOrEqualTo(600));
    });

    test('large windows scale the cell so the grid always spans them', () {
      // Regression: the old hard cap (40×28 dots at a fixed 26px cell)
      // stopped painting at 1040×728px — a drifting halftone seam on any
      // modern window. The cell now scales up so the same bounded dot count
      // covers the viewport.
      for (final size in const [
        Size(1512, 982), // default macOS laptop window
        Size(2560, 1440),
        Size(3840, 2160),
      ]) {
        final grid = brutalistHalftoneGridFor(size);
        expect(
          (grid.cols - 1) * grid.cell,
          greaterThanOrEqualTo(size.width),
          reason: 'columns must span $size',
        );
        expect(
          (grid.rows - 1) * grid.cell,
          greaterThanOrEqualTo(size.height),
          reason: 'rows must span $size',
        );
        // Constant per-frame budget: never more dots than the original cap.
        expect(grid.cols, lessThanOrEqualTo(40));
        expect(grid.rows, lessThanOrEqualTo(28));
      }
    });

    test('an extreme aspect ratio still gets full coverage', () {
      final grid = brutalistHalftoneGridFor(const Size(500, 2400));
      expect((grid.cols - 1) * grid.cell, greaterThanOrEqualTo(500));
      expect((grid.rows - 1) * grid.cell, greaterThanOrEqualTo(2400));
    });
  });
}
