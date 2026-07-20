# Claude-Friendly Codebase Refactor — Design

**Date:** 2026-07-17
**Status:** Approved by user (with §7 addition)
**Goal:** Make the Getman codebase maximally navigable for Claude (and any reader) with the
minimum context load: any concept findable in one search, any file understandable from its
first lines, deep documentation loaded only when the task needs it.

## Motivation

The codebase (385 hand-written Dart files, ~56k lines) was written entirely by Claude across
many sessions. Today, finding "where X lives" relies on a ~9,000-word CLAUDE.md loaded into
every session regardless of relevance, plus greps that depend on lucky naming. This refactor
builds a layered navigation system and slims the always-loaded context.

## Design

### §1 — `docs/CODEMAP.md`: the master index

One file answering "where is X?" in three parts:

1. **Directory map** — every directory under `lib/` with a one-line purpose and its key files.
2. **Concept lookup table** — alphabetical concept → file(s). Examples: "redirect handling →
   `core/network/network_service.dart`", "dirty tracking → `tab_dirty_checker.dart`",
   "variable highlighting → `core/ui/widgets/variable_highlight_controller.dart`".
   Target ~60–80 entries covering everything a task prompt might name.
3. **Cross-cutting flows** — ordered file chains for the multi-file flows no layout can
   express (~9): send-request pipeline, cookie round-trip, env-var resolution, dirty
   tracking, theme resolution + component slots, panel/tab lifecycle, chaining rules run +
   write-back, Postman import/export, auto-update. Each flow is a numbered list of
   `file — role in this step`.

**Self-defense:** `test/docs/codemap_coverage_test.dart` reads CODEMAP.md and asserts every
directory under `lib/` (excluding generated-only dirs) is mentioned. New features cannot
silently escape the map.

### §2 — CLAUDE.md slims down; deep-dives move next to the code

CLAUDE.md keeps only what applies to every session:

- Project one-liner + compressed tech-stack table.
- Mandatory architectural rules and the verification bar (§5/§7 today, tightened wording).
- A short gotchas list (only truly global gotchas — see migration rule below).
- A **read-before-editing routing table**: "touching themes? → `docs/architecture/theming.md`",
  "touching Hive models? → `docs/architecture/persistence-hive.md`", etc.

Deep-dive content (today's §3 Hive ledger and §4 feature deep-dives) relocates to
`docs/architecture/`:

| Doc | Absorbs |
|---|---|
| `tabs-and-panels.md` | §4.2 tabs deep-dive, panels architecture, response time-travel |
| `collections.md` | §4.3 collections, saved examples, workspace git mirror |
| `theming.md` | §4.8 theming, AppComponents slots, pointer to THEME_AUTHORING.md |
| `network-and-cookies.md` | NetworkService redirects/mTLS/proxy, cookie jar, realtime (WS/SSE) |
| `persistence-hive.md` | §3 typeId ledger, field-by-field SettingsModel map, §4.9 write timing |
| `environments-and-chaining.md` | §4.10 environments, dynamic vars, chaining engines |
| `settings-history-updates.md` | §4.5 settings, §4.4 history, updates feature, §4.6 dirty tracking, §4.7 error model |

Nothing is deleted — only relocated to load-on-demand. Target: CLAUDE.md at roughly a third
of its current size.

**Gotcha migration rule (highest-leverage move):** a gotcha that is about ONE file moves into
that file's header (e.g. the `_setControllerPreservingEnd` warning lives atop `url_bar.dart`).
A gotcha spanning files moves to the relevant architecture doc. Only gotchas about *how to
work in this repo at all* (imports, lint stack, Hive regen, identity-based events) stay in
CLAUDE.md.

### §3 — File headers: depth-tiered, plain English

Top-of-file `//` comment block — **not** `///` (avoids the `dangling_library_doc_comments`
lint interplay; greps identically):

- **Tier 1** (simple widgets, entities, small utils): one sentence — what this file is.
- **Tier 2** (services, complex widgets, mappers, data sources): purpose + key collaborators
  + where it's wired in (DI registration, parent widget, etc.).
- **Tier 3** (blocs, engines, cross-cutting services): tier 2 + file-local invariants and
  gotchas migrated from CLAUDE.md per the migration rule.

Coverage: all 385 non-generated `lib/**.dart` files (conditional-export stubs and other
trivial files get a one-liner). Test files: opportunistic only.

Headers are prose, not a tag grammar. They should front-load searchable words: the concept
names a task prompt would use ("redirect", "dirty", "debounce", "drag-and-drop"), so a grep
for the concept hits the owning file's header even when the code uses a different local name.

### §4 — Structural changes (evidence-based; audit 2026-07-17)

An audit of the 14 largest files found only the following genuine issues. Everything else is
cohesive-but-long and is **deliberately left alone** (do not re-litigate):

1. **Split `features/tabs/presentation/widgets/request_editor_tabs.dart` (685 lines)** →
   `params_tab_view.dart`, `headers_tab_view.dart`, `body_tab_view.dart` (the whole
   body-editor family — `_BodyTypeSelector`, `_RawBodyEditor`, `_GraphqlBodyEditor`,
   `_BinaryBodyPicker`, etc. — moves with `BodyTabView`). The shared `_BulkModeToggle`
   (used by params + headers) is promoted to `bulk_mode_toggle.dart` in the same directory.
   Consumers to re-import: `request_config_section.dart`, `unified_request_panel.dart`
   (+ any tests importing the old path). The old file is deleted, not kept as a barrel.
2. **Extract the shortcuts cheat-sheet tab** from
   `features/settings/presentation/widgets/settings_dialog.dart` (898 lines) →
   `settings_shortcuts_tab.dart` as a `StatelessWidget`, taking `_KeyCombo` + `_KeyCap`
   with it. The other four tabs share controllers/state and stay together.
3. **Rename `features/home/presentation/widgets/tab_widget.dart` → `request_tab_chip.dart`**
   and class `TabWidget` → `RequestTabChip`. It renders a single tab chip; the tab *strip*
   lives in `main_screen.dart#_buildTabBar`. The current name misleads searchers.

Confirmed cohesive, left alone: `tabs_bloc.dart`, `curl_utils.dart` (parser only; generate()
delegates to CodeGenService), `panel_selector.dart`, `main_screen.dart`,
`postman_collection_mapper.dart` (bidirectional mapper, conventional), `code_gen_service.dart`
(6 emitters share `_Effective` + helpers), `conflict_resolution_dialog.dart`, `url_bar.dart`,
`response_body_view.dart`, `tab_switcher_sheet.dart`, `collections_list.dart`.

CLAUDE.md / architecture docs are updated wherever they reference the old paths/names.

### §5 — Enforcement

- New `getman_lints` rule **`file_header_required`**: every `lib/**.dart` file (excluding
  `*.g.dart`) must open with a `//` comment line before any directive. Ships with an
  `// expect_lint:` fixture in `tools/getman_lints/example/lib/` per the project mandate.
- New CLAUDE.md workflow mandate: adding or moving a file requires a header (lint-enforced)
  and a CODEMAP entry for new directories/concepts (coverage-test-enforced for directories).

### §6 — Delivery & verification

- Branch: `claude-friendly-refactor` off `master` (independent of open PR #56; headers are
  additive so conflict risk is low — rebase if #56 merges first).
- Headers written in parallel subagent waves, feature-by-feature, each wave verified.
- Full verification bar before done: `fvm flutter analyze`, `fvm dart run custom_lint`,
  fixtures self-test, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format`,
  `fvm flutter test`.
- No wiki changes (internal-only refactor; no user-visible behavior change).
- PR to `master` at the end.

### §7 — Standing "design for Claude" mandate (user addition)

CLAUDE.md gains a permanent workflow mandate, roughly:

> **Design for Claude.** This codebase is written and maintained by Claude. When designing
> new code: (a) name files and symbols with the words a task prompt would use — grep-ability
> is a design constraint; (b) give every new file a header per the tier rules; (c) keep
> CLAUDE.md lean — new deep-dive documentation goes in `docs/architecture/` (linked from the
> routing table), never inline in CLAUDE.md; (d) file-specific knowledge goes in file
> headers, cross-file knowledge in architecture docs, universal rules in CLAUDE.md.

## Success criteria

1. Any concept from a plausible task prompt is findable via CODEMAP.md or a single grep
   whose first hit is the owning file.
2. CLAUDE.md ≈ one-third current size; every removed section reachable via the routing table.
3. Every non-generated `lib/` file opens with a header; lint enforces it; fixtures test the lint.
4. All structural changes behavior-preserving; full verification bar green.
5. The system defends itself: header lint + CODEMAP coverage test + §7 mandate.

## Out of scope

- Splitting cohesive-but-long files (see §4 leave-alone list).
- Directory reorganization / per-feature barrels (Approach C, rejected).
- Test-file headers as a requirement.
- Wiki changes.
