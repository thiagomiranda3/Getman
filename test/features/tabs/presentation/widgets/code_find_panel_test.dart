import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/classic/classic_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart';
import 'package:re_editor/re_editor.dart';

/// Pumps [CodeFindPanel] over a real [CodeFindController] and returns the
/// controller so the test can inspect the search-driving `findInputController`.
Future<CodeFindController> _pumpPanel(WidgetTester tester) async {
  final editing = CodeLineEditingController();
  addTearDown(editing.dispose);
  // A document big enough that, without debounce, a single-character search
  // would enumerate a huge number of matches (the slow path we are fixing).
  editing.text = List.generate(4000, (i) => '"row_$i": "value $i",').join('\n');
  final findCtrl = CodeFindController(editing);
  addTearDown(findCtrl.dispose);
  // Open the find UI (value becomes non-null so the panel renders).
  findCtrl.findMode();

  await tester.pumpWidget(
    MaterialApp(
      theme: classicTheme(Brightness.light),
      home: Scaffold(
        appBar: CodeFindPanel(controller: findCtrl, readOnly: true),
        body: const SizedBox(),
      ),
    ),
  );
  await tester.pump();
  return findCtrl;
}

void main() {
  testWidgets(
    'typing does not drive a search on every keystroke — it is debounced',
    (tester) async {
      final findCtrl = await _pumpPanel(tester);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      // Simulate fast typing: the search-driving controller must NOT update
      // synchronously with each keystroke (that is the O(matches×lines)
      // explosion when an early character like "r" matches thousands of times).
      await tester.enterText(field, 'r');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.enterText(field, 'ra');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.enterText(field, 'rai');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.enterText(field, 'raio');
      await tester.pump(const Duration(milliseconds: 20));

      // No debounce window has elapsed → the search has not been kicked off
      // for any intermediate (high-match) prefix.
      expect(
        findCtrl.findInputController.text,
        isEmpty,
        reason: 'search should not fire while the user is still typing',
      );

      // After the user pauses, exactly the final query drives the search.
      await tester.pump(const Duration(milliseconds: 400));
      expect(findCtrl.findInputController.text, 'raio');
    },
  );

  testWidgets('a progress indicator is shown while a search is pending', (
    tester,
  ) async {
    await _pumpPanel(tester);

    // Idle: no progress indicator.
    expect(find.byKey(const ValueKey('find_searching')), findsNothing);

    await tester.enterText(find.byType(TextField), 'value');
    await tester.pump(const Duration(milliseconds: 20));

    // While the (debounced) search is pending, the user gets feedback that a
    // search is happening — the gap the bug report called out.
    expect(find.byKey(const ValueKey('find_searching')), findsOneWidget);
  });

  testWidgets(
    'a query prefilled from the editor selection mounts fully selected, so '
    'pasting the same text replaces it instead of duplicating it',
    (tester) async {
      final editing = CodeLineEditingController();
      addTearDown(editing.dispose);
      editing
        ..text = 'alpha beta gamma'
        // Select "beta" — a same-line selection is what findMode auto-fills.
        ..selection = const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 6,
          extentIndex: 0,
          extentOffset: 10,
        );
      final findCtrl = CodeFindController(editing);
      addTearDown(findCtrl.dispose);
      // Prefill happens BEFORE the panel mounts (the initState mirror path).
      findCtrl.findMode();

      await tester.pumpWidget(
        MaterialApp(
          theme: classicTheme(Brightness.light),
          home: Scaffold(
            appBar: CodeFindPanel(controller: findCtrl, readOnly: true),
            body: const SizedBox(),
          ),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'beta');
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
        reason:
            'the prefilled query must be fully selected so Cmd+V replaces it',
      );
    },
  );

  testWidgets(
    're-opening find over a new editor selection re-fills the visible field '
    'with the text fully selected (the mounted-panel mirror path)',
    (tester) async {
      final editing = CodeLineEditingController();
      addTearDown(editing.dispose);
      editing.text = 'alpha beta gamma';
      final findCtrl = CodeFindController(editing);
      addTearDown(findCtrl.dispose);
      // Open with no editor selection: nothing prefilled.
      findCtrl.findMode();

      await tester.pumpWidget(
        MaterialApp(
          theme: classicTheme(Brightness.light),
          home: Scaffold(
            appBar: CodeFindPanel(controller: findCtrl, readOnly: true),
            body: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      // Select "gamma" in the editor and hit find again — the finder's
      // external write must mirror into the visible field fully selected.
      editing.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 11,
        extentIndex: 0,
        extentOffset: 16,
      );
      findCtrl.findMode();
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'gamma');
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
    },
  );

  testWidgets(
    'Enter steps to the next match repeatedly; Shift+Enter steps back',
    (tester) async {
      await tester.runAsync(() async {
        final editing = CodeLineEditingController();
        addTearDown(editing.dispose);
        // 40 distinct matches so a few steps never wrap.
        editing.text = List.generate(40, (i) => 'line $i token_zz here').join(
          '\n',
        );
        final findCtrl = CodeFindController(editing);
        addTearDown(findCtrl.dispose);
        findCtrl.findMode();

        await tester.pumpWidget(
          MaterialApp(
            theme: classicTheme(Brightness.light),
            home: Scaffold(
              appBar: CodeFindPanel(controller: findCtrl, readOnly: true),
              body: const SizedBox(),
            ),
          ),
        );
        await tester.pump();

        // Run the search and wait for the real (isolate) result to land.
        await tester.enterText(find.byType(TextField), 'token_zz');
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          final r = findCtrl.value?.result;
          if (r != null &&
              r.option.pattern == 'token_zz' &&
              r.matches.isNotEmpty) {
            break;
          }
        }
        final result = findCtrl.value!.result!;
        expect(result.matches.length, 40);
        final n = result.matches.length;
        final i0 = result.index;

        // Hold focus on the find field so key events route to the panel.
        findCtrl.findInputFocusNode.requestFocus();
        await tester.pump();

        Future<void> enter({bool shift = false}) async {
          if (shift) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.sendKeyEvent(
            LogicalKeyboardKey.enter,
            platform: 'macos',
          );
          if (shift) {
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.pump();
        }

        await enter();
        expect(findCtrl.value!.result!.index, (i0 + 1) % n);

        // The reported bug: the SECOND Enter did nothing — it must advance too.
        await enter();
        expect(findCtrl.value!.result!.index, (i0 + 2) % n);

        // Shift+Enter goes one match back.
        await enter(shift: true);
        expect(findCtrl.value!.result!.index, (i0 + 1) % n);
      });
    },
  );
}
