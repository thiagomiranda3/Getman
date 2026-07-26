// Widget tests for RevertTabButton (A4): visible only when the tab is dirty
// AND linked to an existing node; confirms before dispatching RevertTab;
// hides after the revert lands (config equals baseline again).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/revert_tab_button.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

const _saved = HttpRequestConfigEntity(id: 'cfg1', url: 'https://a.dev');
const _dirty = HttpRequestConfigEntity(id: 'cfg1', url: 'https://a.dev/EDIT');

HttpRequestTabEntity _tab(HttpRequestConfigEntity config, {String? nodeId}) =>
    HttpRequestTabEntity(
      tabId: 't1',
      config: config,
      collectionNodeId: nodeId,
      collectionName: nodeId == null ? null : 'A',
    );

void main() {
  late MockTabsRepository tabsRepo;
  late MockSendRequestUseCase sendUseCase;
  late MockCollectionsRepository collectionsRepo;

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
  });

  setUp(() {
    tabsRepo = MockTabsRepository();
    sendUseCase = MockSendRequestUseCase();
    collectionsRepo = MockCollectionsRepository();
    when(() => tabsRepo.putTab(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deleteTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.saveTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putPanel(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deletePanels(any())).thenAnswer((_) async {});
    when(() => tabsRepo.savePanelMeta(any(), any())).thenAnswer((_) async {});
    when(
      () => collectionsRepo.getCollections(),
    ).thenAnswer((_) async => const []);
    when(() => collectionsRepo.saveCollections(any())).thenAnswer((_) async {});
  });

  Future<({TabsBloc tabs, CollectionsBloc collections})> pumpButton(
    WidgetTester tester,
    HttpRequestTabEntity tab, {
    List<CollectionNodeEntity> nodes = const [],
  }) async {
    when(() => tabsRepo.getPanels()).thenAnswer(
      (_) async => [
        PanelEntity(
          id: 'p1',
          name: 'Panel 1',
          tabs: [tab],
          activeTabId: tab.tabId,
        ),
      ],
    );
    when(() => tabsRepo.getActivePanelId()).thenAnswer((_) async => 'p1');
    final tabsBloc = TabsBloc(
      repository: tabsRepo,
      sendRequestUseCase: sendUseCase,
    )..add(const LoadTabs());
    await tabsBloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);

    final collectionsBloc = CollectionsBloc(
      getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
      saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
      saveDebounce: const Duration(milliseconds: 5),
    )..add(ReplaceCollections(nodes));
    await collectionsBloc.stream.first;

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: tabsBloc),
              BlocProvider.value(value: collectionsBloc),
            ],
            child: const RevertTabButton(tabId: 't1', iconSize: 20, gap: 8),
          ),
        ),
      ),
    );
    await tester.pump();
    return (tabs: tabsBloc, collections: collectionsBloc);
  }

  const savedNode = CollectionNodeEntity(
    id: 'n1',
    name: 'A',
    isFolder: false,
    config: _saved,
  );

  testWidgets('visible for a dirty linked tab', (tester) async {
    final blocs = await pumpButton(
      tester,
      _tab(_dirty, nodeId: 'n1'),
      nodes: const [savedNode],
    );
    addTearDown(blocs.tabs.close);
    addTearDown(blocs.collections.close);

    expect(find.byKey(const ValueKey('revert_tab_button')), findsOneWidget);
  });

  testWidgets('hidden for a CLEAN linked tab and for an UNLINKED tab', (
    tester,
  ) async {
    final clean = await pumpButton(
      tester,
      _tab(_saved, nodeId: 'n1'),
      nodes: const [savedNode],
    );
    addTearDown(clean.tabs.close);
    addTearDown(clean.collections.close);
    expect(find.byKey(const ValueKey('revert_tab_button')), findsNothing);

    final unlinked = await pumpButton(tester, _tab(_dirty));
    addTearDown(unlinked.tabs.close);
    addTearDown(unlinked.collections.close);
    expect(find.byKey(const ValueKey('revert_tab_button')), findsNothing);
  });

  testWidgets('tap → confirm → RevertTab restores baseline and the icon '
      'hides', (tester) async {
    final blocs = await pumpButton(
      tester,
      _tab(_dirty, nodeId: 'n1'),
      nodes: const [savedNode],
    );
    addTearDown(blocs.tabs.close);
    addTearDown(blocs.collections.close);

    await tester.tap(find.byKey(const ValueKey('revert_tab_button')));
    await tester.pumpAndSettle();
    expect(
      find.text('Discard unsaved changes to this request?'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'REVERT'));
    await tester.pumpAndSettle();

    expect(blocs.tabs.state.tabs.first.config, _saved);
    expect(find.byKey(const ValueKey('revert_tab_button')), findsNothing);

    // RevertTab schedules TabsBloc's debounced save (10s); flush it so no
    // pending timer leaks past this test (url_bar_test precedent).
    await tester.pump(const Duration(seconds: 11));
  });
}
