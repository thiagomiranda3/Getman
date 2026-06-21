# Test Coverage Improvement — Design

**Date:** 2026-06-21
**Branch:** `dev`
**Goal:** Add coverage tooling, raise unit/widget coverage by filling the biggest
uncovered code paths, and fix + extend the macOS integration suite against the
recent theme/motion UI changes.

---

## Context & Baseline

- **Unit/widget tests:** 219 files, 1547 cases, all green at start.
- **Integration tests:** 38 patrol_finders flows aggregated into
  `integration_test/all_flows_test.dart`, run on macOS desktop via
  `integration_test/run_macos.sh` (one build, sequential cases).
- **Coverage tooling:** none wired up. `fvm flutter test --coverage` produces
  `coverage/lcov.info` natively; `lcov`/`genhtml` now installed via Homebrew.
- **Baseline coverage (excluding generated `*.g.dart`): 76.27%**
  (14,430 / 18,920 lines).
- **Recent work (last ~40 commits):** almost entirely theme/motion — in-flight
  panel frames, content-swap transitions, tab/panel chip transitions, tree
  drag/drop juice, animated ambient backgrounds (Brutalist halftone, AURIS HUD),
  interactive ambient (cursor force / click ripple), session-rhythm ambient.
  These are the changes most likely to have introduced render overflows or
  moved finders in the integration suite.

---

## Part A — Coverage tooling

**Deliverable:** `tool/coverage.sh` (executable, committed).

Behavior:
1. `fvm flutter test --coverage` → `coverage/lcov.info`.
2. `lcov --remove` strips lines that make the percentage dishonest:
   - `*.g.dart` (generated Hive adapters)
   - `*/hive_registrar.g.dart`
   - abstract repository interfaces under `*/domain/repositories/*.dart`
     (no executable lines)
   - platform stubs/native-only files that cannot execute under the Flutter VM
     test harness: `*/update_gate_io.dart`, `*/dio_adapter_config_io.dart`,
     `lib/main.dart`.
   Filtered output → `coverage/lcov.filtered.info`.
3. `genhtml coverage/lcov.filtered.info -o coverage/html` → browsable report.
4. Print a per-top-level-package summary + grand total to the terminal
   (derived from the filtered lcov).
5. Accept an optional `--open` flag to open `coverage/html/index.html`.

Supporting changes:
- `.gitignore`: add `coverage/` (lcov.info, lcov.filtered.info, html/).
- CLAUDE.md §5 Build & Test Commands: document `tool/coverage.sh`.
- `integration_test/README.md` / a short note: cross-reference the script.

**Non-goal:** no CI gate / threshold enforcement (explicitly out of scope —
chosen "Script + HTML report", not "Script + CI gate").

---

## Part B — Unit/widget back-fill (coverage-gap driven, all layers)

Target: lift overall (post-exclusion) coverage from ~76% toward **~90%**,
prioritized by largest honest uncovered line counts.

### Tier 1 — pure logic at 0% (fast, high value)
- `lib/features/chaining/domain/usecases/request_rules_usecases.dart`
- `lib/features/settings/domain/usecases/settings_usecases.dart`
- `lib/features/chaining/data/datasources/request_rules_local_data_source.dart`
- `lib/features/settings/data/datasources/settings_local_data_source.dart`

Approach: pure-Dart use-case tests with fake/mock repositories; data-source
tests over an in-memory Hive box (the existing pattern in
`test/features/*/data/datasources/`).

### Tier 2 — high-line widgets (widget tests)
Ordered by uncovered lines:
- `url_bar.dart` (260) — cURL-paste detection, send button dispatch,
  overflow menu, URL echo-write, variable highlighting wiring.
- `node_action_sheet.dart` (182) — phone action sheet entries + callbacks.
- `request_view.dart` (175) — split-pane composition, split clamp, beautify
  / save Actions.
- `environments_dialog.dart` (156) — list, add, delete-active → clear active.
- `history_list.dart` (96) — render, tap-to-open, search, empty.
- `environment_selector.dart` (89) — selector rows + active marker.
- `code_export_dialog.dart` (54) — iterates `CodeGenTarget.values`,
  reflects edits.
- `request_kind_method_selector.dart` (52) — method/kind switching.
- `environment_editor.dart` (48), `url_overflow_menu.dart` (44),
  `environment_list_tile.dart` (42), `realtime_button.dart` (35).
- Home widgets: `side_menu.dart` (54), `empty_tabs_placeholder.dart` (25),
  `add_tab_button.dart` (17).
- `response/response_history_timeline.dart` (79).
- Core atoms: `splitter.dart` (26), `hover_highlight.dart` (11).

Approach: widget tests pumping the widget inside the minimal
`BlocProvider`/`RepositoryProvider`/theme scaffolding each needs (mirror the
existing `test/features/.../presentation/widgets/` and
`test/core/ui/widgets/` patterns). Assert rendered structure + that
interactions dispatch the expected bloc events / invoke callbacks.

### Tier 3 — branch gaps + screen-level
- `main_screen.dart` shortcut `Action`s exercised via the computed
  `appShortcuts` map (extend `test/main_shortcuts_test.dart`).
- `editorial_decorations.dart` (49), `classic_press.dart` (19).
- Push branch coverage on partially-covered files surfaced by the report
  (e.g. `injection_container.dart` cold-start paths, selectors with
  active/inactive branches).

Each new/edited test file must pass `fvm flutter test`, `fvm flutter analyze`,
`fvm dart run custom_lint`, and `fvm dart format` before the batch is
considered done.

---

## Part C — Integration tests (run → fix → extend)

### 1. Run
Execute the full suite once: `bash integration_test/run_macos.sh`. Capture the
failing cases and their errors.

### 2. Fix
For each failure, classify:
- **Real lib regression** (e.g. a render overflow under an in-flight frame /
  ambient background, or a broken interaction): write/confirm a failing test
  first, then fix in `lib/` (systematic-debugging + TDD). Overflow guards
  follow the existing `*_components_test.dart` pattern.
- **Test-only drift** (a finder that moved because a label/key changed): fix
  the flow or `support/actions.dart`, never weaken an assertion to mask a real
  problem.

### 3. Extend
New flows for UI behavior not yet automated **and** automatable on macOS:
- **Motion-during-send across loud themes:** for Brutalist / RPG / Glass /
  AURIS / Dracula, send a request and assert the app survives the in-flight
  frame + content-swap transition + send-affordance without crash/overflow and
  the response renders. (Extends `theme_stress_test` philosophy to the new
  motion hooks.)
- **`reduceEffects` ambient path:** toggle reduce-effects on a loud theme,
  send, assert static degradation (no crash, response renders).
- Any concrete interaction gap encountered while fixing (recorded in the plan
  as found).

### Explicitly out of scope (genuinely un-automatable here — per
`integration_test/BACKLOG.md`)
- Native file-dialog flows (import/export, binary/multipart-file body,
  response Save-to-file) — Patrol native automation unsupported on macOS.
- mTLS / proxy / redirects / verify-SSL end-to-end (need a TLS/redirect/proxy
  server).
- re_editor internals (typing into the code editor / find panel) — no standard
  `EditableText` to drive.

---

## Execution Strategy

1. Part A first (tooling) — gives the live report that drives Part B
   prioritization.
2. Part B in batches: fan out independent test-file authoring to parallel
   subagents (subagent-driven-development), with the main session verifying
   `analyze` + `custom_lint` + `flutter test` after each batch and re-running
   `tool/coverage.sh` to confirm the gap closed.
3. Part C sequentially (the macOS run is serial by nature): run, triage, fix,
   re-run, then add new flows and re-run.

## Success Criteria

- `tool/coverage.sh` produces an HTML report + terminal summary; documented.
- Post-exclusion overall coverage ≈ 90% (up from 76%), every Tier-1 file and
  the listed Tier-2 widgets no longer at ~0%.
- Full macOS integration suite green; every failure root-caused (lib fix vs
  finder fix) rather than masked.
- New integration flows for loud-theme motion-during-send + reduce-effects.
- Whole static stack clean (`analyze`, `custom_lint`, `bloc_lint`, `format`)
  and `fvm flutter test` 100% green.
