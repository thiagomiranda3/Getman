# Refactor + Performance Overhaul — Design

**Date:** 2026-06-25
**Branch:** `chore/refactor-perf-overhaul` (off `dev`)
**Status:** approved design → implementation via waves

## Goal

Two fronts across the ~47k-LOC codebase:

1. **Refactoring** — break large multi-responsibility files into smaller,
   composable, single-responsibility units; apply SOLID/DRY; split big widgets
   into composable widgets.
2. **Performance** — move synchronous work off the UI isolate; keep the app
   responsive with big JSON responses/payloads and many open tabs/files; make
   the app ready ASAP at startup; never freeze the main thread.

This is an established, already performance-conscious codebase (parallel Hive
box opening, sync settings read at boot, `compute()` for JSON prettify and
chaining rules, async file-body reads). The work below is the *next* layer:
the remaining confirmed hot-path freezes and the highest-ROI structural splits.

## Decisions (from brainstorming)

- **Audit → backlog → waves.** Evidence first (this doc), then execute
  top-impact items in reviewable waves; the user steers between waves.
- **Perf proof = reasoning + tests + targeted micro-benchmarks.** No full
  DevTools harness. Lightweight `Stopwatch` benchmarks under `test/perf/`
  assert the *architectural property* (decode cached/off-isolate, equality
  skips body bytes, parse memoized) and print before/after; they do **not**
  hard-assert wall-clock latency (avoids flaky CI).
- **ROI-ranked, not size-ranked.** Split files that mix responsibilities or are
  hard to reason about. Large-but-cohesive declarative files (per-theme
  `*_components`/decoration builders, `app_layout`, `settings_model`) are kept
  at the file level; only cross-file duplication in them is addressed.

## Working agreement / contracts

- **Refactors are behavior-preserving.** Pure structural moves; no functional
  change. A latent bug found mid-refactor is flagged separately, not silently
  fixed inside a "refactor" commit.
- **Verification bar after every wave** (the repo done-bar): `fvm flutter
  analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`
  all clean; `fvm dart format lib test tools` clean; `fvm flutter test` 100%
  green. These are independent passes — a clean `analyze` does not imply the
  other two.
- **One umbrella branch**, one commit (or small set) per wave, green at each
  wave boundary. PR at the end.
- **Each wave is independently shippable.**
- **Wiki sync** only for waves that change *how a feature is used* (most waves
  are internal-only).

## Load-bearing invariants to preserve (do NOT break)

Collected from the audit; every wave must respect these:

- **TabsBloc single-bloc `_derive` contract** — `TabsState` exposes
  `tabs`/`activeIndex` as the active panel's view; it cannot become two blocs.
  In-flight sends + `UpdateTab` resolve a tab **across all panels**
  (`_findTab`/`_replaceTabAcrossPanels`).
- **Narrow `buildWhen`/`listenWhen` selectors** — esp. `url_bar` deliberately
  excluding `config.url`. Editor responsiveness depends on these.
- **Echo-suppression** — `KeyValueListEditor._lastEmitted` and `url_bar`'s
  `_setControllerPreservingEnd`; never bypass.
- **Collections expansion ownership** — `_expandedIds` lives in the
  `collections_list` State (H2 regression if value-keyed).
- **`_pendingSyncId` async-cancellation** + cached `_decoded` in
  `response_body_view`.
- **MCP off-build controller sync** via `addPostFrameCallback`.
- **Command-palette unlinked-history rule** (saved examples open unlinked).
- **`ValueKey` E2E anchors** referenced by the integration suite.
- **Hive `typeId`s and `@HiveField` indices** are load-bearing; no renumbering.
- **Web safety** — off-isolate work uses `compute()` (web-safe), never
  `Isolate.run`. Conditional imports keep `dart:io`/native plugins out of web.

## Performance backlog (confirmed, evidence-backed)

IDs map to the full audit at
`scratchpad/audit-perf-hotpaths.md` (kept for detail). Verified spots:

- **P-H1 — eager TREE decode.** `response_body_view.dart:165-167` runs
  `JsonPath.tryDecode(rawBody)` (sync `jsonDecode`) on every normal-path
  response, even when TREE is never opened. *Fix:* decode lazily on first TREE
  select, via `compute()`, cached by body identity; combine with prettify so a
  body is decoded once off-isolate.
- **P-H2 — UI-thread highlight + O(n×m) variable scan.**
  `json_code_editor.dart:47-69` + `variable_json_span_builder.dart:11-86`
  (per-char `overrideAt`). *Fix:* single merge pass over sorted match ranges;
  skip when `variables` empty AND line has no `{{`; cap very long single lines.
- **P-H3 — multi-MB string load into re_editor.** `response_body_view.dart`
  (`responseController.text = prettified`). The encode is off-isolate (good);
  the controller line-model rebuild is not. *Fix:* hard size cap + warning on
  the `alwaysPrettifyLargeResponses` / "PRETTIFY & SHOW" opt-in path.
- **P-H4 — equality compares all bodies + maps all panels.**
  `request_tab_entity.dart:90-100` props include `response` + `responseHistory`;
  `HttpResponseEntity.props` compares full `body` String by value (only
  `bodyBytes` reduced to length). `tabs_bloc.dart:162-170`
  `_replaceTabAcrossPanels` maps every panel. *Fix:* exclude large body strings
  from equality (compare id + length + statusCode, mirroring the `bodyBytes`
  trick) on `HttpResponseEntity`/`ResponseHistoryEntry`/`PanelEntity`/
  `HttpRequestTabEntity`; short-circuit `_replaceTabAcrossPanels` to the owning
  panel.
- **P-H5 — ChainingWriteBackListener iterates all tabs per emit.** *Fix:*
  tighten `listenWhen` to fire only when some tab's `extractionResults` changed.
- **P-H6 — CSV viewer full decode+parse in `build()`** (`csv_response_view.dart:18-24`),
  re-parses every rebuild. *Fix:* memoize by bytes identity; limit parser input
  to display rows + 1; `compute()` for large CSV.
- **P-H7 — HTML viewer full `utf8.decode` per build** (`html_response_view.dart:50`).
  *Fix:* memoize on bytes identity; cap very large HTML.
- **P-H8 — JSON tree flatten every build** (`json_tree_view.dart:70-172`).
  *Fix:* memoize flattened list, invalidate only on `_expanded`/`data`;
  `compute()` for copy-value of huge subtrees.
- **P-H9 — cookie/header parse in `build()`.** *Fix:* memoize by header-value
  identity.
- **P-H10 — startup: macOS workspace-bookmark resolve pre-`runApp`**
  (`main.dart:46-48`). *Fix:* defer behind a readiness gate (needed only before
  the first debounced mirror write). Migrations' *scans* stay pre-frame
  (cheap, correctness); only the one-time re-key is real and acceptable.
- **P-H11 — `MediaKit.ensureInitialized()` pre-`runApp`** (`main.dart:41`).
  *Fix:* lazy-init on first media-viewer show.
- **P-H13 — workspace git-mirror re-encodes whole forest, no diff, sync**
  (`workspace_collections_data_source_io.dart`). *Fix:* diff vs last-written
  forest (like `CollectionsRepositoryImpl._persisted`); `compute()` the encode;
  async `exists()` instead of `existsSync()`.
- **P-H14 — `utf8.encode(body).length` for the size badge**
  (`byte_format.dart:8-18`). *Fix:* use `body.length` / memoize.
- **P-H15 — compare-target build scans full history just to enable a button**
  (`response_body_controls.dart:199-248`). *Fix:* cheap `any` early-out; build
  full targets only when the dialog opens.
- **P-H16 — 4-5 `RegExp` built per extract click**
  (`response_body_view.dart:211-227`). *Fix:* hoist to `static final`.

## Refactor backlog (ROI-ranked)

Full per-file detail in `scratchpad/audit-refactor-*.md`.

**HIGH**
- **R-1 `tabs_bloc.dart` (815).** Split into `part` files along seams
  (persistence/debounce · panel-structure helpers · send pipeline · lifecycle
  vs panel handlers), keeping ONE `TabsBloc`. Extract the pure `_recordResponse`
  into a testable `ResponseRecorder`. (`RequestManager` already extracted.)
- **R-2 `settings_dialog.dart` (724).** Extract each tab body →
  `settings/presentation/widgets/sections/*` (General/Appearance/Network +
  `ShortcutsReferenceSection`); shared row atoms → `settings_controls.dart`.
- **R-3 `tab_widget.dart` (652).** Dedupe the ~95-line tab body built twice
  (drag vs normal) into `_TabChrome`; extract tooltip-overlay controller +
  context-menu helper.
- **R-4 `main_screen.dart` (603).** Lift the 144-line keyboard `Actions` map
  into `MainScreenActions` (must stay below `MaterialApp`+`Navigator` for the
  dialog-opening intents); extract `TabStrip`.

**MEDIUM**
- **R-5 `curl_utils.dart` (539).** Extract the pure shell tokenizer →
  `curl/shell_tokenizer.dart`; keep `parse`/`generate` facade.
- **R-6 cross-file DRY atoms** — `SelectorChip` (the active-bg→contrast idiom
  duplicated in `request_editor_tabs._BodyTypeChip` + `response_body_view`),
  `AnchoredOverlay` (panel_selector + tab_widget tooltip),
  `moveTargetsFor(tab, panels)` (built 3×), `buildSendRequestEvent` (url_bar +
  main_screen), `SplitPane` (request_view + main_screen side-menu).
- **R-7 shared `AnimatedPaintHost`** in `themes/shared/` — collapse the
  identical AnimationController/`CustomPainter(repaint:)` lifecycle repeated in
  6 theme files (rpg/glass components + rpg/glass decorations + auris/brutalist
  ambient). Painters themselves stay per-theme (distinct identities).
- **R-8 `response_body_view.dart` (493) + `request_editor_tabs.dart` (635).**
  Extract `BodyModeToggle` + pure `suggestVariableName`; split the BODY family
  into `request_body_tab.dart`. Pairs with Wave 1's area.
- **R-9 remaining splits** — `collections_list` pure `CollectionSearch`;
  `command_palette` `PaletteCommand` builder; `node_action_sheet` →
  `move_to_sheet.dart` (push flatten into `CollectionsTreeHelper`); `mcp_panel`
  pure `mcpResultText` + arg helpers; `code_gen_service` escaper toolkit +
  `Map<CodeGenTarget,Formatter>` registry; `app_components_defaults`
  `_DefaultStatusBadge`+`_DefaultMetric` → one `_FadingChip`.

**KEPT (LOW ROI, cohesive):** `collections_bloc`, `key_value_list_editor`,
`variable_autocomplete`, `form_data_editor`, `json_tree_view`,
`tab_switcher_sheet`, `app_layout`, `settings_model`, and all per-theme
`*_components`/decoration files at the file level.

## Wave plan

Perf-first, then structural. Each wave green before the next.

1. **Big-JSON responsiveness** — P-H1, P-H2, P-H3, P-H8, P-H14, P-H16 +
   `test/perf/` micro-benchmarks (decode, prettify, variable-scan, utf8-size).
2. **Many-tabs scale** — P-H4 (equality trim + owning-panel short-circuit),
   P-H5, P-H9, P-H15.
3. **Response viewers** — P-H6 (CSV), P-H7 (HTML).
4. **Startup & workspace mirror** — P-H10, P-H11, P-H13.
5. **`tabs_bloc.dart`** — `part`-file split + pure `ResponseRecorder` (R-1).
6. **`settings_dialog.dart`** — section widgets (R-2).
7. **Home chrome** — `_TabChrome` dedupe + `MainScreenActions`/`TabStrip`
   (R-3, R-4).
8. **Response/request editors** — `response_body_view` + `request_editor_tabs`
   splits (R-8).
9. **Cross-cutting DRY** — shared atoms (R-6), `curl` tokenizer (R-5), shared
   `AnimatedPaintHost` (R-7).
10. **Remaining feature splits** — R-9.

## Micro-benchmark approach

- Location: `test/perf/` (pure-Dart where possible; `flutter test` runnable).
- Each asserts an architectural property + prints before/after, e.g.:
  - `json_decode_bench`: decoding a ~1 MB JSON is not on the build path /
    result is cached.
  - `tab_equality_bench`: `HttpRequestTabEntity` equality of two tabs with
    large bodies is O(1)-ish (does not scale with body length) after the props
    trim.
  - `variable_scan_bench`: `findVariables` + range-merge over a 2000-char line.
  - `byte_size_bench`: size label does not `utf8.encode` the whole body.
- No hard latency asserts (CI-stable); numbers are informational.

## Out of scope

- Unrelated refactors with no clarity/perf payoff.
- Splitting cohesive declarative theme files at the file level.
- New features / behavior changes.
- A full DevTools profiling harness.
