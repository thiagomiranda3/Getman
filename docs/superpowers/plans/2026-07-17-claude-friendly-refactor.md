# Claude-Friendly Codebase Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a layered navigation system (CODEMAP + slim CLAUDE.md + docs/architecture + tiered file headers + `file_header_required` lint) plus three surgical structural fixes, so any concept in the codebase is findable in one search with minimal context load.

**Architecture:** Structure changes first (so all docs reference final paths), then file headers in 13 parallel-safe waves, then the lint that enforces headers, then the docs layer (CODEMAP + architecture docs), then the CLAUDE.md rewrite that depends on all of it. Everything is behavior-preserving; tests must stay green throughout.

**Tech Stack:** Flutter/Dart (via `fvm`), custom_lint_builder (analyzer 8.4.0), flutter_test.

**Spec:** `docs/superpowers/specs/2026-07-17-claude-friendly-refactor-design.md`

## Global Constraints

- Branch: `claude-friendly-refactor` (already created off `master`; spec committed).
- Behavior-preserving: no functional change anywhere. Comment/doc/move/rename only, except the three §4 structural tasks.
- Always `fvm flutter ...` / `fvm dart ...`, never bare `flutter`/`dart`.
- Imports are `package:getman/...` everywhere — no relative imports, and `directives_ordering` requires alphabetized import blocks.
- The pre-commit hook runs analyze + custom_lint + fixtures + bloc_lint + format on every commit. Let it run; do not use `--no-verify` (exception: none needed — every task ends in a state the hook accepts).
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **No wiki changes** — this is an internal refactor with zero user-visible behavior change.

### Header format (used by Tasks 4–16, enforced by Task 17)

Every non-generated file under `lib/` opens with a `//` prose comment block, BEFORE any `// ignore_for_file:` line and before imports. Plain `//`, never `///` (a dangling `///` at file top trips `dangling_library_doc_comments`). Max 80 columns. Prose, not tags. Front-load the words a task prompt would use ("redirect", "dirty", "drag-and-drop", "debounce") — the header is a grep target.

**Tier 1** (simple widgets, entities, stubs, small utils) — one sentence:

```dart
// Colored pill badge showing an HTTP method (GET/POST/...); color comes from
// AppPalette.methodColor.
```

**Tier 2** (services, data sources, mappers, complex widgets) — purpose + collaborators + wiring:

```dart
// Hive-backed persistence for request tabs (box: 'tabs'). Converts
// HttpRequestTabModel <-> HttpRequestTabEntity; consumed by
// TabsRepositoryImpl; registered in core/di/injection_container.dart.
```

**Tier 3** (blocs, engines, cross-cutting services — the files named per task) — tier 2 plus file-local invariants/gotchas (sourced from CLAUDE.md per the task's migration list):

```dart
// The URL input row of a request tab: method dropdown + URL field with
// {{variable}} highlighting + SEND/CANCEL button. Dispatches SendRequest with
// env vars resolved via ActiveEnvironmentHelper.
//
// Gotchas: push text into the controller ONLY via _setControllerPreservingEnd
// (anything else jumps the cursor during echo-writes). URL input starting
// with `curl ` is parsed as a full request spec (CurlUtils.parse) and applied
// as a single UpdateTab.
```

**Wave-agent rules:**
1. READ each file before writing its header — never infer content from the filename.
2. If the file already opens with a useful `//` comment, improve it in place (don't stack a second header). Keep existing `///` class docs untouched — the file header describes the file; class docs describe the class. If the primary class already has a thorough `///` doc, the file header may be one line.
3. Touch comments only. Never edit code, imports, or formatting of code lines.
4. Per-file verification after each wave (run from repo root; expect NO output):

```bash
for f in $(find <WAVE_DIRS> -maxdepth 1 -name '*.dart' ! -name '*.g.dart'); do
  head -1 "$f" | grep -q '^//' || echo "MISSING: $f";
done
```

5. End of each wave: `fvm dart format <touched files>` (headers must be format-clean), then commit.

---

### Task 1: Split `request_editor_tabs.dart` into four files

**Files:**
- Create: `lib/features/tabs/presentation/widgets/bulk_mode_toggle.dart`
- Create: `lib/features/tabs/presentation/widgets/params_tab_view.dart`
- Create: `lib/features/tabs/presentation/widgets/headers_tab_view.dart`
- Create: `lib/features/tabs/presentation/widgets/body_tab_view.dart`
- Delete: `lib/features/tabs/presentation/widgets/request_editor_tabs.dart`
- Modify: `lib/features/tabs/presentation/widgets/request_config_section.dart` (import)
- Modify: `lib/features/tabs/presentation/widgets/unified_request_panel.dart` (import)
- Modify: `test/features/tabs/presentation/widgets/body_tab_view_test.dart` (import)
- Modify: `test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart` (import)
- Modify: `test/features/tabs/presentation/widgets/request_section_index_test.dart` (import)

**Interfaces:**
- Produces: public widgets `ParamsTabView`, `HeadersTabView`, `BodyTabView` (unchanged APIs, new files) and `BulkModeToggle` (renamed from private `_BulkModeToggle`; same constructor signature plus the standard optional `super.key` — required by `use_key_in_widget_constructors` once public; amendment recorded during execution, reviewer-sanctioned).
- Tasks 12 and 17 rely on these exact file names.

Current layout of `request_editor_tabs.dart` (685 lines): `_BulkModeToggle` (l.38), `ParamsTabView`+state (l.95–179), `HeadersTabView`+state (l.181–265), `BodyTabView` (l.267) plus its private family `_BodyTypeSelector`, `_BodyTypeChip`, `_RawBodyEditor`(+state), `_GraphqlBodyEditor`, `_GraphqlPane`, `_EmptyBodyHint`, `_BinaryBodyPicker` (l.321–685).

- [ ] **Step 1: Baseline — run the three affected test files**

```bash
fvm flutter test test/features/tabs/presentation/widgets/body_tab_view_test.dart test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart test/features/tabs/presentation/widgets/request_section_index_test.dart
```
Expected: PASS (this is the green baseline the split must preserve).

- [ ] **Step 2: Create `bulk_mode_toggle.dart`**

Move `_BulkModeToggle` verbatim, renamed public. Copy the imports it needs from the old file (check its body for what it references — theme accessors etc.):

```dart
// Small BULK/TABLE mode toggle shared by the params and headers editors:
// flips a KeyValueListEditor between row-editing and bulk-text editing.
// Used by ParamsTabView and HeadersTabView.
import 'package:flutter/material.dart';
// ... exactly the subset of the old file's imports that _BulkModeToggle used.

class BulkModeToggle extends StatelessWidget {
  // body verbatim from _BulkModeToggle, only the class name changes
}
```

- [ ] **Step 3: Create `params_tab_view.dart` and `headers_tab_view.dart`**

Move `ParamsTabView`+`_ParamsTabViewState` and `HeadersTabView`+`_HeadersTabViewState` verbatim into their files. In each, replace `_BulkModeToggle` references with `BulkModeToggle` and add `import 'package:getman/features/tabs/presentation/widgets/bulk_mode_toggle.dart';`. Each file gets a tier-1/2 header (see Global Constraints), e.g. params:

```dart
// PARAMS tab of the request editor: ordered key/value query parameters via
// KeyValueListEditor, with a BulkModeToggle for bulk-text editing. Composed
// by RequestConfigSection (split view) and UnifiedRequestPanel (phone).
```

- [ ] **Step 4: Create `body_tab_view.dart`**

Move `BodyTabView` and the entire private body family (`_BodyTypeSelector`, `_BodyTypeChip`, `_RawBodyEditor`, `_RawBodyEditorState`, `_GraphqlBodyEditor`, `_GraphqlPane`, `_EmptyBodyHint`, `_BinaryBodyPicker`) verbatim. Header:

```dart
// BODY tab of the request editor: body-type selector (none/raw/urlencoded/
// multipart/binary/graphql) and the per-type editors — raw JSON editor,
// dual-pane GraphQL QUERY+VARIABLES editor, binary file picker. Composed by
// RequestConfigSection and UnifiedRequestPanel.
```

- [ ] **Step 5: Delete the old file, update the five importers**

Delete `request_editor_tabs.dart`. In each of the five importing files replace the old import with the specific new file(s) each actually uses (check which symbols each references; `request_config_section.dart` and `unified_request_panel.dart` likely need all three tab views). Keep import blocks alphabetized (`directives_ordering`).

- [ ] **Step 6: Analyze + rerun the three test files**

```bash
fvm flutter analyze
fvm flutter test test/features/tabs/presentation/widgets/body_tab_view_test.dart test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart test/features/tabs/presentation/widgets/request_section_index_test.dart
```
Expected: 0 analyze issues; all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "refactor(tabs): split request_editor_tabs into per-tab view files

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Extract the shortcuts cheat-sheet from `settings_dialog.dart`

**Files:**
- Create: `lib/features/settings/presentation/widgets/settings_shortcuts_tab.dart`
- Modify: `lib/features/settings/presentation/widgets/settings_dialog.dart`

**Interfaces:**
- Produces: `class SettingsShortcutsTab extends StatelessWidget` with a plain `const SettingsShortcutsTab({super.key})` constructor; `settings_dialog.dart` renders it where `_shortcutsTab(context)` was called (l.290).

The cheat-sheet is self-contained: `_shortcutsTab` (l.538), `_shortcutSection` (l.611), `_shortcutRow` (l.631), `_KeyCombo` (l.851), `_KeyCap` (l.869) touch none of the dialog's controllers/state (verify while moving — if any helper reads dialog state, stop and report instead of forcing the split).

- [ ] **Step 1: Baseline**

```bash
fvm flutter test test/features/settings/
```
Expected: PASS.

- [ ] **Step 2: Create `settings_shortcuts_tab.dart`**

New `SettingsShortcutsTab` StatelessWidget whose `build` returns exactly what `_shortcutsTab` returned; `_shortcutSection`/`_shortcutRow` become private functions or methods in the new file; move `_KeyCombo` + `_KeyCap` verbatim. Copy needed imports. Header:

```dart
// SHORTCUTS tab of the settings dialog: a static keyboard-shortcut
// cheat-sheet (sections REQUEST/TABS/PANELS/...), rendered with _KeyCap key
// caps. Purely informational — changing real bindings happens in
// main.dart's appShortcuts map.
```

- [ ] **Step 3: Swap it into the dialog**

In `settings_dialog.dart`: replace the `_shortcutsTab(context)` call with `const SettingsShortcutsTab()`, delete the five moved members, add the import.

- [ ] **Step 4: Analyze + test + commit**

```bash
fvm flutter analyze && fvm flutter test test/features/settings/
git add -A && git commit -m "refactor(settings): extract shortcuts cheat-sheet tab to its own file

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Rename `tab_widget.dart` → `request_tab_chip.dart` (+ class), then full-bar checkpoint

**Files:**
- Rename: `lib/features/home/presentation/widgets/tab_widget.dart` → `request_tab_chip.dart`
- Rename: `test/features/home/presentation/widgets/tab_widget_test.dart` → `request_tab_chip_test.dart`
- Modify: `lib/features/home/presentation/screens/main_screen.dart` (import l.25, doc ref l.183, usage l.585)
- Modify: `lib/core/theme/themes/dracula/dracula_theme.dart` (comment l.44 mentions `TabWidget`)

**Interfaces:**
- Produces: `class RequestTabChip` (was `TabWidget`), same constructor parameters. Tasks 16/18 reference the new name.

- [ ] **Step 1: git-mv both files, rename the class**

```bash
git mv lib/features/home/presentation/widgets/tab_widget.dart lib/features/home/presentation/widgets/request_tab_chip.dart
git mv test/features/home/presentation/widgets/tab_widget_test.dart test/features/home/presentation/widgets/request_tab_chip_test.dart
```

Then in `request_tab_chip.dart`: `TabWidget` → `RequestTabChip`, `_TabWidgetState` → `_RequestTabChipState`. Grep the whole repo for remaining `TabWidget` references and update every one (imports, constructor calls, doc comments — `main_screen.dart`, the test file, `dracula_theme.dart` comment):

```bash
grep -rn "TabWidget\|tab_widget" lib test integration_test
```
Expected after edits: no hits.

- [ ] **Step 2: Full verification bar (checkpoint for Tasks 1–3)**

```bash
fvm flutter analyze
fvm dart run custom_lint
( cd tools/getman_lints/example && fvm dart run custom_lint )
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools
fvm flutter test
```
Expected: 0 issues everywhere, format changes nothing, all tests PASS. If `integration_test/` references the old names, fix those too (they don't run here, but must compile under analyze).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor(home): rename TabWidget to RequestTabChip (it is one chip, not the strip)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Header waves (Tasks 4–16)

Each wave: apply the Global Constraints header rules to every non-generated `.dart` file in the listed directories (non-recursive per directory unless a subtree is listed). Files named under **Tier 3** get the listed gotchas folded into their headers, phrased in the file's own vocabulary (source: current CLAUDE.md §1–§6 — read the relevant section before writing). All other files get tier 1 or 2 per judgment. Each wave ends: verification loop (Global Constraints step 4), `fvm dart format` on touched files, one commit `docs(headers): <area> file headers`.

### Task 4: Wave 1 — core infra (35 files)

**Dirs:** `lib/core/di`, `lib/core/domain`, `lib/core/domain/entities`, `lib/core/error`, `lib/core/navigation`, `lib/core/storage`, `lib/core/network`.

**Tier 3:**
- `core/di/injection_container.dart` — boot order: opens all boxes in parallel; cookies+requestRules hydrate via `openAndHydrateDeferredBoxes` BEFORE `NetworkService` is usable (a post-frame warm-up raced early sends — don't re-defer without a readiness gate); manual `Hive.registerAdapter` calls kept over generated `hive_registrar.g.dart`.
- `core/network/network_service.dart` — manual redirect loop: each hop sent `followRedirects:false` so the cookie interceptor runs per hop; 303 and POST-301/302 become bodyless GETs; 307/308 keep method+body; `Authorization` stripped on cross-host redirect; `applyConfig` rebuilds the adapter only when `NetworkConfig.sameAdapterConfig` says an adapter-relevant field changed, and closes the replaced adapter.
- `core/domain/entities/http_request_config_entity.dart` — shared by tabs/collections/history; lives in core because three features reference it.
- `core/network/http_methods.dart` — single source of the method list; never hardcode `['GET','POST',...]`.
- `core/network/dio_adapter_config_io.dart` (or equivalently named `*_io.dart` in that dir) — the ONLY place a `dart:io` `SecurityContext` is built (mTLS), wrapped in try/catch fallback.

### Task 5: Wave 2 — core git + shared UI atoms + main (26 files)

**Dirs:** `lib/core/git`, `lib/core/ui/widgets`, plus `lib/main.dart`.

**Tier 3:**
- `main.dart` — `appShortcuts` is a computed, `@visibleForTesting`, platform-exclusive map (⌘ vs Ctrl via `buildAppShortcuts(useMeta:)`); ONLY the `Shortcuts` map lives at the root — every `Action` lives in `MainScreen` or deeper, because a root `Actions` above `MaterialApp` is reachable from inside every modal dialog (the old stacked-invisible-tabs bug).
- `core/ui/widgets/key_value_list_editor.dart` — one widget backs params (ordered list), headers (map), and env vars (map) via decode/encode/equals codecs; `_lastEmitted` echo-suppression keeps focus and half-typed state alive across the bloc round-trip — never bypass with a bespoke row editor; optional `secretKeys`/`onSecretKeysChanged` adds lock+reveal (env vars only).
- `core/ui/widgets/variable_highlight_controller.dart` — theme-agnostic constructor; owner pushes variables/colors via `updateVariables`/`updateColors` in `didChangeDependencies`; both notify only on real change (`MapEquality`/`==`) so the URL bar doesn't rebuild per bloc emission.
- `core/git/git_service.dart` (and siblings) — tier 2+; note the inline `git -c user.name=…` identity (never writes global git config; from settings HiveFields 28/29).

### Task 6: Wave 3 — core/utils root (27 files)

**Dirs:** `lib/core/utils` (root only).

**Tier 3:**
- `environment_resolver.dart` — grammar accepts any non-empty non-brace name (`\$?[^{}]+?`, optional inner whitespace); unknown names stay VERBATIM (never blanked); leading `$` = dynamic built-ins (`$guid`/`$randomUUID`/`$timestamp`/`$isoTimestamp`/`$randomInt`), each occurrence independent, env var of same name wins; `isDynamic` is the source of truth.
- `curl_utils.dart` — full cURL PARSER (tokenizer + flags + body-type resolution); `generate()` is a one-line delegate to CodeGenService.
- `code_gen_service.dart` — six per-language emitters over shared `_Effective`; new targets appear in `code_export_dialog.dart` automatically because it iterates `CodeGenTarget.values`.
- `json_utils.dart` — prettify runs in `compute` (off the UI thread).
- `json_path_builder.dart` — emits the exact grammar `JsonPath` accepts (used by TREE-mode copy-path/extract).
- `json_file_io.dart` — THE Postman file-I/O plumbing (`slugFilename`/`saveJsonFileWithFeedback`/`importJsonFilesWithFeedback`); collections + environments both use it; `allowedExtensions` param (response save passes `['json','txt']`).

### Task 7: Wave 4 — core/utils subdirs (25 files)

**Dirs:** `lib/core/utils/apidoc`, `lib/core/utils/io`, `lib/core/utils/openapi`, `lib/core/utils/postman`, `lib/core/utils/workspace`.

**Tier 3:**
- `postman/postman_collection_mapper.dart` — bidirectional (toJson serialize / fromJson deserialize halves); secret env values masked on export (empty value, `type:'secret'`); saved examples are local-only, excluded from export.

### Task 8: Wave 5 — theme core (18 files)

**Dirs:** `lib/core/theme`, `lib/core/theme/extensions`, `lib/core/theme/motion`.

**Tier 3:**
- `theme_registry.dart` — `resolveTheme(themeId)(brightness, isCompact)`; adding a theme = new dir under `themes/` + `ThemeDescriptor` here + ID in `theme_ids.dart`; READ docs/THEME_AUTHORING.md first.
- `extensions/app_components.dart` — 8th extension, per-theme widget slot builders; three slot rules: `surface` must fill (lives in an `Expanded`), `logView` sizes to bounded height, `metric` is a compact inline chip; animated slots build the painter once and drive via `CustomPainter(repaint:)`, degrade to static under `reduceEffects`.
- `motion/photosensitivity.dart` — WCAG 3 Hz flash guard (`safeFlashCount`).

### Task 9: Wave 6 — the seven themes (35 files)

**Dirs:** `lib/core/theme/themes/{auris,brutalist,classic,dracula,editorial,glass,rpg,shared}`.

**Tier 3:**
- `auris/auris_theme.dart` — composes the external `auris` kit; MUST spread `...base.extensions.values` so `AurisScheme` survives `copyWith`; dark `ThemeData.primaryColor` is near-black — use `colorScheme.primary` for accents.
- `brutalist/brutalist_theme.dart` — a handful of Material text sizes are deliberately compact-mode-responsive (marked with comments); don't const them back without a design discussion.
- `rpg/`, `brutalist/`, `glass/` motion/spec files — `*SpecFor` switches use wildcard `_ =>` so a NEW ThemeReaction flavor falls through silently; tests are the net.

### Task 10: Wave 7 — tabs data/domain/bloc (20 files)

**Dirs:** `lib/features/tabs/data`, `lib/features/tabs/data/datasources`, `lib/features/tabs/data/models`, `lib/features/tabs/data/repositories`, `lib/features/tabs/domain/entities`, `lib/features/tabs/domain/repositories`, `lib/features/tabs/domain/usecases`, `lib/features/tabs/presentation/bloc`, `lib/features/tabs/presentation/screens`.

**Tier 3:**
- `presentation/bloc/tabs_bloc.dart` — identity-based events (`tabId`, never index — index events race concurrent emissions; only `SetActiveIndex`/`ReorderTabs` are position-based, and `SetActiveIndex` rejects out-of-range); debounced 10 s save + flush on `close()`; `LoadTabs` sanitizes `isSending=false`; any non-NetworkFailure send error also resets `isSending` (a tab must never stick on SENDING); panels: ≥1 panel invariant, empty panels legal (`activeTabId == ''`), NO auto-seed (the `_ensureNonEmpty` floor was removed — don't reintroduce), in-flight sends resolve tabs ACROSS panels (`_findTab`/`_replaceTabAcrossPanels`); keeps a justified foundation import for `compute` (web-safe) under `// ignore: avoid_flutter_imports`.
- `data/models/request_tab_model.dart` — Hive typeId 2; response stored as four flat columns, `statusCode == null` is the has-response discriminator (the entity keeps `HttpResponseEntity?` — don't re-flatten); `responseHistory` at HiveField(9).
- `data/repositories/` impl — `_toPersistableModel` caps each history body at 1 MiB; `saveLargeResponsesInHistory:false` downgrades superseded large entries to `kHistoryBodyNotKeptPlaceholder`; newest entry always keeps its full body.
- `domain/usecases/send_request_use_case.dart` — couples network call + history write; history is best-effort (caught + logged, never fails the send); NEVER resolve env vars in `_record` — history must keep the templated config so re-sending under another environment works.

### Task 11: Wave 8 — tabs widgets root (24 files)

**Dirs:** `lib/features/tabs/presentation/widgets` (root only; includes the four files Task 1 created — improve their headers if needed).

**Tier 3:**
- `url_bar.dart` — `_setControllerPreservingEnd` is the ONLY safe way to push text into the controller (cursor jumps otherwise); input starting `curl ` parses as a full request spec → single `UpdateTab`; SEND resolves env vars via `ActiveEnvironmentHelper.variablesFor`.
- `request_view.dart` — `splitRatio` clamped to 0.1..0.9, `_splitFlexUnits=1000` (preserve clamping or panes go to zero); all `JsonCodeEditor` controllers built with `createJsonCodeController()`.
- `json_code_editor.dart` — colors come from `jsonHighlightSpanBuilder` via the controller's `spanBuilder` (per-line re_highlight pass); NEVER set `CodeEditorStyle.codeTheme` — it silently reverts to single-color; re_editor eats Cmd+S unless stripped via `_NoSaveCodeShortcutsActivatorsBuilder`.
- `panel_close_coordinator.dart` — `closePanelWithSavePrompt` must be called with a context BELOW MaterialApp (root navigator's): dismissing the selector overlay unmounts the row context.

### Task 12: Wave 9 — response views (21 files)

**Dirs:** `lib/features/tabs/presentation/widgets/response`, `lib/features/tabs/presentation/widgets/response/viewers`.

**Tier 3:**
- `response/response_body_view.dart` — 3-mode PRETTY/RAW/TREE toggle (keys `body_toggle_*`); TREE only when body decodes to JSON object/array under `kLargeResponseViewerChars` (decode cached in `_decoded` so the tree keeps expansion state); `kResponseBodyTooLargePlaceholder` stays plain text; Extract-to-`{{var}}` dispatches `AddExtractionRule` to the global RulesBloc.
- `viewers/` media viewers — bytes capture is live-only (never persisted to Hive); web-safe conditional imports.

### Task 13: Wave 10 — collections data/domain/bloc (43 files)

**Dirs:** `lib/features/collections/data/{datasources,models,repositories,services}`, `lib/features/collections/domain`, `lib/features/collections/domain/{entities,logic,repositories,usecases}`, `lib/features/collections/presentation/bloc`.

**Tier 3:**
- `domain/logic/collections_tree_helper.dart` — ALL tree mutations are pure functions that never mutate input; missing parent in `addToParent` is NOT an error (bloc verifies via `findNode` first, appends to root on miss — correct behavior); sort = favorites, folders, leaves, each alphabetical.
- `data/services/workspace_sync_service.dart` — git-friendly workspace mirror; saved examples are excluded from the mirror and from Postman export.

### Task 14: Wave 11 — collections widgets (22 files)

**Dirs:** `lib/features/collections/presentation/widgets`.

**Tier 3:**
- `collections_list.dart` — sole `TreeView` (two_dimensional_scrollables) consumer; expansion owned manually by `_expandedIds` (Set of node ids) reseeded into `TreeViewNode(expanded:)` each rebuild — value-keyed expansion collapses on every mutation (the H2 regression); fixed `AppLayout.treeRowExtent` + viewport-width `SizedBox` (rows have unbounded cross-axis width in the 2D viewport); drag-and-drop via `Draggable<String>`/`DragTarget<String>` carrying node ids.

### Task 15: Wave 12 — chaining + environments + settings (44 files)

**Dirs:** `lib/features/chaining/**` (all 8 dirs), `lib/features/environments/**` (all 10), `lib/features/settings/**` (all 9 — includes Task 2's new file).

**Tier 3:**
- `chaining/presentation/.../chaining_write_back_listener.dart` (exact name may differ — the write-back coordinator) — widget-layer coordinator writing captured values to the active environment; bloc→bloc coupling deliberately avoided.
- `environments/data/...` + bloc — list sorted case-insensitively by name on read AND on add/update/import (box keys are UUIDs, Hive key order is meaningless); `AddEnvironment` carries the full entity because the dialog needs the id synchronously.
- `environments/presentation/widgets/environments_dialog.dart` — deleting the ACTIVE environment: the dialog (with both blocs in scope) dispatches `UpdateActiveEnvironmentId(null)` after delete.
- `settings/presentation/bloc/settings_bloc.dart` — NO LoadSettings event (settings load synchronously at boot as `initialSettings` — don't add one without changing boot); every `Update*` saves AND emits in the handler; `SettingsEntity.copyWith` uses a sentinel `_unchanged` Object so `activeEnvironmentId` can be explicitly cleared to null.

### Task 16: Wave 13 — history, home, mcp, realtime, cookies, command_palette, updates (43 files)

**Dirs:** `lib/features/history/**`, `lib/features/home/**`, `lib/features/mcp/**`, `lib/features/realtime/**`, `lib/features/cookies/**`, `lib/features/command_palette/**`, `lib/features/updates/**`.

**Tier 3:**
- `history/data/datasources/history_local_data_source.dart` (impl) — history is read-only from the UI (writes only in SendRequestUseCase); dedup by request signature `method+url+body` PLUS body-shape fields (`bodyType`, `graphqlVariables`, `bodyFilePath`, `formFields`); headers differences do NOT dedupe; trim is a `while` loop so lowering `historyLimit` actually shrinks the box; stream via `Box.watch()`, repository reverses to newest-first.
- `history/data/models/request_config_model.dart` — `==`/`hashCode` DELIBERATELY exclude `id` so dedup works on signature; don't re-include without discussion.
- `home/presentation/screens/main_screen.dart` — hosts every keyboard `Action` (dialog-openers need a context below MaterialApp+Navigator); `_buildTabBar` here IS the tab strip (each chip is `RequestTabChip`).
- `home/domain/usecases/tab_dirty_checker.dart` — linked tab compares config vs saved node config; unlinked compares vs default `HttpRequestConfigEntity(id: tab.config.id)`.
- `realtime/presentation/bloc/...` + `realtime_service.dart` (find under realtime or core) — bloc-over-service by design (no domain/data split); optional `webSocketFactory` for testable WS teardown; `buildSseDio` shares verify-SSL/proxy/mTLS adapter + cookie jar with the main client; SSE non-2xx connect surfaces as an `HTTP <code>` error frame; binary WS frames log `[binary frame · N bytes]`; WS proxy/mTLS is a known follow-up.
- `cookies/data/...` cookie store — keyed `domain|path|name`, one put/delete per cookie; `hostOnly` at HiveField(7) implements RFC 6265 (absent Domain attribute → exact-host match).
- `updates/.../update_decision.dart` — `shouldPromptForUpdate` suppresses ONLY the exact skipped version (a still-newer release prompts again; stored value never cleared).
- `updates/presentation/update_gate_io.dart` — the SOLE importer of `updat`/`dart:io`/`package_info_plus`/`path_provider` (web-safety gate); macOS opens the release asset in the browser (sandbox-quarantine made in-app .dmg downloads Gatekeeper-"damaged").

**Extra step for this final wave — whole-lib sweep:**

```bash
for f in $(find lib -name '*.dart' ! -name '*.g.dart'); do
  head -1 "$f" | grep -q '^//' || echo "MISSING: $f";
done
```
Expected: NO output (every non-generated lib file now has a header). Then run the full verification bar (all six commands from Task 3 Step 2) before committing.

---

### Task 17: `file_header_required` lint + fixtures

**Files:**
- Modify: `tools/getman_lints/lib/getman_lints.dart` (new rule + registration)
- Create: `tools/getman_lints/example/lib/file_header_fixture.dart`
- Modify: the 7 fixture files whose first line is `// ignore_for_file:` (add a prose header line above it): `platform_ok_io.dart`, `domain_imports_fixture.dart`, `equatable_fixture.dart`, `sample_bloc.dart`, `platform_bad_fixture.dart`, `sample_widget.dart`, `feature/domain/domain_bad_fixture.dart`
- Modify: `tools/getman_lints/example/lib/existing_rules_fixture.dart` only if its opening comment starts with ignore/expect_lint (it starts with prose — likely no change)

**Interfaces:**
- Produces: lint `file_header_required` (WARNING severity) firing on any `lib/**.dart` (non-`.g.dart`) whose first real comment is missing. "Real" excludes comments starting `// ignore` or `// expect_lint`. Reported at the first token so `// expect_lint:` on the preceding line matches.

- [ ] **Step 1: Write the failing fixture first**

`tools/getman_lints/example/lib/file_header_fixture.dart`:

```dart
// expect_lint: file_header_required
class MissingHeaderFixture {}
```

Run the self-test — expected: FAILURE mentioning an unfulfilled `expect_lint` (the rule doesn't exist yet):

```bash
( cd tools/getman_lints/example && fvm dart run custom_lint )
```

- [ ] **Step 2: Implement the rule**

In `tools/getman_lints/lib/getman_lints.dart` add `import 'package:analyzer/dart/ast/token.dart';` to the imports, register `FileHeaderRequired()` in the `getLintRules` list, and append:

```dart
/// Enforces the file-header mandate (CLAUDE.md §7 "Design for Claude"): every
/// hand-written file under lib/ opens with a `//` prose comment describing
/// what lives in it. Lint-plumbing comments (`// ignore...`,
/// `// expect_lint...`) don't count as headers. Reported at the first token
/// (not offset 0) so `// expect_lint:` fixtures can precede it.
class FileHeaderRequired extends DartLintRule {
  const FileHeaderRequired() : super(code: _code);

  static const _code = LintCode(
    name: 'file_header_required',
    problemMessage:
        'File must open with a `//` header comment describing its purpose '
        '(what lives here; for services also collaborators + wiring). See '
        'CLAUDE.md "Design for Claude".',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final path = _posix(resolver.path);
    if (!path.contains('/lib/') || path.endsWith('.g.dart')) return;

    context.registry.addCompilationUnit((unit) {
      Token? comment = unit.beginToken.precedingComments;
      while (comment != null) {
        final text = comment.lexeme;
        final isPlumbing =
            text.startsWith('// ignore') || text.startsWith('// expect_lint');
        if (!isPlumbing) return; // a real header exists
        comment = comment.next;
      }
      reporter.atOffset(
        offset: unit.beginToken.offset,
        length: unit.beginToken.length,
        diagnosticCode: _code,
      );
    });
  }
}
```

(analyzer 8.4.0: `atOffset` takes `diagnosticCode:`; `errorCode:` is deprecated.)

- [ ] **Step 3: Give the 7 ignore-first fixture files a header line**

Above each `// ignore_for_file:` first line add one prose line, e.g. for `platform_ok_io.dart`:

```dart
// Fixture: *_io.dart files MAY import dart:io (platform_io_outside_io_files).
```

- [ ] **Step 4: Run fixtures self-test + app custom_lint**

```bash
( cd tools/getman_lints/example && fvm dart run custom_lint )
fvm dart run custom_lint
```
Expected: both report no issues (the expect_lint is fulfilled; all app lib files got headers in Tasks 4–16). If the app run reports missing headers, add them (a file was missed) rather than weakening the rule.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(lints): file_header_required rule + fixtures

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 18: `docs/CODEMAP.md` + coverage test

**Files:**
- Create: `docs/CODEMAP.md`
- Create: `test/docs/codemap_coverage_test.dart`

**Interfaces:**
- Produces: CODEMAP.md sections `## Directory map`, `## Where is…? (concept lookup)`, `## Cross-cutting flows`. Task 20's CLAUDE.md links here as the lookup entry point.

- [ ] **Step 1: Write the failing coverage test**

```dart
// Guards docs/CODEMAP.md freshness: every lib/ directory that contains
// hand-written Dart files must be mentioned in the codemap, so new features
// can't silently escape the map.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every lib/ directory with Dart files appears in docs/CODEMAP.md', () {
    final codemap = File('docs/CODEMAP.md').readAsStringSync();
    final missing = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! Directory) continue;
      final hasDart = entity.listSync().whereType<File>().any(
        (f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'),
      );
      if (!hasDart) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (!codemap.contains(path)) missing.add(path);
    }
    expect(
      missing,
      isEmpty,
      reason: 'Add these directories to docs/CODEMAP.md:\n${missing.join('\n')}',
    );
  });
}
```

Run: `fvm flutter test test/docs/codemap_coverage_test.dart`
Expected: FAIL (docs/CODEMAP.md doesn't exist yet).

- [ ] **Step 2: Write `docs/CODEMAP.md`**

Structure (content assembled by reading the tree + headers written in Tasks 4–16):

```markdown
# Getman Code Map

Start here to find anything. Format: literal directory paths (the coverage
test in test/docs/codemap_coverage_test.dart requires every lib/ directory
with Dart files to appear below verbatim).

## Directory map
One row per directory: `lib/<path>` — one-line purpose; 2-4 key files for the
big ones. Cover ALL directories listed by:
`for d in $(find lib -type d); do ...` (the test's exact criterion).

## Where is…? (concept lookup)
Alphabetical table, ~60–80 rows: concept → file path(s). Must include at
minimum: assertions, auth, auto-update, beautify/prettify JSON, body types,
bulk edit, chaining/extraction, code generation, collections tree,
command palette, compare/diff responses, cookies, cURL parse/paste,
dirty tracking, drag-and-drop, dynamic variables, environments, error model,
examples (saved), git sync/branches/PRs/conflicts, GraphQL, history +
dedup, keyboard shortcuts, large responses, MCP, method colors, mTLS/client
certs, OpenAPI import, panels, Postman import/export, proxy, redirects,
response time-travel, secret variables, settings, splitters, SSE, themes +
component slots, tree view (JSON TREE mode), variable highlighting,
WebSocket, workspace mirror.

## Cross-cutting flows
Nine numbered chains, each step `file — role`:
1. Send request: url_bar/main_screen (dispatch + envVars) → tabs_bloc →
   send_request_use_case → tabs repository (env substitution) →
   network_service (redirect loop, cookies) → back via bloc _recordResponse →
   response views; history write as side branch.
2. Cookie round-trip: cookie_interceptor → cookie store → Hive box →
   manager dialog.
3. Environment resolution: environment_resolver ← ActiveEnvironmentHelper ←
   SendRequest dispatchers; URL highlighting via
   variable_highlight_controller.
4. Dirty tracking: tab_dirty_checker ← tab close/save flows.
5. Theme resolution: settings themeId → theme_registry.resolveTheme →
   theme builder → extensions (incl. AppComponents slots) → widgets via
   context.app* accessors.
6. Panel/tab lifecycle: panel events in tabs_bloc → PanelModel persistence →
   panel_selector / tab strip / tab_switcher_sheet.
7. Chaining: response arrives → rules_runner (assertion_engine +
   extraction_engine) → ChainingWriteBackListener → environments bloc.
8. Postman import/export: json_file_io → postman mappers →
   collections/environments blocs.
9. Auto-update: boot check → github_release_data_source → update_decision →
   UpdateController → update_gate (io/stub) → UpdateDialog.
```

Every path mentioned must be real — verify each with a quick `ls` while writing. The directory-map section MUST contain each directory's literal path string.

- [ ] **Step 3: Run the coverage test until green, then the full test suite for regressions**

```bash
fvm flutter test test/docs/codemap_coverage_test.dart
fvm flutter test
```
Expected: PASS / all green.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "docs: CODEMAP master index + coverage test

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 19: `docs/architecture/` deep-dive docs (10 files)

**Files:**
- Create: `docs/architecture/app-shell.md`, `tabs-and-panels.md`, `collections.md`, `theming.md`, `network-and-cookies.md`, `persistence-hive.md`, `environments-and-chaining.md`, `settings-history-updates.md`, `git-sync.md`, `mcp.md`

**Interfaces:**
- Produces: the 10 docs Task 20's routing table links to. Content is RELOCATED from CLAUDE.md (do not delete from CLAUDE.md yet — Task 20 does that).

Disposition (source → destination):

| Destination | Absorbs (current CLAUDE.md) |
|---|---|
| `app-shell.md` | §4.1 boot sequence, DI wiring, MultiBlocProvider/RepositoryProvider inventory, global shortcuts architecture + the root-Actions trap, §4.7 error model |
| `tabs-and-panels.md` | §4.2 entire, panels block from §3, response time-travel, §4.6 dirty tracking (refinement over the spec: it is tab-centric) |
| `collections.md` | §4.3 entire, saved examples, workspace mirror bullet, tree UI notes from §1/§6 |
| `theming.md` | §4.8 entire + theme bullets from §1; link to docs/THEME_AUTHORING.md |
| `network-and-cookies.md` | NetworkService redirect/mTLS/adapter details from §3-settings text, realtime bullet from §2, cookies bullet from §2 |
| `persistence-hive.md` | §3 typeId table + ALL SettingsModel field paragraphs + §4.9 write-timing table + retired-fields ledger |
| `environments-and-chaining.md` | §4.10 entire + chaining bullet from §2 |
| `settings-history-updates.md` | §4.4, §4.5, updates bullet from §2 + auto-update fields text |
| `git-sync.md` | NEW: written from `lib/core/git/` headers + `docs/superpowers/specs/2026-06-26-git-native-collaboration-design.md`, `2026-07-13-git-branch-sync-design.md`, `2026-07-14-git-pr-integration-design.md`, `2026-07-15-git-conflict-resolution-design.md` — a 1-2 page overview: components, flows, where things live |
| `mcp.md` | NEW: written from `lib/features/mcp/` headers + code — 1 page: what the MCP feature does, entities/bloc/widgets, wiring |

Each doc opens with: `> Deep-dive for <area>. Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md.` Keep relocated text verbatim where it is already good; reformat into sections; fix any stale path (e.g. `request_editor_tabs.dart` → the Task 1 split files; `tab_widget.dart` → `request_tab_chip.dart`).

- [ ] **Step 1: Write the 8 relocation docs** (table rows 1–8) — content moved, paths updated.
- [ ] **Step 2: Write `git-sync.md` and `mcp.md`** from specs + code.
- [ ] **Step 3: Verify no stale paths**

```bash
grep -rn "request_editor_tabs\|tab_widget\|TabWidget" docs/architecture/
```
Expected: no hits.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture && git commit -m "docs: architecture deep-dives (relocated from CLAUDE.md + git/mcp)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 20: Rewrite CLAUDE.md (slim core + routing table + Design-for-Claude mandate)

**Files:**
- Modify: `CLAUDE.md` (full rewrite)

**Interfaces:**
- Consumes: Tasks 18–19 docs (links must resolve).

New CLAUDE.md structure (target ≈ one-third of current volume; every cut section must be reachable via the routing table):

1. **Header** — one-liner + compressed tech-stack table (package → role, one line each; the long per-package prose moves to the architecture docs).
2. **Navigation** — "Finding anything: start at `docs/CODEMAP.md`." + the **read-before-editing routing table**:

```markdown
| Touching… | Read first |
|---|---|
| Boot, DI, shortcuts, error model | docs/architecture/app-shell.md |
| Tabs, panels, sending, responses | docs/architecture/tabs-and-panels.md |
| Collections tree, examples, workspace mirror | docs/architecture/collections.md |
| Themes, AppComponents, motion | docs/architecture/theming.md (+ docs/THEME_AUTHORING.md to author) |
| NetworkService, redirects, cookies, WS/SSE | docs/architecture/network-and-cookies.md |
| Any @HiveType / box / typeId | docs/architecture/persistence-hive.md |
| Environments, variables, chaining | docs/architecture/environments-and-chaining.md |
| Settings, history, auto-update | docs/architecture/settings-history-updates.md |
| Git sync/branches/PRs/conflicts | docs/architecture/git-sync.md |
| MCP feature | docs/architecture/mcp.md |
| Open work / backlog | docs/BACKLOG.md |
```

3. **Project structure** — the short tree + the feature list UPDATED to include `mcp` and the git integration (currently missing).
4. **Mandatory rules** — kept verbatim-in-spirit, tightened: domain purity, DI, immutability, theme adherence, atomic widgets, identity-based events principle, `package:` imports, logging rules, surgical edits, wiki-sync mandate, plus:

```markdown
- **Design for Claude.** This codebase is written and maintained by Claude.
  When designing new code: (a) name files and symbols with the words a task
  prompt would use — grep-ability is a design constraint; (b) every new file
  opens with a header per the tier rules (lint: `file_header_required`);
  (c) keep CLAUDE.md lean — new deep-dive documentation goes in
  `docs/architecture/` and gets a routing-table row, never inline here;
  (d) put knowledge at the right layer: file-specific → that file's header,
  cross-file → the architecture doc, universal → here. New lib/ directories
  and new user-facing concepts get a `docs/CODEMAP.md` entry (coverage test
  enforces directories).
```

5. **Hive quick-rules** — never renumber typeIds; next free: 13; retired SettingsModel fields 22/27 (never reuse); regen command; everything else → persistence-hive.md.
6. **Build & verification bar** — §5 kept as is (all commands + the "four independent passes" warning), plus the fixtures note for `file_header_required`.
7. **Global gotchas (short)** — only repo-wide ones: `listenWhen`/`buildWhen` are not optional; `HttpMethods.all`; controller types (TextEditingController vs CodeLineEditingController); Hive regen; `showAppSnackBar`/`ConfirmDialog`/`NamePromptDialog` atoms. Everything file-specific is now in file headers; everything area-specific in the architecture docs.

- [ ] **Step 1: Rewrite CLAUDE.md** per the structure above.
- [ ] **Step 2: Loss audit** — for every §/bullet of the OLD CLAUDE.md (use `git show master:CLAUDE.md`), confirm its content now exists in ≥1 of: new CLAUDE.md, docs/architecture/*, a file header, docs/CODEMAP.md. Fix any orphan. Spot-check the known load-bearing ones: redirect loop semantics, dedup signature, H2 expansion fix, root-Actions trap, `_setControllerPreservingEnd`, no-LoadSettings, typeId ledger, retired HiveFields 22/27.
- [ ] **Step 3: Verify links**

```bash
for f in $(grep -o 'docs/[a-zA-Z0-9_/.-]*\.md' CLAUDE.md | sort -u); do [ -f "$f" ] || echo "BROKEN: $f"; done
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md && git commit -m "docs: slim CLAUDE.md to lean core + routing table + Design-for-Claude mandate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 21: Final verification + PR

- [ ] **Step 1: Full verification bar**

```bash
fvm flutter analyze
fvm dart run custom_lint
( cd tools/getman_lints/example && fvm dart run custom_lint )
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools
fvm flutter test
```
Expected: 0 issues in all four analysis passes, format changes nothing, all tests green. If format changed anything, commit the formatting and rerun.

- [ ] **Step 2: Push + PR**

```bash
git push -u origin claude-friendly-refactor
gh pr create --base master --title "Claude-friendly navigation refactor (CODEMAP, slim CLAUDE.md, file headers, header lint)" --body "$(cat <<'EOF'
## Summary
- docs/CODEMAP.md master index (directory map + concept lookup + 9 cross-cutting flow traces) with a coverage test
- CLAUDE.md slimmed to a lean core + read-before-editing routing table; deep-dives relocated to docs/architecture/ (10 docs, incl. new git-sync + mcp coverage)
- Plain-English tiered headers on every non-generated lib/ file; file-specific gotchas migrated from CLAUDE.md into the headers of the files they describe
- New getman_lints rule `file_header_required` (+ fixture) so headers can't rot
- Surgical structure: request_editor_tabs split into per-tab files, settings shortcuts cheat-sheet extracted, TabWidget → RequestTabChip rename
- New standing mandate: "Design for Claude" (grep-able naming, headers, knowledge at the right layer)

Spec: docs/superpowers/specs/2026-07-17-claude-friendly-refactor-design.md

## Test plan
- [ ] Full verification bar green (analyze, custom_lint, fixtures self-test, bloc_lint, format, tests)
- [ ] codemap coverage test green
- [ ] No behavior change (comment/doc/move-only apart from the three §4 splits, all covered by existing tests)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review notes

- Spec coverage: §1→Task 18; §2→Tasks 19–20; §3→Tasks 4–16; §4→Tasks 1–3; §5→Task 17 (+18's test); §6→Tasks 3/16/21 checkpoints + PR; §7→Task 20 step 1. Spec's 7-doc table expanded to 10 (app-shell, git-sync, mcp) because `lib/core/git` and `lib/features/mcp` exist but were absent from CLAUDE.md; §4.6 dirty-tracking rehomed to tabs-and-panels.md (tab-centric) — both are refinements, not scope changes.
- The `file_header_required` fixture catch-22 (expect_lint comment would itself be a header) is solved by excluding `// ignore*`/`// expect_lint*` comments and reporting at `beginToken` (not offset 0).
- analyzer 8.4.0 `atOffset` verified to take `diagnosticCode:` (checked in pub cache).
- File counts per wave come from a live directory census (2026-07-17); waves list directories, not counts, so drift is harmless.
