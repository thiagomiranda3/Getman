// Widget tests for AuthTabView: scheme selection reveals the right fields and
// edits round-trip into the tab's config.auth map. Uses a real TabsBloc fed by
// a mocked repository + use case alongside SettingsBloc, EnvironmentsBloc, and
// CollectionsBloc (required by TabVariableContextBuilder).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
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
import 'package:getman/features/tabs/presentation/widgets/auth_tab_view.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class MockGetEnvironmentsUseCase extends Mock
    implements GetEnvironmentsUseCase {}

class MockSaveEnvironmentsUseCase extends Mock
    implements SaveEnvironmentsUseCase {}

class MockPutEnvironmentUseCase extends Mock implements PutEnvironmentUseCase {}

class MockDeleteEnvironmentUseCase extends Mock
    implements DeleteEnvironmentUseCase {}

class MockGetCollectionsUseCase extends Mock implements GetCollectionsUseCase {}

class MockSaveCollectionsUseCase extends Mock
    implements SaveCollectionsUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

SettingsBloc _settingsBloc(SettingsEntity settings) {
  final save = MockSaveSettingsUseCase();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(saveSettingsUseCase: save, initialSettings: settings);
}

EnvironmentsBloc _environmentsBloc([
  List<EnvironmentEntity> environments = const [],
]) {
  final get = MockGetEnvironmentsUseCase();
  when(get.call).thenAnswer((_) async => environments);
  return EnvironmentsBloc(
    getEnvironmentsUseCase: get,
    saveEnvironmentsUseCase: MockSaveEnvironmentsUseCase(),
    putEnvironmentUseCase: MockPutEnvironmentUseCase(),
    deleteEnvironmentUseCase: MockDeleteEnvironmentUseCase(),
    initialEnvironments: environments,
  );
}

CollectionsBloc _collectionsBloc() {
  final get = MockGetCollectionsUseCase();
  when(get.call).thenAnswer((_) async => const <CollectionNodeEntity>[]);
  return CollectionsBloc(
    getCollectionsUseCase: get,
    saveCollectionsUseCase: MockSaveCollectionsUseCase(),
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

Future<void> _pump(
  WidgetTester tester,
  TabsBloc bloc,
  String tabId, {
  List<EnvironmentEntity> environments = const [],
  String? activeEnvironmentId,
}) async {
  final settingsBloc = _settingsBloc(
    SettingsEntity(activeEnvironmentId: activeEnvironmentId),
  );
  addTearDown(settingsBloc.close);
  final environmentsBloc = _environmentsBloc(environments);
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
          child: AuthTabView(tabId: tabId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

  HttpRequestTabEntity tabWithAuth(String tabId, Map<String, String> auth) =>
      HttpRequestTabEntity(
        tabId: tabId,
        config: HttpRequestConfigEntity(id: tabId, auth: auth),
      );

  testWidgets('defaults to NO AUTH with no credential fields', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tabWithAuth('t', const {}),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't');

    expect(find.text('NO AUTH'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('selecting Bearer reveals the token field and edits round-trip', (
    tester,
  ) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tabWithAuth('t', const {}),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't');

    // Open the type dropdown and pick Bearer.
    await tester.tap(find.text('NO AUTH'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BEARER TOKEN').last);
    await tester.pumpAndSettle();

    // Token field is now present.
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sk-123');
    await tester.pump();

    expect(
      bloc.state.tabs.byId('t')!.config.auth,
      {'type': 'bearer', 'token': 'sk-123'},
    );

    // Let the bloc's 10s debounced-save timer fire so no timer is pending
    // when the widget tree is torn down.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('renders an existing bearer token prefilled', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tabWithAuth('t', const {'type': 'bearer', 'token': 'preset'}),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't');

    expect(find.text('BEARER TOKEN'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'preset'), findsOneWidget);
  });

  testWidgets('api key in query mode round-trips addTo=query', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tabWithAuth('t', const {}),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't');

    await tester.tap(find.text('NO AUTH'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('API KEY').last);
    await tester.pumpAndSettle();

    // KEY + VALUE fields present.
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), 'api_key');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'v');
    await tester.pump();

    // Switch ADD TO -> QUERY PARAM.
    await tester.tap(find.text('HEADER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QUERY PARAM').last);
    await tester.pumpAndSettle();

    expect(
      bloc.state.tabs.byId('t')!.config.auth,
      {'type': 'apikey', 'key': 'api_key', 'value': 'v', 'addTo': 'query'},
    );

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
    'TOKEN field shows {{var}} autocomplete overlay and accepts suggestion',
    (tester) async {
      final env = EnvironmentEntity(
        id: 'env1',
        name: 'Test',
        variables: const {'host': 'example.com'},
      );
      final bloc = await _loadedBloc(
        repository,
        sendRequestUseCase,
        tabWithAuth('t', const {'type': 'bearer', 'token': ''}),
      );
      addTearDown(bloc.close);

      await _pump(
        tester,
        bloc,
        't',
        environments: [env],
        activeEnvironmentId: 'env1',
      );

      // Enter text that triggers autocomplete for the 'host' variable.
      await tester.enterText(
        find.byKey(const ValueKey('auth_field_TOKEN')),
        '{{ho',
      );
      await tester.pumpAndSettle();

      // The 'host' suggestion must appear in the overlay.
      expect(find.text('host'), findsOneWidget);

      // Tap the suggestion to accept it.
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();

      // The token in the bloc state should be fully completed.
      expect(
        bloc.state.tabs.byId('t')!.config.auth['token'],
        '{{host}}',
      );

      // Flush the debounced-save timer.
      await tester.pump(const Duration(seconds: 11));
    },
  );
}
