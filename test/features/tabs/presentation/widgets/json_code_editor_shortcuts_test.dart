import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/main.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  const builder = AppCodeShortcutsActivatorsBuilder();
  const defaults = DefaultCodeShortcutsActivatorsBuilder();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('drops re_editor save so the app Cmd/Ctrl+S save can fire', () {
    expect(builder.build(CodeShortcutType.save), isNull);
  });

  test('leaves unrelated shortcuts (copy) untouched', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      builder.build(CodeShortcutType.copy),
      equals(defaults.build(CodeShortcutType.copy)),
    );
  });

  group('Cmd/Ctrl+/ pass-through for the shortcuts cheat sheet (E1)', () {
    test(
      'CANARY: re_editor default DOES bind the chord to singleLineComment '
      '(if this fails after an upgrade, the strip below is obsolete)',
      () async {
        // re_editor's DefaultCodeShortcutsActivatorsBuilder picks its map
        // via a top-level `kIsMacOS` (re_editor's `_consts.dart`) that
        // memoizes on first read for the lifetime of the isolate — once any
        // earlier call in THIS isolate has resolved it (e.g. the `copy` test
        // above), flipping debugDefaultTargetPlatformOverride and calling
        // `defaults.build` again keeps returning the first-resolved
        // platform's map. Each platform check below runs in its own fresh
        // `Isolate.run`, which gets a pristine, correctly-resolved cache, so
        // both platforms are genuinely exercised.
        final macActivators = await Isolate.run(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          return const DefaultCodeShortcutsActivatorsBuilder().build(
            CodeShortcutType.singleLineComment,
          );
        });
        expect(
          macActivators,
          contains(
            const SingleActivator(LogicalKeyboardKey.slash, meta: true),
          ),
        );

        final winActivators = await Isolate.run(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          return const DefaultCodeShortcutsActivatorsBuilder().build(
            CodeShortcutType.singleLineComment,
          );
        });
        expect(
          winActivators,
          contains(
            const SingleActivator(LogicalKeyboardKey.slash, control: true),
          ),
        );
      },
    );

    test('drops singleLineComment so ShowShortcutsIntent can fire', () {
      expect(builder.build(CodeShortcutType.singleLineComment), isNull);
    });

    test('multiLineComment (Cmd/Ctrl+Shift+/) is untouched', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(
        builder.build(CodeShortcutType.multiLineComment),
        equals(defaults.build(CodeShortcutType.multiLineComment)),
      );
    });
  });

  group('Cmd/Ctrl+L pass-through for the URL bar (FocusUrlIntent)', () {
    test(
      'CANARY: re_editor default DOES bind the chord to lineSelect '
      '(if this fails after an upgrade, the strip below is obsolete)',
      () async {
        // Same per-isolate kIsMacOS memoization dance as the
        // singleLineComment canary above.
        final macActivators = await Isolate.run(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          return const DefaultCodeShortcutsActivatorsBuilder().build(
            CodeShortcutType.lineSelect,
          );
        });
        expect(
          macActivators,
          contains(const SingleActivator(LogicalKeyboardKey.keyL, meta: true)),
        );

        final winActivators = await Isolate.run(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          return const DefaultCodeShortcutsActivatorsBuilder().build(
            CodeShortcutType.lineSelect,
          );
        });
        expect(
          winActivators,
          contains(
            const SingleActivator(LogicalKeyboardKey.keyL, control: true),
          ),
        );
      },
    );

    test('drops lineSelect so FocusUrlIntent can fire', () {
      expect(builder.build(CodeShortcutType.lineSelect), isNull);
    });
  });

  group('newLine strips the platform send-request chord (Cmd/Ctrl+Enter)', () {
    test('macOS: Cmd+Enter is removed, plain Enter stays', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final activators = builder.build(CodeShortcutType.newLine)!;
      // Cmd+Enter must bubble up to the global SendRequestIntent.
      expect(
        activators,
        isNot(
          contains(const SingleActivator(LogicalKeyboardKey.enter, meta: true)),
        ),
      );
      // Plain Enter still inserts a newline in the editor.
      expect(
        activators,
        contains(const SingleActivator(LogicalKeyboardKey.enter)),
      );
      // Shift+Enter (a distinct newline chord) is untouched.
      expect(
        activators,
        contains(
          const SingleActivator(LogicalKeyboardKey.enter, shift: true),
        ),
      );
    });

    test('non-macOS: Ctrl+Enter is removed, plain Enter stays', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final activators = builder.build(CodeShortcutType.newLine)!;
      expect(
        activators,
        isNot(
          contains(
            const SingleActivator(LogicalKeyboardKey.enter, control: true),
          ),
        ),
      );
      expect(
        activators,
        contains(const SingleActivator(LogicalKeyboardKey.enter)),
      );
    });

    test(
      'macOS: Cmd+NumpadEnter is removed, plain/Shift numpad-Enter stay',
      () async {
        // Fresh isolate: kIsMacOS memoizes per isolate (see the CANARY
        // above), and earlier tests here may have resolved it to another
        // platform already.
        final activators = await Isolate.run(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          return const AppCodeShortcutsActivatorsBuilder().build(
            CodeShortcutType.newLine,
          );
        });
        // Cmd+NumpadEnter must bubble up to the global SendRequestIntent,
        // exactly like Cmd+Enter (re_editor lists both under newLine).
        expect(
          activators,
          isNot(
            contains(
              const SingleActivator(
                LogicalKeyboardKey.numpadEnter,
                meta: true,
              ),
            ),
          ),
        );
        // Unmodified / Shift-ed numpad-Enter still insert a newline.
        expect(
          activators,
          contains(const SingleActivator(LogicalKeyboardKey.numpadEnter)),
        );
        expect(
          activators,
          contains(
            const SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true),
          ),
        );
      },
    );

    test(
      'non-macOS: Ctrl+NumpadEnter is removed, plain numpad-Enter stays',
      () async {
        final activators = await Isolate.run(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          return const AppCodeShortcutsActivatorsBuilder().build(
            CodeShortcutType.newLine,
          );
        });
        expect(
          activators,
          isNot(
            contains(
              const SingleActivator(
                LogicalKeyboardKey.numpadEnter,
                control: true,
              ),
            ),
          ),
        );
        expect(
          activators,
          contains(const SingleActivator(LogicalKeyboardKey.numpadEnter)),
        );
      },
    );
  });

  group('collision guard against the app-level shortcut map', () {
    test(
      'no chord the editor keeps collides with buildAppShortcuts '
      '(catches re_editor upgrades re-introducing swallows)',
      () async {
        // App chords for BOTH platform conventions (⌘ and Ctrl). All current
        // entries are SingleActivators; any other shape is skipped for the
        // same reason as in _liveEditorChordSignatures.
        final appSignatures = <String>{
          for (final map in [
            buildAppShortcuts(useMeta: true),
            buildAppShortcuts(useMeta: false),
          ])
            for (final activator in map.keys)
              if (activator is SingleActivator) _signatureOf(activator),
        };

        // kIsMacOS memoizes per isolate (see the CANARY above), so each
        // platform's editor map must be collected in its own fresh isolate.
        final macChords = await Isolate.run(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          return _liveEditorChordSignatures();
        });
        final winChords = await Isolate.run(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          return _liveEditorChordSignatures();
        });

        final collisions = {
          ...macChords,
          ...winChords,
        }.intersection(appSignatures);
        expect(
          collisions,
          isEmpty,
          reason:
              'AppCodeShortcutsActivatorsBuilder must strip these chords so '
              'the app-level shortcut fires while a code editor has focus '
              '(a re_editor upgrade likely re-introduced them): $collisions',
        );
      },
    );
  });

  // End-to-end: with the editor focused, Cmd+Enter must reach the app's global
  // send shortcut (it used to be swallowed by re_editor as a newline), while
  // plain Enter must still insert a newline in the editor.
  Future<CodeLineEditingController> pumpEditorUnderSendShortcut(
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final controller = createJsonCodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('classic')(Brightness.light, isCompact: false),
        home: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter, meta: true):
                _SendIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
                _SendIntent(),
          },
          child: Actions(
            actions: {
              _SendIntent: CallbackAction<_SendIntent>(
                onInvoke: (_) {
                  _sendCount++;
                  return null;
                },
              ),
            },
            child: Scaffold(body: JsonCodeEditor(controller: controller)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Ensure the code editor holds focus before sending keys.
    await tester.tap(find.byType(JsonCodeEditor));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('Cmd+Enter in the editor fires the app send shortcut', (
    tester,
  ) async {
    _sendCount = 0;
    final controller = await pumpEditorUnderSendShortcut(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
    // Reset within the body: the testWidgets invariant check runs before
    // tearDown, and it forbids a leaked foundation debug override.
    debugDefaultTargetPlatformOverride = null;

    expect(_sendCount, 1, reason: 'send shortcut should fire from the editor');
    expect(
      controller.text,
      isEmpty,
      reason: 'Cmd+Enter must not insert a newline',
    );
  });

  testWidgets('Cmd+NumpadEnter in the editor fires the app send shortcut', (
    tester,
  ) async {
    _sendCount = 0;
    final controller = await pumpEditorUnderSendShortcut(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(_sendCount, 1, reason: 'send shortcut should fire from the editor');
    expect(
      controller.text,
      isEmpty,
      reason: 'Cmd+NumpadEnter must not insert a newline',
    );
  });

  testWidgets('plain Enter in the editor inserts a newline and does not send', (
    tester,
  ) async {
    _sendCount = 0;
    final controller = await pumpEditorUnderSendShortcut(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(_sendCount, 0, reason: 'plain Enter must not trigger send');
    expect(
      controller.text,
      contains('\n'),
      reason: 'plain Enter should still insert a newline',
    );
  });
}

int _sendCount = 0;

class _SendIntent extends Intent {
  const _SendIntent();
}

/// Signature on (trigger key + full modifier set) — [SingleActivator] has no
/// value equality, so chords are compared via this rendered string.
String _signatureOf(SingleActivator activator) =>
    '${activator.trigger.debugName ?? activator.trigger.keyId} '
    '(ctrl:${activator.control} meta:${activator.meta} '
    'shift:${activator.shift} alt:${activator.alt})';

/// Every [SingleActivator] chord [AppCodeShortcutsActivatorsBuilder] leaves
/// live for the CURRENT platform, as signatures. Non-SingleActivator shapes
/// are skipped: re_editor 0.9.0 uses SingleActivator exclusively, and other
/// shapes carry no single (trigger + modifier set) identity to compare on.
/// Top-level (not a closure) so [Isolate.run] can send it cleanly.
Set<String> _liveEditorChordSignatures() {
  const builder = AppCodeShortcutsActivatorsBuilder();
  return {
    for (final type in CodeShortcutType.values)
      for (final activator
          in builder.build(type) ?? const <ShortcutActivator>[])
        if (activator is SingleActivator) _signatureOf(activator),
  };
}
