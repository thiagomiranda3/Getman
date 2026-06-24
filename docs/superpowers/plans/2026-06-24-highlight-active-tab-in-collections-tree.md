# Highlight & Reveal Active Tab's Linked Request in Collections Tree — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a request tab is focused, if it is linked to a saved collection request, highlight that request in the collections tree, auto-expand its ancestor folders, and scroll it into view.

**Architecture:** Pure widget-layer coordination. `CollectionsList` reads `TabsBloc`, derives the active tab's `collectionNodeId`, and drives a "selected" highlight on the matching `CollectionNodeRow` plus expand + scroll. No bloc→bloc coupling, no new bloc state, no Hive/model changes. A new pure helper `CollectionsTreeHelper.ancestorFolderIds` supplies the folders to expand.

**Tech Stack:** Flutter, `flutter_bloc`, `two_dimensional_scrollables` (`TreeView`), `bloc_test`/`mocktail` (tests). Always invoke Flutter as `fvm flutter ...`.

## Global Constraints

- Flutter is pinned via `.fvmrc` — always run `fvm flutter ...`, never plain `flutter`.
- Done-bar (run all, expect zero issues): `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test tools`, and `fvm flutter test` (100% green).
- Imports are `package:getman/...` everywhere (no relative imports; `directives_ordering` enforced — keep imports alphabetically ordered).
- No hardcoded colors/sizes/radii/weights in widgets — pull from `context.appLayout` / `theme.primaryColor` etc. `Colors.black/white/red` literals are banned by `avoid_hardcoded_brand_colors` (outside `lib/core/theme/`).
- Domain layer (`domain/`) imports only pure Dart + `equatable` — no Flutter, no `data/`.
- `listenWhen`/`buildWhen` are mandatory on expensive rebuild paths (the tree).
- Expansion is owned by `_expandedIds` (`Set<String>`), reseeded into `TreeViewNode(expanded:)` each rebuild — do NOT switch to value-keyed expansion (H2 regression).
- Keep the GitHub wiki in sync (Collections page) — this changes how the feature is used.

---

### Task 1: `CollectionsTreeHelper.ancestorFolderIds` (pure helper)

**Files:**
- Modify: `lib/features/collections/domain/logic/collections_tree_helper.dart` (add a public static method near the existing `_pathTo` at lines 121-133)
- Test: `test/collections_tree_helper_test.dart` (append a new `group`)

**Interfaces:**
- Consumes: the existing private `static List<CollectionNodeEntity>? _pathTo(List<CollectionNodeEntity> nodes, String id)`.
- Produces: `static List<String> ancestorFolderIds(List<CollectionNodeEntity> nodes, String id)` — the ids of every ancestor on the path down to `id` (root first, nearest parent last), excluding `id` itself. Returns `[]` for a root node or an unknown id.

- [ ] **Step 1: Write the failing tests**

Append to `test/collections_tree_helper_test.dart`, inside `void main() { ... }` (after the last existing `group`, before the closing `}`):

```dart
  group('ancestorFolderIds', () {
    test('returns empty for a root node', () {
      final nodes = [folder('a', 'A'), leaf('b', 'B')];
      expect(CollectionsTreeHelper.ancestorFolderIds(nodes, 'a'), isEmpty);
      expect(CollectionsTreeHelper.ancestorFolderIds(nodes, 'b'), isEmpty);
    });

    test('returns empty for an unknown id', () {
      final nodes = [folder('a', 'A', children: [leaf('b', 'B')])];
      expect(CollectionsTreeHelper.ancestorFolderIds(nodes, 'zzz'), isEmpty);
    });

    test('returns ordered ancestor ids (root first) for a nested leaf', () {
      final nodes = [
        folder(
          'root',
          'Root',
          children: [
            folder(
              'mid',
              'Mid',
              children: [leaf('deep', 'Deep')],
            ),
          ],
        ),
      ];
      expect(
        CollectionsTreeHelper.ancestorFolderIds(nodes, 'deep'),
        ['root', 'mid'],
      );
    });

    test('excludes the target node itself', () {
      final nodes = [
        folder('root', 'Root', children: [leaf('child', 'Child')]),
      ];
      final ids = CollectionsTreeHelper.ancestorFolderIds(nodes, 'child');
      expect(ids, ['root']);
      expect(ids, isNot(contains('child')));
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/collections_tree_helper_test.dart`
Expected: FAIL — `The method 'ancestorFolderIds' isn't defined for the type 'CollectionsTreeHelper'`.

- [ ] **Step 3: Implement the helper**

In `lib/features/collections/domain/logic/collections_tree_helper.dart`, add this method immediately after the `_pathTo` method (after line 133):

```dart
  /// The ids of every ancestor folder on the path down to [id] (root first,
  /// nearest parent last), excluding [id] itself. Empty if [id] is a root node
  /// or is not found. Used to auto-expand a node into view.
  static List<String> ancestorFolderIds(
    List<CollectionNodeEntity> nodes,
    String id,
  ) {
    final path = _pathTo(nodes, id);
    if (path == null || path.length < 2) return const [];
    return [for (final node in path.sublist(0, path.length - 1)) node.id];
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/collections_tree_helper_test.dart`
Expected: PASS (all `ancestorFolderIds` tests green, existing tests still green).

- [ ] **Step 5: Analyze + format**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test`
Expected: No issues found; formatter reports 0 changed (or formats the 2 touched files).

- [ ] **Step 6: Commit**

```bash
git add lib/features/collections/domain/logic/collections_tree_helper.dart test/collections_tree_helper_test.dart
git commit -m "feat(collections): add ancestorFolderIds tree helper"
```

---

### Task 2: `CollectionNodeRow` `isSelected` highlight

**Files:**
- Modify: `lib/features/collections/presentation/widgets/collection_node_row.dart`
- Test: `test/features/collections/presentation/widgets/collection_node_row_test.dart` (create)

**Interfaces:**
- Consumes: `context.appLayout.borderThick` (double), `Theme.of(context).primaryColor`.
- Produces: `CollectionNodeRow({required CollectionNodeEntity node, required bool isExpanded, required int depth, required VoidCallback onToggle, required double rowWidth, required double rowHeight, bool isSelected = false, Key? key})`. When `isSelected` is true, the request row paints a left accent bar (`theme.primaryColor`, width `layout.borderThick`) + a `theme.primaryColor.withValues(alpha: 0.12)` background fill.

- [ ] **Step 1: Write the failing test**

Create `test/features/collections/presentation/widgets/collection_node_row_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/widgets/collection_node_row.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

void main() {
  late MockCollectionsRepository repo;

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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/collection_node_row_test.dart`
Expected: FAIL — `No named parameter with the name 'isSelected'` (compile error).

- [ ] **Step 3: Add the `isSelected` field**

In `lib/features/collections/presentation/widgets/collection_node_row.dart`, update the constructor + fields (lines 18-33). Add `this.isSelected = false,` to the constructor parameter list (after `required this.rowHeight,`) and add the field declaration (after `final double rowHeight;`):

Constructor — change:

```dart
  const CollectionNodeRow({
    required this.node,
    required this.isExpanded,
    required this.depth,
    required this.onToggle,
    required this.rowWidth,
    required this.rowHeight,
    super.key,
  });
```

to:

```dart
  const CollectionNodeRow({
    required this.node,
    required this.isExpanded,
    required this.depth,
    required this.onToggle,
    required this.rowWidth,
    required this.rowHeight,
    this.isSelected = false,
    super.key,
  });
```

Fields — change:

```dart
  final double rowWidth;
  final double rowHeight;
```

to:

```dart
  final double rowWidth;
  final double rowHeight;

  /// Whether this row is the saved request linked to the currently-focused
  /// tab — painted with an accent bar + tint so the user can see which tree
  /// node their active tab came from.
  final bool isSelected;
```

- [ ] **Step 4: Paint the selected decoration on the request row**

In the same file, in the request branch (the `else` at line 149), replace the `AnimatedContainer`'s `decoration` (currently lines 173-175):

```dart
                decoration: BoxDecoration(
                  color: _isHovered ? theme.hoverColor : Colors.transparent,
                ),
```

with:

```dart
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? theme.primaryColor.withValues(alpha: 0.12)
                      : (_isHovered ? theme.hoverColor : Colors.transparent),
                  border: widget.isSelected
                      ? Border(
                          left: BorderSide(
                            color: theme.primaryColor,
                            width: layout.borderThick,
                          ),
                        )
                      : null,
                ),
```

(Leave the folder branch unchanged — a linked `collectionNodeId` always points at a leaf request.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `fvm flutter test test/features/collections/presentation/widgets/collection_node_row_test.dart`
Expected: PASS (both tests green).

- [ ] **Step 6: Analyze + format**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add lib/features/collections/presentation/widgets/collection_node_row.dart test/features/collections/presentation/widgets/collection_node_row_test.dart
git commit -m "feat(collections): add isSelected accent-bar highlight to CollectionNodeRow"
```

---

### Task 3: `CollectionsList` coordinator — derive selection, reveal, scroll

**Files:**
- Modify: `lib/features/collections/presentation/widgets/collections_list.dart`
- Modify: `test/features/collections/presentation/widgets/collections_list_test.dart` (existing tests need a `TabsBloc` ancestor once the listener is added; plus a new behavior test)

**Interfaces:**
- Consumes: `CollectionsTreeHelper.ancestorFolderIds` (Task 1); `CollectionNodeRow(isSelected:)` (Task 2); `TabsBloc`/`TabsState` (`state.tabs`, `state.activeIndex`, `HttpRequestTabEntity.collectionNodeId`); `TreeView.verticalDetails` (a `ScrollableDetails`); `CollectionsTreeHelper.findNode`.
- Produces: no public API; internal behavior only.

- [ ] **Step 1: Write the failing behavior test**

Replace the entire contents of `test/features/collections/presentation/widgets/collections_list_test.dart` with the version below. It adds a `MockTabsBloc`, gives every existing test a `TabsBloc` ancestor (required now that `CollectionsList` listens to it), and adds the new highlight+reveal test. The shared `host(...)` helper drives the `TabsBloc` via `whenListen` so the listener fires.

```dart
// Widget tests for the collections tree:
//  - H2 fix: folders stay expanded across unrelated mutations.
//  - Import menu opens.
//  - Active-tab linkage: focusing a tab linked to a saved request auto-expands
//    its ancestor folders and highlights the matching row.

import 'package:bloc_test/bloc_test.dart';
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
import 'package:getman/features/collections/presentation/widgets/collection_node_row.dart';
import 'package:getman/features/collections/presentation/widgets/collections_list.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

HttpRequestTabEntity _tab(String tabId, {String? linkedNodeId}) =>
    HttpRequestTabEntity(
      tabId: tabId,
      config: HttpRequestConfigEntity(id: tabId),
      collectionNodeId: linkedNodeId,
    );

TabsState _stateWith(HttpRequestTabEntity tab) =>
    TabsState(tabs: [tab], activeIndex: 0);

void main() {
  late MockCollectionsRepository repo;

  setUpAll(() {
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(_FakeTabsEvent());
  });

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  CollectionsBloc build() => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
    saveDebounce: const Duration(milliseconds: 5),
  );

  // Builds the widget under a CollectionsBloc + a MockTabsBloc. [tabsStates], if
  // given, are emitted (after [tabsInitial]) so the active-tab listener fires.
  Widget host(
    CollectionsBloc collections,
    MockTabsBloc tabs, {
    TabsState tabsInitial = const TabsState(),
    List<TabsState> tabsStates = const [],
  }) {
    when(() => tabs.state).thenReturn(
      tabsStates.isNotEmpty ? tabsStates.last : tabsInitial,
    );
    whenListen(
      tabs,
      Stream<TabsState>.fromIterable(tabsStates),
      initialState: tabsInitial,
    );
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<CollectionsBloc>.value(value: collections),
            BlocProvider<TabsBloc>.value(value: tabs),
          ],
          child: const CollectionsList(),
        ),
      ),
    );
  }

  testWidgets('folder stays expanded after a child inside it is renamed', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    const child = CollectionNodeEntity(
      id: 'C',
      name: 'ChildReq',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'C'),
    );
    const folder = CollectionNodeEntity(
      id: 'F',
      name: 'Folder',
      children: [child],
    );
    const sibling = CollectionNodeEntity(
      id: 'S',
      name: 'Sibling',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'S'),
    );

    bloc.add(const ReplaceCollections([folder, sibling]));
    await bloc.stream.first;

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    expect(find.text('ChildReq'), findsNothing);

    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();
    expect(find.text('ChildReq'), findsOneWidget);

    bloc.add(const RenameNode('C', 'ChildRenamed'));
    await bloc.stream.first;
    await tester.pumpAndSettle();

    expect(find.text('ChildRenamed'), findsOneWidget);
  });

  testWidgets('import button opens a menu with Postman + OpenAPI entries', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload));
    await tester.pumpAndSettle();

    expect(find.text('FROM POSTMAN'), findsOneWidget);
    expect(find.text('FROM OPENAPI / SWAGGER'), findsOneWidget);
  });

  testWidgets(
    'focusing a tab linked to a request inside a collapsed folder reveals + '
    'highlights it',
    (tester) async {
      final bloc = build();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      const child = CollectionNodeEntity(
        id: 'req-1',
        name: 'GetUser',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'req-1'),
      );
      const folder = CollectionNodeEntity(
        id: 'F',
        name: 'ApiFolder',
        children: [child],
      );

      bloc.add(const ReplaceCollections([folder]));
      await bloc.stream.first;

      // Emit a state whose active tab is linked to the nested request.
      await tester.pumpWidget(
        host(
          bloc,
          tabs,
          tabsStates: [_stateWith(_tab('t1', linkedNodeId: 'req-1'))],
        ),
      );
      await tester.pumpAndSettle();

      // The folder auto-expanded → the nested request row is now rendered.
      expect(find.text('GetUser'), findsOneWidget);

      // And that row is marked selected.
      final row = tester.widget<CollectionNodeRow>(
        find.byType(CollectionNodeRow).last,
      );
      expect(row.node.id, 'req-1');
      expect(row.isSelected, isTrue);
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/collections_list_test.dart`
Expected: FAIL — the new "reveal + highlights" test fails (folder not auto-expanded / `isSelected` is false), because the coordinator isn't wired yet. (The two pre-existing tests should already pass with the new `host` helper.)

- [ ] **Step 3: Add imports to `collections_list.dart`**

In `lib/features/collections/presentation/widgets/collections_list.dart`, add these imports in alphabetical position among the existing `package:getman/...` imports (after the `collections_state.dart` import on line 16 add the tree-helper import; add the three `tabs` imports after the `environments` imports on lines 20-21):

```dart
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
```

and:

```dart
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
```

(Final import order must be alphabetical by path — `directives_ordering`. Run `fvm dart format` does not reorder; verify ordering matches the existing convention: `collections/domain/...` before `collections/presentation/...`, and `tabs/...` after `environments/...` but before `two_dimensional_scrollables`.)

- [ ] **Step 4: Add coordinator state fields + helpers to `_CollectionsListState`**

In `lib/features/collections/presentation/widgets/collections_list.dart`, add two fields to `_CollectionsListState` (after the `_searchDebouncer` field at line 48):

```dart
  // The id of the saved request linked to the currently-focused tab, or null
  // (unlinked tab / no tabs / linked node deleted). Drives the row highlight.
  String? _selectedNodeId;
  // Owns the TreeView's vertical scroll so we can scroll the selected row into
  // view when the focused tab changes.
  final ScrollController _verticalController = ScrollController();
```

Update `initState` (lines 50-55) to seed the initial selection from the already-active tab and reveal it after first layout:

```dart
  @override
  void initState() {
    super.initState();
    _rebuildTree();
    _searchController.addListener(() => _searchDebouncer.run(_rebuildTree));
    _selectedNodeId = _activeLinkedNodeId(context.read<TabsBloc>().state);
    final initial = _selectedNodeId;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealAndScrollTo(initial);
      });
    }
  }
```

Update `dispose` (lines 57-62) to dispose the controller:

```dart
  @override
  void dispose() {
    _verticalController.dispose();
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }
```

Add these helper methods to `_CollectionsListState` (place them right after `dispose`, before `_rebuildTree`):

```dart
  /// The collectionNodeId of the active panel's focused tab, or null when the
  /// tab is unlinked, there are no tabs, or the index is out of range.
  String? _activeLinkedNodeId(TabsState s) {
    if (s.activeIndex < 0 || s.activeIndex >= s.tabs.length) return null;
    return s.tabs[s.activeIndex].collectionNodeId;
  }

  /// React to the focused tab changing: update the highlight, then (if the tab
  /// links to a known node) expand its ancestor folders and scroll it in.
  void _onSelectedNodeChanged(String? id) {
    setState(() => _selectedNodeId = id);
    if (id != null) _revealAndScrollTo(id);
  }

  /// Expand the ancestor folders of [id] and scroll its row into view. No-op if
  /// the node isn't in the current tree.
  void _revealAndScrollTo(String id) {
    final collections = context.read<CollectionsBloc>().state.collections;
    if (CollectionsTreeHelper.findNode(collections, id) == null) return;
    final ancestors = CollectionsTreeHelper.ancestorFolderIds(collections, id);
    final before = _expandedIds.length;
    _expandedIds.addAll(ancestors);
    if (_expandedIds.length != before) {
      _rebuildTree();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToNode(id);
    });
  }

  /// Scroll the vertical viewport so the row for [id] is visible. Uses the
  /// fixed row height; honours the current expansion state.
  void _scrollToNode(String id) {
    if (!_verticalController.hasClients) return;
    final index = _visibleRowIndexOf(id);
    if (index == null) return;
    final rowHeight = _rowHeight();
    final target = (index * rowHeight).clamp(
      0.0,
      _verticalController.position.maxScrollExtent,
    );
    _verticalController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// The display-order (flattened, expansion-aware) row index of node [id], or
  /// null if it isn't currently visible.
  int? _visibleRowIndexOf(String id) {
    var row = 0;
    int? walk(List<TreeViewNode<_TreeItem>> nodes) {
      for (final n in nodes) {
        final item = n.content;
        if (item is _NodeItem && item.node.id == id) return row;
        row++;
        if (item is _NodeItem && _expandedIds.contains(item.node.id)) {
          final found = walk(n.children ?? const []);
          if (found != null) return found;
        }
      }
      return null;
    }

    return walk(_tree);
  }

  /// The fixed row height the TreeView uses (mirrors the build()-time calc).
  double _rowHeight() =>
      context.appLayout.treeRowExtent > context.touchTargetMin
      ? context.appLayout.treeRowExtent
      : context.touchTargetMin;
```

- [ ] **Step 5: Wrap the tree in a `TabsBloc` listener + pass `isSelected` + wire the scroll controller**

In the `build` method (lines 176-368):

(a) Replace the outer `BlocListener<CollectionsBloc, CollectionsState>` (lines 181-183) and its `child:` with a `MultiBlocListener`. Change:

```dart
    return BlocListener<CollectionsBloc, CollectionsState>(
      listenWhen: (prev, next) => prev.collections != next.collections,
      listener: (_, _) => _rebuildTree(),
      child: Column(
```

to:

```dart
    return MultiBlocListener(
      listeners: [
        BlocListener<CollectionsBloc, CollectionsState>(
          listenWhen: (prev, next) => prev.collections != next.collections,
          listener: (_, _) => _rebuildTree(),
        ),
        BlocListener<TabsBloc, TabsState>(
          listenWhen: (prev, next) =>
              _activeLinkedNodeId(prev) != _activeLinkedNodeId(next),
          listener: (_, state) =>
              _onSelectedNodeChanged(_activeLinkedNodeId(state)),
        ),
      ],
      child: Column(
```

(The closing `);` of the original `BlocListener` at line 367 now closes the `MultiBlocListener` — structure is unchanged otherwise.)

(b) Pass the scroll controller to the `TreeView` — in the `TreeView<_TreeItem>(` constructor (starts line 309), add `verticalDetails:` right after `controller: _treeController,` (line 311):

```dart
                      controller: _treeController,
                      verticalDetails: ScrollableDetails.vertical(
                        controller: _verticalController,
                      ),
```

(c) Pass `isSelected` to `CollectionNodeRow` — in `treeNodeBuilder`, update the `CollectionNodeRow(...)` (lines 342-350) to add `isSelected:`:

```dart
                        return CollectionNodeRow(
                          key: ValueKey(nodeItem.node.id),
                          node: nodeItem.node,
                          isExpanded: node.isExpanded,
                          depth: node.depth ?? 0,
                          onToggle: () => _treeController.toggleNode(node),
                          rowWidth: rowWidth,
                          rowHeight: rowHeight,
                          isSelected: nodeItem.node.id == _selectedNodeId,
                        );
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `fvm flutter test test/features/collections/presentation/widgets/collections_list_test.dart`
Expected: PASS — all three tests green (the reveal+highlight test now expands the folder and finds `isSelected: true`).

- [ ] **Step 7: Run the full done-bar**

Run:
```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
```
Expected: `No issues found!` from each analyzer; formatter clean; all tests green.

- [ ] **Step 8: Commit**

```bash
git add lib/features/collections/presentation/widgets/collections_list.dart test/features/collections/presentation/widgets/collections_list_test.dart
git commit -m "feat(collections): highlight + reveal active tab's linked request in the tree"
```

---

### Task 4: Sync the wiki (Collections page)

**Files:**
- Modify: the `Getman.wiki.git` repo's Collections page (cloned separately — NOT in this repo).

**Interfaces:** none (docs only).

- [ ] **Step 1: Clone the wiki (if not already present) into a scratch path**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /private/tmp/claude-501/-Users-thiago-git-getman/158c4f4e-5eb3-4a3b-9963-563e55da2fba/scratchpad/Getman.wiki
```

- [ ] **Step 2: Identify the Collections page**

```bash
ls /private/tmp/claude-501/-Users-thiago-git-getman/158c4f4e-5eb3-4a3b-9963-563e55da2fba/scratchpad/Getman.wiki
```
Expected: a Collections-related `*.md` (e.g. `Collections.md`). If the exact name differs, pick the page documenting the collections tree.

- [ ] **Step 3: Add a sentence describing the behavior**

In the Collections page, under the section that describes opening saved requests, add:

```markdown
When you focus a tab that was opened from a saved request, Getman highlights
that request in the collections tree — auto-expanding its folders and scrolling
it into view — so you can always see which saved request your active tab came
from. Tabs opened from a saved *example* are unlinked and are not highlighted.
```

Use verbatim UI behavior; keep wording accurate to the app.

- [ ] **Step 4: Commit + push the wiki**

```bash
cd /private/tmp/claude-501/-Users-thiago-git-getman/158c4f4e-5eb3-4a3b-9963-563e55da2fba/scratchpad/Getman.wiki
git add -A
git commit -m "docs: focusing a tab highlights its linked request in the collections tree"
git push origin master
```
Expected: push succeeds (the wiki's default branch is `master`).

---

## Self-Review

**Spec coverage:**
- Highlight matching row → Task 2 (`isSelected` accent bar + tint) + Task 3 (passes `isSelected`). ✓
- Reveal (auto-expand ancestors) → Task 1 (`ancestorFolderIds`) + Task 3 (`_revealAndScrollTo` adds to `_expandedIds`). ✓
- Scroll into view → Task 3 (`_scrollToNode` + `verticalDetails` controller). ✓
- Clears when unlinked / no tabs / out-of-range → Task 3 (`_activeLinkedNodeId` returns null; `_onSelectedNodeChanged(null)` just clears highlight). ✓
- Deleted linked node → Task 3 (`_revealAndScrollTo` `findNode == null` guard). ✓
- Panel switch recompute → Task 3 (`listenWhen` on `_activeLinkedNodeId`, derived from `state.tabs`). ✓
- Examples unlinked / no example highlight → no code change needed; covered by the linkage only being set for request nodes. ✓
- Initial selection at mount → Task 3 (`initState` seeds `_selectedNodeId` + post-frame reveal). ✓
- Performance (no per-keystroke rebuild) → Task 3 (`listenWhen` gated to the linked id). ✓
- Wiki sync → Task 4. ✓
- No bloc→bloc coupling / no Hive change → satisfied (widget-layer only). ✓

**Placeholder scan:** None. Every code step shows complete code; commands and expected output are concrete.

**Type consistency:** `ancestorFolderIds(List<CollectionNodeEntity>, String) → List<String>` is used identically in Task 1 (definition) and Task 3 (call). `CollectionNodeRow(isSelected:)` (bool, default false) defined in Task 2, consumed in Task 3. `_activeLinkedNodeId(TabsState) → String?`, `_onSelectedNodeChanged(String?)`, `_revealAndScrollTo(String)`, `_scrollToNode(String)`, `_visibleRowIndexOf(String) → int?`, `_rowHeight() → double` are all defined and called consistently within Task 3. `_TreeItem`/`_NodeItem` are the existing private union types in `collections_list.dart`. ✓
