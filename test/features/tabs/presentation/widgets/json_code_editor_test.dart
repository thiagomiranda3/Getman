import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/auris/auris_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/response/large_body_find_view.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets(
    'find searches beyond the preview and restores complete editing',
    (
      tester,
    ) async {
      final text = '${'a' * (maxRenderedLineChars + 1000)} needle';
      final controller = createJsonCodeController()..text = text;
      final finder = CodeFindController(controller);
      addTearDown(finder.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: aurisTheme(Brightness.light),
          home: Scaffold(
            body: JsonCodeEditor(
              controller: controller,
              findController: finder,
              autofocus: false,
            ),
          ),
        ),
      );
      finder.findMode();
      await tester.pump();
      expect(find.byType(LargeBodyFindView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('large_find_field')).hitTestable(),
        findsOneWidget,
      );
      // No re_editor viewport may remain to lay out the unbounded line.
      expect(find.byType(CodeEditor), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('large_find_field')),
        'needle',
      );
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 500 && find.text('1/1').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('1/1'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('large_find_window_text')),
            )
            .textSpan!
            .toPlainText(),
        contains('needle'),
      );
      expect(controller.text, text);
      await tester.tap(find.byKey(const ValueKey('large_find_close')));
      await tester.pump();
      expect(find.byType(CodeEditor), findsOneWidget);
      controller.selectAll();
      expect(controller.selectedText, text);
      // An enormous selection must not become a huge find TextField.
      finder.findMode();
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('large_find_field')))
            .controller!
            .text,
        isEmpty,
      );
      // Model replacement while find is open must show the new document.
      controller.text = 'replacement';
      await tester.pump();
      expect(find.byType(CodeEditor), findsOneWidget);
      expect(controller.text, 'replacement');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('render budget preserves the complete editable document', (
    tester,
  ) async {
    // docs/PERFORMANCE.md records the unbounded-line layout stall. The
    // rendering budget must never become a request-content limit.
    final text = 'a' * (maxRenderedLineChars + 1000);
    final controller = createJsonCodeController()..text = text;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: aurisTheme(Brightness.light),
        home: Scaffold(
          body: JsonCodeEditor(controller: controller, autofocus: false),
        ),
      ),
    );
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.maxLengthSingleLineRendering, maxRenderedLineChars);
    expect(controller.text, text);
    controller.selectAll();
    expect(controller.selectedText, text);
  });

  testWidgets(
    'cursor color uses colorScheme.primary, visible in AURIS dark',
    (tester) async {
      final controller = createJsonCodeController();
      addTearDown(controller.dispose);

      final theme = aurisTheme(Brightness.dark);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: JsonCodeEditor(controller: controller, autofocus: false),
          ),
        ),
      );

      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      // Regression: previously used theme.primaryColor, which in AURIS dark is
      // the near-black surface default (the kit never sets primaryColor), so
      // the caret vanished against the dark code background.
      // colorScheme.primary is the real (bright) brand accent.
      expect(editor.style!.cursorColor, theme.colorScheme.primary);
      expect(editor.style!.cursorColor, isNot(theme.primaryColor));
    },
  );
}
