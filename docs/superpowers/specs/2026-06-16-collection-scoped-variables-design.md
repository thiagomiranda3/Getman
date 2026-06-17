# Collection-scoped variables — design

**Date:** 2026-06-16
**Status:** Approved (ready for implementation plan)
**Branch:** `dev`

## Problem

Getman has only **global** environment variables (one active environment at a
time, substituted into `{{var}}` placeholders at send). Postman additionally
lets a collection (and its folders) define their own variables, scoped to the
requests inside. We want the same: when the user opens a folder/collection they
can define **collection-scoped** variables that apply to the requests beneath
it.

## Decisions (locked)

- **Scope level:** *any folder*. A request inherits variables from **all**
  ancestor folders on its path; the **deepest** folder wins on name clashes.
  (Postman-style folder-level variables.)
- **Precedence:** the **active environment overrides** collection variables
  (Postman-accurate: `Environment > Collection`). Collection variables act as
  built-in defaults the user can override by selecting an environment.
- **Parity:** full — name/value **plus secret flag** (lock + reveal, like env
  vars) **plus** Postman v2.1 import/export **plus** git workspace mirror
  round-trip.
- **UI label:** the entry point reads **"VARIABLES"** on every folder.

### Full resolution order (lowest → highest priority)

1. **Collection layer** — merge of every folder on the path root → request's
   parent, deepest folder winning on name clashes.
2. **Active environment** — overlays (wins over) the collection layer.
3. **Dynamic vars** (`{{$guid}}`, `{{$timestamp}}`, …) — final fallback when a
   name is in neither map (unchanged behavior).

History still records the **templated (unresolved)** config — re-sending a
history entry under a different environment must still work. Collection vars
resolve only at send time, exactly like env vars.

## Non-goals (v1)

- Per-request (leaf) variables — only folders hold variables; a request edits
  vars on its containing folder.
- A separate non-environment "globals" layer beyond environments.
- Surfacing *which specific* ancestor folder supplied a value, beyond a generic
  "Collection" source label in the hover tooltip.

## Architecture

The send pipeline is **untouched**. `TabsRepositoryImpl.sendRequest`,
`RequestSerializer`, and `SendRequestUseCase` already resolve whatever
`Map<String,String> envVars` they are handed and record the templated config.
We only enrich the map computed at the dispatch sites.

### 1. Data model

`CollectionNodeEntity` (domain) gains:

```dart
final Map<String, String> variables;   // default const {}
final Set<String> secretKeys;           // default const {}
```

`CollectionNode` (Hive model, `typeId: 3`) gains:

- `@HiveField(8) Map<String, String> variables`
- `@HiveField(9) List<String> secretKeys`  // Set in entity, List in model
  (mirrors `EnvironmentModel.secretKeys`)

Next free `HiveField` on `CollectionNode` becomes **10**. Update `copyWith`,
`props`, `toEntity`, `fromEntity`, then regenerate adapters
(`dart run build_runner build --delete-conflicting-outputs`). Existing persisted
nodes read back with empty `variables`/`secretKeys` (defaults), so no migration
is needed.

Only folders surface the editor; leaf nodes keep the fields empty.

### 2. Pure tree logic (`CollectionsTreeHelper`, collections domain)

```dart
// Mirrors describeInTree — sets both maps on the node with [id].
static List<CollectionNodeEntity> setVariablesInTree(
  List<CollectionNodeEntity> nodes,
  String id,
  Map<String, String> variables,
  Set<String> secretKeys,
);

// Walks root → the node with [leafId], merging every folder layer on the
// path (deepest wins). The winning layer decides each name's secret-ness.
// Returns empty maps if [leafId] is missing.
static ({Map<String, String> variables, Set<String> secretKeys})
    collectVariables(List<CollectionNodeEntity> nodes, String leafId);
```

`collectVariables` implementation walks the existing recursive structure to find
the ancestor path (no parent pointers exist). For each node on the path in
root→leaf order, overlay its `variables`; for each overlaid key, set/replace its
secret flag from that node's `secretKeys` (last writer wins). The leaf request's
own (empty) maps contribute nothing.

### 3. Merge helper (`lib/core/utils/request_variable_resolver.dart`)

New `RequestVariableResolver`. Placement follows the existing precedent of
`core/utils/postman/*` mappers, which already import feature-owned entities
(`CollectionNodeEntity`, `EnvironmentEntity`). Pure Dart, unit-testable.

```dart
class RequestVariableResolver {
  /// Collection layer (deepest folder wins) overlaid by the active environment
  /// (environment wins). Used for send dispatch and URL highlighting.
  static Map<String, String> variablesFor({
    required List<EnvironmentEntity> environments,
    required String? activeEnvironmentId,
    required List<CollectionNodeEntity> collections,
    required String? collectionNodeId,
  });

  /// Merged secret key names (env secret-ness wins for env-supplied names).
  /// Used by the URL hover tooltip to mask collection-sourced secrets.
  static Set<String> secretKeysFor({ ...same params... });
}
```

`collectionNodeId == null` (unlinked tab) → collection layer is empty, behavior
identical to today.

### 4. Wiring the dispatch sites

All three sites already read `EnvironmentsBloc` + `SettingsBloc`; each gains a
read of `CollectionsBloc` and the tab's `collectionNodeId`:

- `url_bar.dart` — the SEND button (`_activeVariables` becomes a
  `RequestVariableResolver.variablesFor(...)` call; `widget.tabId` →
  `TabsBloc.state.tabs.byId(...).collectionNodeId`). The existing `listenWhen`
  on line ~152 already reacts to `collectionNodeId` changes, so the highlighter
  resyncs when a tab links/unlinks.
- `MainScreen`'s `SendRequestIntent` — resolves with the active tab's
  `collectionNodeId`.
- `realtime_button.dart` — same enrichment for WS/SSE URL + header resolution.

### 5. URL highlighting + hover tooltip

- **Highlight:** `url_bar` feeds the merged map to
  `VariableHighlightController.updateVariables`, so collection vars render
  resolved (green). No controller change needed.
- **Hover tooltip:** extend `VariableResolutionHelper` with a layered classify
  that knows both layers and returns a source label:

  ```dart
  static ResolvedVariable classifyLayered({
    required String name,
    required Map<String, String> collectionVariables,
    required Set<String> collectionSecrets,
    required Map<String, String> environmentVariables,
    required Set<String> environmentSecrets,
    required String? environmentName,
  });
  ```

  `ResolvedVariable` gains an optional `sourceLabel` (e.g. the environment name,
  or `"Collection"` when the value came from the collection layer). The popover
  prefers `sourceLabel` when present, else the existing `environmentName`. The
  existing `classify` stays for callers without a collection context.

### 6. UI: editor + entry point

- New `CollectionVariablesDialog` under
  `lib/features/collections/presentation/widgets/`. Wraps `KeyValueListEditor`
  in a `ResponsiveDialog`, passing `secretKeys` + `onSecretKeysChanged` so each
  row gets the lock toggle + reveal affordance (identical to the env editor).
  Prunes stale secret flags on key rename/delete (intersect with live keys),
  matching `EnvironmentEditor`. On confirm, dispatches `UpdateNodeVariables`.
- **Entry point** (folders only):
  - Desktop `collection_node_menu.dart` — add a `PopupMenuItem` **"VARIABLES"**
    guarded by `node.isFolder`.
  - Phone `node_action_sheet.dart` — add an `_Action` **"VARIABLES"** guarded by
    `node.isFolder`.

### 7. New event + handler (`CollectionsBloc`)

```dart
class UpdateNodeVariables extends CollectionsEvent {
  final String id;
  final Map<String, String> variables;
  final Set<String> secretKeys;
}
```

`_onUpdateNodeVariables` mirrors `_onUpdateNodeDescription`: `findNode` guard,
then `_commit(emit, CollectionsTreeHelper.setVariablesInTree(...))`. Collections
persist the whole tree immediately (existing behavior).

### 8. Postman v2.1 interop (`PostmanCollectionMapper`)

- **Export:**
  - Folder item gains `'variable': [...]` when non-empty (sibling of `item`).
  - Root collection gains a top-level `'variable': [...]` (sibling of `info` /
    `item`) from `rootNode.variables` when the root is a folder with vars.
  - Each entry: `{key, value, type}`. Secret keys → `type: 'secret'`, `value: ''`
    (mirrors `PostmanEnvironmentMapper._envToMap`).
- **Import:**
  - Parse `item['variable']` (folder) and top-level `parsed['variable']`
    (collection) into `variables` + `secretKeys`. `type == 'secret'` →
    secret key; `disabled == true` → skip (matches header/query parsing).

### 9. Git workspace mirror (`WorkspaceCollectionSerializer`)

The mirror is two-way (`read` → `ReplaceCollections`), so without this, a
workspace re-import would silently drop collection variables.

- `folderToJson` gains `variables` + `secretKeys` arrays. Secret values are
  **masked to empty** on write (avoids committing secrets to git; matches
  Postman export semantics — a documented round-trip limitation for secret
  *values*, while key names + non-secret values round-trip fully).
- `folderFromJson` reads them back. (Note: `description` is already omitted by
  this serializer today; we leave that as-is and do **not** expand scope to it.)

## Testing

- **Unit:**
  - `collections_tree_helper_test` — `setVariablesInTree`, `collectVariables`
    (nested merge deepest-wins, secret tracking, missing id, no-collection).
  - `request_variable_resolver_test` — env overlays collection, env wins on
    clash, collection-only, neither, unlinked tab.
  - `postman_collection_mapper_test` — folder + collection-level var round-trip,
    secret masking on export, secret import.
  - `workspace_collection_serializer_test` — folder var round-trip + secret
    masking.
  - `collections_bloc_test` — `UpdateNodeVariables` persists + emits.
  - `variable_resolution_helper_test` — `classifyLayered` source/precedence/
    secret.
- **Widget:** light `CollectionVariablesDialog` test (open, edit, confirm
  dispatches event).
- Full static-analysis stack (`fvm flutter analyze`, `fvm dart run custom_lint`,
  `fvm dart run bloc_tools:bloc lint lib`), `fvm dart format`, and
  `fvm flutter test` all green.

## Wiki

Update the Environments page (and/or Collections page) on the GitHub wiki:
document collection variables, precedence (`Environment > Collection`), the
nested-folder merge (deepest wins), secrets, and the "VARIABLES" entry point.
Per the §7 mandate this ships with the feature, not deferred.

## Affected files (summary)

- `lib/features/collections/domain/entities/collection_node_entity.dart`
- `lib/features/collections/data/models/collection_node_model.dart` (+ regen `.g.dart`)
- `lib/features/collections/domain/logic/collections_tree_helper.dart`
- `lib/core/utils/request_variable_resolver.dart` (new)
- `lib/core/utils/variable_resolution_helper.dart`
- `lib/features/tabs/presentation/widgets/url_bar.dart`
- `lib/features/tabs/presentation/widgets/realtime_button.dart`
- `lib/features/tabs/presentation/screens/main_screen.dart` (SendRequestIntent)
- `lib/features/collections/presentation/widgets/collection_variables_dialog.dart` (new)
- `lib/features/collections/presentation/widgets/collection_node_menu.dart`
- `lib/features/collections/presentation/widgets/node_action_sheet.dart`
- `lib/features/collections/presentation/bloc/collections_event.dart`
- `lib/features/collections/presentation/bloc/collections_bloc.dart`
- `lib/core/utils/postman/postman_collection_mapper.dart`
- `lib/core/utils/workspace/workspace_collection_serializer.dart`
- tests as above; CLAUDE.md typeId/HiveField table note; GitHub wiki.
