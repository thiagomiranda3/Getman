// Widget test for TabVariableContextBuilder — verifies that the widget
// correctly assembles a LayeredVariableContext from live bloc state (env vars +
// collection-node vars for the tab's linked node).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
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
import 'package:mocktail/mocktail.dart';

class _MockTabsRepository extends Mock implements TabsRepository {}

class _MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class _MockGetEnvironmentsUseCase extends Mock
    implements GetEnvironmentsUseCase {}

class _MockSaveEnvironmentsUseCase extends Mock
    implements SaveEnvironmentsUseCase {}

class _MockPutEnvironmentUseCase extends Mock
    implements PutEnvironmentUseCase {}

class _MockDeleteEnvironmentUseCase extends Mock
    implements DeleteEnvironmentUseCase {}

class _MockCollectionsRepository extends Mock
    implements CollectionsRepository {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(const SettingsEntity());
  });

  testWidgets('exposes env + collection layered context for the tab', (
    tester,
  ) async {
    // --- Arrange ---

    // Environment with a 'host' variable.
    final env = EnvironmentEntity(
      id: 'env1',
      name: 'Production',
      variables: const {'host': 'https://api.example.com'},
    );

    // Collection node (leaf) with a 'path' variable.
    const node = CollectionNodeEntity(
      id: 'node1',
      name: 'GetUsers',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'node1'),
      variables: {'path': '/v1'},
    );

    // Tab linked to the collection node.
    const tab = HttpRequestTabEntity(
      tabId: 'tab1',
      config: HttpRequestConfigEntity(id: 'tab1', url: 'https://example.com'),
      collectionNodeId: 'node1',
    );

    // --- Blocs ---

    // SettingsBloc: active environment = env1.
    final mockSaveSettings = _MockSaveSettingsUseCase();
    when(() => mockSaveSettings(any())).thenAnswer((_) async {});
    final settingsBloc = SettingsBloc(
      saveSettingsUseCase: mockSaveSettings,
      initialSettings: const SettingsEntity(activeEnvironmentId: 'env1'),
    );
    addTearDown(settingsBloc.close);

    // EnvironmentsBloc: seeded synchronously via initialEnvironments so no
    // async LoadEnvironments event is needed before pump.
    final mockGetEnv = _MockGetEnvironmentsUseCase();
    when(mockGetEnv.call).thenAnswer((_) async => [env]);
    final environmentsBloc = EnvironmentsBloc(
      getEnvironmentsUseCase: mockGetEnv,
      saveEnvironmentsUseCase: _MockSaveEnvironmentsUseCase(),
      putEnvironmentUseCase: _MockPutEnvironmentUseCase(),
      deleteEnvironmentUseCase: _MockDeleteEnvironmentUseCase(),
      initialEnvironments: [env],
    );
    addTearDown(environmentsBloc.close);

    // TabsBloc: one panel containing the linked tab.
    final tabsRepo = _MockTabsRepository();
    when(tabsRepo.getPanels).thenAnswer(
      (_) async => [
        PanelEntity(
          id: 'p1',
          name: 'Panel 1',
          tabs: const [tab],
          activeTabId: tab.tabId,
        ),
      ],
    );
    when(tabsRepo.getActivePanelId).thenAnswer((_) async => 'p1');
    when(() => tabsRepo.saveTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putTab(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deleteTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putPanel(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deletePanels(any())).thenAnswer((_) async {});
    when(() => tabsRepo.savePanelMeta(any(), any())).thenAnswer((_) async {});

    final tabsBloc = TabsBloc(
      repository: tabsRepo,
      sendRequestUseCase: _MockSendRequestUseCase(),
    )..add(const LoadTabs());
    await tabsBloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
    addTearDown(tabsBloc.close);

    // CollectionsBloc: seeded with the node carrying 'path' = '/v1'.
    final collectionsRepo = _MockCollectionsRepository();
    when(collectionsRepo.getCollections).thenAnswer((_) async => const []);
    when(
      () => collectionsRepo.saveCollections(any()),
    ).thenAnswer((_) async {});

    final collectionsBloc = CollectionsBloc(
      getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
      saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
      saveDebounce: const Duration(milliseconds: 5),
    )..add(const ReplaceCollections([node]));
    await collectionsBloc.stream.first;
    addTearDown(collectionsBloc.close);

    // --- Capture the context ---
    late LayeredVariableContext captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: settingsBloc),
              BlocProvider.value(value: environmentsBloc),
              BlocProvider.value(value: tabsBloc),
              BlocProvider.value(value: collectionsBloc),
            ],
            child: TabVariableContextBuilder(
              tabId: 'tab1',
              builder: (_, ctx) {
                captured = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // --- Assert ---
    expect(captured.environmentVariables['host'], 'https://api.example.com');
    expect(captured.collectionVariables['path'], '/v1');
    expect(captured.allVariables.keys, containsAll(['host', 'path']));
  });
}
