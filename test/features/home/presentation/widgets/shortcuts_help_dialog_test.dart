// Widget tests for ShortcutsHelpDialog: Cmd+/ opens it (via a verbatim copy
// of MainScreen's ShowShortcutsIntent action — same convention as
// main_screen_actions_test.dart), it renders the shared table under the
// KEYBOARD SHORTCUTS title, Esc closes it, and Cmd+/ pressed again closes
// it (the root Shortcuts map reaches into the dialog; its local Actions
// pops — the toggle needs no shared state).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/shortcut_reference_table.dart';
import 'package:getman/features/home/presentation/widgets/shortcuts_help_dialog.dart';
import 'package:getman/main.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  await tester.pumpWidget(
    Shortcuts(
      shortcuts: buildAppShortcuts(useMeta: true),
      child: MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Builder(
          builder: (context) => Actions(
            actions: <Type, Action<Intent>>{
              // Verbatim copy of MainScreen's OPEN action.
              ShowShortcutsIntent: CallbackAction<ShowShortcutsIntent>(
                onInvoke: (_) {
                  unawaited(ShortcutsHelpDialog.show(context));
                  return null;
                },
              ),
            },
            child: const Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pressCmdSlash(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.slash);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('Cmd+/ opens the dialog rendering the shared table', (
    tester,
  ) async {
    await _pumpShell(tester);
    await _pressCmdSlash(tester);

    expect(find.text('KEYBOARD SHORTCUTS'), findsOneWidget);
    expect(find.byType(ShortcutReferenceTable), findsOneWidget);

    // Reset within the body: the testWidgets invariant check runs before
    // tearDown, and it forbids a leaked foundation debug override.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Esc closes the dialog', (tester) async {
    await _pumpShell(tester);
    await _pressCmdSlash(tester);
    expect(find.text('KEYBOARD SHORTCUTS'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('KEYBOARD SHORTCUTS'), findsNothing);

    // Reset within the body: the testWidgets invariant check runs before
    // tearDown, and it forbids a leaked foundation debug override.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Cmd+/ pressed again closes the dialog (toggle)', (
    tester,
  ) async {
    await _pumpShell(tester);
    await _pressCmdSlash(tester);
    expect(find.text('KEYBOARD SHORTCUTS'), findsOneWidget);

    await _pressCmdSlash(tester);
    expect(find.text('KEYBOARD SHORTCUTS'), findsNothing);

    // And a third press re-opens: focus returned to the shell.
    await _pressCmdSlash(tester);
    expect(find.text('KEYBOARD SHORTCUTS'), findsOneWidget);

    // Reset within the body: the testWidgets invariant check runs before
    // tearDown, and it forbids a leaked foundation debug override.
    debugDefaultTargetPlatformOverride = null;
  });
}
