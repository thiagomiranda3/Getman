# Getman — Verified Backlog (resume point)

> Generated 2026-06-14 from an adversarial verification workflow (5 dimension
> reviewers → per-finding skeptics that confirmed each item against the live
> code). Every item below was **confirmed still-open** against `dev` at commit
> `4d15cd5`-ish (the improvement-pass tip). Items already fixed are NOT listed.

## Current state
- Branch `dev`. App **builds** (`fvm flutter build macos --debug` → `✓ Built …getman.app`).
- `fvm flutter analyze` → `No issues found!`; `fvm flutter test` → all green (~579).
- The improvement pass (≈22 commits after `7533cb3`) is committed and clean.

## Working agreement (how to resume)
1. **One concern per commit**, message `type(scope): summary`, end with
   `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
2. **TDD for bugs**: write a failing test first, then fix.
3. **Green between commits**: `fvm flutter analyze` clean AND `fvm flutter test` 100%.
4. **⚠️ `analyze` can give false passes** on generic-variance issues (it once
   accepted `Stream<Uint8List>.transform(Utf8Decoder)` that the CFE rejected).
   For any compile-affecting change, verify with a real compile —
   `fvm flutter test` (CFE) or `fvm flutter build macos --debug` — not just analyze.
5. Theme/atom mandates per `CLAUDE.md` §4.8/§6 (no hardcoded sizes/colors/radii;
   `showAppSnackBar`/`showAppSnackBarVia`, `ConfirmDialog`, `context.app*`).
6. After any `@HiveType`/`@HiveField` change: `dart run build_runner build
   --delete-conflicting-outputs`, then re-run analyze + tests.

Recommended order: the HIGH bugs first (data fidelity / data loss), then the
cheap LOW wins to bank momentum, then features/refactors as scoped.

---

## 🔴 HIGH

### H1 — Postman export/import drops multipart & urlencoded form bodies
- **Files**: `lib/core/utils/postman/postman_collection_mapper.dart` (`_configToRequest` ~112-124 export; `_parseBody` ~238-246 import).
- **Problem**: Export only emits raw bodies (`if (config.body.isNotEmpty) … mode:'raw'`) and never reads `config.bodyType`/`config.formFields`; for urlencoded/multipart the send path builds the payload purely from `formFields` (so `config.body` is empty) → exported form requests carry **no body**. Import symmetrically returns `''` for any non-`raw` mode.
- **Fix**: In `_configToRequest`, switch on `config.bodyType`: emit Postman `formdata` mode (array of `{key,value,type:'file'|'text',src}`) for multipart and `urlencoded` mode for urlencoded, from `config.formFields`. Mirror in `_parseBody` to reconstruct `formFields`+`bodyType` on import.
- **Effort**: M. **Verify**: extend `test/core/utils/postman/postman_collection_mapper_test.dart` with a round-trip (export→import) for a multipart and a urlencoded request.

### H2 — Collections folder tree collapses on ANY mutation
- **Files**: `lib/features/collections/presentation/widgets/collections_list.dart` (`_rebuildTree` ~57-64, BlocListener ~99-101); `collection_node_entity.dart` (Equatable props ~39-46).
- **Problem**: `flutter_fancy_tree_view`'s `TreeController.toggledNodes` is keyed by **value-equality**. Mutations build new non-equal `CollectionNodeEntity`s (copyWith rewrites the whole ancestor chain), so after rename/add/favorite/config-edit the expansion state is lost and folders collapse. `expandAll()` only runs during active search.
- **Fix**: Own expansion state keyed by `node.id` — maintain a `Set<String> expandedIds` in `_CollectionsListState`, re-applied after each `roots` assignment (collapse-then-expand still-present ids), OR override the controller's `getExpansionState`/`setExpansionState` to key by id. This is also the natural seam for the H?/two_dimensional_scrollables migration (M5).
- **Effort**: M. **Verify**: widget test — expand a folder, dispatch a rename of a sibling, assert the folder stays expanded.

### H3 — OAuth 2.0 auth flow (with token refresh)
- **Files**: `lib/core/domain/entities/auth_config.dart`, `lib/features/tabs/presentation/widgets/auth_tab_view.dart`, `lib/features/tabs/data/request_serializer.dart`, `lib/core/utils/code_gen_service.dart`.
- **Problem**: `AuthType` is only none/inherit/bearer/basic/apikey. No OAuth2 anywhere (grep: zero `oauth|grant_type|pkce|refresh_token`).
- **Fix**: Add an `oauth2` `AuthType` + value object (grant type, token/refresh/auth URLs, client id/secret, scope, cached token+expiry; persist in the existing raw `auth` map → no Hive migration). Add a token-fetch/refresh step in the send pipeline (off the UI isolate) before applying the header; AUTH-tab fields; code-gen handling. Start with PKCE + client-credentials.
- **Effort**: L. **Verify**: unit-test the token value object + a mocked token fetch; widget-test the AUTH fields.

### H4 — Collection runner (batch-run a folder)
- **Files**: new `lib/features/collections/domain/usecases/run_folder_use_case.dart`; `tabs_bloc.dart` send path; `node_action_sheet.dart` (add a Run action).
- **Problem**: No batch orchestration; chaining runs one request at a time. The per-request verdict primitive exists (`rules_runner.dart` `runRules` / `RulesRunOutput`, called once per send).
- **Fix**: `RunFolderUseCase` walks a `CollectionNodeEntity` subtree, sends each leaf sequentially through the existing send + rules pipeline (reuse active-env resolution), aggregates pass/fail, emits a run-summary state. Surface a "Run" folder action + a results panel.
- **Effort**: L. **Verify**: use-case test over a small tree with a mocked send.

---

## 🟡 MEDIUM

### M1 — Multipart send with a missing/deleted file fails silently
- **Files**: `lib/features/tabs/data/request_serializer.dart` (`buildBody` file reads ~104/117), `lib/features/tabs/presentation/bloc/tabs_bloc.dart` (catch-all ~375-381).
- **Problem**: `readFileBytes` throws `FileSystemException`; it's not a `NetworkFailure`, so `SendRequestUseCase` doesn't catch it and the bloc catch-all only `debugPrint`s + clears `isSending` — no error response, no snackbar, no history.
- **Fix**: Catch file-read errors and surface a synthetic error `HttpResponseEntity` (statusCode 0, body `File not found: <path>`) so the response panel shows it.
- **Effort**: M. **Verify**: bloc test with a non-existent multipart file path.

### M2 — `NetworkCancelHandle` domain-purity leak
- **Files**: `lib/features/tabs/domain/repositories/tabs_repository.dart:3`, `…/domain/usecases/send_request_use_case.dart:6` import `core/network/network_service.dart` (which imports dio + flutter).
- **Fix**: Extract `NetworkCancelHandle` into its own pure-Dart file (`lib/core/network/cancel_handle.dart`, no dio/flutter); `NetworkService` adapts to Dio's `CancelToken` internally; repoint the two domain imports.
- **Effort**: S. **Verify**: analyze + tests; grep confirms no `core/network/network_service` import under `lib/features/*/domain`.

### M3 — `send_request_use_case.dart` imports `package:flutter/foundation.dart` for `debugPrint`
- **Files**: `lib/features/tabs/domain/usecases/send_request_use_case.dart:1,70` (the only Flutter import in the whole domain layer).
- **Fix**: Replace `debugPrint` with a pure-Dart logging seam (`dart:developer log()`, an injected logger callback, or an abstract `Logger` port in core).
- **Effort**: S.

### M4 — Tab-strip dirty-check storm (perf)
- **Files**: `tab_widget.dart` (BlocSelector ~94-96), `tab_dirty_checker.dart` (~13-16), `collections_tree_helper.dart` (`findNode` ~52-59), `collections_state.dart`.
- **Problem**: For each linked tab, the `BlocSelector<CollectionsBloc>` re-runs on **every** CollectionsState emission and calls `findNode` — an O(nodes) DFS. T tabs × O(N) per collection mutation on the UI isolate (only the rebuild short-circuits, not the scan). Unlinked tabs already short-circuit cheaply (caps real-world impact → medium).
- **Fix**: Add a precomputed `Map<String, HttpRequestConfigEntity>` (id→config) to `CollectionsState` built once per emission; `TabDirtyChecker` does O(1) lookup. Turns T×O(N) into O(N)+T×O(1).
- **Effort**: M. **Verify**: existing collections/tab tests stay green; ideally a perf_trace span.

### M5 — `flutter_fancy_tree_view` (discontinued) → `two_dimensional_scrollables`
- **Files**: `pubspec.yaml:20`; sole consumer `collections_list.dart` (`TreeController`/`AnimatedTreeView`/`TreeEntry`/`TreeIndentation`).
- **Fix**: Do **H2 first** (own expansion state by id), then swap to `TreeView.builder`; drag-and-drop (`Draggable<String>`/`DragTarget<String>`) is lib-independent.
- **Effort**: L.

### M6 — `response_section.dart` god file (~735 LOC, 8 classes)
- **Fix**: Split each `_Response*View` into `lib/features/tabs/presentation/widgets/response/` siblings; `ResponseSection` stays the shell. Behavior-preserving.
- **Effort**: M. **Verify**: `response_section_test.dart` stays green.

### M7 — Untested critical paths
- **Files**: `realtime_service.dart` (SSE cancel/flush/teardown — only its bloc is tested via mocks), `main_screen.dart`, repo impls (environments/settings/request_rules/collections; tabs+history are tested).
- **Fix**: Prioritize `realtime_service` (mock Dio + a fake `WebSocketChannel`; assert frame logging, SSE cancel path, teardown). Repo-impl tests are quick (mock data source, assert exception→Failure). `request_rules_repository_impl` has an untested `rules.isEmpty → deleteRules` branch.
- **Effort**: M.

### M8 — GraphQL body type
- **Files**: `body_type.dart:4`, `request_config_entity.dart`, `request_serializer.dart`, `request_editor_tabs.dart`.
- **Fix**: Add a `graphql` `BodyType` (new wire string for back-compat); store query + variables JSON; serialize `{query,variables}` with `application/json` at send; dual-pane editor.
- **Effort**: M.

### M9 — Pre-request scripts (no-code)
- **Files**: `lib/features/chaining/…` (post-response only today), send pipeline in `tabs_bloc.dart`.
- **Fix**: Prefer a **no-code** pre-request rules pass (set-header-from-variable, compute-HMAC, set-timestamp) mirroring `RulesRunInput`, run before dispatch — consistent with the existing no-code chaining design (avoid a JS sandbox initially).
- **Effort**: L.

### M10 — Request/folder descriptions + saved examples
- **Files**: `collection_node_entity.dart` + `collection_node_model.dart` (typeId 3), `request_config_entity.dart`.
- **Fix**: Add a nullable `description` (entity + fresh `@HiveField` on `CollectionNode`) and a notes panel. Saved examples are larger (examples list on leaf nodes + capture UI).
- **Effort**: M (descriptions) / L (examples). Needs `build_runner`.

### M11 — Secret/masked environment variables
- **Files**: `environment_entity.dart`, `environment_model.dart`, `environments_dialog.dart`.
- **Fix**: Add a per-variable secret flag (a parallel secret-keys set avoids a heavy Hive migration); render secret values with `obscureText` + reveal toggle (pattern exists in `auth_tab_view.dart:156`); mask on export. Resolution at send unchanged.
- **Effort**: M.

### M12 — Cookie-jar manager UI
- **Files**: `settings_dialog.dart` (only a CLEAR button today), `cookie_store.dart`, `in_memory_cookie_store.dart`.
- **Fix**: A Cookies manager dialog (list/inspect/delete per cookie grouped by domain). `CookieStore.all()` already exists "for a manager UI"; add a `remove(domain,name)` to the public `CookieStore` API.
- **Effort**: M.

---

## 🟢 LOW / quick wins

### L1 — Basic auth emits a header with empty credentials  *(quick)*
- **Files**: `lib/features/tabs/data/request_serializer.dart:43-48`.
- **Problem**: `AuthType.basic` unconditionally sets `Authorization: Basic <base64(':')>` even when user+pass are both empty (bearer/apiKey guard on empty).
- **Fix**: Skip the header when both resolved user and pass are empty. **Effort**: S. **Verify**: serializer test.

### L2 — `MultipartFieldEntity.contentType` persisted but never applied  *(quick)*
- **Files**: `multipart_field_entity.dart`, `request_serializer.dart:102-104`, `form_data_editor.dart`.
- **Problem**: `contentType` is round-tripped (Hive field 4 + workspace serializer) but never passed to `MultipartFile.fromBytes` and dropped by the form editor's row state.
- **Fix**: Either thread it through (`DioMediaType` + add to `_RowState`) or remove the field. **Effort**: S.

### L3 — Hardcoded bottom-sheet corner radii  *(quick)*
- **Files**: `node_action_sheet.dart:25-26` and `:211-212` (`_MoveToSheet` — 3 sites total), `tab_switcher_sheet.dart:28-29`. (`tab_switcher_sheet` already themes other radii via `context.appShape.panelRadius`.)
- **Fix**: Add `sheetRadius` to `AppShape` (or reuse `dialogRadius`/`panelRadius`), replace the `Radius.circular(12)` literals, drop `const`. **Effort**: S.

### L4 — Collection tree node tiles missing `ValueKey`  *(quick)*
- **Files**: `collections_list.dart` (both `_CollectionNodeWidget` constructions, phone ~150-153 + desktop ~161-166).
- **Problem**: `_CollectionNodeWidget` holds mutable `_isHovered`/`_isDragOver` but is built without a key → positional element matching can re-associate the wrong State on reorder/move/filter. (Memoizing `_filterNodes` is NOT needed — `listenWhen` + the search debouncer already gate it.)
- **Fix**: Add `key: ValueKey(entry.node.id)`. **Effort**: S.

### L5 — RPG starfield/sparkle painters allocate per element per frame
- **Files**: `rpg_decorations.dart` (`_StarfieldPainter.paint` ~248-254), `rpg_sparkle.dart` (`_SparklePainter.paint` ~187-216).
- **Fix**: Hoist glow/core `Paint`s to fields (mutate `.color`); build the 4-point sparkle `Path` once at unit size, reuse via canvas transforms. Low impact (behind RepaintBoundary, 30fps-quantized, lifecycle-gated). **Effort**: S.

### L6 — Save-response-to-file (copy exists; save does not)  *(quick-ish)*
- **Files**: `response_section.dart` (next to `_copyButton` ~242), reuse `core/utils/json_file_io.dart` `saveJsonFileWithFeedback` (currently JSON-locked at allowedExtensions:['json'] — generalize with an extension param).
- **Fix**: A Save action writing the verbatim body (incl. the large-body cache via `_copyableText`/`_largeBody`). **Effort**: S.

### L7 — No switch-tab keyboard shortcuts (Ctrl+Tab / Cmd+1-9)  *(quick)*
- **Files**: `lib/main.dart:76-89` (global Shortcuts), `lib/core/navigation/intents.dart`, scoped Actions in `main_screen.dart`.
- **Fix**: Add `NextTabIntent`/`PrevTabIntent` (Ctrl+Tab / Ctrl+Shift+Tab) + optional `JumpToTabIntent` (Cmd+1..9) → `SetActiveIndex` on `TabsBloc`; wire where `context.read<TabsBloc>()` is reachable (MainScreen). **Effort**: S.

### L8 — No focus-URL-bar shortcut  *(quick)*
- **Files**: `lib/main.dart`, `intents.dart`, `url_bar.dart` (URL `TextField` has no `focusNode`).
- **Fix**: Add `FocusUrlIntent` (Cmd/Ctrl+L) + expose a `FocusNode` on the URL field that the action calls `requestFocus()` on. **Effort**: S.

### L9 — Only 3 code-gen targets
- **Files**: `code_gen_service.dart:9` (`CodeGenTarget` enum), `code_export_dialog.dart`.
- **Fix**: Add targets incrementally (Node axios, Go net/http, Java OkHttp); the `_Effective` abstraction already normalizes auth+content-type, so each is a pure formatter. **Effort**: M.

### L10 — `url_bar.dart` / `main_screen.dart` / `environments_dialog.dart` god files
- **Fix**: Extract standalone sub-widgets (`_RealtimeButton`/`_OverflowMenu` from url_bar; `_TabChip` from main_screen; `_EnvironmentListTile`/`_EnvironmentEditor` from environments_dialog). **Effort**: M.

### L11 — No max-redirects limit / client-certificate (mTLS) support
- **Files**: `network_config.dart`, `settings_entity.dart`, `settings_dialog.dart`, `dio_adapter_config_io.dart`.
- **Fix**: Add `maxRedirects` (int) to `NetworkConfig`+settings+UI and apply to Dio options; for client certs, install a `SecurityContext` from a user-provided cert/key+passphrase in the platform-split adapter config. Niche/enterprise → low priority. **Effort**: M.

### L12 — Collections whole-tree serialization on the UI isolate
- **Files**: `collections_repository_impl.dart`, `collection_node_model.dart` (`fromEntity` recursion), `hive_helpers.dart`.
- **Note**: Mostly mitigated this pass — saves are now debounced/coalesced (2s), so it's one whole-tree write per burst, not per edit. Residual jank only on very large Postman imports.
- **Fix**: Move `fromEntity`-forest serialization to a background isolate via `compute`, or move collections to keyed/subtree writes (tabs/environments/cookies already are). **Effort**: M.
