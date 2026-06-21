// Widget tests for CodeExportDialog: target selection updates generated code,
// all targets appear in dropdown, and CLOSE dismisses the dialog.
// Pure StatefulWidget with no bloc dependency.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/utils/code_gen_service.dart';
import 'package:getman/features/tabs/presentation/widgets/code_export_dialog.dart';

const _config = HttpRequestConfigEntity(
  id: 'export-test',
  url: 'https://example.com/api',
);

Widget _buildDirect() {
  return MaterialApp(
    theme: brutalistTheme(Brightness.light),
    home: const Scaffold(
      body: CodeExportDialog(config: _config),
    ),
  );
}

void main() {
  testWidgets(
    'renders generated_code_text and all CodeGenTarget items in dropdown',
    (
      tester,
    ) async {
      await tester.pumpWidget(_buildDirect());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('generated_code_text')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('code_gen_target_dropdown')),
        findsOneWidget,
      );

      // Open the dropdown.
      await tester.tap(find.byKey(const ValueKey('code_gen_target_dropdown')));
      await tester.pumpAndSettle();

      for (final target in CodeGenTarget.values) {
        expect(find.text(target.label), findsWidgets);
      }
    },
  );

  testWidgets('selecting a different target updates the generated code', (
    tester,
  ) async {
    await tester.pumpWidget(_buildDirect());
    await tester.pumpAndSettle();

    // Capture initial code (cURL is default).
    final initialText =
        (tester.widget(find.byKey(const ValueKey('generated_code_text')))
                as SelectableText)
            .data!;

    // Switch to Python.
    await tester.tap(find.byKey(const ValueKey('code_gen_target_dropdown')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Python — requests').last);
    await tester.pumpAndSettle();

    final updatedText =
        (tester.widget(find.byKey(const ValueKey('generated_code_text')))
                as SelectableText)
            .data!;

    expect(updatedText, isNot(equals(initialText)));
  });

  testWidgets('CLOSE button dismisses the dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => CodeExportDialog.show(ctx, _config),
            child: const Text('OPEN'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.text('GENERATE CODE'), findsOneWidget);

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    expect(find.text('GENERATE CODE'), findsNothing);
  });

  testWidgets('no overflow', (tester) async {
    await tester.pumpWidget(_buildDirect());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
