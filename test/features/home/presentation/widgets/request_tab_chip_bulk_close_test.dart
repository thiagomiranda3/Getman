// D6 bulk-close coverage for RequestTabChip's context menu — CLOSE OTHERS and
// the directional CLOSE TO THE LEFT / CLOSE TO THE RIGHT flows, including the
// unsaved-changes confirm dialog — split out of request_tab_chip_test.dart to
// keep that file's main() under the function_lines_of_code metric gate. Small
// helpers (mocks, tab factories, openContextMenu) are deliberately duplicated
// here rather than shared.
import 'package:flutter/gestures.dart';
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
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/home/presentation/widgets/request_tab_chip.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

HttpRequestTabEntity _linkedTab() => const HttpRequestTabEntity(
  tabId: 'tab1',
  config: HttpRequestConfigEntity(id: 'node1', url: 'https://api/users'),
  collectionName: 'GetUsers',
  collectionNodeId: 'node1',
);

HttpRequestTabEntity _emptyTab() => const HttpRequestTabEntity(
  tabId: 'tab2',
  config: HttpRequestConfigEntity(id: 'node2'),
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
    when(() => tabsRepo.saveTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putTab(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deleteTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putPanel(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deletePanels(any())).thenAnswer((_) async {});
    when(
      () => tabsRepo.savePanelMeta(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => collectionsRepo.getCollections(),
    ).thenAnswer((_) async => const []);
    when(() => collectionsRepo.saveCollections(any())).thenAnswer((_) async {});
  });

  Future<void> openContextMenu(
    WidgetTester tester, {
    String title = 'GetUsers',
  }) async {
    await tester.tapAt(
      tester.getCenter(find.text(title)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
  }

  group('D6: bulk close confirms unsaved changes', () {
    // _linkedTab() is DIRTY by construction here: it links to collection node
    // 'node1', but collectionsRepo returns no saved collections in setUp, so
    // TabDirtyChecker treats the missing saved config as dirty. _emptyTab()
    // is clean (matches the pristine default config for an unlinked tab).
    Future<(TabsBloc, CollectionsBloc)> pumpTwoTabs(
      WidgetTester tester,
      HttpRequestTabEntity dirty,
      HttpRequestTabEntity clean,
    ) async {
      when(() => tabsRepo.getPanels()).thenAnswer(
        (_) async => [
          PanelEntity(
            id: 'p1',
            name: 'Panel 1',
            tabs: [dirty, clean],
            activeTabId: clean.tabId,
          ),
        ],
      );
      when(() => tabsRepo.getActivePanelId()).thenAnswer((_) async => 'p1');

      final tabsBloc = TabsBloc(
        repository: tabsRepo,
        sendRequestUseCase: sendUseCase,
      )..add(const LoadTabs());
      await tabsBloc.stream.firstWhere(
        (s) => !s.isLoading && s.tabs.length == 2,
      );

      final collectionsBloc = CollectionsBloc(
        getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
        saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
        saveDebounce: const Duration(milliseconds: 5),
      )..add(const ReplaceCollections([]));
      await collectionsBloc.stream.first;

      addTearDown(tabsBloc.close);
      addTearDown(collectionsBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: tabsBloc),
                BlocProvider.value(value: collectionsBloc),
              ],
              child: RepositoryProvider<TabDirtyChecker>.value(
                value: const TabDirtyChecker(),
                child: Center(
                  child: RequestTabChip(
                    tabId: clean.tabId,
                    index: 1,
                    isActive: true,
                    onTap: () {},
                    onClose: () async => true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (tabsBloc, collectionsBloc);
    }

    testWidgets(
      'CLOSE OTHERS with a dirty affected tab shows a confirm dialog; '
      'CANCEL does not dispatch',
      (tester) async {
        final dirty = _linkedTab();
        final clean = _emptyTab();
        final (tabsBloc, _) = await pumpTwoTabs(tester, dirty, clean);

        final titlePos = tester.getCenter(find.text('NEW REQUEST'));
        await tester.tapAt(titlePos, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        await tester.tap(find.text('CLOSE OTHERS'));
        // The confirm dialog is opened via a post-frame callback (deferred
        // until the popup menu route is fully dismissed).
        await tester.pumpAndSettle();

        expect(find.text('UNSAVED CHANGES'), findsOneWidget);

        await tester.tap(find.text('CANCEL'));
        await tester.pumpAndSettle();

        expect(tabsBloc.state.tabs.length, 2, reason: 'nothing was closed');
      },
    );

    testWidgets(
      'CLOSE OTHERS with a dirty affected tab: CLOSE ANYWAY dispatches '
      'CloseOtherTabs',
      (tester) async {
        final dirty = _linkedTab();
        final clean = _emptyTab();
        final (tabsBloc, _) = await pumpTwoTabs(tester, dirty, clean);

        final titlePos = tester.getCenter(find.text('NEW REQUEST'));
        await tester.tapAt(titlePos, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        await tester.tap(find.text('CLOSE OTHERS'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('CLOSE ANYWAY'));
        await tester.pumpAndSettle();

        expect(tabsBloc.state.tabs.length, 1);
        expect(tabsBloc.state.tabs.single.tabId, clean.tabId);
      },
    );

    testWidgets(
      'CLOSE OTHERS with no dirty affected tabs dispatches immediately — no '
      'confirm dialog',
      (tester) async {
        final clean = _emptyTab();
        const otherClean = HttpRequestTabEntity(
          tabId: 'tab3',
          config: HttpRequestConfigEntity(id: 'tab3'),
        );
        final (tabsBloc, _) = await pumpTwoTabs(tester, otherClean, clean);

        final titlePos = tester.getCenter(find.text('NEW REQUEST'));
        await tester.tapAt(titlePos, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        await tester.tap(find.text('CLOSE OTHERS'));
        await tester.pumpAndSettle();

        expect(find.text('UNSAVED CHANGES'), findsNothing);
        expect(tabsBloc.state.tabs.length, 1);
        expect(tabsBloc.state.tabs.single.tabId, clean.tabId);
      },
    );
  });

  group('D6: directional bulk closes', () {
    // Pumps [tabs] into one panel with the chip rendered for [chipTab] at
    // [chipIndex]; returns the live bloc for state assertions.
    Future<TabsBloc> pumpStrip(
      WidgetTester tester,
      List<HttpRequestTabEntity> tabs,
      HttpRequestTabEntity chipTab,
      int chipIndex,
    ) async {
      when(() => tabsRepo.getPanels()).thenAnswer(
        (_) async => [
          PanelEntity(
            id: 'p1',
            name: 'Panel 1',
            tabs: tabs,
            activeTabId: chipTab.tabId,
          ),
        ],
      );
      when(() => tabsRepo.getActivePanelId()).thenAnswer((_) async => 'p1');

      final tabsBloc = TabsBloc(
        repository: tabsRepo,
        sendRequestUseCase: sendUseCase,
      )..add(const LoadTabs());
      await tabsBloc.stream.firstWhere(
        (s) => !s.isLoading && s.tabs.length == tabs.length,
      );

      final collectionsBloc = CollectionsBloc(
        getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
        saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
        saveDebounce: const Duration(milliseconds: 5),
      )..add(const ReplaceCollections([]));
      await collectionsBloc.stream.first;

      addTearDown(tabsBloc.close);
      addTearDown(collectionsBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: tabsBloc),
                BlocProvider.value(value: collectionsBloc),
              ],
              child: RepositoryProvider<TabDirtyChecker>.value(
                value: const TabDirtyChecker(),
                child: Center(
                  child: RequestTabChip(
                    tabId: chipTab.tabId,
                    index: chipIndex,
                    isActive: true,
                    onTap: () {},
                    onClose: () async => true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tabsBloc;
    }

    HttpRequestTabEntity cleanTab(String id) => HttpRequestTabEntity(
      tabId: id,
      config: HttpRequestConfigEntity(id: id),
    );

    // A linked tab whose collection node has no saved config → dirty.
    HttpRequestTabEntity dirtyTab(String id) => HttpRequestTabEntity(
      tabId: id,
      config: HttpRequestConfigEntity(id: id, url: 'https://$id.dev'),
      collectionName: id,
      collectionNodeId: 'missing_$id',
    );

    testWidgets(
      'CLOSE TO THE LEFT with clean targets dispatches immediately',
      (tester) async {
        final left = cleanTab('left');
        final mid = cleanTab('mid');
        final right = cleanTab('right');
        final tabsBloc = await pumpStrip(tester, [left, mid, right], mid, 1);

        await openContextMenu(tester, title: 'NEW REQUEST');
        await tester.tap(find.text('CLOSE TO THE LEFT'));
        await tester.pumpAndSettle();

        expect(find.text('UNSAVED CHANGES'), findsNothing);
        expect(
          tabsBloc.state.tabs.map((t) => t.tabId),
          ['mid', 'right'],
        );
      },
    );

    testWidgets(
      'CLOSE TO THE RIGHT with a dirty target confirms before dispatching',
      (tester) async {
        final left = cleanTab('left');
        final mid = cleanTab('mid');
        final right = dirtyTab('right');
        final tabsBloc = await pumpStrip(tester, [left, mid, right], mid, 1);

        await openContextMenu(tester, title: 'NEW REQUEST');
        await tester.tap(find.text('CLOSE TO THE RIGHT'));
        await tester.pumpAndSettle();

        expect(find.text('UNSAVED CHANGES'), findsOneWidget);
        await tester.tap(find.text('CLOSE ANYWAY'));
        await tester.pumpAndSettle();

        expect(
          tabsBloc.state.tabs.map((t) => t.tabId),
          ['left', 'mid'],
        );
      },
    );

    testWidgets(
      'CLOSE OTHERS with two dirty targets shows the plural confirm message',
      (tester) async {
        final left = dirtyTab('left');
        final mid = cleanTab('mid');
        final right = dirtyTab('right');
        final tabsBloc = await pumpStrip(tester, [left, mid, right], mid, 1);

        await openContextMenu(tester, title: 'NEW REQUEST');
        await tester.tap(find.text('CLOSE OTHERS'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            '2 TABS HAVE UNSAVED CHANGES. ARE YOU SURE YOU WANT TO '
            'CLOSE THEM?',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('CLOSE ANYWAY'));
        await tester.pumpAndSettle();

        expect(tabsBloc.state.tabs.map((t) => t.tabId), ['mid']);
      },
    );
  });
}
