import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/classic/classic_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/body_json_validation.dart';
import 'package:re_editor/re_editor.dart';

Widget _host(
  CodeLineEditingController controller, {
  bool enabled = true,
  bool offstage = false,
}) => MaterialApp(
  theme: classicTheme(Brightness.light),
  home: Scaffold(
    body: Offstage(
      offstage: offstage,
      child: TickerMode(
        enabled: !offstage,
        child: BodyJsonValidation(
          controller: controller,
          enabled: enabled,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  ),
);

void main() {
  final advisory = find.byKey(const ValueKey('body-json-validation-error'));

  testWidgets('initial malformed body is visible in the first frame', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('{');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    expect(advisory.hitTestable(), findsOneWidget);
    expect(find.textContaining('line 1, column 2'), findsOneWidget);
  });

  testWidgets('clears stale errors immediately and debounces replacement', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('{');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    controller.text = '[1,';
    await tester.pump();
    expect(advisory, findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(advisory.hitTestable(), findsOneWidget);
    controller.text = '[1]';
    await tester.pump();
    expect(advisory, findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(advisory, findsNothing);
  });

  testWidgets('caret moves retain error and click navigates to its location', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('{\n"a": ]\n}');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 1,
    );
    await tester.pump();
    expect(advisory.hitTestable(), findsOneWidget);
    await tester.tap(advisory);
    expect(controller.selection.extentIndex, 1);
    expect(controller.selection.extentOffset, 5);
    await tester.pump();
    expect(advisory.hitTestable(), findsOneWidget);
  });

  testWidgets('offstage edits are current on the first returning frame', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('{}');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpWidget(_host(controller, offstage: true));
    controller.text = '{';
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_host(controller));
    expect(advisory.hitTestable(), findsOneWidget);
  });

  testWidgets('controller swap and disable clear obsolete diagnostics', (
    tester,
  ) async {
    final old = CodeLineEditingController.fromText('{');
    final replacement = CodeLineEditingController.fromText('{}');
    addTearDown(old.dispose);
    addTearDown(replacement.dispose);
    await tester.pumpWidget(_host(old));
    old.text = '[';
    await tester.pumpWidget(_host(replacement));
    await tester.pump(const Duration(milliseconds: 300));
    expect(advisory, findsNothing);
    old.text = '{broken';
    await tester.pump();
    expect(advisory, findsNothing);
    replacement.text = '{';
    await tester.pump(const Duration(milliseconds: 300));
    expect(advisory.hitTestable(), findsOneWidget);
    await tester.pumpWidget(_host(replacement, enabled: false));
    expect(advisory, findsNothing);
    await tester.pumpWidget(_host(replacement));
    expect(advisory.hitTestable(), findsOneWidget);
  });

  testWidgets('error navigation expands a folded line', (tester) async {
    final controller = CodeLineEditingController.fromText(
      '{\n"outer": {\n"value": ]\n}\n}',
    );
    addTearDown(controller.dispose);
    controller.collapseChunk(1, 3);
    await tester.pumpWidget(_host(controller));
    await tester.tap(advisory);
    expect(controller.unfoldLineSelection.extentIndex, 2);
    expect(controller.selection.extentOffset, 9);
    expect(controller.lineIndex2Index(2).chunkIndex, -1);
    await tester.pump();
    expect(advisory.hitTestable(), findsOneWidget);
  });

  testWidgets('large background validation cannot restore an obsolete error', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText(
      '[${'0,' * 60000}]',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    expect(advisory, findsNothing);
    // A real compute task must finish before testing its invalidation path.
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (advisory.evaluate().isNotEmpty) return;
      }
    });
    expect(advisory.hitTestable(), findsOneWidget);
    // Start another large validation, then replace its controller before the
    // isolate can publish its result. The new document must stay valid.
    final replacement = CodeLineEditingController.fromText('{}');
    addTearDown(replacement.dispose);
    controller.text = '[${'1,' * 60000}]';
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_host(replacement));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(advisory, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose cancels pending validation', (tester) async {
    final controller = CodeLineEditingController.fromText('{}');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    controller.text = '{';
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
