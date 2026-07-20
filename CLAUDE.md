# Getman — Project Documentation & Mandates

Getman is a high-performance, aesthetically pleasing HTTP client built with
Flutter, featuring a Neo-Brutalist design. Tabbed request UI, collections tree
with drag-and-drop, request history, git-native collaboration, local-only
persistence.

This CLAUDE.md is the **lean core** — mandates + a routing table, nothing more.
Deep-dive knowledge lives in `docs/architecture/*.md` (one per area) and in each
file's own `//` header. Keep it that way (see **Design for Claude** below).

## Tech stack

Flutter SDK is pinned via `.fvmrc` — **always invoke as `fvm flutter …` / `fvm
dart …`, never plain `flutter`/`dart`.** State uses `flutter_bloc` with strict
UI/business-logic separation; every state/event is `Equatable`.

| Package | Role | Load-bearing note |
|---|---|---|
| `flutter_bloc` | State management | Strict UI/logic split; `Equatable` everywhere |
| `get_it` | DI | Only in `lib/core/di/` + `main.dart` — never widgets |
| `hive_ce` / `hive_ce_flutter` | Persistence | Community Hive fork (analyzer 7+); adapters via `hive_ce_generator` |
| `dio` | Networking | Cancel tokens wrapped by `NetworkCancelHandle` |
| `go_router` | Routing | Single route today (`AppRouter`) |
| `re_editor` / `re_highlight` | Code editor | Controller is `CodeLineEditingController`, **not** `TextEditingController` |
| `two_dimensional_scrollables` | Collections tree | `TreeView`; manual id-keyed expansion (H2 fix) |
| `web_socket_channel` | Realtime | WebSocket; SSE rides `dio` streams via `SseParser` |
| `file_picker` | File I/O | Import/export, binary & multipart bodies |
| `google_fonts` | Typography | Lexend base, JetBrainsMono in editors |
| `uuid` | IDs | Entities generate their own IDs when not given |
| `collection` | Reactive helpers | `MapEquality`, `ListEquality`, `firstWhereOrNull` |
| `shimmer` | Loading UI | Response-pending skeleton |
| `updat` + `package_info_plus` + `path_provider` + `provider` | Auto-update | Web-safe behind the `*_io.dart` gate |

## Navigation

**Finding anything: start at [`docs/CODEMAP.md`](docs/CODEMAP.md)** — the master
"where is X?" index (directory map + concept lookup + cross-cutting flows). Every
`lib/` file also opens with a `//` header; read it for file-level detail.

**Read-before-editing routing table** — before touching an area, read its doc:

| Touching… | Read first |
|---|---|
| Boot, DI, shortcuts, error model | [docs/architecture/app-shell.md](docs/architecture/app-shell.md) |
| Tabs, panels, sending, responses | [docs/architecture/tabs-and-panels.md](docs/architecture/tabs-and-panels.md) |
| Collections tree, examples, workspace mirror | [docs/architecture/collections.md](docs/architecture/collections.md) |
| Themes, AppComponents, motion | [docs/architecture/theming.md](docs/architecture/theming.md) (+ [docs/THEME_AUTHORING.md](docs/THEME_AUTHORING.md) to author) |
| NetworkService, redirects, cookies, WS/SSE | [docs/architecture/network-and-cookies.md](docs/architecture/network-and-cookies.md) |
| Any `@HiveType` / box / typeId | [docs/architecture/persistence-hive.md](docs/architecture/persistence-hive.md) |
| Environments, variables, chaining | [docs/architecture/environments-and-chaining.md](docs/architecture/environments-and-chaining.md) |
| Settings, history, auto-update | [docs/architecture/settings-history-updates.md](docs/architecture/settings-history-updates.md) |
| Git sync/branches/PRs/conflicts | [docs/architecture/git-sync.md](docs/architecture/git-sync.md) |
| MCP feature | [docs/architecture/mcp.md](docs/architecture/mcp.md) |
| Open work / backlog | [docs/BACKLOG.md](docs/BACKLOG.md) |

The user-facing feature wiki is <https://github.com/thiagomiranda3/Getman/wiki>
(separate `Getman.wiki.git` repo) — keep it in sync (see mandates).

## Project structure (feature-first + clean architecture)

```
lib/
  core/            # Cross-feature: di, domain/entities, error, git, navigation,
                   # network, storage, theme, ui/widgets, utils
  features/<feature>/
    domain/        # Entities + abstract repositories + use cases (pure Dart)
    data/          # Hive models (DTOs) + data sources + repository impls
    presentation/  # BLoC (event/state/bloc) + widgets + screens
  main.dart        # Boot, global Shortcuts map, MultiBlocProvider, MaterialApp.router
```

Features: `tabs`, `collections`, `history`, `settings`, `home`, `environments`,
`chaining`, `cookies`, `realtime`, `mcp`, `command_palette`, `updates`.
**Git-native collaboration** (review/commit, branch/sync, PRs, conflict
resolution) is built into `collections` (`collections/data/services/` +
`collections/domain/`) over the `lib/core/git/` CLI gateways — see git-sync.md.
`realtime_service.dart` and `mcp_service.dart` both live in `lib/core/network/`.
Cross-cutting (no own feature dir): auth (`auth_config.dart`), code generation
(`code_gen_service.dart`), body types (`body_type.dart`), and the git-friendly
workspace mirror (`workspace_sync_service.dart`). Find any of these in CODEMAP.

## Mandatory rules

**Architecture**
- **Domain layer is pure Dart** (+ `equatable`): zero imports from `data/`,
  Flutter, `dart:ui`/`dart:io`, `dio`, or `hive_ce`. New features start
  domain-first (entity + abstract repository + use case) before any `data/` or
  widgets.
- **BLoCs depend on abstract `Repository` types** — never `...Impl` or Hive/Dio.
- **DI stays in DI**: widgets reach services via `BlocProvider`,
  `RepositoryProvider`, or constructor injection — never `sl<T>()` from a widget.
- **Immutability**: `Equatable` on every state/event, `copyWith` on every entity.
- **Layering**: shared entities used by >1 feature → `lib/core/domain/entities/`;
  feature-owned entities stay in that feature. Reusable atoms →
  `lib/core/ui/widgets/`; feature-specific widgets stay in the feature.

**UI / styling**
- **Theme adherence**: never hardcode sizes, colors, radii, weights, or paddings.
  Read them through `context.appLayout` / `.appPalette` / `.appShape` /
  `.appTypography` / `.appDecoration` / `.appComponents`. If a value isn't in an
  extension, add a field to that extension. Details → theming.md.

**Conventions**
- **`package:getman/…` imports everywhere** — no relative imports (enforced by
  `always_use_package_imports` + `directives_ordering`).
- **Identity-based events**: BLoC events carry a stable `tabId`/`id`, not an
  `int index`; look items up with `firstWhereOrNull`, never index across
  emissions. Index is used only where position *is* the operation.
- **Logging**: `print` is banned. BLoCs use `dart:developer`'s
  `log(msg, name: '<BlocName>')` — never `debugPrint` (a `flutter/foundation`
  import trips `bloc_lint`). Non-bloc layers use `debugPrint`. (`tabs_bloc.dart`
  keeps one justified foundation import for `compute`.)
- **Surgical edits**: one concern per change; don't restructure unrelated code.
- **Keep the wiki in sync**: any change to how a feature is *used* — new feature,
  new/renamed/removed setting, changed shortcut, new body/auth/code-gen type,
  renamed UI label, changed default/limit — updates the GitHub wiki as part of
  the same work. Clone `https://github.com/thiagomiranda3/Getman.wiki.git`, edit
  the feature's `*.md` page (nav in `_Sidebar.md`), commit + push (branch
  `master`). Use verbatim UI labels. Pure internal refactors need no wiki edit.

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

## Hive quick-rules

- **Never renumber an existing `typeId`.** Add new models with a fresh ID —
  **next free: 13** (highest in use is 12, `PanelModel`).
- **Retired `SettingsModel` fields — never reuse these indices:** `HiveField(22)`
  (`reduceVisualEffects`) and `HiveField(27)` (`enableThemeSounds`).
- After any `@HiveType`/`@HiveField` change, regenerate:
  `dart run build_runner build --delete-conflicting-outputs`.
- The full typeId ledger, every `SettingsModel` field, and per-feature write
  timing are in [persistence-hive.md](docs/architecture/persistence-hive.md).

## Build & verification bar

```
fvm flutter analyze                                           # very_good_analysis — 0 issues
fvm dart run custom_lint                                      # getman_lints (7 rules) + solid_lints metrics
( cd tools/getman_lints/example && fvm dart run custom_lint ) # getman_lints fixtures self-test
fvm dart run bloc_tools:bloc lint lib                         # bloc_lint
fvm dart format lib test tools                                # formatter
fvm flutter test                                              # all tests green
dart run build_runner build --delete-conflicting-outputs      # after any @HiveType change
fvm flutter run -d macos                                      # desktop run
bash tool/coverage.sh                                         # coverage report
```

Work is **not done** until **all four independent static-analysis passes** report
zero issues — `fvm flutter analyze` (very_good_analysis, incl. `close_sinks` +
`discarded_futures`), `fvm dart run custom_lint` (the seven getman_lints
architecture rules + three `solid_lints` metric gates), the `getman_lints`
fixtures self-test, and `fvm dart run bloc_tools:bloc lint lib` — **and** the tree
is `dart format`-clean **and** `fvm flutter test` is 100% green. These are
separate processes; a clean `flutter analyze` does **not** imply the others are
clean. The `.githooks/pre-commit` hook runs the first five automatically (enable
once per clone: `git config core.hooksPath .githooks`). CI adds OSV-Scanner +
Dependabot (supply-chain, not local).

The seven `tools/getman_lints/` rules: `avoid_get_it_in_widgets`,
`avoid_hardcoded_brand_colors`, `domain_no_infrastructure_imports`,
`bloc_depends_on_abstractions`, `platform_io_outside_io_files`,
`equatable_props_complete`, `file_header_required` (every hand-written `lib/`
file must open with a `//` header). **Adding a rule takes two steps, not one:**
register it in the plugin **and** add its name to the `custom_lint.rules`
allowlist in `analysis_options.yaml` (custom_lint runs opt-in,
`enable_all_lint_rules: false`) — plus ship a `// expect_lint:` fixture in
`tools/getman_lints/example/lib/` (the fixtures self-test, which covers all seven
including `file_header_required`, is part of the gate). Suppress a justified
exception with a per-line `// ignore: <rule>` + a one-line reason.

The three `solid_lints` metrics are permissive regression-gate baselines, not
style targets — `cyclomatic_complexity: 50`, `number_of_parameters: 50`,
`function_lines_of_code: 1000` (configured with full rationale in
`analysis_options.yaml`) — they block new runaway additions, not pre-existing
complexity.

## Global gotchas

Only repo-wide ones live here; area-specific gotchas are in the architecture docs,
file-specific ones in each file's `//` header.

- **`listenWhen` / `buildWhen` are not optional.** Narrow selectors are how the
  editor stays responsive — a bare `BlocBuilder` rebuilds on every emission.
- **HTTP method list is `HttpMethods.all`** (`core/network/http_methods.dart`) —
  never hardcode `['GET','POST',…]`.
- **Controller types don't mix**: `KeyValueListEditor` uses
  `TextEditingController`; body/response editors use re_editor's
  `CodeLineEditingController`.
- **Hive regen is not optional** after any `@HiveType`/`@HiveField` change.
- **Shared chrome atoms, always**: snackbars → `showAppSnackBar(context, …)`
  (never inline `SnackBar`s); irreversible actions confirm via
  `ConfirmDialog.show(…)`; single-line text prompts → `NamePromptDialog.show(…)`.
