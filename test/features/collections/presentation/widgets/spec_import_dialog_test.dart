import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/presentation/widgets/spec_import_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/spec_import_preview.dart';
import 'package:mocktail/mocktail.dart';

class _MockNetworkService extends Mock implements NetworkService {}

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
  void Function(ImportResult) onImport, {
  NetworkService? networkService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => SpecImportDialog.show(
              context,
              networkService: networkService, // null: paste-only paths
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

  testWidgets('deselecting a single leaf prunes just that request', (
    tester,
  ) async {
    ImportResult? captured;
    await _open(tester, (r) => captured = r);
    await tester.tap(find.text('PASTE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, _spec);
    await tester.tap(find.widgetWithText(TextButton, 'PARSE'));
    await tester.pumpAndSettle();

    // Uncheck the 'List' request leaf (the only child of the Users folder).
    final listCheckbox = find.descendant(
      of: find.ancestor(of: find.text('List'), matching: find.byType(Row)),
      matching: find.byType(Checkbox),
    );
    await tester.tap(listCheckbox.first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'IMPORT'));
    await tester.pumpAndSettle();

    expect(captured!.root.children, hasLength(1));
    expect(captured!.root.children.single.name, 'Pets');
  });

  testWidgets('a malformed paste shows the error and disables IMPORT', (
    tester,
  ) async {
    await _open(tester, (_) {});
    await tester.tap(find.text('PASTE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'not a spec at all');
    await tester.tap(find.widgetWithText(TextButton, 'PARSE'));
    await tester.pumpAndSettle();

    expect(find.byType(SpecImportErrorText), findsOneWidget);
    final import = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'IMPORT'),
    );
    expect(import.onPressed, isNull);
  });

  testWidgets('LOAD ANOTHER resets back to the source input', (tester) async {
    // Minified: the paste controller keeps its text across the reset, and a
    // multi-line spec would re-render the paste editor at maxLines (12) —
    // overflowing the 600px test surface (see the layout note in the report).
    final oneLineSpec = _spec.replaceAll('\n', ' ');
    await _open(tester, (_) {});
    await tester.tap(find.text('PASTE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, oneLineSpec);
    await tester.tap(find.widgetWithText(TextButton, 'PARSE'));
    await tester.pumpAndSettle();
    expect(find.text('LOAD ANOTHER'), findsOneWidget);

    await tester.tap(find.text('LOAD ANOTHER'));
    await tester.pumpAndSettle();

    // Back on step 1: the source input is shown, the preview is gone and
    // IMPORT is disabled again.
    expect(find.widgetWithText(TextButton, 'PARSE'), findsOneWidget);
    expect(find.text('Users'), findsNothing);
    final import = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'IMPORT'),
    );
    expect(import.onPressed, isNull);
  });

  group('URL source', () {
    testWidgets('FETCH parses the fetched spec into the preview', (
      tester,
    ) async {
      final service = _MockNetworkService();
      when(
        () => service.request(
          url: any(named: 'url'),
          method: any(named: 'method'),
        ),
      ).thenAnswer(
        (_) async => const HttpResponseEntity(
          statusCode: 200,
          body: _spec,
          headers: {},
          durationMs: 5,
        ),
      );

      await _open(tester, (_) {}, networkService: service);
      await tester.tap(find.text('URL'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/openapi.json',
      );
      await tester.tap(find.widgetWithText(TextButton, 'FETCH'));
      await tester.pumpAndSettle();

      verify(
        () => service.request(
          url: 'https://example.com/openapi.json',
          method: 'GET',
        ),
      ).called(1);
      expect(find.text('Users'), findsOneWidget);
    });

    testWidgets('a failed fetch surfaces a Fetch failed error', (
      tester,
    ) async {
      final service = _MockNetworkService();
      when(
        () => service.request(
          url: any(named: 'url'),
          method: any(named: 'method'),
        ),
      ).thenThrow(Exception('offline'));

      await _open(tester, (_) {}, networkService: service);
      await tester.tap(find.text('URL'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'https://x.dev/s');
      await tester.tap(find.widgetWithText(TextButton, 'FETCH'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fetch failed'), findsOneWidget);
    });

    testWidgets('FETCH with an empty URL asks for one', (tester) async {
      await _open(tester, (_) {}, networkService: _MockNetworkService());
      await tester.tap(find.text('URL'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'FETCH'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a URL to fetch.'), findsOneWidget);
    });

    testWidgets('FETCH without a network service reports unavailable', (
      tester,
    ) async {
      await _open(tester, (_) {});
      await tester.tap(find.text('URL'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'FETCH'));
      await tester.pumpAndSettle();

      expect(find.text('Remote fetch is unavailable.'), findsOneWidget);
    });
  });
}
