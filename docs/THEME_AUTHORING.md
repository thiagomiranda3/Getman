# Theme Authoring & Reactive-Design Guide

**Read this whenever you create a new theme or meaningfully change an existing
one.** A Getman theme is not just colors and radii — since the reactive-motion
work, a theme also has a **personality in motion**: how it reacts to sending a
request, to a `200` vs a `500`, to latency, to being switched to. A theme that
sets a palette but leaves `AppMotion` at identity is half-finished.

> Raw ideas to pull from while designing a theme's motion live in
> [`BACKLOG.md`](BACKLOG.md) under **🎨 Themes, Visuals & Motion**.

---

## 1. A theme is 7 ThemeExtensions

Every theme builder (`lib/core/theme/themes/<name>/<name>_theme.dart`) returns a
`ThemeData` carrying all seven. Pull values through `context.app*` in widgets —
never hardcode. (Theme-internal files under `lib/core/theme/themes/<name>/` may
use that theme's own palette constants and effect-specific literals.)

| Extension | Accessor | Owns |
|---|---|---|
| `AppLayout` | `context.appLayout` | sizes, paddings, border widths, row extents |
| `AppPalette` | `context.appPalette` | method/status/variable/diff colors, `codeBackground`, `statusColor(int)` |
| `AppShape` | `context.appShape` | panel/button/input/dialog/sheet radii |
| `AppTypography` | `context.appTypography` | `TextTheme`, `codeFontFamily`, display/title/body weights |
| `AppDecoration` | `context.appDecoration` | `panelBox`, `tabShape`, `wrapInteractive`, `scaffoldBackground`, `frost`, `brandedTabIndicator` |
| `AppCopy` | `context.appCopy` | user-facing strings (e.g. `emptyResponse`) |
| **`AppMotion`** | `context.appMotion` | **`reactionOverlay`, `sendAffordance`** — event-driven motion |

Builders take `(Brightness brightness, {bool isCompact, bool reduceEffects})`.
`reduceEffects` is load-bearing for motion (see §5). Register the theme in
`lib/core/theme/theme_registry.dart` (`appThemes`) with an id constant in
`theme_ids.dart`. No widget edits are required — the picker + command palette
iterate `appThemes`.

---

## 2. First, decide the theme's motion personality

Before writing any effect, answer: **is this a loud theme or a calm theme?**

- **Loud** (Arcane Quest, Liquid Glass, Brutalist): full reaction overlays,
  send rituals, often animated ambient backgrounds. The effects are part of the
  theme's identity and should feel distinct from every other theme.
- **Calm** (Classic, Editorial, Dracula): restrained, color-forward feedback
  (a status-pulse bar), no background motion, no screen shake. The calm themes
  exist as the *contrast* that makes the loud ones pop — keep them quiet on
  purpose.

A new theme picks a lane (or a deliberate point between). Don't give a "calm,
native, Postman-like" theme a sparkle shower; don't give a maximalist theme a
single thin pulse bar.

---

## 3. The reactive checklist (do this for every theme)

The spine that drives all of this: a request produces a `ThemeReaction`
(`lib/core/theme/motion/theme_reaction.dart`) — one of `sendStarted`,
`success`, `clientError`, `serverError`, `networkError`, `cancelled`, carrying
`statusCode` and `durationMs`. `TabsBloc` emits it; `ThemeReactionListener`
pushes it into `ThemeReactionController`; your theme's `reactionOverlay`
subscribes (via `ReactionStage`) and plays the effect.

For the new/changed theme, decide **each of these** and make each express the
theme's identity:

- [ ] **`sendStarted` / in-flight** — the send ritual. What does pressing SEND
  feel like in this theme? (`AppMotion.sendAffordance`, wraps the SEND button;
  it also gets `isSending` for a "charging/working" state.)
- [ ] **`success` (2xx/3xx)** — the reward. The signature "it worked" moment.
- [ ] **`clientError` (4xx)** — a softer "you did something wrong" cue.
- [ ] **`serverError` (5xx) / `networkError`** — the heaviest negative; this is
  where loud themes earn their drama (crack, shake, glitch). **Screen shake, if
  any, MUST be small and MUST respect `reduceVisualEffects`** (vestibular
  safety).
- [ ] **`cancelled`** — a "dispelled/aborted" cue (often a gentle reverse/fizzle,
  or nothing).
- [ ] **Latency (`durationMs`)** — high-value and already wired: does a slow
  response feel different from a fast one? Use the shipped
  `latencyWeight(durationMs)` (0→1) from `lib/core/theme/motion/latency_weight.dart`
  to scale a resolution effect's intensity/duration, and `inFlightTension(elapsedMs)`
  for a live build-up on the SEND control (drive it from `sendAffordance`'s
  `isSending` + a local `_build` controller). **Build-controller restart guard:**
  edge-detect on the old widget — `if (widget.isSending && !old.isSending)
  forward(from:0); else if (!widget.isSending && old.isSending) stop()+reset` —
  NOT `!_build.isAnimating` (that flickers on long sends). All loud themes follow
  this.
- [ ] **Status-code personalities (`statusCode`)** — also wired: map the exact
  code via `flavorFor(reaction)` → `StatusReactionFlavor`
  (`lib/core/theme/motion/status_reaction_flavor.dart`), then render each flavor
  in your theme's idiom (loud themes do bespoke effects; calm themes just tint /
  blink-count the pulse). Reuse the classifier — don't re-derive HTTP semantics.
- [ ] **Ambient background** — does this theme have *living* motion behind the
  app? (loud: yes; calm: no.) Implemented in the theme's `scaffoldBackground`
  painter, with a **separate static variant for `reduceEffects`**.
- [ ] **Theme-switch in** — `ThemeSwitchTransition` plays a generic sweep on
  switch today; a motion-first theme may want its own signature entrance
  (e.g. a CRT power-on). Optional.
- [ ] **Sound cues** — if `enableThemeSounds` is on, the service plays
  `assets/sounds/<themeId>/{send,success,error}.mp3`. Provide cues that match
  the theme's voice (or accept the shared/quiet default). Off by default.
- [ ] **`reduceVisualEffects`** — define the degraded form of every item above
  (see §5). This is not optional.
- [ ] **Flash safety** — any repeating flash/blink respects
  `kMaxSafeFlashesPerSecond` via the photosensitivity guard (§5b).

Use the existing themes as a tonal map: **Glass** = elegant/fluid (ripple,
crack-and-heal, liquid send), **Arcane** = game-y/magical (sparkle shower, runic
crack, screen shake, rune-ring cast), **Brutalist** = blunt/impactful (ink-stamp
of the status code, glitch-shake, hard slam), **Calm** (Classic/Editorial/
Dracula) = a thin status-colored pulse only.

---

## 4. How motion plugs in (mechanics)

`AppMotion` (`lib/core/theme/extensions/app_motion.dart`) has two
identity-defaulting hooks:

```dart
reactionOverlay(context, {required Widget child, required ThemeReactionController controller})
sendAffordance(context, {required Widget child, required bool isSending})
```

Write a `lib/core/theme/themes/<name>/<name>_motion.dart` exposing:

```dart
AppMotion <name>Motion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();          // degrade to identity
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _MyReactionOverlay(controller: controller, child: child),
    sendAffordance: (context, {required child, required isSending}) =>
        _MySendAffordance(isSending: isSending, child: child),
  );
}
```

and wire it into the theme's `extensions: [...]` list:
`<name>Motion(reduceEffects: reduceEffects)`.

Inside the overlay:
- Wrap your effect tree in **`ReactionStage`**
  (`lib/core/theme/motion/reaction_stage.dart`) — it subscribes to the
  controller and calls your `onReaction(ThemeReaction)` exactly once per event,
  with built-in dedupe. Don't re-implement subscription.
- **Hoist `widget.child` out of per-frame rebuilds.** Pass it as
  `AnimatedBuilder(child: widget.child, builder: (context, child) => …
  Stack(children: [child!, …effectPainters]))`. The effect painters/Transforms
  rebuild per frame; the app subtree must NOT. (`glass_motion.dart` is the
  reference; the rpg/brutalist overlays were fixed to this pattern.)

Ambient backgrounds live in the theme's `scaffoldBackground`
(`<name>_decorations.dart`), **not** in `AppMotion`. Provide an animated widget
for full effects and a static one for `reduceEffects` (see `rpg_decorations.dart`
`rpgScaffoldBackground` vs `rpgStaticScaffoldBackground`, and `glass`'s
`GlassWallpaper(animate: …)`).

---

## 5. `reduceVisualEffects` — mandatory degradation

`reduceEffects` threads into every builder and is part of the `_themeDataCache`
key, and the root `BlocBuilder<SettingsBloc>` rebuilds `MaterialApp` when it
toggles. When it is **on**, your theme MUST:

- return `const AppMotion()` from `<name>Motion(...)` (identity overlay + send),
- use the **static** `scaffoldBackground` variant (no controller, no per-frame
  paint),
- never shake, crack, flash, or spawn particles,
- make any theme-switch transition an instant cut.

Pointer-reactive ambient (cursor parallax/sheen) must be gated so it neither
subscribes nor repaints in the static path (see the `pointer: animate ? … : null`
gating in `glass_decorations.dart`). Sound is independently gated by
`enableThemeSounds` (separate from `reduceVisualEffects`).

---

## 5b. Photosensitivity (flash safety) — mandatory

WCAG 2.3.1 (general flash threshold): nothing may flash more than **3 times per
second**. This is independent of `reduceVisualEffects` (a motion/vestibular
concern) — flash safety applies even at full effects.

- Any **repeating** flash/blink/strobe MUST cap its rate via
  `lib/core/theme/motion/photosensitivity.dart`: clamp the count with
  `safeFlashCount(sweep, desired)` or gate the period at `kMinFlashPeriod`.
  (See `shared/calm_motion.dart` `_onReaction` for the reference use.)
- **Large / full-screen** flashes are the real hazard — they MUST route through
  the guard *and* still degrade under `reduceVisualEffects`. Small-area
  one-shot fades/sweeps/sparkles are not "flashes" and need no clamp, but never
  let a count parameter scale them into a rapid full-screen strobe.
- Audited at this writing: calm's pulse-bar blink is guarded; rpg/brutalist/
  glass terminal effects are single-shot or small-area below the cap.

---

## 6. Performance discipline (reuse the proven patterns)

- **One** `AnimationController` per always-on ambient layer; `RepaintBoundary`
  around painters; pause on `AppLifecycleState` (`WidgetsBindingObserver`);
  frame-quantize long loops (see `_RpgAnimatedBackground`'s 30-step quantizer).
- **Reuse `Paint` objects** across draws (mutate `.color`/`.shader`), build any
  reusable `Path` once. Avoid per-element-per-frame allocation in `paint`.
- **Transient effects** (a success burst, a crack) spawn a short-lived
  `AnimationController` that **disposes itself on `AnimationStatus.completed`**;
  `State.dispose()` disposes any still-running ones. Guard against
  double-dispose (e.g. `if (_stamp == c)`).
- Cursor-reactive effects are **pointer-only** (`MouseRegion`), no-op on touch.
- Web/CanvasKit is a target: keep particle counts modest, prefer paint/shader
  over rebuilding widget trees, lean on the `reduceVisualEffects` escape hatch.

---

## 7. Reference implementations to copy

- **Child-hoist + transient overlay**: `themes/glass/glass_motion.dart`
  (`_GlassReactionOverlay` — the cleanest pattern).
- **Screen shake (error-only) + sparkle/crack painters**:
  `themes/rpg/rpg_motion.dart`.
- **Stamp overlay + status-color from `context.appPalette` + slam send**:
  `themes/brutalist/brutalist_motion.dart`.
- **Restrained calm overlay (status-pulse bar, no shake/ambient)**:
  `themes/shared/calm_motion.dart` (shared by Classic/Editorial/Dracula).
- **Animated vs static ambient + pointer gating**: `themes/rpg/rpg_decorations.dart`,
  `themes/glass/glass_decorations.dart`.
- **Subscription/dedupe base**: `motion/reaction_stage.dart`.
- **Theme-switch sweep**: `motion/theme_switch_transition.dart`.

---

## 8. Step-by-step: adding a new theme

1. **Decide personality** (§2) and sketch the reactive checklist (§3).
2. Create `lib/core/theme/themes/<name>/`: `<name>_palette.dart`,
   `<name>_decorations.dart` (incl. animated + static `scaffoldBackground`),
   `<name>_motion.dart`, `<name>_theme.dart` (the builder, attaching all 7
   extensions including `<name>Motion(reduceEffects:)`).
3. Add an id constant in `theme_ids.dart`; register a `ThemeDescriptor` in
   `theme_registry.dart`'s `appThemes`.
4. (If sound) add `assets/sounds/<name>/` with `send/success/error.mp3`
   (CC0/royalty-free) and register the dir in `pubspec.yaml`. Service no-ops if
   absent.
5. Tests: a theme-attaches-AppMotion check is already generic (it iterates
   `appThemes`); add a `<name>_motion_test.dart` (reduced ⇒ identity; full ⇒
   overlay renders child + survives a success and an error reaction without
   throwing) and an ambient smoke test if the theme animates its background.
6. **Done-bar**: `fvm flutter analyze` + `fvm dart run custom_lint` +
   `fvm dart run bloc_tools:bloc lint lib` all 0 issues, `fvm dart format` clean,
   `fvm flutter test` green.
7. **Sync the wiki** (CLAUDE.md §7) — the Themes page must describe the new
   theme's look *and* its reactive behavior.

---

## 9. When changing an existing theme

- Touching colors/shape/typography? Still re-read §3 and ask whether the change
  affects how reactions *read* (e.g. a new accent changes the ripple/pulse
  color, which is sourced from `Theme.of(context).primaryColor` /
  `context.appPalette` at runtime — usually automatic, but verify contrast).
- Touching motion? Keep the `reduceEffects` degradation (§5) and the
  ticker-lifecycle discipline (§6) intact; re-run the theme's motion + ambient
  tests.
- Don't quietly turn a calm theme loud (or vice versa) without a design reason —
  the calm/loud contrast is intentional.
