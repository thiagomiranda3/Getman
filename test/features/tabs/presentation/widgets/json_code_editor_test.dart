import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/auris/auris_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';

void main() {
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
