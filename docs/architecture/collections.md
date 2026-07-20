# Collections — the folder/request tree

> Deep-dive for the collections feature (the tree of folders/requests), saved examples, and the git-friendly workspace mirror. Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md. Git *workflow* (branches, review, PRs, conflicts) is in docs/architecture/git-sync.md.

The collections tree is an immutable forest of `CollectionNodeEntity`.

## Pure tree mutations

All mutations go through **pure** `CollectionsTreeHelper` functions (`addToParent`, `removeFromTree`, `renameInTree`, `toggleFavoriteInTree`, `updateConfigInTree`, `describeInTree`, `sort`, `findNode`). These never mutate input.

**Parent-lookup pattern:** `CollectionsTreeHelper.addToParent` does **not** signal a missing parent — it is a no-op on a missing `parentId`. So the BLoC verifies the parent exists via `findNode` *before* calling it; if the parent is not found, the node is appended to root instead (the deliberate root-fallback behavior).

**Sort order:** favorites first, then folders, then leaves, each group alphabetical.

## Drag-and-drop

Implemented with **typed** `Draggable<NodeDragData>` and `DragTarget<NodeDragData>` (the payload type lives in `node_drag_data.dart`), **not** a bare `Draggable<String>`. Drop on root goes via the outer `DragTarget` at the list level (`collections_list.dart`); per-row targets and the drag handle live in `collection_node_row.dart`.

## Descriptions

Nodes carry an optional free-text `description` (folders and requests). Edited via "EDIT DESCRIPTION" in both the phone `NodeActionSheet` and the desktop popup menu → `UpdateNodeDescription` → `CollectionsTreeHelper.describeInTree`. An empty string clears it. The prompt uses `NamePromptDialog.show(..., allowEmpty: true, multiline: true)`.

## Saved examples (M10)

A leaf node carries a `List<SavedExampleEntity> examples` (separate from `children`). Captured from the response panel's "Save as example" button (`SaveExampleToNode`); each is a `{id, name, capturedAt, config}` where `config` carries the response snapshot. In the tree they render as inline expandable sub-rows (the `TreeView` content is a `_TreeItem` union — node vs example); tapping one opens it via `AddTab(response: …)` as an **unlinked** tab (so re-sending never overwrites the saved request). Rename/delete via the per-example menu (`RenameExample`/`DeleteExample`). Examples are local-only — excluded from Postman export and the git workspace mirror.

## Tree UI (`two_dimensional_scrollables`)

The tree uses `two_dimensional_scrollables`'s `TreeView` (sole consumer: `collections_list.dart`). It has no id-keyed expansion hook, so expansion is owned manually:

- Expansion is tracked by `CollectionNodeEntity.id` in a `Set<String>` (`_expandedIds`) seeded into each `TreeViewNode(expanded:)` on rebuild. Tapping a node updates the set in `onNodeToggle`. **Don't switch to value-keyed expansion** — it collapses on every mutation (the H2 regression).
- Rows use `TreeViewIndentationType.none` + manual `depthPaddingMultiplier` padding, a **fixed** `AppLayout.treeRowExtent` (no content-sizing in the 2D viewport — size via the layout field, never a literal), and a viewport-width `SizedBox` (rows have unbounded cross-axis width in the 2D viewport, so this restores the `Expanded` layout + neutralizes horizontal scroll).

## Git-friendly workspace mirror

`collections/data/services/workspace_sync_service.dart` mirrors the collections forest to a clean, diff-friendly on-disk tree so it can be tracked by git. Hive stays the source of truth during a session: opening a workspace imports disk → Hive once (`read`), then every mutation debounces a Hive → disk write (`scheduleMirror`). The serializer (`core/utils/workspace/workspace_collection_serializer.dart`) omits response-cache fields and saved examples from the mirrored files. See docs/architecture/git-sync.md for the full git workflow built on top of this mirror.
