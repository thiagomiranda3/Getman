# Static-Analysis Hardening — Design

- **Date:** 2026-06-26
- **Status:** Approved (brainstorming) → ready for implementation plan
- **Scope owner:** static-analysis stack (CLAUDE.md §5, §7)

## 1. Motivation

Getman already gates four independent static-analysis passes (`very_good_analysis`
via `flutter analyze`, project-local `custom_lint` in `tools/getman_lints/`,
`bloc_lint`, and `dart format`) through both the `.githooks/pre-commit` hook and
CI (`.github/workflows/ci.yml`). The baseline is strong — VGA already enables the
analyzer strict language modes (`strict-casts`/`strict-inference`/`strict-raw-types`).

What it does **not** yet catch:

1. The project's documented architecture mandates (CLAUDE.md §2/§7) are honor-system —
   only two of them are machine-enforced (`avoid_get_it_in_widgets`,
   `avoid_hardcoded_brand_colors`).
2. A silent class of bug: `Equatable` subclasses whose `props` omit a field
   (states compare equal → UI fails to rebuild).
3. Code-complexity outliers (no cyclomatic-complexity / parameter-count / function-length budget).
4. Dead code and unused files (the analyzer only finds unused *private* members and imports).
5. Dependency vulnerabilities and stale dependencies (no supply-chain tooling at all).
6. Two cheap lint gaps: VGA pins `close_sinks` to `ignore` (no undisposed-sink
   detection), and `discarded_futures` (the non-async companion to the
   already-enabled `unawaited_futures`) is off.

This effort closes those gaps. The user chose **hard-gate everything now**: every
new check must fail CI, and the codebase must be made clean against each as part of
this work (not warn-first).

## 2. Locked decisions

- **Tooling split:** metrics via **`solid_lints`** (runs inside the existing
  `dart run custom_lint` pass — no new CI infra, free OSS, cherry-picked rules);
  **DCM** (standalone CLI, free tier, MIT as of 2026-07-16) added *only* for
  unused-code / unused-files, which `solid_lints` cannot do.
- **Rollout:** hard-gate everything now; fix all surfaced violations in-scope.
- **Equatable rule:** hand-written in `getman_lints` (consistent with the
  architecture-rules package the project owns), not DCM's `list_all_equatable_fields`.
- **Feature isolation: dropped.** Cross-feature imports are pervasive and
  deliberate here (`home` is the shell wiring every feature; `command_palette`
  reads every bloc by design; `tabs` composes collections/chaining/realtime/mcp/
  history at the presentation layer). The only defensible narrow form —
  "no cross-feature `data/` imports" — hits exactly 5 sites, all the shared
  `HttpRequestConfig` Hive model (typeId 1, documented "shared between history and
  collection nodes"); relocating it is a load-bearing typeId migration, out of
  scope. The real layering invariant is already covered by rules A1/A2 below.

## 3. Pre-measured violation surface (baseline, 2026-06-26)

| Check | Current violations | Notes |
|---|---|---|
| A1 domain boundary | **0** | hard-gate immediately |
| A2 bloc abstraction | **0** | 8 bloc/cubit files, all clean |
| A3 platform-safety | **0** | all 9 `dart:io`/`path_provider`/`updat`/`package_info_plus` sites are `*_io.dart` |
| B Equatable props | TBD | 49 files use `equatable`; expect a small handful of intentional exclusions to `// ignore` |
| D metrics | TBD | thresholds calibrated against measured distribution before gating |
| E unused code/files | TBD | will surface real dead code (e.g. the unwired `AppDropdown<T>` noted in CLAUDE.md §4.8) |
| G `close_sinks` | **0** | measured 2026-06-26 with `close_sinks: warning` override |
| G `discarded_futures` | **0** | measured 2026-06-26 with `discarded_futures: true` |

## 4. Components

### A. Architecture custom_lint rules (`tools/getman_lints/`)

Three new `DartLintRule`s, WARNING severity (matching the two existing rules;
`custom_lint` fails the pass on any finding regardless of severity). Each rule
normalizes paths via the existing `_posix` helper and skips non-`/lib/` files.

- **A1 `domain_no_infrastructure_imports`** — a file whose path contains `/domain/`
  may not import: `package:flutter/*`, `dart:io`, `dart:ui`, `package:dio/*`,
  `package:hive*`, or any `package:getman/…/data/…`. Encodes "domain = pure Dart +
  equatable" (CLAUDE.md §2).
- **A2 `bloc_depends_on_abstractions`** — a file named `*_bloc.dart` or
  `*_cubit.dart` may not import any `package:getman/…/data/…`, `package:dio/*`, or
  `package:hive*`. Encodes "BLoCs depend on abstract Repository types, never
  `…Impl`/Hive/Dio directly" (CLAUDE.md §2/§7). Detection is by import-directory /
  package, not by an `Impl` name heuristic (more robust).
- **A3 `platform_io_outside_io_files`** — `dart:io`, `package:updat/*`,
  `package:path_provider/*`, `package:package_info_plus/*` may only be imported
  from files whose name ends in `_io.dart` (the project's conditional-import
  native-side convention). Protects web builds (CLAUDE.md §1 web-safety note).

Implementation note: A1/A2/A3 inspect import directives (`addImportDirective` /
the resolved `LibraryImport` URI), unlike the existing rules which inspect
identifiers — but the same `custom_lint` plugin surface.

Each rule ships a `*_test.dart` under `tools/getman_lints/test/` using the
`custom_lint` test harness (lint-expectation comments), written test-first (TDD).

### B. Equatable props completeness (`tools/getman_lints/`)

- **`equatable_props_complete`** — for a class that extends `Equatable` or mixes
  `EquatableMixin`, every declared instance field must appear in the `props`
  getter's returned list. Flags omitted fields.
  - Handles `...super.props` spreads (a superclass contributing its own props).
  - Considers only stored instance fields (not static fields, not computed getters).
  - Intentional exclusions use `// ignore: equatable_props_complete` + a one-line
    reason (same convention as the other rules; e.g. a field deliberately outside
    equality).
  - Ships `equatable_props_complete_test.dart` (positive + negative + spread cases),
    written test-first.

### D. Metrics thresholds via `solid_lints`

- Add `solid_lints` as a dev_dependency.
- Enable **exactly three** rules, all pure metrics with no VGA overlap:
  - `cyclomatic_complexity` (start: `max_complexity: 20`)
  - `number_of_parameters` (start: `max_parameters: 8`)
  - `function_lines_of_code` (start: `max_lines: 100`)
- **Explicitly not enabled:** `member_ordering`, `avoid_late_keyword`,
  `prefer_match_file_name`, `avoid_returning_widgets`, and the rest — noisy and/or
  overlapping with VGA.
- Mechanism: `solid_lints` rules run through the existing `custom_lint` plugin, so
  no new CI step. Implementation must verify (via `dart run custom_lint`) that
  **only** the three intended `solid_lints` rules plus the four `getman_lints`
  rules are active — i.e. `solid_lints`' other rules are not silently enabled.
  Use whichever `custom_lint` config form achieves that (opt-in
  `enable_all_lint_rules: false` listing every desired rule, or per-rule disable);
  decide during implementation by inspecting the actual `custom_lint` output.
- **Hard-gate calibration:** measure the current distribution first, set each
  threshold to catch genuine outliers, then fix every violation above the line
  (refactor, or `// ignore` a justified one-off with a reason). Final numbers
  replace the starting points above.

### E. Unused code / files via DCM (standalone CLI)

- Two CI checks: `dcm check-unused-code lib` and `dcm check-unused-files lib`.
- DCM runs as an external binary (bundles its own analyzer → does **not** interact
  with the project's analyzer pin / pub deps). Free tier covers both commands.
- CI: install DCM (official action / install script), activate with a free license
  key stored as a repo secret, run both checks as gating steps.
- Hard-gate cleanup: delete genuinely-dead code surfaced (e.g. unwired
  `AppDropdown<T>`); for anything intentionally retained-but-unreferenced, suppress
  with DCM's documented ignore mechanism + a reason.
- Local: add to the pre-commit hook **only if** DCM is installed (guard like the
  hook's existing `command -v fvm` check), so contributors without DCM aren't
  blocked locally; CI is the authoritative gate.
- **External dependency:** the user adds the `DCM_CI_KEY` (or equivalent) repo
  secret; the exact secret name + CLI flags are confirmed during implementation
  against current DCM docs.

### F. Supply-chain

- **OSV-Scanner** — new CI job using `google/osv-scanner-action` (or its reusable
  workflow) scanning `pubspec.lock` against the OSV database. No code changes;
  independent of the other gates. Runs on PR + push to master.
- **Dependabot** — new `.github/dependabot.yml` watching two ecosystems:
  - `pub` (app dependencies)
  - `github-actions` (the pinned actions in the workflows)
  - Weekly schedule, grouped updates to limit PR noise.

### G. Config-only leak / async lints (`analysis_options.yaml`)

Two VGA-baseline tweaks, both already clean (0 violations, measured 2026-06-26 →
hard-gate is free):

- **`close_sinks`** — VGA enables the rule but pins it to `ignore` in its `errors:`
  block. Re-promote it in the project's own `analyzer.errors:` block
  (`close_sinks: warning`) to catch undisposed `StreamController`/`Sink`s
  (relevant to `RealtimeService` and stream-owning blocs). Known to be
  false-positive-prone on ownership transfer; any false positive gets a per-line
  `// ignore: close_sinks` + reason.
- **`discarded_futures`** — not in VGA. Add `discarded_futures: true` to
  `linter.rules`. Companion to the already-enabled `unawaited_futures`: flags
  fire-and-forget futures in *non*-async contexts (constructors, `void` callbacks).
  Intentional fire-and-forget sites use `unawaited(...)` or `// ignore`.

Both ride the existing `flutter analyze` pass — no new CI step or hook line.

## 5. Wiring & process changes

- **`.githooks/pre-commit`** — `solid_lints` rides the existing `custom_lint` step
  (no new line). Add a guarded DCM step (skip if `dcm` not on PATH). OSV stays
  CI-only (needs network/DB).
- **`.github/workflows/ci.yml`** — add a DCM job and an OSV-Scanner job to the
  existing run-every-gate-then-fail matrix, and extend the PR summary comment
  (`ci.yml` "Build summary comment" + `ci-comment.yml`) to report the two new rows.
- **CLAUDE.md** — update §5 (verification bar: list the new gates) and §7
  (Development Mandates: document the new architecture rules + the metrics budget +
  DCM). In-repo docs only — no wiki change (these are contributor-facing, not
  end-user-facing).
- **Testing** — TDD per custom rule (failing lint test first), per the project's
  `test-driven-development` discipline. Full done-bar after every change:
  `flutter analyze`, `dart run custom_lint`, `bloc lint`, `dart format`,
  `flutter test` all green.

## 6. Implementation order (suggested)

1. **A1/A2/A3** (custom rules, already-clean) — TDD each, wire into the existing
   `getman_lints` plugin entry point. Lowest risk; immediate gate. Land **G**
   (the two `analysis_options.yaml` lint tweaks, also already-clean) alongside.
2. **B** (`equatable_props_complete`) — TDD; then run against `lib/`, fix/ignore the
   surfaced handful.
3. **D** (`solid_lints` metrics) — add dep, configure the 3 rules, verify only
   those are active, measure distribution, set thresholds, fix violations.
4. **E** (DCM) — add CI job + guarded hook step; run, clean up dead code; user adds
   the secret.
5. **F** (OSV-Scanner + Dependabot) — independent; can land any time.
6. **Wiring + CLAUDE.md** — fold in as each piece lands; final CI/comment update.

## 7. Risks & open items

- **DCM secret + exact CLI/action details** — needs the user to add a repo secret;
  exact names/flags confirmed against current DCM docs at implementation time.
- **`solid_lints` cherry-pick mechanic** — must verify the config actually limits
  active rules to the intended set (no silent enablement). Net is the explicit
  `dart run custom_lint` output check.
- **Equatable rule edge cases** — superclass `props` spreads, deliberate
  exclusions. Mitigated by the `// ignore` convention + thorough tests.
- **Metric thresholds** — set conservatively against measured data so the
  hard-gate cleanup is bounded; tightening later is a separate, optional pass.

## 8. Out of scope (considered, not selected)

- Feature-isolation enforcement (section 2 rationale).
- Relocating `HttpRequestConfig` out of `history/data` (load-bearing typeId migration).
- DCM-provided rules beyond unused-code/files (e.g. its own `list_all_equatable_fields`).

## 9. Success criteria

- All four new `getman_lints` rules implemented + tested; `lib/` clean against them.
- Three `solid_lints` metric rules active (and only those), `lib/` clean.
- `close_sinks` re-promoted + `discarded_futures` enabled; `flutter analyze` clean.
- DCM unused-code/files green in CI; dead code removed.
- OSV-Scanner + Dependabot live in CI/repo.
- Pre-commit hook + CI + CLAUDE.md updated.
- Full done-bar green: `flutter analyze`, `custom_lint`, `bloc lint`,
  `dart format`, `flutter test`.
