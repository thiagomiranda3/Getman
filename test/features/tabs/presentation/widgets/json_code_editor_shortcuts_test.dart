import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
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
