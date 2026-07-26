// Widget tests for the PARAMS tab's per-row enable/disable checkboxes (B1):
// unchecking removes the pair from the URL and parks it (greyed, read-only,
// in place); re-checking re-inserts into the URL at the clamped remembered
// position. One UpdateTab per toggle (URL + parked list change atomically).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
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
import 'package:getman/features/tabs/presentation/widgets/params_tab_view.dart';
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

  Future<TabsBloc> pumpParamsTab(
    WidgetTester tester, {
    String url = 'https://x.test/?a=1&b=2&c=3',
    List<ParkedParamEntity> parked = const [],
  }) async {
    final tab = HttpRequestTabEntity(
      tabId: 't',
      config: HttpRequestConfigEntity(
        id: 't',
        url: url,
        disabledParams: parked,
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
            child: const ParamsTabView(tabId: 't'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  HttpRequestConfigEntity configOf(TabsBloc bloc) =>
      bloc.state.tabs.first.config;

  testWidgets('unchecking removes the pair from the URL and parks it', (
    tester,
  ) async {
    final bloc = await pumpParamsTab(tester);

    await tester.tap(find.byKey(const ValueKey('param_enabled_1')));
    await tester.pumpAndSettle();

    expect(configOf(bloc).url, 'https://x.test/?a=1&c=3');
    expect(
      configOf(bloc).disabledParams,
      [const ParkedParamEntity(key: 'b', value: '2', rowIndex: 1)],
    );
    // The parked row still renders in place, unchecked and read-only.
    expect(find.text('b'), findsOneWidget);
    final checkbox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('param_enabled_1')),
    );
    expect(checkbox.value, isFalse);
    expect(
      find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring),
      findsNWidgets(2),
      reason: 'parked param rows are read-only (key + value cells)',
    );
    await tester.pump(const Duration(seconds: 11)); // flush debounced save
  });

  testWidgets('re-checking re-inserts into the URL at the parked position', (
    tester,
  ) async {
    final bloc = await pumpParamsTab(
      tester,
      url: 'https://x.test/?a=1&c=3',
      parked: const [ParkedParamEntity(key: 'b', value: '2', rowIndex: 1)],
    );

    await tester.tap(find.byKey(const ValueKey('param_enabled_1')));
    await tester.pumpAndSettle();

    expect(configOf(bloc).url, 'https://x.test/?a=1&b=2&c=3');
    expect(configOf(bloc).disabledParams, isEmpty);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('a stale beyond-range rowIndex clamps on display and unpark', (
    tester,
  ) async {
    final bloc = await pumpParamsTab(
      tester,
      url: 'https://x.test/?a=1',
      parked: const [ParkedParamEntity(key: 'z', value: '9', rowIndex: 99)],
    );

    // Composed view is [a, z]; z's checkbox renders at display index 1.
    await tester.tap(find.byKey(const ValueKey('param_enabled_1')));
    await tester.pumpAndSettle();

    expect(configOf(bloc).url, 'https://x.test/?a=1&z=9');
    expect(configOf(bloc).disabledParams, isEmpty);
    await tester.pump(const Duration(seconds: 11));
  });
}
