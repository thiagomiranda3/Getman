# Theme Motion Expansion — VM-B1/B2/B3 + VM-C1/C2 (Design)

**Date:** 2026-06-20
**Status:** Approved design — ready for implementation plan
**Backlog items:** VM-B1, VM-B2, VM-B3, VM-C1, VM-C2 (under
[`docs/BACKLOG.md`](../../BACKLOG.md) → **🎨 Themes, Visuals & Motion**)
**Read first:** [`docs/THEME_AUTHORING.md`](../../THEME_AUTHORING.md) — the per-theme
reactive checklist; this design extends the spine it documents.

---

## 1. Summary

Extend the existing reactive-motion system to five new moments, all expressing
per-theme personality:

- **VM-B1** — a themed in-flight treatment on the request+response panels while a
  request is sending (beyond the SEND button).
- **VM-B2** — themed transition choreography: a content-area swap on tab/panel
  switch, plus tab-strip chip enter/exit on create/close.
- **VM-B3** — themed collections-tree drag-drop juice: drag feedback, a
  drop-absorb on accept, and an expand/collapse flourish.
- **VM-C1** — interactive ambient backgrounds: cursor force field + click ripple
  (desktop/web pointer only).
- **VM-C2** — session-rhythm ambient: idle dimming/slowing + send-burst
  intensification.

This builds entirely on the shipped spine (`lib/core/theme/motion/`, `AppMotion`,
`ThemeReactionController`, `ReactionStage`, the ambient `scaffoldBackground`
painters). No new Hive types, no domain/data changes.

### Locked-in scope decisions

| Decision | Choice |
|---|---|
| Deliverable structure | **One** combined design + one phased implementation plan |
| Theme coverage | **Loud full, calm degrade** — Arcane / Glass / Brutalist / AURIS get full effects; Classic / Editorial / Dracula degrade to identity-or-minimal (honors THEME_AUTHORING §2 calm/loud contrast) |
| Architecture | **Approach C (hybrid)** — discrete event hooks for B1/B2/B3; one shared `AmbientSignals` object threaded into the painters for C1/C2 |
| B1 manifestation | Panel-frame treatment (not full-screen ambient modulation) |
| B2 scope | Content swap (tab + panel switch) **and** tab-strip chip open/close |
| B3 scope | Drag feedback **+** drop-absorb **+** expand/collapse flourish |
| C1/C2 theme scope | **All four loud themes** — including **new ambient painters for Brutalist + AURIS** (they have none today) |
| C1 interactions | Cursor force field + click impulse/ripple (no drag inertia) |
| C2 signals | Idle dimming/slowing + send-burst intensification (no env-switch mood shift) |

### Out of scope (declined during brainstorming)

- Full-screen ambient modulation for in-flight (B1) — frame only.
- Drag inertia/momentum on the ambient (C1).
- Environment-switch mood/palette shift (C2).
- Adding ambient to calm themes — they stay quiet by design.
- New user-facing settings — everything rides under the existing
  `reduceVisualEffects` toggle and the loud/calm split.

---

## 2. Architecture (Approach C — hybrid)

The recurring shape of every feature is **(a) a signal** and **(b) a per-theme
rendering hook**. Approach C keeps the discrete-event hooks consistent with the
existing `reactionOverlay`/`sendAffordance` pattern, but consolidates the
*ambient* inputs (which C1 and C2 both feed into the **same** painters) into one
value object so each painter's constructor is touched exactly once.

```
┌─ Event-in-time features (discrete hooks on AppMotion) ──────────────┐
│  B1  inFlightFrame      mounted around request+response panel area  │
│  B2  contentTransition  mounted around tab_content_stack            │
│  B2  tabChipTransition  used in the tab strip's AnimatedSwitcher    │
│  B3  tree-motion hooks   layered on Draggable/DragTarget rows       │
└─────────────────────────────────────────────────────────────────────┘

┌─ Ambient features (shared AmbientSignals → scaffoldBackground) ─────┐
│  C1  pointer + impulses (captured locally by the ambient widget)    │
│  C2  activityLevel + idleFactor (from WorkspacePulseController)      │
│        ↓ bundled into AmbientSignals ↓                              │
│  rpg / glass painters (extend) + brutalist / auris painters (new)   │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.1 New `AppMotion` hooks (identity-default → backward compatible)

`AppMotion` (`lib/core/theme/extensions/app_motion.dart`) today has
`reactionOverlay` + `sendAffordance`, both with identity defaults. We add new
fields, **each defaulting to identity**, so every existing theme and the shared
`calm_motion.dart` keep compiling and behave unchanged until they opt in. The
generic `theme_has_*` tests iterate `appThemes` and only assert the extension is
attached, so identity-default fields don't break them. `copyWith`/`lerp` extend
to the new fields (lerp stays a no-op, as today).

```dart
// B1
typedef InFlightFrameBuilder = Widget Function(
  BuildContext context, {required Widget child, required bool isSending});

// B2
typedef ContentTransitionBuilder = Widget Function(
  BuildContext context, {required Widget child, required String transitionKey});
typedef TabChipTransitionBuilder = Widget Function(
  BuildContext context, {required Widget child, required Animation<double> animation});

// B3 — tree motion. Exact grouping (one bundle vs three small hooks) is a
// plan-time detail; they belong on AppMotion because they are event-driven
// motion (AppDecoration is the static-styling alternative if the plan prefers).
//   - treeDragFeedback(context, {required child})
//   - treeDropHighlight(context, {required child, required bool active})  // + self-disposing absorb on accept
//   - treeExpandFlourish(context, {required child, required bool expanded})
```

All builders default to returning `child` (or the supplied animation's default
fade), so calm themes and `reduceEffects` inherit no-op behavior for free.

### 2.2 `AmbientSignals` value object (C1/C2)

One small immutable struct, passed into each `scaffoldBackground` painter and
plumbed **once** per painter:

```dart
@immutable
class AmbientSignals {
  final ValueListenable<Offset> pointer;        // normalized; passive parallax today, forces in C1
  final ValueListenable<List<AmbientImpulse>> impulses;  // active click ripples (origin + birth)
  final double activityLevel;                   // 0→1, recent send frequency (C2 send-burst)
  final double idleFactor;                      // 0→1, rises with inactivity (C2 idle)
  final bool isDark;
}
```

- `pointer` + `impulses` are captured **locally** by the ambient widget
  (`MouseRegion` for hover, `Listener` for taps) — desktop/web pointer only,
  no-op on touch.
- `activityLevel` / `idleFactor` come from `WorkspacePulseController` (§2.3),
  read from context by the ambient widget.
- Each painter reads only the fields it uses; adding C1 then C2 is just reading
  more fields off the same object — the constructor signature does not churn.
- `AmbientImpulse` entries are **self-disposing**: the ambient widget drops them
  from the list once aged past their lifetime, so the list never grows unbounded.

### 2.3 `WorkspacePulseController` (`ChangeNotifier`, C2)

```dart
class WorkspacePulseController extends ChangeNotifier {
  double get activityLevel; // decaying counter of recent reactions, clamped 0..1
  double get idleFactor;    // 0 when active, rises toward 1 after an idle timeout
  void bump();              // called on each ThemeReaction (a send happened)
  void touch();             // called on pointer/click — resets idle
  // internal ~1 Hz tick decays activityLevel and raises idleFactor; NOT per-frame
}
```

- **Provided** in `main.dart` beside `ThemeReactionController` (currently
  `ChangeNotifierProvider.value`, ~main:198) so the ambient `scaffoldBackground`
  can read it from context.
- **Fed** by the existing `ThemeReactionListener`
  (`lib/features/home/presentation/widgets/theme_reaction_listener.dart`): it
  already fires `ThemeReactionController` on every reaction — add a
  `pulse.bump()` call alongside. Ambient widgets call `pulse.touch()` on
  pointer/click.
- **Logic-free painters:** all rhythm logic lives in the controller and is
  unit-tested in isolation; painters just read two doubles.
- Tick is ~1 Hz, lifecycle-aware (no work when paused / no listeners).

---

## 3. Feature designs

### 3.1 VM-B1 — In-flight panel frame

- **Mount:** wraps the request+response panel area in `request_view.dart` (the
  split-pane content) via `context.appMotion.inFlightFrame(child:, isSending:)`.
- **Signal:** the **displayed tab's** `isSending`, read with a narrow
  `BlocSelector<TabsBloc, bool>` at the mount point. The frame surrounds the work
  you are looking at, so it tracks the active tab — **no global "any in flight"
  signal is required** for B1. (Cross-tab activity is already captured for C2 via
  `WorkspacePulseController`.)
- **Per loud theme** (continuous motion, **not** flashing — sidesteps the 3 Hz
  rule):
  - **Arcane** — runic circuit-trace running along the panel border.
  - **Glass** — the frame edge frost "breathes."
  - **Brutalist** — a marching ink loading-bar along the edge (must not strobe).
  - **AURIS** — a HUD scanline sweep on the frame (colors from `AurisScheme`).
- **Calm / reduceEffects:** identity (no frame).

### 3.2 VM-B2 — Transition choreography

**Content swap:**
- `tab_content_stack.dart` wrapped in
  `contentTransition(child:, transitionKey: "$activePanelId/$activeTabId")`.
- Mirrors `ThemeSwitchTransition`
  (`lib/core/theme/motion/theme_switch_transition.dart`) exactly: detect a
  `transitionKey` change → play the themed sweep. **`child` is hoisted out of
  per-frame rebuilds** (the documented child-hoist rule; `glass_motion.dart` is
  the reference). Panel switches get a directional swipe; tab switches get the
  theme's signature swap (Arcane scroll-unfurl, Glass frost-dissolve, Brutalist
  slam-in).

**Tab-strip chips:**
- Each chip in the tab strip is wrapped via `tabChipTransition` used as the
  `transitionBuilder` of an `AnimatedSwitcher`/`AnimatedList`, so chips animate in
  on create and out on close (themed enter/exit).
- Touch point: the tab strip widget (`BrandedTabBar` / the tabs strip). This is a
  list-rendering change (different mechanism from the content swap) — sequence it
  carefully in the plan.

**Calm / reduceEffects:** instant cut for the content swap; chips use the default
fast fade.

### 3.3 VM-B3 — Tree drag-drop juice

- **Mount:** `collections_list.dart` / `collection_node_row.dart`, layering onto
  the existing `Draggable<String>` / `DragTarget<String>`.
- **Drag feedback:** themed builder for the `Draggable.feedback` widget.
- **Drop-absorb:** themed `DragTarget` highlight while a candidate hovers, plus a
  short **self-disposing** "absorb/snap" animation on accept (Arcane glow-pull,
  Glass ripple-in, Brutalist slam, AURIS lock-on).
- **Expand/collapse flourish:** the `TreeView` row extent is **fixed**
  (`AppLayout.treeRowExtent`; no content-sizing in the 2D viewport — CLAUDE.md),
  so this is an icon/glow flourish or a brief one-shot overlay on toggle —
  **explicitly not true height animation**.
- **Calm / reduceEffects:** default Flutter drag feedback; no absorb, no flourish.

### 3.4 VM-C1 — Interactive ambient (cursor force + click ripple)

All via `AmbientSignals` (§2.2) into the painters.

- **Cursor force field:** upgrades passive pointer use to active forces. Arcane
  motes repel from the cursor; Glass blobs/sheen lean toward it; Brutalist dots
  clump/displace; AURIS nodes lean + a tracking reticle. Reads
  `AmbientSignals.pointer`.
- **Click ripple/impulse:** a `Listener` on the ambient widget pushes a transient
  `AmbientImpulse` (origin + birth time) into `AmbientSignals.impulses`; each
  painter renders its idiom — Glass ripple, Arcane shockwave, Brutalist
  ink-splat, AURIS target-ping. Self-disposing.
- **Gating:** desktop/web pointer only (`MouseRegion`/`Listener` no-op on touch);
  fully off under `reduceEffects` (static `scaffoldBackground`, no signals read —
  follow glass's `pointer: animate ? … : null` gating).

### 3.5 VM-C2 — Session rhythm (idle dim + send-burst intensify)

- **Idle:** `idleFactor` dims/slows the field after inactivity; any
  pointer/click/send revives it (`pulse.touch()`/`bump()`).
- **Send-burst:** `activityLevel` intensifies density/speed.
- Both are multipliers the painters apply to existing animation parameters — no
  new per-painter machinery beyond reading two doubles.

### 3.6 Two new ambient systems (Brutalist + AURIS)

Each needs an **animated** `scaffoldBackground` **and** a **static**
`reduceEffects` variant (rpg/glass discipline: one controller, `RepaintBoundary`,
reused `Paint`, lifecycle pause, frame-quantized loop). These are the largest
single chunk of the work and get their own plan phase.

- **Brutalist** — a slow risograph/halftone dot-grid with slight registration
  ghosting; monochrome + one accent. Cursor clumps dots; click stamps an
  ink-splat. Static variant = a flat grain texture.
- **AURIS** — a scanning HUD grid with drifting telemetry glyphs / a slow radar
  sweep. **Must read its colors from the `auris` kit's `AurisScheme`** and the
  builder must preserve that extension (the §10/THEME_AUTHORING force-unwrap
  caveat — AURIS spreads `...base.extensions.values`). Cursor adds a reticle;
  click pings a target-lock. Static variant = a still grid.

---

## 4. Cross-cutting concerns

### 4.1 Performance (THEME_AUTHORING §6)

- One `AnimationController` per always-on ambient layer; `RepaintBoundary` around
  every painter; pause on `AppLifecycleState.paused` (`WidgetsBindingObserver`);
  frame-quantize long loops.
- Reuse `Paint` objects (mutate `.color`/`.shader`); build reusable `Path`s once.
  No per-element-per-frame allocation in `paint`.
- Transient effects (click ripples, drop-absorb, content sweeps) spawn
  short-lived controllers that **self-dispose on `AnimationStatus.completed`**,
  with double-dispose guards; `State.dispose()` cleans up any still-running.
- **Child-hoist rule** enforced on `inFlightFrame` and `contentTransition` — the
  app subtree must not rebuild per frame.
- `WorkspacePulseController` ticks ~1 Hz, never per-frame.

### 4.2 Accessibility & degradation (mandatory)

- **`reduceVisualEffects`** → every new hook returns identity, ambient uses the
  static variant (no signals subscribed/read), transitions become instant cuts.
  This is the headline contract and part of the `_themeDataCache` key already.
- **Photosensitivity (WCAG 2.3.1, independent of `reduceEffects`):** the B1 frame
  uses continuous motion, not flashing; any repeating flash anywhere routes
  through `safeFlashCount` / `kMaxSafeFlashesPerSecond` (3 Hz)
  (`lib/core/theme/motion/photosensitivity.dart`).
- Touch devices: C1 pointer/click effects no-op.
- **No new screen shake** is introduced; the existing error-shake is untouched.

### 4.3 Testing

- `WorkspacePulseController` unit test: `bump` raises activity, it decays over
  ticks, `idleFactor` rises after the timeout, `touch` resets it.
- Each loud theme's new hooks: renders `child`, survives a `success` + an `error`
  reaction without throwing, returns identity under `reduceEffects`.
- New `brutalist` / `auris` ambient smoke tests: animated + static variants paint
  without throwing; pointer-gated path under `reduceEffects`.
- **Under-theme overflow guards (the AURIS lesson):** render the real
  `ResponseSection` + the collections tree under each loud theme with the new
  wrappers and assert no `RenderFlex` overflow — especially the fixed-extent tree
  rows (B3).
- B2: `contentTransition` plays on `transitionKey` change and is an instant cut
  under `reduceEffects`; tab-chip enter/exit smoke test.
- **Done-bar:** `fvm flutter analyze` (very_good_analysis) +
  `fvm dart run custom_lint` + `fvm dart run bloc_tools:bloc lint lib` all report
  zero issues; `fvm dart format` clean; `fvm flutter test` 100% green. These are
  independent passes.

### 4.4 Docs / wiki (CLAUDE.md §7 mandate)

- These change how four themes *feel* and add ambient to Brutalist + AURIS, so
  the GitHub wiki **Themes-and-Appearance** page must describe the new in-flight,
  transition, tree, and ambient behaviors (clone `Getman.wiki.git`, edit, commit,
  push to `master`).
- `THEME_AUTHORING.md`'s reactive checklist (§3) should gain rows for the new
  moments (in-flight frame, transitions, tree juice, interactive/session-rhythm
  ambient) so future themes are reminded to address them.

---

## 5. Suggested implementation phasing

The plan (written next via the writing-plans skill) will sequence roughly:

1. **Shared infra** — new `AppMotion` hooks (identity defaults) + `AmbientSignals`
   + `WorkspacePulseController` (provided + fed by `ThemeReactionListener`), with
   unit tests. No visible behavior yet.
2. **VM-B1** — `inFlightFrame` + the four loud-theme frame effects.
3. **VM-B2** — `contentTransition` (content swap) then `tabChipTransition`
   (tab-strip enter/exit).
4. **VM-B3** — tree hooks (drag feedback, drop-absorb, expand flourish).
5. **New ambient systems** — Brutalist + AURIS animated + static
   `scaffoldBackground` (the biggest chunk).
6. **VM-C1** — wire pointer forces + click impulses through `AmbientSignals` into
   all four painters (rpg/glass extended, brutalist/auris built in #5).
7. **VM-C2** — wire `activityLevel`/`idleFactor` multipliers into all four
   painters.
8. **Docs/wiki sync** + final done-bar pass.

Each phase ends green on the full done-bar before the next begins.
