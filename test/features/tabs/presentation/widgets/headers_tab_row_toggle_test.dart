// Widget tests for the HEADERS tab's per-row enable/disable checkboxes (B1):
// unchecking parks the key in disabledHeaderKeys (the header stays in the
// map), re-checking removes it, renaming a disabled row's key renames the
// set entry, and deleting a disabled row prunes the set.

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
import 'package:getman/features/tabs/presentation/widgets/headers_tab_view.dart';
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
  final saveUseCase = MockSaveSettingsUseCase();
  when(() => saveUseCase(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: saveUseCase,
    initialSettings: settings,
  );
}

EnvironmentsBloc _environmentsBloc() {
  final get = MockGetEnvironmentsUseCase();
  when(get.call).thenAnswer((_) async => const <EnvironmentEntity>[]);
  return EnvironmentsBloc(
    getEnvironmentsUseCase: get,
    saveEnvironmentsUseCase: MockSaveEnvironmentsUseCase(),
    putEnvironmentUseCase: MockPutEnvironmentUseCase(),
    deleteEnvironmentUseCase: MockDeleteEnvironmentUseCase(),
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

  Future<TabsBloc> pumpHeadersTab(
    WidgetTester tester, {
    Map<String, String> headers = const {'Accept': '*/*', 'X-Auth': 'token'},
    Set<String> disabled = const {},
  }) async {
    final tab = HttpRequestTabEntity(
      tabId: 't',
      config: HttpRequestConfigEntity(
        id: 't',
        headers: headers,
        disabledHeaderKeys: disabled,
      ),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);
    final settingsBloc = _settingsBloc(const SettingsEntity());
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
            child: const HeadersTabView(tabId: 't'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  HttpRequestConfigEntity configOf(TabsBloc bloc) =>
      bloc.state.tabs.first.config;

  testWidgets('unchecking parks the key; the header stays in the map', (
    tester,
  ) async {
    final bloc = await pumpHeadersTab(tester);

    await tester.tap(find.byKey(const ValueKey('header_enabled_1')));
    await tester.pumpAndSettle();

    expect(configOf(bloc).disabledHeaderKeys, {'X-Auth'});
    expect(
      configOf(bloc).headers,
      {'Accept': '*/*', 'X-Auth': 'token'},
      reason: 'a disabled header stays in the map, order preserved',
    );
    await tester.pump(const Duration(seconds: 11)); // flush debounced save
  });

  testWidgets('re-checking removes the key from the set', (tester) async {
    final bloc = await pumpHeadersTab(tester, disabled: {'X-Auth'});

    final checkbox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('header_enabled_1')),
    );
    expect(checkbox.value, isFalse, reason: 'seeded disabled row starts off');

    await tester.tap(find.byKey(const ValueKey('header_enabled_1')));
    await tester.pumpAndSettle();

    expect(configOf(bloc).disabledHeaderKeys, isEmpty);
    expect(configOf(bloc).headers, {'Accept': '*/*', 'X-Auth': 'token'});
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('renaming a disabled row key renames the set entry too', (
    tester,
  ) async {
    final bloc = await pumpHeadersTab(tester, disabled: {'X-Auth'});

    await tester.enterText(
      find.byKey(const ValueKey('header_key_1')),
      'X-Auth-2',
    );
    await tester.pumpAndSettle();

    expect(configOf(bloc).headers.containsKey('X-Auth-2'), isTrue);
    expect(configOf(bloc).headers.containsKey('X-Auth'), isFalse);
    expect(configOf(bloc).disabledHeaderKeys, {'X-Auth-2'});
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('deleting a disabled row prunes the set', (tester) async {
    final bloc = await pumpHeadersTab(tester, disabled: {'X-Auth'});

    await tester.tap(find.byIcon(Icons.delete_outline).at(1));
    await tester.pumpAndSettle();

    expect(configOf(bloc).headers, {'Accept': '*/*'});
    expect(configOf(bloc).disabledHeaderKeys, isEmpty);
    await tester.pump(const Duration(seconds: 11));
  });
}
