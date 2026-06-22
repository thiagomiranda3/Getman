// Widget tests for BodyTabView: the body-type selector switches the active
// editor and form rows round-trip into config.formFields.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
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
import 'package:getman/features/tabs/presentation/widgets/form_data_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/request_editor_tabs.dart';
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
  }) => HttpRequestTabEntity(
    tabId: 't',
    config: HttpRequestConfigEntity(
      id: 't',
      bodyType: type,
      formFields: fields,
    ),
  );

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
}
