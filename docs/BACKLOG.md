# Getman — Backlog (organized by feature type)

> **How this is organized.** Open work is grouped **by feature type** in the
> "Open backlog" section below. Each item has an ID (stable across reorgs),
> a one-line idea, the **seam** (the real code hook it plugs into), and a rough
> effort (S/M/L). This backlog tracks **open work only** — completed items are
> dropped (git history + `CLAUDE.md` are the record of what shipped). The
> working agreement is at the bottom.
>
> **Themes/visuals work:** before starting any item under
> **🎨 Themes, Visuals & Motion** — or creating/altering any theme — read
> [`docs/THEME_AUTHORING.md`](THEME_AUTHORING.md) first. It is the per-theme
> reactive-design checklist; these backlog items are its raw material.

## Current state
- Branch `dev` (pushed to `origin/dev`). `fvm flutter analyze` / `custom_lint` /
  `bloc_lint` all 0 issues; `fvm flutter test` green (**~1263**).
- The **theme reactive-motion** feature shipped (commits `17f7ad5..ace6b6e`): the
  `AppMotion` extension, the `ThemeReaction`/`ThemeReactionController`/
  `ThemeReactionListener` spine, per-theme reaction overlays + send rituals,
  ambient enrichments, a theme-switch transition, and opt-in themed sound
  (`enableThemeSounds`, HiveField 27). Everything below in **🎨 Themes, Visuals
  & Motion** builds on that infrastructure.
- **VM-A1 + VM-A2 shipped** (commits `5e42afc..3ac2922`, on `dev`, unmerged):
  latency-reactive effects (in-flight build-up on SEND + resolution scaled by
  `durationMs`) and status-code micro-personalities via the shared pure-Dart
  `StatusReactionFlavor` classifier + `latencyWeight`/`inFlightTension`
  (`lib/core/theme/motion/`). Loud themes full, calm themes restrained; codes
  201/204/304/401/403/404/408/429/500/503. No spine change. Wiki synced
  (`Themes-and-Appearance`).
- **VM-A3 + VM-E4 shipped** (commits `5de9850..f9110c3`, on `dev`, unmerged):
  transport-failure sub-personalities (client `send`/`receive`/`connection`
  timeout → the existing `timeout` flavor; bad TLS cert → a new
  `badCertificate` flavor; refused/unknown stay generic `networkError`) plus a
  photosensitivity flash-safety guard. New reusable pieces in
  `lib/core/theme/motion/`: theme-local `TransportFailureKind` on
  `ThemeReaction`, `StatusReactionFlavor.badCertificate`, and
  `photosensitivity.dart` (`kMaxSafeFlashesPerSecond` / `safeFlashCount`) — a
  WCAG 2.3.1 3 Hz cap any repeating flash MUST route through (see
  THEME_AUTHORING §5b). `NetworkFailureType.connection` was split into
  `connectionTimeout`/`connectionError`. No wiki change (internal motion
  polish, no new user-facing control).
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

## 🎨 Themes, Visuals & Motion

> **Read [`docs/THEME_AUTHORING.md`](THEME_AUTHORING.md) before touching these.**
> The reactive spine (`lib/core/theme/motion/`, `AppMotion`) drives all of this.
> **VM-A1/A2/A3 + VM-E4 shipped** (see Current state) — the shared
> `lib/core/theme/motion/` toolkit now includes: the `StatusReactionFlavor`
> classifier (`flavorFor`, incl. transport-failure flavors via
> `TransportFailureKind`), `latencyWeight`/`inFlightTension`, and the
> `photosensitivity.dart` flash guard (`safeFlashCount`). New themes/effects
> should reuse these rather than re-deriving status/latency/flash-rate
> semantics.

### B. Extend reactions to more app moments

#### VM-B1 — Themed in-flight state (app-wide, beyond the SEND button)
- **Idea**: while sending, the whole theme reacts — Arcane traces arcane
  circuit-lines along panel borders, Glass's frost breathes, Brutalist runs a
  marching loading bar. Today only the SEND button reacts during a request.
- **Seam**: a new `AppMotion.inFlight` overlay hook, or drive a full-screen
  treatment from an "any request in flight" signal on `ThemeReactionController`.
- **Effort**: M.

#### VM-B2 — Tab / panel transition choreography
- **Idea**: themed tab open/close and panel switches (Arcane scroll-unfurl,
  Glass frost-dissolve, Brutalist slam-in, panel-switch swipe). We only did the
  *theme*-switch sweep so far.
- **Seam**: a per-theme transition hook mirroring `ThemeSwitchTransition`, mounted
  around `tab_content_stack.dart` / the panel view; keyed on tab/panel id changes.
- **Effort**: M–L.

#### VM-B3 — Collections tree & drag-drop juice
- **Idea**: drag leaves a themed trail; dropping into a folder snaps/absorbs;
  expand/collapse is themed (Arcane chest opening, Glass accordion of frosted
  panes).
- **Seam**: `collections_list.dart` / `collection_node_row.dart`, the existing
  `Draggable<String>`/`DragTarget<String>`; a per-theme tree-motion hook on
  `AppMotion` or `AppDecoration`.
- **Effort**: M.

#### VM-B4 — Realtime stream visualization (WS / SSE)
- **Idea**: each incoming WS/SSE message triggers a small themed pulse/ripple/
  spark; a waveform of message frequency; a heartbeat line. Arcane = arriving
  spell-echoes, Glass = ripples on the surface.
- **Seam**: the `realtime` feature + `RealtimeBloc`'s message stream → feed a
  controller like `ThemeReactionController`; a per-theme realtime-motion view.
- **Effort**: L.

### C. Interactivity & a "living workspace"

#### VM-C1 — Interactive ambient particles (desktop)
- **Idea**: cursor repels/attracts the Arcane motes; clicking the Glass
  wallpaper sends a ripple; inertia/momentum on the starfield when dragging.
- **Seam**: the ambient painters already take a pointer notifier (added in the
  motion phase): `rpg_decorations.dart` `_StarfieldPainter` and
  `glass_decorations.dart` `_GlassMeshPainter`. Extend pointer → forces / click
  impulses. Desktop/web pointer only; gate off touch + `reduceVisualEffects`.
- **Effort**: M.

#### VM-C2 — Session-rhythm ambient
- **Idea**: the background reflects activity — idle a while → starfield dims/
  slows; a burst of sends → it intensifies; environment switch → mood/palette
  shift. The workspace feels alive to your session.
- **Seam**: ambient painters + a lightweight activity signal (reaction frequency
  from `ThemeReactionController`; active env from `SettingsBloc`/
  `EnvironmentsBloc`).
- **Effort**: M–L.

#### VM-C3 — Themed cursor (desktop)
- **Idea**: an Arcane glowing-rune cursor, a Glass refraction-lens cursor.
- **Seam**: `MouseRegion.cursor` per theme, or a custom pointer overlay following
  `_pointer`. Desktop/web only.
- **Effort**: M.

### D. New motion-first themes (cheap now that `AppMotion` exists)

> Design these *around* their reactions from the start (see THEME_AUTHORING.md).
> Pick one as the next flagship.

#### VM-D1 — Synthwave / CRT theme
- **Idea**: neon grid + scanlines + chromatic glow ambient; VHS/RGB-split glitch
  on error; a CRT power-on sweep as the theme-switch transition.
- **Seam**: new `lib/core/theme/themes/synthwave/` (palette + decorations +
  `synthwave_motion.dart`), register in `theme_registry.dart`.
- **Effort**: L.

#### VM-D2 — Terminal / Hacker theme
- **Idea**: matrix-rain ambient, typewriter/cursor-blink reveals, a glitch on
  error, monospace-forward typography.
- **Effort**: L.

#### VM-D3 — Zen / Nature theme
- **Idea**: water-ripple ambient, falling leaves/petals, calm breathing
  gradients; success = a gentle bloom, error = a soft wilt. A restrained
  counterpoint to the loud themes.
- **Effort**: L.

### E. Audio, accessibility & delight

#### VM-E1 — Layered / richer audio
- **Idea**: beyond the Phase-3 one-shots — a very-low opt-in ambient drone per
  theme, pitch-shifted success chimes by status code, a subtle typing texture.
- **Seam**: extend `ThemeSoundService` (currently single-shot `play`).
- **Depends on**: real CC0 audio assets being sourced (the six
  `assets/sounds/<theme>/` dirs exist but are empty; the service no-ops until
  files are added).
- **Effort**: M.

#### VM-E2 — "Calm but present" accessibility tier
- **Idea**: a middle setting between full effects and `reduceVisualEffects` —
  color-only feedback, zero motion (no shake, no particles, no sweeps).
- **Seam**: replace the boolean `reduceVisualEffects` thread with a 3-state enum
  (full / calm / off) through the theme builders + `_themeDataCache` key, and
  honor "calm" in each `*Motion`.
- **Effort**: M.

#### VM-E3 — Transient milestone celebrations (stateless — NOT persistent XP)
- **Idea**: rare, surprising delight: confetti on the first 2xx of a session, an
  all-green collection run, a 100th request. No persisted scoring (that was
  explicitly declined) — purely in-memory, opt-in.
- **Seam**: `ThemeReactionController` + a session-scoped counter; the all-green
  case pairs with **H4** (collection runner).
- **Effort**: M.

#### VM-E5 — Haptics (supported platforms)
- **Idea**: a subtle haptic tick on send/success/error (macOS trackpad / mobile).
- **Seam**: a platform haptic service triggered from `ThemeReactionListener`
  alongside sound; web/unsupported no-op. Niche.
- **Effort**: S–M.

---

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
- **Pairs with**: **VM-E3** (an all-green run is a natural milestone celebration)
  and a themed **VM-B4**-style progress visualization.

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
   **For theme/motion work, follow [`docs/THEME_AUTHORING.md`](THEME_AUTHORING.md).**
6. After any `@HiveType`/`@HiveField` change: `dart run build_runner build
   --delete-conflicting-outputs`, then re-run analyze + tests.
