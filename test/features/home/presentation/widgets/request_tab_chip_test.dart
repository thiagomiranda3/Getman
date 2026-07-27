import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<TabsBloc> pumpTab(
    WidgetTester tester,
    HttpRequestTabEntity tab, {
    bool isActive = true,
    VoidCallback? onTap,
    Future<bool> Function()? onClose,
  }) async {
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
                child: RequestTabChip(
                  tabId: tab.tabId,
                  index: 0,
                  isActive: isActive,
                  onTap: onTap ?? () {},
                  onClose: onClose ?? () async => true,
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
    final rect = tester.getRect(find.byType(RequestTabChip));
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
                child: RequestTabChip(
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
                  child: RequestTabChip(
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
                  child: RequestTabChip(
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

  group('Wave-3 context-menu entries', () {
    testWidgets('REOPEN CLOSED TAB is present and disabled when the stack is '
        'empty', (tester) async {
      await pumpTab(tester, _linkedTab());
      await openContextMenu(tester);

      expect(find.text('REOPEN CLOSED TAB'), findsOneWidget);
      final item = tester.widget<PopupMenuItem<void>>(
        find.ancestor(
          of: find.text('REOPEN CLOSED TAB'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem<void>),
        ),
      );
      expect(item.enabled, isFalse);
    });

    testWidgets(
      'CLOSE SAVED TABS dispatches CloseSavedTabs for the active panel — '
      'closes the clean tab onto the reopen stack and keeps the dirty one',
      (tester) async {
        // Two tabs in the SAME panel: `dirty` (_linkedTab, linked to node1
        // with no matching saved node → DIRTY) and `clean` (_emptyTab,
        // unlinked → matches the pristine default config → CLEAN). This is
        // discriminating: a single-dirty-tab panel passes
        // `hasLength(1)` whether CLOSE SAVED TABS actually ran, used the
        // wrong panelId, or was never dispatched at all — a second, closable
        // tab is required to prove the dispatch actually reached the bloc.
        final dirty = _linkedTab();
        final clean = _emptyTab();
        when(() => tabsRepo.getPanels()).thenAnswer(
          (_) async => [
            PanelEntity(
              id: 'p1',
              name: 'Panel 1',
              tabs: [dirty, clean],
              activeTabId: dirty.tabId,
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
                      tabId: dirty.tabId,
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

        await openContextMenu(tester);

        await tester.tap(find.text('CLOSE SAVED TABS'));
        await tester.pumpAndSettle();

        expect(
          tabsBloc.state.tabs.map((t) => t.tabId),
          [dirty.tabId],
          reason: 'the clean tab closed; the dirty tab was kept',
        );
        expect(
          tabsBloc.canReopenClosedTab,
          isTrue,
          reason: 'the closed clean tab landed on the reopen stack',
        );
      },
    );

    testWidgets('REVERT CHANGES appears only for a DIRTY linked tab, confirms, '
        'and reverts', (tester) async {
      // Seed collections so the linked node exists with a DIFFERENT config →
      // dirty. The harness's collectionsBloc is reachable via the tree.
      const saved = HttpRequestConfigEntity(
        id: 'node1',
        url: 'https://api/users?orig=1',
      );
      await pumpTab(tester, _linkedTab()); // config url https://api/users
      final chipState = tester.state<State<RequestTabChip>>(
        find.byType(RequestTabChip),
      );
      chipState.context.read<CollectionsBloc>().add(
        const ReplaceCollections([
          CollectionNodeEntity(
            id: 'node1',
            name: 'GetUsers',
            isFolder: false,
            config: saved,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await openContextMenu(tester);
      expect(find.text('REVERT CHANGES'), findsOneWidget);

      await tester.tap(find.text('REVERT CHANGES'));
      await tester.pumpAndSettle();

      expect(
        find.text('Discard unsaved changes to this request?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'REVERT'));
      await tester.pumpAndSettle();

      final tabsBloc = chipState.context.read<TabsBloc>();
      expect(tabsBloc.state.tabs.first.config, saved);

      // RevertTab schedules TabsBloc's 10s save debounce; flush it so no
      // Timer is left pending when the test ends (mirrors url_bar_test.dart).
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('REVERT CHANGES is absent for a clean linked tab', (
      tester,
    ) async {
      await pumpTab(tester, _linkedTab());
      final chipState = tester.state<State<RequestTabChip>>(
        find.byType(RequestTabChip),
      );
      // Saved node config IDENTICAL to the tab's → clean.
      chipState.context.read<CollectionsBloc>().add(
        const ReplaceCollections([
          CollectionNodeEntity(
            id: 'node1',
            name: 'GetUsers',
            isFolder: false,
            config: HttpRequestConfigEntity(
              id: 'node1',
              url: 'https://api/users',
            ),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await openContextMenu(tester);
      expect(find.text('REVERT CHANGES'), findsNothing);
    });
  });

  group('chip interactions', () {
    testWidgets('tapping the chip fires onTap', (tester) async {
      var tapped = false;
      await pumpTab(tester, _linkedTab(), onTap: () => tapped = true);

      await tester.tap(find.text('GetUsers'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets(
      'close button animates the chip out and dispatches RemoveTab',
      (tester) async {
        final tabsBloc = await pumpTab(tester, _linkedTab());

        await tester.tap(find.byKey(const ValueKey('tab_close_tab1')));
        // Confirm callback + the 300ms reverse size animation.
        await tester.pumpAndSettle();

        expect(tabsBloc.state.tabs, isEmpty);
      },
    );

    testWidgets('close is a no-op when onClose declines', (tester) async {
      final tabsBloc = await pumpTab(
        tester,
        _linkedTab(),
        onClose: () async => false,
      );

      await tester.tap(find.byKey(const ValueKey('tab_close_tab1')));
      await tester.pumpAndSettle();

      expect(tabsBloc.state.tabs, hasLength(1));
    });

    testWidgets('inactive dirty chip renders the dirty star', (tester) async {
      // _linkedTab() links to node1 with no saved collections → dirty.
      await pumpTab(tester, _linkedTab(), isActive: false);

      expect(find.text('*'), findsOneWidget);
    });

    testWidgets(
      'long-press drag shows the drag-feedback chip and the dimmed ghost',
      (tester) async {
        await pumpTab(tester, _linkedTab());

        final center = tester.getCenter(find.text('GetUsers'));
        final gesture = await tester.startGesture(center);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await gesture.moveBy(const Offset(60, 60));
        await tester.pump();

        // The title now paints twice: once in the childWhenDragging ghost,
        // once in the floating _TabDragFeedback chip.
        expect(find.text('GetUsers'), findsNWidgets(2));
        expect(
          tester
              .widgetList<Opacity>(find.byType(Opacity))
              .any((w) => w.opacity == 0.4),
          isTrue,
          reason: 'the ghost dims the in-strip chip while dragging',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.text('GetUsers'), findsOneWidget);
      },
    );
  });

  group('context-menu actions', () {
    testWidgets('DUPLICATE dispatches DuplicateTab and shows a snackbar', (
      tester,
    ) async {
      final tabsBloc = await pumpTab(tester, _linkedTab());
      await openContextMenu(tester);

      await tester.tap(find.text('DUPLICATE'));
      await tester.pumpAndSettle();

      expect(tabsBloc.state.tabs, hasLength(2));
      expect(find.text('Tab duplicated'), findsOneWidget);

      // DuplicateTab schedules TabsBloc's save debounce; flush it.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('COPY URL puts the tab URL on the clipboard', (tester) async {
      final clipboardLog = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardLog.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpTab(tester, _linkedTab());
      await openContextMenu(tester);

      await tester.tap(find.text('COPY URL'));
      await tester.pumpAndSettle();

      expect(clipboardLog, hasLength(1));
      expect(
        (clipboardLog.single.arguments as Map<Object?, Object?>)['text'],
        'https://api/users',
      );
      expect(find.text('URL copied'), findsOneWidget);
    });

    testWidgets(
      'REOPEN CLOSED TAB is enabled after a close and restores the tab',
      (tester) async {
        final tabsBloc = await pumpTab(tester, _linkedTab());

        // Duplicate first so a close leaves the chip's own tab in place.
        await openContextMenu(tester);
        await tester.tap(find.text('DUPLICATE'));
        await tester.pumpAndSettle();
        expect(tabsBloc.state.tabs, hasLength(2));

        // Close the duplicate (clean? both are linked copies — close via
        // CLOSE OTHERS which prompts for the dirty duplicate).
        await openContextMenu(tester);
        await tester.tap(find.text('CLOSE OTHERS'));
        await tester.pumpAndSettle();
        // The duplicate is dirty (linked node1 has no saved config) → confirm.
        await tester.tap(find.text('CLOSE ANYWAY'));
        await tester.pumpAndSettle();
        expect(tabsBloc.state.tabs, hasLength(1));
        expect(tabsBloc.canReopenClosedTab, isTrue);

        await openContextMenu(tester);
        final item = tester.widget<PopupMenuItem<void>>(
          find.ancestor(
            of: find.text('REOPEN CLOSED TAB'),
            matching: find.byWidgetPredicate((w) => w is PopupMenuItem<void>),
          ),
        );
        expect(item.enabled, isTrue);

        await tester.tap(find.text('REOPEN CLOSED TAB'));
        await tester.pumpAndSettle();

        expect(tabsBloc.state.tabs, hasLength(2));

        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'MOVE TO PANEL → NEW PANEL… moves the tab into a fresh panel',
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
                    child: RequestTabChip(
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

        await openContextMenu(tester);
        await tester.tap(
          find.byKey(const ValueKey('tab_context_move_to_panel')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('tab_move_to_new_panel')));
        await tester.pumpAndSettle();

        expect(tabsBloc.state.panels, hasLength(3));
        final newPanel = tabsBloc.state.panels.last;
        expect(newPanel.tabs.single.tabId, tab1.tabId);

        await tester.pump(const Duration(seconds: 11));
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
