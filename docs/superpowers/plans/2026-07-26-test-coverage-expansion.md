# Test Coverage Expansion + Integration Suite Repair Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise unit/widget coverage well above the 86.61% baseline (20696/23895
lines) by testing the worst-covered files, repair any macOS integration flows
broken by QoL waves 1–2, and add new e2e flows for every recently shipped
feature that has none.

**Architecture:** Three workstreams. (1) Unit/widget test expansion fanned out
across ~10 area-scoped subagents, each in an isolated git worktree so
`fvm flutter test` runs don't contend; each targets specific files with known
uncovered line ranges from `coverage/lcov.filtered.info`. (2) Integration-suite
repair in the main tree, driven by the baseline `run_macos.sh` result.
(3) New e2e flows for QoL wave 1/2 features, appended to `all_flows_test.dart`.

**Tech Stack:** flutter_test, bloc_test, mocktail, patrol_finders +
integration_test (macOS), lcov.

## Global Constraints

- Always `fvm flutter …` / `fvm dart …`, never plain.
- Tests follow repo conventions: `package:getman/…` imports, no relative
  imports; mirror `test/` path to `lib/` path (`test/<same path>_test.dart`).
- Test files do NOT need the `//` file header (lint applies to `lib/` only),
  but a short intent header is the house style — keep it.
- Never modify `lib/` from a coverage subagent unless a genuine bug is found —
  report it instead. Adding an intentional `ValueKey` for e2e anchoring is the
  one allowed lib/ change, and only in the e2e workstream.
- After tapping SEND in e2e flows: never `pumpAndSettle` — use
  `waitForStatus($, code)` / `.waitUntilVisible()`.
- Verification bar (whole session): `fvm flutter analyze`,
  `fvm dart run custom_lint`, getman_lints fixtures self-test,
  `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test tools`,
  `fvm flutter test` all green, plus a full green `run_macos.sh`.

---

## Workstream 1 — unit/widget coverage areas (one subagent each, worktree-isolated)

Uncovered-line ranges below come from `coverage/lcov.filtered.info`
(2026-07-26 run). Each agent: read the target file + its existing tests, write
tests for the uncovered behaviours, run the tests for the areas touched, run
`fvm dart format` on new files, and commit on their worktree branch.

### Task U1: tabs core widgets
- `lib/features/tabs/presentation/screens/request_view.dart` (92: 74-76,81-83,95,99,105,112-121,132-147,168-189,208-296,352-421)
- `lib/features/tabs/presentation/widgets/body_tab_view.dart` (68: 205-272,361-443)
- `lib/features/tabs/presentation/widgets/form_data_editor.dart` (51: 98-141,188-302,353)
- `lib/features/tabs/presentation/bloc/tabs_event.dart` (46: props/ctor coverage)
- `lib/features/tabs/data/repositories/tabs_repository_impl.dart` (19)

### Task U2: response viewers
- `lib/features/tabs/presentation/widgets/response/response_body_view.dart` (65)
- `lib/features/tabs/presentation/widgets/response/viewers/media_response_view.dart` (59)
- `lib/features/tabs/presentation/widgets/response/viewers/pdf_response_view.dart` (30)
- `lib/features/tabs/presentation/widgets/response/viewers/response_media_panel.dart` (19)
- `lib/features/tabs/presentation/widgets/response/response_body_controls.dart` (24)
- `lib/features/tabs/presentation/widgets/response/json_tree_view.dart` (28) + `json_tree_filter.dart` (18)

### Task U3: tabs chrome
- `lib/features/tabs/presentation/widgets/url_bar.dart` (61: 163-170,229-267,300-302,437-446,465-466,534-572,612-616,694-696)
- `lib/features/home/presentation/widgets/request_tab_chip.dart` (70)
- `lib/features/tabs/presentation/widgets/tab_switcher_sheet.dart` (33)
- `lib/features/tabs/presentation/widgets/panel_selector.dart` (28)
- `lib/features/home/presentation/widgets/tab_widget.dart` (gaps)

### Task U4: collections dialogs
- `lib/features/collections/presentation/widgets/export_api_docs_dialog.dart` (50, 23.1%)
- `lib/features/collections/presentation/widgets/spec_import_dialog.dart` (46) + `spec_import_preview.dart` (28)
- `lib/features/collections/presentation/widgets/review_changes_dialog.dart` (36)
- `lib/features/collections/presentation/widgets/pull_requests_dialog.dart` (30)
- `lib/features/collections/presentation/widgets/branch_chip.dart` (28)
- `lib/features/collections/presentation/widgets/workspace_settings_tile.dart` (43, 52.2%)

### Task U5: collections tree + events
- `lib/features/collections/presentation/widgets/collection_node_menu.dart` (43, 65%)
- `lib/features/collections/presentation/widgets/collections_list.dart` (34)
- `lib/features/collections/presentation/widgets/collection_node_row.dart` (32)
- `lib/features/collections/presentation/widgets/node_action_sheet.dart` (30)
- `lib/features/collections/presentation/bloc/collections_event.dart` (37) + `review_event.dart` (16)
- `lib/features/collections/presentation/bloc/collections_bloc.dart` (16)

### Task U6: settings + environments
- `lib/features/settings/presentation/bloc/settings_event.dart` (66, 12%)
- `lib/features/settings/presentation/widgets/client_certificate_tile.dart` (33)
- `lib/features/settings/presentation/widgets/settings_dialog.dart` (31)
- `lib/features/settings/presentation/widgets/git_identity_settings_tile.dart` (16)
- `lib/features/environments/presentation/widgets/environments_dialog.dart` (44)

### Task U7: core/utils (pure Dart — cheapest wins)
- `lib/core/utils/code_gen_service.dart` (60)
- `lib/core/utils/json_file_io.dart` (41, 21.2%)
- `lib/core/utils/openapi/normalized_api.dart` (26) + `openapi_v3_normalizer.dart` (25) + `collection_builder.dart` (16)
- `lib/core/utils/apidoc/api_doc.dart` (23) + `yaml_emitter.dart` (22) + `openapi_serializer.dart` (16)
- `lib/core/utils/workspace/workspace_bookmark.dart` (17) + `workspace_picker.dart` (0/6)

### Task U8: core misc
- `lib/core/error/exceptions.dart` + `failures.dart` (10)
- `lib/core/ui/widgets/responsive_dialog.dart` (33, 52.9%)
- `lib/core/ui/widgets/variable_hover_popover.dart` (22) + `key_value_list_editor.dart` (17)
- `lib/core/git/gh_service_io.dart` (23, 28.1%) + `git_service_io.dart` (18)
- `lib/core/di/injection_container.dart` (42)
- `lib/core/network/http_methods.dart`, `lib/core/storage/hive_boxes.dart` (1-liners)

### Task U9: feature panels misc
- `lib/features/mcp/presentation/widgets/mcp_panel.dart` (39)
- `lib/features/realtime/presentation/widgets/realtime_panel.dart` (19) + `realtime_event.dart`
- `lib/features/chaining/presentation/widgets/rules_tab_view.dart` (31) + `assertion_rule_row.dart` (23) + `rules_event.dart`
- `lib/features/history/presentation/bloc/history_event.dart` + `history_usecases.dart`

### Task U10 (exploratory): MainScreen harness
- `lib/features/home/presentation/screens/main_screen.dart` (286, 0.3%).
- Attempt a full-DI widget-test boot: `di.init(storageDirectoryOverride: tempDir)`
  + MultiBlocProvider mirroring `main.dart`, pump `MainScreen`, avoid
  `pumpAndSettle` (ambient tickers never settle — use bounded `pump`s).
- The header of `main_screen_actions_test.dart` documents why this was skipped
  before; if it genuinely can't work, stop and report why rather than forcing it.

## Workstream 2 — integration suite repair (main tree)

- [ ] Baseline `bash integration_test/run_macos.sh` (running).
- [ ] For each failing flow: systematic-debugging — decide UI-drift vs real
  regression; fix test or code accordingly; re-run that flow.
- [ ] Re-run full aggregator until green.

## Workstream 3 — new e2e flows (main tree, after repair)

New flows per uncovered recent features (anchors from the feature-surface
exploration report):
- [ ] D1 open-tabs dropdown (tab strip)
- [ ] D2 tree search-by-method + collapse-all
- [ ] D3 history management: day headers, hover delete + UNDO, clear-all + confirm, empty state
- [ ] E1 Cmd+/ shortcuts cheat-sheet dialog (incl. escaping re_editor)
- [ ] E3 unresolved-variable warning chip (appears/disappears with env)
- [ ] PR #62: tab-strip double-click new tab; tree right-click context menu; URL Enter-to-send
- [ ] A1: saved-example delete UNDO snackbar
- [ ] Register all in `all_flows_test.dart`; run full suite green.

## Final gate

- [ ] Merge all worktree branches into the session branch; resolve conflicts.
- [ ] `bash tool/coverage.sh` — record new overall % (target: meaningful jump from 86.61%).
- [ ] All six verification commands green + full e2e green.
- [ ] Update `integration_test/BACKLOG.md` + `docs/BACKLOG.md` if affected.
