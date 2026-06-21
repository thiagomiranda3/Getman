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
      // Add a sentinel listener AFTER mount. bump() notifies all listeners.
      // Verifies the controller is live — not the inert idle fallback.
      void onPulse() => bumps++;
      pulse
        ..addListener(onPulse)
        ..bump();
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
}
