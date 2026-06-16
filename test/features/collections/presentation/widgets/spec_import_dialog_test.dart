import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/presentation/widgets/spec_import_dialog.dart';

const _spec = '''
{
  "openapi": "3.0.0",
  "info": {"title": "Demo"},
  "servers": [{"url": "https://api.example.com"}],
  "paths": {
    "/users": {"get": {"summary": "List", "tags": ["Users"]}},
    "/pets": {"get": {"summary": "Pets", "tags": ["Pets"]}}
  }
}
''';

Future<void> _open(
  WidgetTester tester,
  void Function(ImportResult) onImport,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => SpecImportDialog.show(
              context,
              networkService: null, // paste path doesn't touch the network
              onImport: onImport,
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

void main() {
  testWidgets('paste → preview lists folders, import fires callback', (
    tester,
  ) async {
    ImportResult? captured;
    await _open(tester, (r) => captured = r);

    // Switch to the Paste tab and enter the spec.
    await tester.tap(find.text('PASTE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, _spec);
    await tester.tap(find.widgetWithText(TextButton, 'PARSE'));
    await tester.pumpAndSettle();

    // Preview shows both folders. (In this fixture the `/pets` operation's
    // summary is also "Pets", so it appears once as the folder name and once
    // as the request-leaf name — hence findsWidgets, not findsOneWidget.)
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Pets'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'IMPORT'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.root.name, 'Demo');
    expect(captured!.root.children, hasLength(2));
    expect(captured!.environments, hasLength(1));
  });

  testWidgets('deselecting a folder excludes it from the import', (
    tester,
  ) async {
    ImportResult? captured;
    await _open(tester, (r) => captured = r);
    await tester.tap(find.text('PASTE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, _spec);
    await tester.tap(find.widgetWithText(TextButton, 'PARSE'));
    await tester.pumpAndSettle();

    // Uncheck the "Pets" folder checkbox.
    final petsCheckbox = find.descendant(
      of: find.ancestor(
        of: find.text('Pets'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Checkbox),
    );
    await tester.tap(petsCheckbox.first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'IMPORT'));
    await tester.pumpAndSettle();

    expect(captured!.root.children, hasLength(1));
    expect(captured!.root.children.single.name, 'Users');
  });
}
