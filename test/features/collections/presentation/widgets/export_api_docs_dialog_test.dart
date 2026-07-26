// test/features/collections/presentation/widgets/export_api_docs_dialog_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/widgets/export_api_docs_dialog.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockEnvironmentsBloc extends Mock implements EnvironmentsBloc {}

class _MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  const node = CollectionNodeEntity(
    id: 'r',
    name: 'My API',
    children: [
      CollectionNodeEntity(
        id: 'a',
        name: 'Ping',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'c',
          url: 'https://api.test.com/ping',
        ),
      ),
    ],
  );

  test('buildExport: OpenAPI JSON produces .openapi.json content', () {
    final out = buildExport(node, null, ExportDocFormat.openApiJson);
    expect(out.fileName, 'my_api.openapi.json');
    expect(out.ext, ['json']);
    expect(out.content.contains('"openapi": "3.0.3"'), isTrue);
  });

  test('buildExport: OpenAPI YAML produces .openapi.yaml content', () {
    final out = buildExport(node, null, ExportDocFormat.openApiYaml);
    expect(out.fileName, 'my_api.openapi.yaml');
    expect(out.ext, ['yaml']);
    expect(out.content.startsWith('openapi:'), isTrue);
  });

  test('buildExport: Markdown produces .md content', () {
    final out = buildExport(node, null, ExportDocFormat.markdown);
    expect(out.fileName, 'my_api.md');
    expect(out.ext, ['md']);
    expect(out.content.startsWith('# My API'), isTrue);
  });

  test('buildExport reports no warnings for a clean absolute URL', () {
    final out = buildExport(node, null, ExportDocFormat.openApiJson);
    expect(out.warnings, isEmpty);
  });

  test('buildExport surfaces a warning for an unresolvable server URL', () {
    final out = buildExport(
      const CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [
          CollectionNodeEntity(
            id: 'a',
            name: 'x',
            isFolder: false,
            config: HttpRequestConfigEntity(id: 'c', url: 'orphan/path'),
          ),
        ],
      ),
      null,
      ExportDocFormat.openApiJson,
    );
    expect(out.warnings, isNotEmpty);
    expect(out.warnings.first, contains('Could not determine'));
  });

  group('ExportApiDocsDialog widget', () {
    // The node's URL leads with a `{{base}}` template — the one server shape
    // CollectionToApiDoc resolves against an environment — so resolution is
    // observable in the exported content.
    const templatedNode = CollectionNodeEntity(
      id: 'r',
      name: 'My API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Ping',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'c',
            url: '{{base}}/ping',
          ),
        ),
      ],
    );
    final prodEnv = EnvironmentEntity(
      id: 'e1',
      name: 'Prod',
      variables: const {'base': 'https://api.test.com'},
    );

    late _MockEnvironmentsBloc envsBloc;
    late _MockSettingsBloc settingsBloc;
    late List<MethodCall> pickerCalls;

    setUp(() {
      envsBloc = _MockEnvironmentsBloc();
      settingsBloc = _MockSettingsBloc();
      when(() => envsBloc.state).thenReturn(
        EnvironmentsState(environments: [prodEnv]),
      );
      when(() => envsBloc.stream).thenAnswer((_) => const Stream.empty());
      when(() => settingsBloc.state).thenReturn(
        const SettingsState(
          settings: SettingsEntity(activeEnvironmentId: 'e1'),
        ),
      );
      when(() => settingsBloc.stream).thenAnswer((_) => const Stream.empty());
      pickerCalls = [];
    });

    /// Mocks file_picker's method channel: records every call and answers
    /// `null` ("user canceled the save panel") so no real file IO runs —
    /// the exported content is still observable via the `bytes` argument.
    void mockFilePickerChannel(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
        (call) async {
          pickerCalls.add(call);
          return null;
        },
      );
    }

    Future<void> openDialog(
      WidgetTester tester, {
      CollectionNodeEntity node = templatedNode,
    }) async {
      mockFilePickerChannel(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<EnvironmentsBloc>.value(value: envsBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => ExportApiDocsDialog.show(context, node),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    String savedContent() {
      final call = pickerCalls.singleWhere((c) => c.method == 'save');
      final args = call.arguments as Map<Object?, Object?>;
      return utf8.decode(args['bytes']! as Uint8List);
    }

    Map<Object?, Object?> savedArgs() {
      final call = pickerCalls.singleWhere((c) => c.method == 'save');
      return call.arguments as Map<Object?, Object?>;
    }

    DropdownButton<String?> envDropdown(WidgetTester tester) {
      return tester.widget<DropdownButton<String?>>(
        find.byKey(const ValueKey('export_env_dropdown')),
      );
    }

    testWidgets('seeds the environment dropdown from the active environment', (
      tester,
    ) async {
      await openDialog(tester);
      expect(envDropdown(tester).value, 'e1');
    });

    testWidgets('falls back to No Environment for an unknown active id', (
      tester,
    ) async {
      when(() => settingsBloc.state).thenReturn(
        const SettingsState(
          settings: SettingsEntity(activeEnvironmentId: 'gone'),
        ),
      );
      await openDialog(tester);
      expect(envDropdown(tester).value, isNull);
    });

    testWidgets(
      'EXPORT hands OpenAPI JSON to the save picker with env vars resolved',
      (tester) async {
        await openDialog(tester);
        await tester.tap(find.byKey(const ValueKey('export_confirm')));
        await tester.pumpAndSettle();

        final args = savedArgs();
        expect(args['fileName'], 'my_api.openapi.json');
        expect(args['allowedExtensions'], ['json']);
        final content = savedContent();
        expect(content, contains('"openapi": "3.0.3"'));
        expect(content, contains('api.test.com'));
        // The dialog pops after the export completes.
        expect(find.text('EXPORT AS API DOCS'), findsNothing);
      },
    );

    testWidgets('selecting No Environment leaves template vars unresolved', (
      tester,
    ) async {
      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('export_env_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No Environment').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('export_confirm')));
      await tester.pumpAndSettle();

      expect(savedContent(), isNot(contains('api.test.com')));
    });

    testWidgets('the Markdown radio exports a .md file', (tester) async {
      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('fmt_markdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export_confirm')));
      await tester.pumpAndSettle();

      final args = savedArgs();
      expect(args['fileName'], 'my_api.md');
      expect(args['allowedExtensions'], ['md']);
      expect(savedContent(), startsWith('# My API'));
    });

    testWidgets('the YAML radio exports a .openapi.yaml file', (tester) async {
      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('fmt_openapi_yaml')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export_confirm')));
      await tester.pumpAndSettle();

      expect(savedArgs()['fileName'], 'my_api.openapi.yaml');
      expect(savedContent(), startsWith('openapi:'));
    });

    testWidgets('export warnings surface in a snackbar after the save', (
      tester,
    ) async {
      const orphanNode = CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [
          CollectionNodeEntity(
            id: 'a',
            name: 'x',
            isFolder: false,
            config: HttpRequestConfigEntity(id: 'c', url: 'orphan/path'),
          ),
        ],
      );
      await openDialog(tester, node: orphanNode);
      await tester.tap(find.byKey(const ValueKey('export_confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not determine'), findsOneWidget);
    });

    testWidgets('CANCEL closes without touching the file picker', (
      tester,
    ) async {
      await openDialog(tester);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(find.text('EXPORT AS API DOCS'), findsNothing);
      expect(pickerCalls, isEmpty);
    });
  });
}
