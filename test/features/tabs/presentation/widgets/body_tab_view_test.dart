// Widget tests for BodyTabView: the body-type selector switches the active
// editor and form rows round-trip into config.formFields; the NONE hint,
// the BINARY file picker (mocked platform channel), and the RAW beautify
// button (both format and no-op outcomes).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/navigation/shortcut_catalog.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/body_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart';
import 'package:getman/features/tabs/presentation/widgets/form_data_editor.dart';
import 'package:mocktail/mocktail.dart';
import 'package:re_editor/re_editor.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class _MockGetEnvironmentsUseCase extends Mock
    implements GetEnvironmentsUseCase {}

class _MockSaveEnvironmentsUseCase extends Mock
    implements SaveEnvironmentsUseCase {}

class _MockPutEnvironmentUseCase extends Mock
    implements PutEnvironmentUseCase {}

class _MockDeleteEnvironmentUseCase extends Mock
    implements DeleteEnvironmentUseCase {}

class _MockGetCollectionsUseCase extends Mock
    implements GetCollectionsUseCase {}

class _MockSaveCollectionsUseCase extends Mock
    implements SaveCollectionsUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

// Minimal SettingsBloc with no active environment (no env/collection vars;
// dynamic built-ins remain suggestable, so fields still wire autocomplete).
SettingsBloc _settingsBloc() {
  final save = _MockSaveSettingsUseCase();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity(),
  );
}

// Minimal EnvironmentsBloc with no environments.
EnvironmentsBloc _environmentsBloc() {
  final get = _MockGetEnvironmentsUseCase();
  when(get.call).thenAnswer((_) async => const []);
  return EnvironmentsBloc(
    getEnvironmentsUseCase: get,
    saveEnvironmentsUseCase: _MockSaveEnvironmentsUseCase(),
    putEnvironmentUseCase: _MockPutEnvironmentUseCase(),
    deleteEnvironmentUseCase: _MockDeleteEnvironmentUseCase(),
  );
}

// Minimal CollectionsBloc with no collections.
CollectionsBloc _collectionsBloc() {
  final get = _MockGetCollectionsUseCase();
  when(get.call).thenAnswer((_) async => const <CollectionNodeEntity>[]);
  return CollectionsBloc(
    getCollectionsUseCase: get,
    saveCollectionsUseCase: _MockSaveCollectionsUseCase(),
  );
}

Future<TabsBloc> _loadedBloc(
  MockTabsRepository repository,
  MockSendRequestUseCase useCase,
  HttpRequestTabEntity tab,
) async {
  when(() => repository.getPanels()).thenAnswer(
    (_) async => [
      PanelEntity(
        id: 'p1',
        name: 'Panel 1',
        tabs: [tab],
        activeTabId: tab.tabId,
      ),
    ],
  );
  when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
  final bloc = TabsBloc(repository: repository, sendRequestUseCase: useCase)
    ..add(const LoadTabs());
  await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  return bloc;
}

Future<CodeLineEditingController> _pump(
  WidgetTester tester,
  TabsBloc bloc,
  String tabId,
) async {
  final controller = CodeLineEditingController();
  final variablesController = CodeLineEditingController();
  addTearDown(variablesController.dispose);
  // TabVariableContextBuilder (used by FormDataEditor + the body editor)
  // requires all four blocs. Build eagerly — when() stubs must not run inside
  // pumpWidget callbacks. Close via addTearDown so handlers don't outlive it.
  final settingsBloc = _settingsBloc();
  addTearDown(settingsBloc.close);
  final environmentsBloc = _environmentsBloc();
  addTearDown(environmentsBloc.close);
  final collectionsBloc = _collectionsBloc();
  addTearDown(collectionsBloc.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<EnvironmentsBloc>.value(value: environmentsBloc),
            BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
          ],
          child: BodyTabView(
            tabId: tabId,
            controller: controller,
            variablesController: variablesController,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    // Required by _settingsBloc() → when(() => save(any())) where save takes
    // a SettingsEntity; mocktail needs a fallback for sound null safety.
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.deletePanels(any())).thenAnswer((_) async {});
    when(
      () => repository.savePanelMeta(any(), any()),
    ).thenAnswer((_) async {});
  });

  HttpRequestTabEntity tab(
    BodyType type, {
    List<MultipartFieldEntity> fields = const [],
    String? bodyFilePath,
  }) => HttpRequestTabEntity(
    tabId: 't',
    config: HttpRequestConfigEntity(
      id: 't',
      bodyType: type,
      formFields: fields,
      bodyFilePath: bodyFilePath,
    ),
  );

  /// Stubs file_picker's platform channel so tapping CHOOSE FILE resolves to
  /// [files] (each map needs at least name/path/size) — null means the user
  /// cancelled the native dialog.
  void mockFilePickerChannel(
    WidgetTester tester,
    List<Map<String, Object?>>? files,
  ) {
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => files,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
  }

  testWidgets('defaults to RAW with the JSON code editor', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.raw),
    );
    addTearDown(bloc.close);

    final controller = await _pump(tester, bloc, 't');
    addTearDown(controller.dispose);

    expect(find.text('RAW'), findsOneWidget);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.byType(FormDataEditor), findsNothing);
  });

  testWidgets('tapping FORM switches the body type and shows FormDataEditor', (
    tester,
  ) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.raw),
    );
    addTearDown(bloc.close);

    final controller = await _pump(tester, bloc, 't');
    addTearDown(controller.dispose);

    await tester.tap(find.text('FORM'));
    await tester.pumpAndSettle();

    expect(bloc.state.tabs.byId('t')!.config.bodyType, BodyType.urlencoded);
    expect(find.byType(FormDataEditor), findsOneWidget);
    expect(find.byType(CodeEditor), findsNothing);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('urlencoded form rows round-trip into config.formFields', (
    tester,
  ) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.urlencoded),
    );
    addTearDown(bloc.close);

    final controller = await _pump(tester, bloc, 't');
    addTearDown(controller.dispose);

    // One empty row → name + value fields.
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), 'a');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'b');
    await tester.pump();

    expect(
      bloc.state.tabs.byId('t')!.config.formFields,
      const [MultipartFieldEntity(name: 'a', value: 'b')],
    );

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('multipart shows the file-toggle affordance', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.multipart),
    );
    addTearDown(bloc.close);

    final controller = await _pump(tester, bloc, 't');
    addTearDown(controller.dispose);

    // multipart rows expose an attach-file toggle (urlencoded does not).
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
  });

  testWidgets('beautify button drops below the find panel while it is open', (
    tester,
  ) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.raw),
    );
    addTearDown(bloc.close);

    final controller = await _pump(tester, bloc, 't');
    addTearDown(controller.dispose);

    final beautify = find.widgetWithIcon(IconButton, Icons.auto_fix_high);
    final closedTop = tester.getTopLeft(beautify).dy;

    // Open find mode the same way the Cmd/Ctrl+F shortcut does. The editor
    // must expose its find controller for the Beautify overlay to react.
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(
      editor.findController,
      isNotNull,
      reason:
          'the raw body editor owns the find controller so the beautify '
          'button can move out of the way of the find panel',
    );
    editor.findController!.findMode();
    await tester.pumpAndSettle();

    // The panel overlays the editor's top edge; the beautify button must
    // clear it rather than covering its close button.
    final closeButton = find.descendant(
      of: find.byType(CodeFindPanel),
      matching: find.widgetWithIcon(IconButton, Icons.close),
    );
    expect(closeButton, findsOneWidget);
    expect(
      tester.getRect(beautify).overlaps(tester.getRect(closeButton)),
      isFalse,
    );
    expect(
      tester.getTopLeft(beautify).dy,
      greaterThanOrEqualTo(closedTop + kFindPanelHeight),
    );

    // Closing the panel restores the resting position.
    editor.findController!.close();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(beautify).dy, closedTop);
  });

  testWidgets('GRAPHQL shows the query + variables panes', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.graphql),
    );
    addTearDown(bloc.close);

    final controller = await _pump(tester, bloc, 't');
    addTearDown(controller.dispose);

    expect(find.text('GRAPHQL'), findsOneWidget);
    expect(find.text('QUERY'), findsOneWidget);
    expect(find.text('VARIABLES (JSON)'), findsOneWidget);
    // Two code editors: query + variables.
    expect(find.byType(CodeEditor), findsNWidgets(2));
  });

  testWidgets('beautify tooltip carries the platform shortcut hint', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.raw),
    );
    addTearDown(bloc.close);

    final controller = await _pump(tester, bloc, 't');
    addTearDown(controller.dispose);
    // Reset within the body: the testWidgets invariant check runs before
    // addTearDown, and it forbids a leaked foundation debug override.
    debugDefaultTargetPlatformOverride = null;

    expect(
      find.byTooltip(
        'Beautify JSON — '
        '${shortcutHint(AppShortcutAction.beautifyJson, useMeta: true)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('NONE shows the empty-body hint and no editor', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.none),
    );
    addTearDown(bloc.close);

    final controller = await _pump(tester, bloc, 't');
    addTearDown(controller.dispose);

    expect(find.text('THIS REQUEST HAS NO BODY'), findsOneWidget);
    expect(find.byType(CodeEditor), findsNothing);
    expect(find.byType(FormDataEditor), findsNothing);
  });

  group('BINARY body picker', () {
    testWidgets('with no file selected shows the CHOOSE FILE prompt', (
      tester,
    ) async {
      final bloc = await _loadedBloc(
        repository,
        sendRequestUseCase,
        tab(BodyType.binary),
      );
      addTearDown(bloc.close);

      final controller = await _pump(tester, bloc, 't');
      addTearDown(controller.dispose);

      expect(find.text('NO FILE SELECTED'), findsOneWidget);
      expect(find.text('CHOOSE FILE'), findsOneWidget);
    });

    testWidgets('with a saved file path shows its basename and CHANGE FILE', (
      tester,
    ) async {
      final bloc = await _loadedBloc(
        repository,
        sendRequestUseCase,
        tab(BodyType.binary, bodyFilePath: '/tmp/uploads/payload.bin'),
      );
      addTearDown(bloc.close);

      final controller = await _pump(tester, bloc, 't');
      addTearDown(controller.dispose);

      expect(find.text('payload.bin'), findsOneWidget);
      expect(find.text('CHANGE FILE'), findsOneWidget);
      expect(find.text('NO FILE SELECTED'), findsNothing);
    });

    testWidgets('picking a file stores its path on config.bodyFilePath', (
      tester,
    ) async {
      mockFilePickerChannel(tester, [
        {
          'name': 'upload.bin',
          'path': '/tmp/picked/upload.bin',
          'size': 3,
          'bytes': null,
          'identifier': null,
        },
      ]);
      final bloc = await _loadedBloc(
        repository,
        sendRequestUseCase,
        tab(BodyType.binary),
      );
      addTearDown(bloc.close);

      final controller = await _pump(tester, bloc, 't');
      addTearDown(controller.dispose);

      await tester.tap(find.text('CHOOSE FILE'));
      await tester.pumpAndSettle();

      expect(
        bloc.state.tabs.byId('t')!.config.bodyFilePath,
        '/tmp/picked/upload.bin',
      );
      expect(find.text('upload.bin'), findsOneWidget);
      expect(find.text('CHANGE FILE'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('a pathless pick (web) explains and stores nothing', (
      tester,
    ) async {
      mockFilePickerChannel(tester, [
        {
          'name': 'upload.bin',
          'path': null,
          'size': 0,
          'bytes': null,
          'identifier': null,
        },
      ]);
      final bloc = await _loadedBloc(
        repository,
        sendRequestUseCase,
        tab(BodyType.binary),
      );
      addTearDown(bloc.close);

      final controller = await _pump(tester, bloc, 't');
      addTearDown(controller.dispose);

      await tester.tap(find.text('CHOOSE FILE'));
      await tester.pumpAndSettle();

      expect(
        find.text('Binary bodies need the desktop or mobile app.'),
        findsOneWidget,
      );
      expect(bloc.state.tabs.byId('t')!.config.bodyFilePath, isNull);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('cancelling the native dialog leaves the config untouched', (
      tester,
    ) async {
      mockFilePickerChannel(tester, null);
      final bloc = await _loadedBloc(
        repository,
        sendRequestUseCase,
        tab(BodyType.binary),
      );
      addTearDown(bloc.close);

      final controller = await _pump(tester, bloc, 't');
      addTearDown(controller.dispose);

      await tester.tap(find.text('CHOOSE FILE'));
      await tester.pumpAndSettle();

      expect(bloc.state.tabs.byId('t')!.config.bodyFilePath, isNull);
      expect(find.text('NO FILE SELECTED'), findsOneWidget);
    });
  });

  group('RAW beautify button', () {
    testWidgets('formats valid JSON and confirms via snackbar', (tester) async {
      const ugly = '{"a":1,"b":[2,3]}';
      final bloc = await _loadedBloc(
        repository,
        sendRequestUseCase,
        tab(BodyType.raw),
      );
      addTearDown(bloc.close);

      final controller = await _pump(tester, bloc, 't');
      addTearDown(controller.dispose);
      controller.text = ugly;
      await tester.pump();

      // prettify hops to a background isolate (compute), which needs the real
      // event loop — drive the tap and wait for the result under runAsync.
      String? expected;
      await tester.runAsync(() async {
        expected = await JsonUtils.prettify(ugly);
        await tester.tap(find.widgetWithIcon(IconButton, Icons.auto_fix_high));
        for (var i = 0; i < 100 && controller.text == ugly; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();

      expect(expected, isNot(ugly));
      expect(controller.text, expected);
      expect(find.text('JSON formatted'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('leaves non-JSON untouched and says so', (tester) async {
      const notJson = 'plain text body';
      final bloc = await _loadedBloc(
        repository,
        sendRequestUseCase,
        tab(BodyType.raw),
      );
      addTearDown(bloc.close);

      final controller = await _pump(tester, bloc, 't');
      addTearDown(controller.dispose);
      controller.text = notJson;
      await tester.pump();

      // Non-JSON short-circuits before the isolate hop, so a plain tap works.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.auto_fix_high));
      await tester.pumpAndSettle();

      expect(controller.text, notJson);
      expect(find.text('Already formatted or not valid JSON'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
    });
  });

  testWidgets('swapping the body controller rebinds editor + find controller', (
    tester,
  ) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tab(BodyType.raw),
    );
    addTearDown(bloc.close);

    final controllerA = CodeLineEditingController();
    addTearDown(controllerA.dispose);
    final controllerB = CodeLineEditingController();
    addTearDown(controllerB.dispose);
    final variablesController = CodeLineEditingController();
    addTearDown(variablesController.dispose);

    final settingsBloc = _settingsBloc();
    addTearDown(settingsBloc.close);
    final environmentsBloc = _environmentsBloc();
    addTearDown(environmentsBloc.close);
    final collectionsBloc = _collectionsBloc();
    addTearDown(collectionsBloc.close);

    Widget build(CodeLineEditingController controller) => MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<EnvironmentsBloc>.value(value: environmentsBloc),
            BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
          ],
          child: BodyTabView(
            tabId: 't',
            controller: controller,
            variablesController: variablesController,
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(controllerA));
    await tester.pumpAndSettle();
    final before = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .findController;

    await tester.pumpWidget(build(controllerB));
    await tester.pumpAndSettle();

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.controller, controllerB);
    expect(
      editor.findController,
      isNot(same(before)),
      reason:
          'didUpdateWidget must recreate the find controller for the new '
          'editing controller',
    );
  });
}
