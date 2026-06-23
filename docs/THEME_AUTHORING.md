# Theme Authoring Guide

**Read this whenever you create a new theme or meaningfully change an existing
one.** A Getman theme is not just colors and radii — it also has **a personality
in motion** (ambient background, tree drag/drop juice, theme-switch transition)
and since the AURIS work it can field its **own component widgets** (§10).
A theme that sets a palette but never tries an original component is half-finished.

> Raw ideas to pull from while designing a theme's motion live in
> [`BACKLOG.md`](BACKLOG.md) under **🎨 Themes, Visuals & Motion**.

---

## 1. A theme is 8 ThemeExtensions

Every theme builder (`lib/core/theme/themes/<name>/<name>_theme.dart`) returns a
`ThemeData` carrying all eight. Pull values through `context.app*` in widgets —
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
| **`AppMotion`** | `context.appMotion` | **`treeDragFeedback`, `treeDropHighlight`, `treeExpandFlourish`** — collections-tree drag/drop juice |
| **`AppComponents`** | `context.appComponents` | **per-theme widget builders** for slottable UI atoms (`surface`, `methodBadge`, `statusBadge`, `metric`, `toggle`, `logView`, `dataRow`, `select`, `pendingIndicator`, `statusBanner`) — see §10 |

Builders take `(Brightness brightness, {bool isCompact, bool reduceEffects})`.
`reduceEffects` is passed to the ambient `scaffoldBackground` so it can degrade
to a static variant (see §5). Register the theme in
`lib/core/theme/theme_registry.dart` (`appThemes`) with an id constant in
`theme_ids.dart`. No widget edits are required — the picker + command palette
iterate `appThemes`.

---

## 2. First, decide the theme's motion personality

Before writing any effect, answer: **is this a loud theme or a calm theme?**

- **Loud** (Arcane Quest, Liquid Glass, Brutalist, AURIS): animated ambient
  backgrounds reacting to pointer and idle rhythm, expressive tree drag/drop
  juice. The effects are part of the theme's identity and should feel distinct
  from every other theme.
- **Calm** (Classic, Editorial, Dracula): no background motion, identity-pass
  tree hooks. The calm themes exist as the *contrast* that makes the loud ones
  pop — keep them quiet on purpose.

A new theme picks a lane (or a deliberate point between). Don't give a
"calm, native, Postman-like" theme animated particles; don't give a maximalist
theme a plain static background.

---

## 3. The motion checklist (do this for every theme)

For the new/changed theme, decide **each of these** and make each express the
theme's personality:

- [ ] **Ambient background** — does this theme have *living* motion behind the
  app? (Loud: yes; calm: no.) Implemented in the theme's `scaffoldBackground`
  painter, with a **separate static variant for `reduceEffects`**.
- [ ] **Interactive ambient** — cursor parallax + idle breathing?
  Via `AmbientSignals` (`lib/core/theme/motion/ambient_signals.dart`):
  `signals.pointer` is a normalized `Offset` listenable; `signals.pulse`
  (`WorkspacePulseController`) spikes on each send and decays over ~6 s.
  Pass `null` in the static (`reduceEffects`) path so nothing subscribes or
  repaints. Loud themes only.
- [ ] **Tree juice** — drag feedback, drop-absorb highlight, expand flourish?
  (`AppMotion.treeDragFeedback`, `.treeDropHighlight`, `.treeExpandFlourish`).
  These three hooks decorate the collections tree without touching TreeView
  internals. Loud themes add visual drag handles, hover glows, and a brief icon
  flourish on expand/collapse; calm themes identity-pass.
- [ ] **Theme-switch in** — `ThemeSwitchTransition` plays a generic sweep on
  switch today; a motion-forward theme may want its own signature entrance
  (e.g. a CRT power-on). Optional.
- [ ] **`wrapInteractive`** — every theme uses the shared `SubtlePress`
  (`lib/core/theme/themes/shared/subtle_press.dart`, ~1% scale + slight opacity
  dim). No per-theme override is needed or expected here.
- [ ] **`reduceEffects`** — define the degraded form of every animated item
  above (see §5). This is not optional.

Use the existing themes as a tonal map: **Glass** = elegant/fluid (frost blur,
cursor sheen), **Arcane** = game-y/magical (starfield, runic drag handles),
**Brutalist** = blunt/impactful (halftone-dot ambient), **AURIS** = sci-fi HUD
(grid wallpaper, radar sweep), **Calm** (Classic/Editorial/Dracula) = static
background, identity tree hooks.

---

## 4. How motion plugs in (mechanics)

`AppMotion` (`lib/core/theme/extensions/app_motion.dart`) has three
identity-defaulting tree-juice hooks:

```dart
treeDragFeedback(context, {required Widget child})
treeDropHighlight(context, {required Widget child, required bool isActive})
treeExpandFlourish(context, {required Widget child, required bool isExpanded})
```

Write a `lib/core/theme/themes/<name>/<name>_motion.dart` exposing:

```dart
AppMotion <name>Motion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();          // degrade to identity
  return AppMotion(
    treeDragFeedback: (context, {required child}) => _MyDragFeedback(child: child),
    treeDropHighlight: (context, {required child, required isActive}) =>
        _MyDropHighlight(isActive: isActive, child: child),
    treeExpandFlourish: (context, {required child, required isExpanded}) =>
        _MyExpandFlourish(isExpanded: isExpanded, child: child),
  );
}
```

and wire it into the theme's `extensions: [...]` list:
`<name>Motion(reduceEffects: reduceEffects)`.

Ambient backgrounds live in the theme's `scaffoldBackground`
(`<name>_decorations.dart`), **not** in `AppMotion`. Provide an animated widget
for full effects and a static one for `reduceEffects` (see `rpg_decorations.dart`
`rpgScaffoldBackground` vs `rpgStaticScaffoldBackground`, and `glass`'s
`GlassWallpaper(animate: …)`).

> **All loud themes ship an animated ambient** — Brutalist (halftone-dot field,
> `brutalist_ambient.dart`), AURIS (HUD-grid wallpaper, `auris_ambient.dart`),
> Arcane Quest, and Liquid Glass. If you add a new loud theme, authoring an
> ambient is **expected, not optional**. Both degrade to a static variant under
> `reduceEffects`. The `AmbientSignals` bundle is passed into the animated
> variant so the background reacts to pointer movement and session rhythm; the
> static variant receives `null` and subscribes to nothing.

---

## 5. `reduceEffects` — mandatory degradation

`reduceEffects` threads into every builder as a named parameter. When it is
**on**, your theme MUST:

- return `const AppMotion()` from `<name>Motion(...)` (identity tree hooks),
- use the **static** `scaffoldBackground` variant (no controller, no per-frame
  paint),
- never spawn particles,
- make any theme-switch transition an instant cut.

Pointer-reactive ambient (cursor parallax/sheen) must be gated so it neither
subscribes nor repaints in the static path (see the `pointer: animate ? … : null`
gating in `glass_decorations.dart`).

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
  over rebuilding widget trees, lean on the `reduceEffects` escape hatch.

---

## 7. Reference implementations to copy

- **Tree juice (drag/drop/expand hooks)**: `themes/brutalist/brutalist_motion.dart`
  (ink-press drag handle) and `themes/rpg/rpg_motion.dart` (runic expand flourish).
- **Calm / identity tree hooks**: `themes/shared/calm_motion.dart`
  (shared by Classic/Editorial/Dracula — all three hooks are identity-pass).
- **Animated vs static ambient + pointer gating**: `themes/rpg/rpg_decorations.dart`,
  `themes/glass/glass_decorations.dart`.
- **AmbientSignals (pointer + pulse)**: `motion/ambient_signals.dart`.
- **WorkspacePulseController (session rhythm)**: `motion/workspace_pulse_controller.dart`.
- **Theme-switch sweep**: `motion/theme_switch_transition.dart`.
- **Uniform press**: `themes/shared/subtle_press.dart`.

---

## 8. Step-by-step: adding a new theme

1. **Decide personality** (§2) and sketch the motion checklist (§3).
2. Create `lib/core/theme/themes/<name>/`: `<name>_palette.dart`,
   `<name>_decorations.dart` (incl. animated + static `scaffoldBackground`),
   `<name>_motion.dart` (tree-juice hooks), `<name>_theme.dart` (the builder,
   attaching all 8 extensions including `<name>Motion(reduceEffects:)` and either
   `defaultAppComponents()` or a bespoke `<name>Components()` — see §10), and
   ideally `<name>_components.dart` (your original widgets — **§10 says always
   try this**).
3. Add an id constant in `theme_ids.dart`; register a `ThemeDescriptor` in
   `theme_registry.dart`'s `appThemes`.
4. Tests: a theme-attaches-AppMotion / -AppComponents check is already generic
   (it iterates `appThemes`); add a `<name>_motion_test.dart` (reduced ⇒
   identity; full ⇒ tree hooks render without throwing), an ambient smoke test
   if the theme animates its background, and — if you ship `<name>Components()` —
   a `<name>_components_test.dart` (each overridden slot renders under the theme
   + an under-theme render/overflow guard for the panels & metadata row; §10).
5. **Done-bar**: `fvm flutter analyze` + `fvm dart run custom_lint` +
   `fvm dart run bloc_tools:bloc lint lib` all 0 issues, `fvm dart format` clean,
   `fvm flutter test` green.
6. **Sync the wiki** (CLAUDE.md §7) — the Themes page must describe the new
   theme's look and its ambient/motion personality.

---

## 9. When changing an existing theme

- Touching colors/shape/typography? Still re-read §3 and ask whether the change
  affects how the ambient background reads (e.g. a new accent color changes the
  parallax/sheen tint, which is sourced from `context.appPalette` at runtime —
  usually automatic, but verify contrast).
- Touching motion? Keep the `reduceEffects` degradation (§5) and the
  ticker-lifecycle discipline (§6) intact; re-run the theme's motion + ambient
  tests.
- Don't quietly turn a calm theme loud (or vice versa) without a design reason —
  the calm/loud contrast is intentional.

---

## 10. Components: always try to build original widgets that fit the theme

A theme is **not just colours, shapes, and motion** — since the AURIS work it can
also swap in its own *widgets*. **When authoring (or upgrading) a theme, always
try to give it original components that express its personality**, not just a
recoloured default. AURIS was the proof: a sci-fi-HUD panel, a chamfered switch, a
live terminal-style log, and status "badges" read as a different *product*, not a
re-skin. As of VM-F1 **every theme except Classic ships a bespoke set** — study
the one nearest your new theme's tone as a reference: `brutalist_components.dart`
(ink-press, the cleanest hand-authored example), `rpg_components.dart` (runic
panels + a faceted-gem `CustomPainter`), `glass_components.dart` (reuses the
theme's real `frost`), `editorial_components.dart` (fully static / calm),
`dracula_components.dart` (a ≤1.5 Hz blinking cursor — the flash-safe animated
example), and `auris_components.dart` (composes an external kit). Classic stays on
`defaultAppComponents()` by design (the calm native default).

**The seam — `AppComponents`** (`lib/core/theme/extensions/app_components.dart`,
read via `context.appComponents`): per-theme widget builders for the slottable
atoms `surface / methodBadge / statusBadge / metric / toggle / logView / dataRow
/ select / pendingIndicator / statusBanner`. Every app consumer already calls the
slot, so **no app-widget edits are ever needed** to change how these render.

**How to add originals:**
1. Write `lib/core/theme/themes/<name>/<name>_components.dart` exporting
   `AppComponents <name>Components()` = `defaultAppComponents().copyWith(...)`,
   overriding only the slots you're customizing (inherit the defaults for the
   rest). Author the theme's own private widgets there, or compose an external
   widget kit (AURIS composes the `auris` package — see `auris_components.dart`,
   the reference implementation).
2. Attach `<name>Components()` (instead of `defaultAppComponents()`) in the
   theme builder's `extensions:` list.
3. The generic `theme_has_components_test` already asserts every theme attaches
   `AppComponents`; add `<name>_components_test.dart` (each overridden slot
   renders under the theme without throwing).

**Pick the highest-personality slots first**: `surface` (panels), `methodBadge`/
`statusBadge`, `logView` (realtime), then `metric`/`toggle`. Inherit the rest.

**Caveats (learned from AURIS):**
- **Test the layout under your theme, not just in isolation.** Custom widgets
  often differ in size — `surface` must *fill* (it lives inside an `Expanded`),
  `logView` must size to available height, and an inline `metric` must not
  overflow the metadata `Wrap`. AURIS hit real `RenderFlex` overflows here and
  added documented fallbacks (a compact chip for `metric`, chrome-aware height
  for `logView`). Render the real `ResponseSection` (metadata + a sending tab)
  and `RealtimePanel` under your theme and assert no overflow.
- **Respect the calm/loud contrast (§2).** "Original" does not mean "loud":
  calm themes (Classic/Editorial/Dracula) should stay close to the defaults by
  design — give them at most quiet refinements. Loud themes earn bespoke widgets.
- If a slot widget depends on an external kit's `ThemeExtension` (AURIS widgets
  force-unwrap `AurisScheme`), make sure your builder **preserves that extension**
  (AURIS spreads `...base.extensions.values` into `copyWith`), and that the
  override is attached *only* by your theme so other themes never construct it.

> The per-theme bespoke sets (Brutalist ink-stamps, Arcane runic panels, Glass
> frosted tiles, Editorial article panels, Dracula console log, …) shipped under
> [`BACKLOG.md`](BACKLOG.md) **VM-F1** — see each `<name>_components.dart` for the
> concrete reference. The `select` slot is still inherited everywhere (VM-F2).

