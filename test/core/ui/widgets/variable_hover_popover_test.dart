import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

Future<void> _pump(WidgetTester tester, ResolvedVariable data) {
  return tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme(kBrutalistThemeId)(
        Brightness.light,
        isCompact: false,
      ),
      home: Scaffold(
        body: Center(child: VariableHoverPopover(data: data)),
      ),
    ),
  );
}

void main() {
  testWidgets('resolved variable shows name, value, and source', (
    tester,
  ) async {
    await _pump(
      tester,
      const ResolvedVariable(
        name: 'base_url',
        kind: VariableValueKind.resolved,
        value: 'https://api.example.com',
        environmentName: 'Production',
      ),
    );
    expect(find.text('{{base_url}}'), findsOneWidget);
    expect(find.text('https://api.example.com'), findsOneWidget);
    expect(find.textContaining('Production'), findsOneWidget);
  });

  testWidgets('secret masks value until reveal is toggled', (tester) async {
    await _pump(
      tester,
      const ResolvedVariable(
        name: 'token',
        kind: VariableValueKind.secret,
        value: 'sk-123',
        environmentName: 'Production',
      ),
    );
    expect(find.text('sk-123'), findsNothing);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(find.text('sk-123'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('dynamic variable shows generated-per-request label', (
    tester,
  ) async {
    await _pump(
      tester,
      const ResolvedVariable(
        name: r'$timestamp',
        kind: VariableValueKind.dynamicValue,
        value: '1700000000',
        environmentName: 'Production',
      ),
    );
    expect(find.textContaining('Generated per request'), findsOneWidget);
    expect(find.text('1700000000'), findsOneWidget);
  });

  testWidgets('unresolved with no env shows no-active-environment', (
    tester,
  ) async {
    await _pump(
      tester,
      const ResolvedVariable(name: 'x', kind: VariableValueKind.unresolved),
    );
    expect(find.textContaining('No active environment'), findsOneWidget);
  });

  testWidgets('unresolved with env shows not-defined-in', (tester) async {
    await _pump(
      tester,
      const ResolvedVariable(
        name: 'x',
        kind: VariableValueKind.unresolved,
        environmentName: 'Production',
      ),
    );
    expect(find.textContaining('Not defined in'), findsOneWidget);
    expect(find.textContaining('Production'), findsOneWidget);
  });

  group('VariableHoverController', () {
    const data = ResolvedVariable(
      name: 'base_url',
      kind: VariableValueKind.resolved,
      value: 'https://api.example.com',
    );

    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme(kBrutalistThemeId)(
            Brightness.light,
            isCompact: false,
          ),
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      return ctx;
    }

    testWidgets('showFor inserts the popover; hideNow removes it', (
      tester,
    ) async {
      final controller = VariableHoverController();
      addTearDown(controller.dispose);
      final ctx = await pumpHost(tester);

      controller.showFor(ctx, data, const Offset(100, 100));
      await tester.pump();
      expect(find.byType(VariableHoverPopover), findsOneWidget);
      expect(find.text('{{base_url}}'), findsOneWidget);

      controller.hideNow();
      await tester.pump();
      expect(find.byType(VariableHoverPopover), findsNothing);
    });

    testWidgets('anchors below the pointer and clamps to the right edge', (
      tester,
    ) async {
      final controller = VariableHoverController();
      addTearDown(controller.dispose);
      final ctx = await pumpHost(tester);

      controller.showFor(ctx, data, const Offset(100, 50));
      await tester.pump();
      Positioned positionedCard() => tester.widget<Positioned>(
        find
            .ancestor(
              of: find.byType(VariableHoverPopover),
              matching: find.byType(Positioned),
            )
            .first,
      );
      expect(positionedCard().left, 100);
      expect(positionedCard().top, 68, reason: '18px below the pointer');

      // Far off the right edge: the 320-wide card + 4px gutter must stay
      // on-screen (test viewport is 800 logical px wide).
      controller.showFor(ctx, data, const Offset(10000, 50));
      await tester.pump();
      expect(find.byType(VariableHoverPopover), findsOneWidget);
      expect(positionedCard().left, 800 - 324);
    });

    testWidgets('re-anchoring replaces the entry — never two popovers', (
      tester,
    ) async {
      final controller = VariableHoverController();
      addTearDown(controller.dispose);
      final ctx = await pumpHost(tester);

      controller.showFor(ctx, data, const Offset(100, 100));
      await tester.pump();
      controller.showFor(
        ctx,
        const ResolvedVariable(
          name: 'token',
          kind: VariableValueKind.resolved,
          value: 't',
        ),
        const Offset(200, 200),
      );
      await tester.pump();

      expect(find.byType(VariableHoverPopover), findsOneWidget);
      expect(find.text('{{token}}'), findsOneWidget);
      expect(find.text('{{base_url}}'), findsNothing);
    });

    testWidgets('scheduleHide hides after the travel delay', (tester) async {
      final controller = VariableHoverController();
      addTearDown(controller.dispose);
      final ctx = await pumpHost(tester);

      controller.showFor(ctx, data, const Offset(100, 100));
      await tester.pump();
      controller.scheduleHide();

      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byType(VariableHoverPopover),
        findsOneWidget,
        reason: 'still visible inside the 120ms travel window',
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(VariableHoverPopover), findsNothing);
    });

    testWidgets('cancelHide keeps a scheduled hide from firing', (
      tester,
    ) async {
      final controller = VariableHoverController();
      addTearDown(controller.dispose);
      final ctx = await pumpHost(tester);

      controller.showFor(ctx, data, const Offset(100, 100));
      await tester.pump();
      controller
        ..scheduleHide()
        ..cancelHide();

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(VariableHoverPopover), findsOneWidget);
    });

    testWidgets(
      'pointer entering the card cancels the hide; leaving re-schedules it',
      (tester) async {
        final controller = VariableHoverController();
        addTearDown(controller.dispose);
        final ctx = await pumpHost(tester);

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: const Offset(700, 500));
        addTearDown(gesture.removePointer);
        await tester.pump();

        controller.showFor(ctx, data, const Offset(100, 100));
        await tester.pump();
        controller.scheduleHide();

        // Travel from the token into the card: onEnter must cancel the hide.
        await gesture.moveTo(
          tester.getCenter(find.byType(VariableHoverPopover)),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byType(VariableHoverPopover),
          findsOneWidget,
          reason: 'hovering the card must keep it open past the hide delay',
        );

        // Leaving the card re-schedules the hide.
        await gesture.moveTo(const Offset(700, 500));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(VariableHoverPopover), findsNothing);
      },
    );

    testWidgets('dispose removes a visible popover', (tester) async {
      final controller = VariableHoverController();
      final ctx = await pumpHost(tester);

      controller.showFor(ctx, data, const Offset(100, 100));
      await tester.pump();
      expect(find.byType(VariableHoverPopover), findsOneWidget);

      controller.dispose();
      await tester.pump();
      expect(find.byType(VariableHoverPopover), findsNothing);
    });
  });
}
