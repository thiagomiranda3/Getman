import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/home/presentation/widgets/tab_widget.dart';
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

/// Stub the panel reads so [LoadTabs] surfaces [tab] in the active panel.
void _stubLoad(MockTabsRepository repo, HttpRequestTabEntity tab) {
  when(() => repo.getPanels()).thenAnswer(
    (_) async => [
      PanelEntity(
        id: 'p1',
        name: 'Panel 1',
        tabs: [tab],
        activeTabId: tab.tabId,
      ),
    ],
  );
  when(() => repo.getActivePanelId()).thenAnswer((_) async => 'p1');
}

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

  Future<void> pumpTab(WidgetTester tester, HttpRequestTabEntity tab) async {
    _stubLoad(tabsRepo, tab);
    final tabsBloc = TabsBloc(
      repository: tabsRepo,
      sendRequestUseCase: sendUseCase,
    )..add(const LoadTabs());
    await tabsBloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);

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
              // Centered so the screen's top-left corner (Offset.zero) is
              // OUTSIDE the tab — lets the pointer move on/off it to fire
              // MouseRegion onEnter/onExit.
              child: Center(
                child: TabWidget(
                  tabId: tab.tabId,
                  index: 0,
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
  }

  // The screen's top-left corner, outside the centered tab — moving on/off it
  // fires MouseRegion onEnter/onExit.
  const outside = Offset.zero;

  Future<TestGesture> hoverTab(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: outside);
    addTearDown(gesture.removePointer);
    await tester.pump();
    // The tab content is aligned to the top-left of its (tall) layout box, over
    // the title — not the geometric center. Aim just inside the top-left.
    final rect = tester.getRect(find.byType(TabWidget));
    await gesture.moveTo(rect.topLeft + const Offset(12, 12));
    await tester.pumpAndSettle();
    return gesture;
  }

  testWidgets('shows name + URL in a tooltip after the hover delay', (
    tester,
  ) async {
    await pumpTab(tester, _linkedTab());
    final tooltip = find.byKey(const ValueKey('tab_tooltip_tab1'));

    await hoverTab(tester);
    // Before the delay elapses, nothing is shown.
    await tester.pump(const Duration(milliseconds: 200));
    expect(tooltip, findsNothing);

    // After the delay, the tooltip appears with both lines.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(tooltip, findsOneWidget);
    expect(
      find.descendant(of: tooltip, matching: find.text('GetUsers')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tooltip, matching: find.text('https://api/users')),
      findsOneWidget,
    );
  });

  testWidgets(
    'switching between a flat and a rounded theme does not crash the tab '
    'chrome (no borderRadius-on-non-uniform-border lerp)',
    (tester) async {
      final tab = _linkedTab();
      _stubLoad(tabsRepo, tab);
      final tabsBloc = TabsBloc(
        repository: tabsRepo,
        sendRequestUseCase: sendUseCase,
      )..add(const LoadTabs());
      await tabsBloc.stream.firstWhere(
        (s) => !s.isLoading && s.tabs.isNotEmpty,
      );
      final collectionsBloc = CollectionsBloc(
        getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
        saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
        saveDebounce: const Duration(milliseconds: 5),
      )..add(const ReplaceCollections([]));
      await collectionsBloc.stream.first;
      addTearDown(tabsBloc.close);
      addTearDown(collectionsBloc.close);

      Widget appWith(ThemeData theme) => MaterialApp(
        theme: theme,
        // Snap the theme so the tabShape flips immediately; this isolates the
        // AnimatedContainer's own decoration tween (the crash source) from
        // MaterialApp's implicit AnimatedTheme transition.
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: tabsBloc),
              BlocProvider.value(value: collectionsBloc),
            ],
            child: RepositoryProvider<TabDirtyChecker>.value(
              value: const TabDirtyChecker(),
              child: Center(
                child: TabWidget(
                  tabId: tab.tabId,
                  index: 0,
                  isActive: true,
                  onTap: () {},
                  onClose: () async => true,
                ),
              ),
            ),
          ),
        ),
      );

      // Brutalist: an asymmetric (non-uniform) tab border and no radius.
      await tester.pumpWidget(appWith(brutalistTheme(Brightness.light)));
      await tester.pumpAndSettle();

      // Glass: a uniform border WITH a top radius. The AnimatedContainer must
      // not tween between the two shape families — a mid-tween frame would
      // carry a non-uniform border AND a borderRadius, which Border.paint
      // rejects ("A borderRadius can only be given on borders with uniform
      // colors").
      await tester.pumpWidget(appWith(glassTheme(Brightness.light)));
      await tester.pump(const Duration(milliseconds: 100)); // mid-tween frame

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('omits the URL line when the tab has no URL', (tester) async {
    await pumpTab(tester, _emptyTab());
    final tooltip = find.byKey(const ValueKey('tab_tooltip_tab2'));

    await hoverTab(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(tooltip, findsOneWidget);
    expect(
      find.descendant(of: tooltip, matching: find.text('NEW REQUEST')),
      findsOneWidget,
    );
    // Only the name line — no muted URL row.
    expect(
      find.descendant(of: tooltip, matching: find.byType(Text)),
      findsOneWidget,
    );
  });

  testWidgets('does not show the tooltip if the pointer leaves before delay', (
    tester,
  ) async {
    await pumpTab(tester, _linkedTab());
    final tooltip = find.byKey(const ValueKey('tab_tooltip_tab1'));

    final gesture = await hoverTab(tester);
    await tester.pump(const Duration(milliseconds: 200)); // < 500ms delay
    await gesture.moveTo(outside); // leave the tab
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tooltip, findsNothing);
  });

  testWidgets(
    'context menu shows MOVE TO PANEL when multiple panels exist',
    (tester) async {
      final tab1 = _linkedTab();
      final tab2 = _emptyTab();
      // Set up two panels so the MOVE TO PANEL item appears.
      when(() => tabsRepo.getPanels()).thenAnswer(
        (_) async => [
          PanelEntity(
            id: 'p1',
            name: 'Panel 1',
            tabs: [tab1],
            activeTabId: tab1.tabId,
          ),
          PanelEntity(
            id: 'p2',
            name: 'Panel 2',
            tabs: [tab2],
            activeTabId: tab2.tabId,
          ),
        ],
      );
      when(() => tabsRepo.getActivePanelId()).thenAnswer((_) async => 'p1');

      final tabsBloc = TabsBloc(
        repository: tabsRepo,
        sendRequestUseCase: sendUseCase,
      )..add(const LoadTabs());
      await tabsBloc.stream.firstWhere(
        (s) => !s.isLoading && s.tabs.isNotEmpty,
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
                  child: TabWidget(
                    tabId: tab1.tabId,
                    index: 0,
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

      // The tab title text is inside the GestureDetector — tap there with the
      // secondary mouse button to trigger onSecondaryTapDown → context menu.
      final titlePos = tester.getCenter(find.text('GetUsers'));
      await tester.tapAt(titlePos, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('tab_context_move_to_panel')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'MOVE TO PANEL submenu dispatches MoveTabToPanel on target panel tap',
    (tester) async {
      final tab1 = _linkedTab();
      final tab2 = _emptyTab();
      when(() => tabsRepo.getPanels()).thenAnswer(
        (_) async => [
          PanelEntity(
            id: 'p1',
            name: 'Panel 1',
            tabs: [tab1],
            activeTabId: tab1.tabId,
          ),
          PanelEntity(
            id: 'p2',
            name: 'Panel 2',
            tabs: [tab2],
            activeTabId: tab2.tabId,
          ),
        ],
      );
      when(() => tabsRepo.getActivePanelId()).thenAnswer((_) async => 'p1');

      final tabsBloc = TabsBloc(
        repository: tabsRepo,
        sendRequestUseCase: sendUseCase,
      )..add(const LoadTabs());
      await tabsBloc.stream.firstWhere(
        (s) => !s.isLoading && s.tabs.isNotEmpty,
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
                  child: TabWidget(
                    tabId: tab1.tabId,
                    index: 0,
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

      // Tap the tab title with the secondary button to open the context menu.
      final titlePos2 = tester.getCenter(find.text('GetUsers'));
      await tester.tapAt(titlePos2, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Tap MOVE TO PANEL — this triggers the post-frame callback that opens
      // the submenu.
      await tester.tap(
        find.byKey(const ValueKey('tab_context_move_to_panel')),
      );
      // Let the post-frame callback fire and the submenu build.
      await tester.pumpAndSettle();

      // The submenu should show Panel 2 (not Panel 1, which owns this tab).
      expect(
        find.byKey(const ValueKey('tab_move_to_panel_p2')),
        findsOneWidget,
      );
      // Panel 1 should NOT appear (it's the owner).
      expect(find.byKey(const ValueKey('tab_move_to_panel_p1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tab_move_to_panel_p2')));
      await tester.pumpAndSettle();

      // The bloc should have received MoveTabToPanel for tab1 → p2.
      expect(
        tabsBloc.state.panels
            .firstWhere((p) => p.id == 'p2')
            .tabs
            .any((t) => t.tabId == tab1.tabId),
        isTrue,
      );
    },
  );

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
                  child: TabWidget(
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
}
