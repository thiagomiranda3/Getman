# Getman — Backlog (organized by feature type)

> **How this is organized.** Open work is grouped **by feature type** in the
> "Open backlog" section below. Each item has an ID (stable across reorgs),
> a one-line idea, the **seam** (the real code hook it plugs into), and a rough
> effort (S/M/L). This backlog tracks **open work only** — completed items are
> dropped (git history + `CLAUDE.md` are the record of what shipped). The
> working agreement is at the bottom.

## Current state
- Branch `dev` (pushed to `origin/dev`). `fvm flutter analyze` / `custom_lint` /
  `bloc_lint` all 0 issues; `fvm flutter test` green (**~1263**).
- **M8 GraphQL body type shipped** (merged from `master`, `feat/graphql-body`):
  a `graphql` `BodyType` (wire `'graphql'`, back-compat) with a dual-pane
  QUERY + VARIABLES (JSON) editor; send posts `{query,variables}` as
  `application/json` with `{{var}}` resolved in both panes; invalid variables
  surface a status-0 error response. New `graphqlVariables` field on the request
  config (entity + Hive model typeId 1 `@HiveField(15)`; query reuses `body`).
  Round-trips through code-gen, Postman import/export, and the git workspace
  mirror. Spec + plan under `docs/superpowers/`.

---

# Open backlog (by feature type)

## 🔐 Auth & Security

### H3 — OAuth 2.0 auth flow (with token refresh)
- **Files**: `lib/core/domain/entities/auth_config.dart`,
  `lib/features/tabs/presentation/widgets/auth_tab_view.dart`,
  `lib/features/tabs/data/request_serializer.dart`,
  `lib/core/utils/code_gen_service.dart`.
- **Problem**: `AuthType` is only none/inherit/bearer/basic/apikey. No OAuth2
  anywhere (grep: zero `oauth|grant_type|pkce|refresh_token`).
- **Fix**: Add an `oauth2` `AuthType` + value object (grant type, token/refresh/
  auth URLs, client id/secret, scope, cached token+expiry; persist in the
  existing raw `auth` map → no Hive migration). Add a token-fetch/refresh step in
  the send pipeline (off the UI isolate) before applying the header; AUTH-tab
  fields; code-gen handling. Start with PKCE + client-credentials.
- **Effort**: L. **Verify**: unit-test the token value object + a mocked token
  fetch; widget-test the AUTH fields.

---

## 📦 Request & Body Types

### M9 — Pre-request scripts (no-code)
- **Files**: `lib/features/chaining/…` (post-response only today), send pipeline
  in `tabs_bloc.dart`.
- **Fix**: Prefer a **no-code** pre-request rules pass (set-header-from-variable,
  compute-HMAC, set-timestamp) mirroring `RulesRunInput`, run before dispatch —
  consistent with the existing no-code chaining design (avoid a JS sandbox
  initially).
- **Effort**: L.

---

## 🗂️ Collections & Runner

### H4 — Collection runner (batch-run a folder)
- **Files**: new `lib/features/collections/domain/usecases/run_folder_use_case.dart`;
  `tabs_bloc.dart` send path; `node_action_sheet.dart` (add a Run action).
- **Problem**: No batch orchestration; chaining runs one request at a time. The
  per-request verdict primitive exists (`rules_runner.dart` `runRules` /
  `RulesRunOutput`, called once per send).
- **Fix**: `RunFolderUseCase` walks a `CollectionNodeEntity` subtree, sends each
  leaf sequentially through the existing send + rules pipeline (reuse active-env
  resolution), aggregates pass/fail, emits a run-summary state. Surface a "Run"
  folder action + a results panel.
- **Effort**: L. **Verify**: use-case test over a small tree with a mocked send.

---

## 🧭 UX, Layout & Accessibility

### L13 — Compact-phone (≤500px) can't close a panel  *(tab-panels follow-up)*
- **Files**: `lib/features/tabs/presentation/widgets/tab_switcher_sheet.dart`
  (the panel-chip row / `_PanelChip`);
  `lib/features/tabs/presentation/widgets/panel_close_coordinator.dart`
  (`closePanelWithSavePrompt` already exists + works).
- **Problem**: The tab-panels feature deliberately scoped the compact-phone
  bottom-sheet panel UI to create / switch / rename / move only (spec §8.3) —
  there's no ✕/close affordance, so a phone-width user can't close a panel at
  all. Desktop/tablet close via the `PanelSelector` row ✕.
- **Fix**: Add a close affordance to each panel chip/row in the switcher sheet
  that calls `closePanelWithSavePrompt(context, panelId)` (the sheet's context is
  below `MaterialApp`, so the existing coordinator works). Hide it when only one
  panel remains.
- **Effort**: S. **Verify**: extend `tab_switcher_sheet_test.dart` — close a
  clean panel → `RemovePanel`; affordance absent with one panel.

### L14 — Panel widgets hardcode a few layout sizes/paddings (not in `AppLayout`)  *(tab-panels follow-up)*
- **Files**: `panel_selector.dart` (module-level `_labelMaxWidth=120`,
  `_labelMaxWidthCompact=64`, `_menuWidth=260`, `_menuGap=4`); `tab_widget.dart`
  (`_TabDragFeedback` paddings); `tab_switcher_sheet.dart` (panel-chip paddings).
- **Problem**: CLAUDE.md §6 mandates no hardcoded sizes/paddings in widgets (pull
  from `context.appLayout`). The panels pass left a few literals; not
  `custom_lint`-caught (that rule only covers colors).
- **Fix**: Add fields to `AppLayout` (e.g. `selectorLabelMaxWidth`,
  `panelMenuWidth`, a chip padding) and route these through all theme builders.
- **Effort**: S. **Verify**: analyze clean; rendering unchanged. *Note*: debatable
  whether menu-overlay geometry belongs in the theme extension; consider lifting
  `EnvironmentSelector`'s identical 120 label cap at the same time.

---

## 🪶 Lightweight & Privacy

> **Strategic lens** (brainstorm, 2026-06-20): Getman wins on the things people
> *dislike* about Postman — forced accounts, cloud-captured data, telemetry,
> bloat — not on feature-for-feature parity. These items lean into "fast,
> offline, no-account, yours." See also **🚫 Deferred / Non-goals**.

### LW1 — Encrypted-at-rest secrets (local vault)
- **Idea**: secret env vars are masked on export today but stored **plaintext**
  in Hive (`secretKeys` only flags them). Offer optional encryption of secret
  *values* with a passphrase / OS keychain, so secrets at rest are never
  readable. A strong differentiator — Postman keeps secrets in *its* cloud.
- **Seam**: `EnvironmentModel.secretKeys` (`HiveField(3)`, typeId 4) + a crypto
  layer at the Hive read/write boundary; a passphrase/keychain unlock on launch.
  Send-time resolution must stay unchanged (decrypt → resolve like any var).
- **Effort**: L. **Verify**: secrets round-trip encrypted; wrong passphrase
  fails closed; export still masks.

### LW2 — One-file workspace backup / restore
- **Idea**: export everything (collections + environments + history + settings)
  to a single portable file and re-import on another machine — "your data is
  yours," no cloud. Simpler than the git mirror for casual backup.
- **Seam**: extend `core/utils/json_file_io.dart` +
  `collections/data/services/workspace_sync_service.dart`.
- **Effort**: M.

### LW3 — Git-native sync as a headline feature (your repo, not our cloud)
- **Idea**: promote the existing workspace mirror into a first-class "sync
  across machines via your own git remote," with a setup wizard + basic conflict
  handling. The privacy-respecting answer to Postman cloud sync.
- **Seam**: `workspace_sync_service.dart` (the git-friendly mirror already
  exists); add remote push/pull orchestration + conflict surfacing.
- **Effort**: M–L.

### LW4 — "What Getman stores" data inspector
- **Idea**: a settings panel listing every local Hive box with its size/count
  and a per-category clear button. Builds trust ("nothing leaves this machine")
  and keeps the install lean.
- **Seam**: `core/storage/HiveBoxes` (box-name constants) + a settings section;
  reuse `ConfirmDialog` for clears.
- **Effort**: M.

### LW5 — Cold-start & memory budget guard
- **Idea**: make "lightweight" measurable — a perf smoke test asserting boot
  time stays under a budget so we catch regressions as features land.
- **Seam**: `main.dart` / `di.init()` (already opens boxes in parallel via
  `Future.wait`); add a timing probe + a test.
- **Effort**: S–M.

---

## ✨ Delight & Differentiation

> Make Getman the client people *enjoy* using daily, and good at the things
> Postman does poorly.

### DL2 — Inline JWT / base64 decoder
- **Idea**: detect a JWT or base64 blob in a body/header/auth value and offer a
  decoded view (JWT header/payload/exp; base64 → text).
- **Seam**: response views + a small pure-Dart util in `core/utils`.
- **Effort**: S.

### DL3 — Timing waterfall + response insights
- **Idea**: show as much of the request timeline as `dio` exposes (TTFB via an
  interceptor, total via the existing `durationMs`) plus friendly hints ("no
  cache headers", "slow TTFB"). Postman buries this.
- **Seam**: `core/network/NetworkService` + the response metadata view
  (`ResponseMetadataItem`).
- **Effort**: M.

### DL4 — Command palette → command *system*
- **Idea**: Cmd/Ctrl+K jumps to saved requests/envs/themes today; extend it to
  run *any* app action (new tab, send, switch env, export, …) — keyboard-first
  everything (also a dev-native win).
- **Seam**: `features/command_palette` (reads bloc state, dispatches existing
  events); register an action registry instead of jump-only entries.
- **Effort**: M.

### DL7 — Pinned quick-access request bar
- **Idea**: favorites exist in the tree; add a pinned launch strip for daily-
  driver requests, one tap to open as a tab.
- **Seam**: collections favorites (`toggleFavoriteInTree`) + a strip widget;
  opens via `AddTab`.
- **Effort**: S–M.

---

## ⚙️ Developer Workflow & Integration

> "It fits how I already work." Dev-native interchange + variable ergonomics,
> kept lean. (A headless CI runner was considered and **declined** — see
> **🚫 Deferred / Non-goals**.)

### DW1 — `.http` file import / export (VS Code / JetBrains REST Client)
- **Idea**: import/export the `.http` REST-client format devs already keep in
  their repos — a dev-native interchange standard alongside Postman + OpenAPI.
- **Seam**: a new parser in `core/utils` + the picker/snackbar plumbing in
  `json_file_io.dart`.
- **Effort**: M.

### DW2 — `.env` import + OS-environment vars at send time
- **Idea**: import a `.env` file into an environment; optionally resolve a new
  `{{$env:VAR}}` dynamic var from the shell at send time.
- **Seam**: `core/utils/environment_resolver.dart` (already resolves `{{$...}}`
  dynamic vars) + an importer; web/no-shell falls back to verbatim.
- **Effort**: S–M.

### DW4 — OpenAPI drift detection
- **Idea**: re-sync a collection imported from a spec when that spec changes;
  flag added/removed/changed endpoints instead of a blind re-import.
- **Seam**: `core/utils/openapi/*` (normalized model already exists) + a diff
  over the normalized spec.
- **Effort**: M–L. **Pairs with**: DW3 (shipped — collection→API-docs export
  via the `ApiDoc` IR in `core/utils/apidoc/`; reuse that IR + the importer's
  normalized model for the diff).

### DW5 — Global / scoped variables
- **Idea**: today there are environment + collection variables; add a **global**
  scope with clear precedence (global < collection < env < dynamic `{{$…}}`).
- **Seam**: `environment_resolver.dart` resolution order + a settings-owned
  global map (new `HiveField` on `SettingsModel`).
- **Effort**: M.

---

## 🚫 Deferred / Non-goals (for now)

> Recorded so they stop resurfacing. Both cut against the chosen lightweight
> stance (brainstorm, 2026-06-20); revisit only if a genuinely lean approach
> appears.

- **gRPC support** — heavyweight parity play (proto management, reflection,
  streaming UI). Out of scope while we stay lightweight.
- **Built-in mock server** — runs a local server + persisted mock rules; large
  surface for a client whose identity is "lightweight + local." Deferred.
- **Headless `getman` CLI / CI runner** — considered as a Newman replacement
  (the domain layer is already Flutter-decoupled), but declined for now to avoid
  a second entrypoint/binary and the maintenance surface. The in-app collection
  runner (**H4**) covers the interactive case.

---

# Working agreement (how to resume)
1. **One concern per commit**, message `type(scope): summary`, end with
   `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
2. **TDD for bugs**: write a failing test first, then fix.
3. **Green between commits**: `fvm flutter analyze` + `fvm dart run custom_lint` +
   `fvm dart run bloc_tools:bloc lint lib` all clean AND `fvm flutter test` 100%.
4. **⚠️ `analyze` can give false passes** on generic-variance issues (it once
   accepted `Stream<Uint8List>.transform(Utf8Decoder)` that the CFE rejected).
   For any compile-affecting change, verify with a real compile —
   `fvm flutter test` (CFE) or `fvm flutter build macos --debug` — not just analyze.
5. Theme/atom mandates per `CLAUDE.md` §4.8/§6 (no hardcoded sizes/colors/radii;
   `showAppSnackBar`/`showAppSnackBarVia`, `ConfirmDialog`, `context.app*`).
6. After any `@HiveType`/`@HiveField` change: `dart run build_runner build
   --delete-conflicting-outputs`, then re-run analyze + tests.
