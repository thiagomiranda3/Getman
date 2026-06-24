# Highlight & reveal the active tab's linked request in the collections tree

**Date:** 2026-06-24
**Status:** Approved (design) — pending implementation plan

## Problem

When the user focuses a request tab that was opened from a saved request in the
collections tree, there is no visual connection back to that saved request. The
user can't tell *which* node in the collections tree corresponds to the tab they
are currently working in.

## Goal

When a tab is focused (becomes the active tab), if it is linked to a saved
collection node, the collections tree should:

1. **Highlight** the matching request row as "selected".
2. **Reveal** it — auto-expand its ancestor folders so the row exists in the tree.
3. **Scroll** the tree so the highlighted row is visible.

When the active tab is *not* linked to a collection node (a scratch tab, or a tab
opened from a saved example, which is intentionally unlinked), the highlight
clears and nothing scrolls.

## Existing facts the design relies on

- **Linkage already exists.** `HttpRequestTabEntity.collectionNodeId`
  (`lib/features/tabs/domain/entities/request_tab_entity.dart`) holds the saved
  node's id. It is set in the `AddTab` handler when a request is opened from the
  tree (`collection_node_row.dart` request-row `onTap`). No new model/Hive field
  is required.
- **Active tab.** `TabsState.tabs[TabsState.activeIndex]` is the active panel's
  focused tab (recomputed on every emit). `activeIndex` changes via
  `SetActiveIndex`; panel switches change `state.tabs` wholesale.
- **The tree.** `collections_list.dart` (`_CollectionsListState`) is the sole
  `TreeView` consumer. Expansion is owned manually via `_expandedIds`
  (`Set<String>`), reseeded into each `TreeViewNode(expanded:)` on rebuild (the
  H2 pattern — do not switch to value-keyed expansion). Rows are built in
  `treeNodeBuilder`; request/folder rows are `CollectionNodeRow`, example rows
  are `ExampleRow`. Row height is a fixed `rowHeight`.
- **Path helper.** `CollectionsTreeHelper` already has a private `_pathTo(nodes,
  id)` returning the root→…→node chain.
- **Examples open unlinked.** Tabs opened from a saved example carry no
  `collectionNodeId`, so they never match — example rows need no change.

## Approach

Pure **widget-layer coordination** in `CollectionsList`: it reads `TabsBloc`,
derives the active tab's `collectionNodeId`, and drives highlight + reveal +
scroll locally.

**Rejected alternative:** adding a `selectedNodeId` to `CollectionsBloc`/state.
That couples Collections to Tabs (the codebase deliberately avoids bloc→bloc
coupling; coordinators live in the widget layer). Selection is a transient *view*
concern, not persisted collection data, so it does not belong in the bloc.

## Components

### 1. `CollectionsTreeHelper.ancestorFolderIds` (new pure function)

```dart
/// The ids of every ancestor folder on the path down to [id] (root first,
/// nearest parent last), excluding [id] itself. Empty if [id] is a root or not
/// found. Used to auto-expand a node into view.
static List<String> ancestorFolderIds(
  List<CollectionNodeEntity> nodes,
  String id,
)
```

Implemented by reusing `_pathTo` and dropping the last element
(`path.sublist(0, path.length - 1).map((n) => n.id)`). Pure, no side effects;
unit-tested.

### 2. `CollectionNodeRow` — `isSelected` parameter

Add `final bool isSelected;` (default `false`). When `true`, the **request** row
renders the **accent bar + tint** treatment:

- Background fill: `theme.primaryColor.withValues(alpha: 0.12)` (takes priority
  over the hover fill — selected stays visible while hovering).
- Left accent bar: `Border(left: BorderSide(width: layout.borderThick, color:
  theme.primaryColor))`.

Colors come from `theme.primaryColor`; the bar width from
`context.appLayout.borderThick`. No banned color literals (the `0.12` alpha
mirrors the existing inline `0.3` drag-over alpha already in this file). The
`AnimatedContainer`'s 200ms transition gives the highlight a smooth fade.

Folders are never linked (a `collectionNodeId` always points at a leaf with a
config), so the folder branch is left unchanged.

### 3. `CollectionsList` (`_CollectionsListState`) — the coordinator

State additions:

- `String? _selectedNodeId;`
- `final ScrollController _verticalController = ScrollController();` (disposed in
  `dispose`).

Wiring:

- Pass the controller to the `TreeView` via
  `verticalDetails: ScrollableDetails.vertical(controller: _verticalController)`.
- Wrap the existing subtree in a `BlocListener<TabsBloc, TabsState>` with
  `listenWhen: (p, n) => _activeLinkedNodeId(p) != _activeLinkedNodeId(n)` where:

  ```dart
  String? _activeLinkedNodeId(TabsState s) {
    if (s.activeIndex < 0 || s.activeIndex >= s.tabs.length) return null;
    return s.tabs[s.activeIndex].collectionNodeId;
  }
  ```

- In the listener:
  1. Compute `id = _activeLinkedNodeId(next)`; set `_selectedNodeId = id` via
     `setState`.
  2. If `id == null` or `CollectionsTreeHelper.findNode(collections, id) == null`
     → stop (highlight cleared; nothing to reveal).
  3. Otherwise add `ancestorFolderIds(collections, id)` to `_expandedIds`, then
     `_rebuildTree()` (rebuilds `_tree` honoring the new expansion).
  4. `WidgetsBinding.instance.addPostFrameCallback`: compute the node's flat
     visible row index by DFS over `_tree` (descend into a node's children only
     when it is expanded; count node rows and example rows alike), then
     `_verticalController.animateTo((index * rowHeight).clamp(0,
     maxScrollExtent), duration: 200ms, curve: easeOut)`. Guard on
     `_verticalController.hasClients`.

- In `treeNodeBuilder`, pass
  `isSelected: nodeItem.node.id == _selectedNodeId` to `CollectionNodeRow`.

The initial selection (a linked tab already active at mount) is handled by also
computing `_selectedNodeId` once in `initState`/first build from the current
`TabsBloc` state, so the highlight is correct before the first tab switch.

## Data flow

```
TabsBloc emits (activeIndex / panel / tabs change)
  -> BlocListener.listenWhen detects active-tab collectionNodeId changed
     -> setState(_selectedNodeId = id)          // highlight
     -> _expandedIds += ancestorFolderIds(id)   // reveal
     -> _rebuildTree()
     -> post-frame: _verticalController.animateTo(rowIndex * rowHeight)  // scroll
  -> build: treeNodeBuilder passes isSelected to each CollectionNodeRow
     -> selected request row paints accent bar + tint
```

## Edge cases

- **Unlinked / no tabs / out-of-range index:** `_activeLinkedNodeId` returns
  `null` → highlight clears, no scroll.
- **Linked node was deleted:** `findNode` returns `null` → highlight set to the
  (now-missing) id matches nothing → effectively no highlight, no scroll. No
  crash.
- **Panel switch:** `state.tabs` changes wholesale; `listenWhen` recomputes the
  active linked id and updates accordingly.
- **Search filtering active:** if the linked node is filtered out by the search
  query it simply won't render/scroll; this is acceptable (the user is actively
  filtering). No special-casing.
- **Performance:** `listenWhen` fires only when the active tab's
  `collectionNodeId` actually changes — not on request-editor keystrokes — so the
  tree is not rebuilt per keystroke.

## Testing

- **Unit:** `CollectionsTreeHelper.ancestorFolderIds` — root node → `[]`; nested
  leaf → ordered ancestor folder ids; unknown id → `[]`.
- **Widget:** `CollectionNodeRow(isSelected: true)` renders the accent
  decoration (find the primary-colored left border / tint) and `isSelected:
  false` does not.
- **Widget:** `CollectionsList` — given a collapsed folder containing a request,
  emitting a `TabsState` whose active tab is linked to that request auto-expands
  the folder (the row becomes findable) and the row is highlighted. Scroll
  position is best-effort (assert no throw + controller offset moves when the
  list overflows).

## Wiki

The Collections page in the GitHub wiki gets a sentence: focusing a tab opened
from a saved request highlights and scrolls to that request in the collections
tree. (This changes how the feature is used → wiki sync required per CLAUDE.md.)

## Out of scope

- Tree → tab direction (clicking the tree already opens/focuses a tab; unchanged).
- Highlighting saved *examples* (their tabs are unlinked by design).
- Persisting selection across restarts (it is derived from the active tab).
