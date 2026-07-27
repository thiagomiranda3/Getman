import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collection_node_row.dart';
import 'package:getman/features/collections/presentation/widgets/node_drag_data.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/tab_drag_data.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

void main() {
  late MockCollectionsRepository repo;

  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
  });

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  CollectionsBloc buildBloc() => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
  );

  const requestNode = CollectionNodeEntity(
    id: 'req-1',
    name: 'GetUser',
    isFolder: false,
    config: HttpRequestConfigEntity(id: 'req-1'),
  );

  const favoriteFolder = CollectionNodeEntity(
    id: 'fav-1',
    name: 'Favorites',
    isFavorite: true,
  );

  Widget host({required bool isSelected}) {
    final bloc = buildBloc();
    return MaterialApp(
      theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
      home: Scaffold(
        body: BlocProvider<CollectionsBloc>.value(
          value: bloc,
          child: CollectionNodeRow(
            node: requestNode,
            isExpanded: false,
            depth: 0,
            onToggle: () {},
            rowWidth: 300,
            rowHeight: 44,
            isSelected: isSelected,
          ),
        ),
      ),
    );
  }

  Widget favoriteHost(ThemeData theme) {
    final bloc = buildBloc();
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: BlocProvider<CollectionsBloc>.value(
          value: bloc,
          child: const CollectionNodeRow(
            node: favoriteFolder,
            isExpanded: false,
            depth: 0,
            onToggle: _noop,
            rowWidth: 300,
            rowHeight: 44,
          ),
        ),
      ),
    );
  }

  // Finds the AnimatedContainer whose BoxDecoration has a non-null border —
  // the selected accent bar. Returns null if none.
  BoxDecoration? selectedDecoration(WidgetTester tester) {
    final containers = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => c.decoration! as BoxDecoration)
        .where((d) => d.border != null);
    return containers.isEmpty ? null : containers.first;
  }

  testWidgets('request row paints a left accent border when selected', (
    tester,
  ) async {
    await tester.pumpWidget(host(isSelected: true));
    await tester.pumpAndSettle();

    final deco = selectedDecoration(tester);
    expect(deco, isNotNull, reason: 'selected row should have a border');
    final border = deco!.border! as Border;
    expect(border.left.width, greaterThan(0));
    // Background fill is present (non-transparent).
    expect(deco.color, isNotNull);
    expect(deco.color, isNot(Colors.transparent));
  });

  testWidgets('request row has no accent border when not selected', (
    tester,
  ) async {
    await tester.pumpWidget(host(isSelected: false));
    await tester.pumpAndSettle();

    expect(selectedDecoration(tester), isNull);
  });

  // Regression: the favorite-folder star used `theme.primaryColor`, which AURIS
  // leaves unset so Material defaults it to `colorScheme.surface` in dark mode
  // (near-black) — the star vanished into the background. It must use the brand
  // accent (`colorScheme.primary`), which is visible in both brightnesses.
  testWidgets('AURIS dark: favorite star is the visible brand accent', (
    tester,
  ) async {
    final theme = resolveTheme('auris')(Brightness.dark, isCompact: false);
    await tester.pumpWidget(favoriteHost(theme));
    await tester.pumpAndSettle();

    final star = tester.widget<Icon>(find.byIcon(Icons.star));
    expect(star.color, theme.colorScheme.primary);
    expect(
      star.color,
      isNot(theme.colorScheme.surface),
      reason: 'star must not match the surface/background color',
    );
  });

  // Right-click anywhere on a row must open the same context menu as the
  // trailing "⋮" button (standard desktop QoL), at the cursor.
  testWidgets('right-clicking a request row opens the node context menu', (
    tester,
  ) async {
    await tester.pumpWidget(host(isSelected: false));
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('GetUser'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('RENAME'), findsOneWidget);
    expect(find.text('DELETE'), findsOneWidget);
    // Folder-only entries must not appear for a request.
    expect(find.text('ADD SUBFOLDER'), findsNothing);
    expect(find.text('VARIABLES'), findsNothing);

    // Selecting an entry routes to the same action as the "⋮" menu: RENAME
    // opens the name prompt dialog.
    await tester.tap(find.text('RENAME'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('right-clicking a folder row opens the folder context menu', (
    tester,
  ) async {
    final theme = resolveTheme('brutalist')(Brightness.light, isCompact: false);
    await tester.pumpWidget(favoriteHost(theme));
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Favorites'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('ADD SUBFOLDER'), findsOneWidget);
    expect(find.text('VARIABLES'), findsOneWidget);
    expect(find.text('UNFAVORITE'), findsOneWidget);
  });

  // Regression: leaf request rows had no DragTarget, so dropping a request onto
  // another request inside a folder fell through to the list-level root target
  // and moved it to the ROOT. A leaf drop must land in the target's folder.
  testWidgets(
    'dropping a request onto a request inside a folder moves it into that '
    'folder, not to the root',
    (tester) async {
      const draggedId = 'dragged';
      final tree = <CollectionNodeEntity>[
        const CollectionNodeEntity(
          id: 'f1',
          name: 'Folder1',
          children: [requestNode], // req-1 lives inside Folder1
        ),
        const CollectionNodeEntity(
          id: draggedId,
          name: 'Dragged',
          isFolder: false,
          config: HttpRequestConfigEntity(id: draggedId),
        ),
      ];
      when(() => repo.getCollections()).thenAnswer((_) async => tree);

      final bloc = buildBloc()..add(const LoadCollections());

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<CollectionsBloc>.value(
              value: bloc,
              child: const CollectionNodeRow(
                node: requestNode, // the leaf that lives inside Folder1
                isExpanded: false,
                depth: 1,
                onToggle: _noop,
                rowWidth: 300,
                rowHeight: 44,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dragTarget = tester.widget<DragTarget<NodeDragData>>(
        find.byType(DragTarget<NodeDragData>),
      );
      dragTarget.onAcceptWithDetails!(
        DragTargetDetails<NodeDragData>(
          data: const NodeDragData(draggedId),
          offset: Offset.zero,
        ),
      );
      // Let the MoveNode handler emit, then fire the bloc's debounced-save
      // timer so no timer is left pending when the widget tree is disposed.
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final folder = bloc.state.collections.firstWhere((n) => n.id == 'f1');
      expect(
        folder.children.map((c) => c.id),
        containsAll(<String>['req-1', draggedId]),
        reason: 'dragged request should land inside Folder1',
      );
      expect(
        bloc.state.collections.map((n) => n.id),
        isNot(contains(draggedId)),
        reason: 'dragged request should no longer be at the root',
      );
    },
  );

  // D5 regression: the leaf target highlighted ANY non-self drag, unlike the
  // folder target (which already checks isDescendantOrSelf). Dropping folder
  // F onto a request that lives inside F highlighted, then silently no-op'd
  // (the bloc rejects moving a folder into its own subtree) — the leaf guard
  // must mirror the folder's.
  testWidgets(
    'dragging an ancestor folder over one of its own descendant requests '
    'does not highlight the leaf target (D5)',
    (tester) async {
      const folderId = 'f1';
      final tree = <CollectionNodeEntity>[
        const CollectionNodeEntity(
          id: folderId,
          name: 'Folder1',
          children: [requestNode], // req-1 lives inside Folder1
        ),
      ];
      when(() => repo.getCollections()).thenAnswer((_) async => tree);
      final bloc = buildBloc()..add(const LoadCollections());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<CollectionsBloc>.value(
              value: bloc,
              child: const CollectionNodeRow(
                node: requestNode, // the leaf that lives inside Folder1
                isExpanded: false,
                depth: 1,
                onToggle: _noop,
                rowWidth: 300,
                rowHeight: 44,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dragTarget = tester.widget<DragTarget<NodeDragData>>(
        find.byType(DragTarget<NodeDragData>),
      );
      // Drag the ANCESTOR folder over its own descendant leaf.
      dragTarget.onWillAcceptWithDetails!(
        DragTargetDetails<NodeDragData>(
          data: const NodeDragData(folderId),
          offset: Offset.zero,
        ),
      );
      await tester.pump();

      expect(
        _isBrutalistDropHighlightActive(tester),
        isFalse,
        reason:
            'dropping an ancestor folder onto its own descendant must not '
            'highlight — the bloc silently rejects that move',
      );
    },
  );

  testWidgets(
    'dragging an unrelated node over a leaf DOES highlight it (contrast '
    'check for the D5 assertion above)',
    (tester) async {
      const otherId = 'unrelated-node';
      final tree = <CollectionNodeEntity>[requestNode];
      when(() => repo.getCollections()).thenAnswer((_) async => tree);
      final bloc = buildBloc()..add(const LoadCollections());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<CollectionsBloc>.value(
              value: bloc,
              child: const CollectionNodeRow(
                node: requestNode,
                isExpanded: false,
                depth: 0,
                onToggle: _noop,
                rowWidth: 300,
                rowHeight: 44,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dragTarget = tester.widget<DragTarget<NodeDragData>>(
        find.byType(DragTarget<NodeDragData>),
      );
      dragTarget.onWillAcceptWithDetails!(
        DragTargetDetails<NodeDragData>(
          data: const NodeDragData(otherId),
          offset: Offset.zero,
        ),
      );
      await tester.pump();

      expect(_isBrutalistDropHighlightActive(tester), isTrue);
    },
  );

  // D4 regression: a tab dragged out of the tab strip must not be accepted
  // (or even highlight) a collections-tree drop target — the two used to
  // share `Draggable<String>`/`DragTarget<String>`, so a tab dropped on a
  // folder row would light it up and dispatch a no-op MoveNode.
  testWidgets(
    'a tab drag (TabDragData) is rejected by a folder row — no highlight, '
    'no MoveNode dispatched',
    (tester) async {
      const folderNode = CollectionNodeEntity(id: 'folder-1', name: 'Folder');
      when(
        () => repo.getCollections(),
      ).thenAnswer((_) async => const [folderNode]);
      final bloc = buildBloc()..add(const LoadCollections());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<CollectionsBloc>.value(
              value: bloc,
              child: const Column(
                children: [
                  LongPressDraggable<TabDragData>(
                    key: ValueKey('tab_drag_source'),
                    data: TabDragData('tab-1'),
                    feedback: Material(child: Text('tab-1')),
                    child: SizedBox(
                      width: 100,
                      height: 50,
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ),
                  CollectionNodeRow(
                    node: folderNode,
                    isExpanded: false,
                    depth: 0,
                    onToggle: _noop,
                    rowWidth: 300,
                    rowHeight: 44,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sourceCenter = tester.getCenter(
        find.byKey(const ValueKey('tab_drag_source')),
      );
      final targetCenter = tester.getCenter(find.byType(CollectionNodeRow));
      final gesture = await tester.startGesture(sourceCenter);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(targetCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        _isBrutalistDropHighlightActive(tester),
        isFalse,
        reason: 'a foreign (tab) payload must not highlight a node target',
      );
      expect(
        bloc.state.collections,
        const [folderNode],
        reason: 'no MoveNode should have been dispatched',
      );
    },
  );

  // Hosts a row under both a CollectionsBloc and a (mock) TabsBloc so leaf
  // taps can dispatch AddTab.
  Widget rowHostWithTabs(
    CollectionsBloc collections,
    TabsBloc tabs,
    CollectionNodeEntity node, {
    VoidCallback onToggle = _noop,
  }) {
    return MaterialApp(
      theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<CollectionsBloc>.value(value: collections),
            BlocProvider<TabsBloc>.value(value: tabs),
          ],
          child: CollectionNodeRow(
            node: node,
            isExpanded: false,
            depth: 0,
            onToggle: onToggle,
            rowWidth: 300,
            rowHeight: 44,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'tapping a request row opens it in a new tab linked to the node',
    (tester) async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      await tester.pumpWidget(rowHostWithTabs(bloc, tabs, requestNode));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GetUser'));
      await tester.pump();

      final added =
          verify(() => tabs.add(captureAny())).captured.single as AddTab;
      expect(added.collectionNodeId, 'req-1');
      expect(added.collectionName, 'GetUser');
      expect(added.config?.id, 'req-1');
    },
  );

  testWidgets(
    'request with saved examples shows a toggle chevron + example count, and '
    'the chevron toggles without opening a tab',
    (tester) async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);
      var toggled = 0;

      final nodeWithExamples = requestNode.copyWith(
        examples: [
          SavedExampleEntity(
            id: 'e1',
            name: 'First',
            capturedAt: DateTime.utc(2026, 7, 26),
            config: const HttpRequestConfigEntity(id: 'req-1'),
          ),
          SavedExampleEntity(
            id: 'e2',
            name: 'Second',
            capturedAt: DateTime.utc(2026, 7, 26),
            config: const HttpRequestConfigEntity(id: 'req-1'),
          ),
        ],
      );

      await tester.pumpWidget(
        rowHostWithTabs(
          bloc,
          tabs,
          nodeWithExamples,
          onToggle: () => toggled++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pump();

      expect(toggled, 1);
      verifyNever(() => tabs.add(any()));
    },
  );

  testWidgets(
    'a request without examples reserves the chevron space but shows none',
    (tester) async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      await tester.pumpWidget(rowHostWithTabs(bloc, tabs, requestNode));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_right), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    },
  );

  testWidgets(
    'a non-HTTP request shows its protocol label instead of an HTTP method',
    (tester) async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      const wsNode = CollectionNodeEntity(
        id: 'ws-1',
        name: 'LiveFeed',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'ws-1',
          kind: RequestKind.webSocket,
        ),
      );

      await tester.pumpWidget(rowHostWithTabs(bloc, tabs, wsNode));
      await tester.pumpAndSettle();

      expect(find.text('WS'), findsOneWidget);
      expect(find.text('GET'), findsNothing);
    },
  );

  testWidgets(
    'dropping a node onto a folder row moves it into that folder',
    (tester) async {
      const folderNode = CollectionNodeEntity(id: 'f1', name: 'Folder1');
      const draggedId = 'dragged';
      final tree = <CollectionNodeEntity>[
        folderNode,
        const CollectionNodeEntity(
          id: draggedId,
          name: 'Dragged',
          isFolder: false,
          config: HttpRequestConfigEntity(id: draggedId),
        ),
      ];
      when(() => repo.getCollections()).thenAnswer((_) async => tree);
      final bloc = buildBloc()..add(const LoadCollections());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<CollectionsBloc>.value(
              value: bloc,
              child: const CollectionNodeRow(
                node: folderNode,
                isExpanded: false,
                depth: 0,
                onToggle: _noop,
                rowWidth: 300,
                rowHeight: 44,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dragTarget = tester.widget<DragTarget<NodeDragData>>(
        find.byType(DragTarget<NodeDragData>),
      );
      dragTarget.onAcceptWithDetails!(
        DragTargetDetails<NodeDragData>(
          data: const NodeDragData(draggedId),
          offset: Offset.zero,
        ),
      );
      // Let MoveNode emit, then fire the debounced-save timer so no timer is
      // left pending at teardown.
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final folder = bloc.state.collections.firstWhere((n) => n.id == 'f1');
      expect(folder.children.map((c) => c.id), contains(draggedId));
      expect(
        bloc.state.collections.map((n) => n.id),
        isNot(contains(draggedId)),
      );
    },
  );

  testWidgets(
    'a legal drag over a folder row highlights it and leaving clears it',
    (tester) async {
      const folderNode = CollectionNodeEntity(id: 'f1', name: 'Folder1');
      when(
        () => repo.getCollections(),
      ).thenAnswer(
        (_) async => const [
          folderNode,
          CollectionNodeEntity(
            id: 'other',
            name: 'Other',
            isFolder: false,
            config: HttpRequestConfigEntity(id: 'other'),
          ),
        ],
      );
      final bloc = buildBloc()..add(const LoadCollections());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
          home: Scaffold(
            body: BlocProvider<CollectionsBloc>.value(
              value: bloc,
              child: const CollectionNodeRow(
                node: folderNode,
                isExpanded: false,
                depth: 0,
                onToggle: _noop,
                rowWidth: 300,
                rowHeight: 44,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dragTarget = tester.widget<DragTarget<NodeDragData>>(
        find.byType(DragTarget<NodeDragData>),
      );
      dragTarget.onWillAcceptWithDetails!(
        DragTargetDetails<NodeDragData>(
          data: const NodeDragData('other'),
          offset: Offset.zero,
        ),
      );
      await tester.pump();
      expect(_isBrutalistDropHighlightActive(tester), isTrue);

      dragTarget.onLeave!(const NodeDragData('other'));
      await tester.pump();
      expect(_isBrutalistDropHighlightActive(tester), isFalse);
    },
  );

  testWidgets(
    'phone width: long-pressing a row opens the node action sheet',
    (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bloc = buildBloc();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      await tester.pumpWidget(rowHostWithTabs(bloc, tabs, requestNode));
      await tester.pumpAndSettle();

      // Phone rows are not draggable — long-press opens the action sheet.
      expect(find.byType(Draggable<NodeDragData>), findsNothing);

      await tester.longPress(find.text('GetUser'));
      // Bounded pumps: let the bottom-sheet entrance animation run.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('MOVE TO...'), findsOneWidget);
      expect(find.text('RENAME'), findsOneWidget);
    },
  );

  testWidgets('dragging a row shows the drag feedback with the node name', (
    tester,
  ) async {
    final bloc = buildBloc();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    await tester.pumpWidget(rowHostWithTabs(bloc, tabs, requestNode));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('GetUser')),
    );
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();

    expect(
      find.text('GetUser'),
      findsNWidgets(2),
      reason: 'row + drag feedback should both show the name mid-drag',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('GetUser'), findsOneWidget);
  });
}

/// Whether the brutalist theme's tree-drop highlight is currently active.
/// `_BrutalistTreeDropHighlight` is a private widget internal to the theme's
/// motion file, so it's matched by its runtime type name and its `active`
/// field is read dynamically — there's no public hook to query it otherwise.
bool _isBrutalistDropHighlightActive(WidgetTester tester) {
  final matches = tester.widgetList(
    find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_BrutalistTreeDropHighlight',
    ),
  );
  if (matches.isEmpty) return false;
  return (matches.single as dynamic).active as bool;
}

void _noop() {}
