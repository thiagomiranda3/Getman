import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required ValueChanged<String> onConfirm,
    String? initial,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => NamePromptDialog.show(
                context,
                title: 'NAME',
                initialText: initial,
                onConfirm: onConfirm,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirm is disabled while the field is empty', (tester) async {
    final confirmed = <String>[];
    await pump(tester, onConfirm: confirmed.add);

    final saveButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'SAVE'),
    );
    expect(saveButton.onPressed, isNull, reason: 'empty -> disabled');

    await tester.enterText(find.byType(TextField), 'My Folder');
    await tester.pump();
    final enabled = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'SAVE'),
    );
    expect(enabled.onPressed, isNotNull, reason: 'non-empty -> enabled');

    await tester.tap(find.widgetWithText(TextButton, 'SAVE'));
    await tester.pumpAndSettle();
    expect(confirmed, ['My Folder']);
  });

  testWidgets('whitespace-only input keeps confirm disabled', (tester) async {
    await pump(tester, onConfirm: (_) {});
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    final saveButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'SAVE'),
    );
    expect(saveButton.onPressed, isNull);
  });
}
