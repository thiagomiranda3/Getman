# Theme reactive motion ("theme juice") — design

**Date:** 2026-06-19
**Status:** Approved (design), ready for implementation plan

## Motivation

The two animated themes (Arcane Quest, Liquid Glass) have ambient background
motion today, but the effects are passive and the themes don't feel *alive* in
response to what the user is actually doing. The user wants to add **more** —
standout animations, transitions, and effects that make the spicy themes pop
over the calmer ones, and that feel original to an HTTP client.

The defining insight: this is an **HTTP client**, so the *work itself* can drive
the visuals — sending a request, the status code that comes back, the latency.
No other API tool reacts to a `200 OK` with a themed flourish or cracks the
glass on a `500`. That reactivity is the original hook.

This adds a new **reactive motion layer** that every theme plugs into, scaled to
its personality: loud and showy for Arcane/Glass/Brutalist, restrained for
Classic/Editorial/Dracula.

## Scope (locked with user)

- **Tier:** "Reactive juice" — visual/motion juice **plus** effects driven by
  real request outcomes (send / success / status code / latency). **No**
  persisted gamification (XP, levels, achievements, streaks) — explicitly out of
  scope.
- **Themes:** **all six**, scaled by personality (loud themes get loud effects,
  calm themes get subtle ones — the contrast is the point).
- **Sound:** in scope, behind a **new setting that defaults OFF**.
- **Theme-switch transition:** in scope (a brief sweep/dissolve when the active
  theme changes).
- Extending the theme interfaces is sanctioned — this adds a new
  `ThemeExtension`.

## Design decisions (locked with user)

- The per-theme reactive visuals plug in via a **new 7th `ThemeExtension`,
  `AppMotion`** (accessed `context.appMotion`), keeping static styling
  (`AppDecoration`) separate from event-driven motion.
- Two hooks on `AppMotion`, both defaulting to **identity** so calm themes and
  any future theme need zero motion code unless they opt in:
  - `reactionOverlay` — wraps the whole app; may `Transform` the child (shake)
    and `Stack` transient effects on top; subscribes to the reaction controller.
  - `sendAffordance` — wraps the SEND control; plays the theme's send ritual and
    its "charging" state while `isSending`.
- **Ambient** enrichments (shooting stars, cursor sheen) are **not** new hooks —
  they're in-place upgrades to each theme's existing `scaffoldBackground`
  painter, which already owns the background.
- The reaction **outcome is sourced from the bloc** (single source of truth — it
  already classifies cancel vs network failure vs HTTP status). It is surfaced
  as a **transient** per-tab signal in `TabsState`, never persisted (reset on
  `LoadTabs`, no Hive model/typeId change, no migration).
- All heavy motion gates behind the **existing `reduceVisualEffects`** master
  toggle. Screen shake *always* respects it (vestibular safety).
- Sound is gated by a **separate** `enableThemeSounds` setting so a user can
  have silent juice or quiet visuals independently.

## Architecture fit

### 1. `AppMotion` extension (the new interface)

A 7th `ThemeExtension` alongside the existing six (`AppCopy`, `AppDecoration`,
`AppLayout`, `AppPalette`, `AppShape`, `AppTypography`). Attached by every theme
builder. Accessed via a new `context.appMotion` accessor in
`extension AppThemeAccess on BuildContext`.

```dart
typedef ReactionOverlayBuilder = Widget Function(
  BuildContext context, {
  required Widget child,
  required ThemeReactionController controller,
});

typedef SendAffordanceBuilder = Widget Function(
  BuildContext context, {
  required Widget child,
  required bool isSending,
});

class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    this.reactionOverlay = _identityReactionOverlay, // returns child unchanged
    this.sendAffordance = _identitySendAffordance,   // returns child unchanged
  });
  final ReactionOverlayBuilder reactionOverlay;
  final SendAffordanceBuilder sendAffordance;
  // copyWith / lerp => this (mirrors AppDecoration: closures don't lerp).
}
```

Identity defaults mean a theme that supplies no motion is completely unaffected
(same pattern as `AppDecoration.frost`).

### 2. The event spine (shared by every theme)

- **`ThemeReaction`** — a small sealed/enum value type:
  `sendStarted` / `success(int code, int durationMs)` / `clientError(int code)`
  / `serverError(int code)` / `networkError` / `cancelled`. Lives in
  `lib/core/theme/motion/` (theme-layer, pure).
- **`ThemeReactionController`** — a `ChangeNotifier` exposing the latest
  reaction + a monotonic token so overlays fire each reaction exactly once.
  Registered as a lazy singleton in `injection_container.dart`, exposed to the
  widget tree via `RepositoryProvider` (read with `context.read<...>()`, never
  `sl<T>()`).
- **`ThemeReactionListener`** — a `BlocListener<TabsBloc>` mounted in
  `MainScreen`, a direct twin of `ChainingWriteBackListener`: it tracks each
  tab's transient reaction signal (last-seen token per `tabId`, à la
  `_written`) and pushes the matching `ThemeReaction` into the controller
  exactly once. **No bloc→bloc coupling** — it reads bloc state at the widget
  layer, the same rule the rest of the app follows.

#### Outcome classification (in the bloc)

`TabsBloc` already maps `DioExceptionType.cancel → NetworkFailure(cancelled)`
and surfaces HTTP errors as responses with a `statusCode`. On each terminal
transition it sets a transient per-tab reaction signal:

- `isSending` false→true ⇒ `sendStarted`.
- response recorded, `200..399` ⇒ `success(code, durationMs)`.
- response recorded, `400..499` ⇒ `clientError(code)`; `500..599` ⇒
  `serverError(code)`.
- `NetworkFailure(cancelled)` ⇒ `cancelled`.
- any other `NetworkFailure` (no response) ⇒ `networkError`.

The signal carries a monotonic counter so identical consecutive outcomes (two
`200`s in a row) still fire. It is reset to none on `LoadTabs` and is **not**
written to the Hive model — purely in-memory, like the `isSending=false`
sanitization on restart.

### 3. Mounting

- `reactionOverlay` is mounted in `main.dart`'s `MaterialApp.router` builder,
  composed with the existing `scaffoldBackground` (overlay wraps the app content
  so it can both shake the child and paint transient effects above it). It reads
  the controller from `RepositoryProvider`.
- `sendAffordance` wraps the SEND button in `url_bar.dart` (and the realtime
  send/connect control where applicable), passing the active tab's `isSending`.
- `ThemeReactionListener` wraps `MainScreen`'s body next to
  `ChainingWriteBackListener`.

## Effect catalog — per theme, scaled by personality

### 🗡️ ARCANE QUEST (the showpiece — loud)
- **Ambient** (enrich `_StarfieldPainter`): occasional **shooting star** streak;
  faint **constellation lines** briefly linking nearby motes then fading;
  **cursor parallax** (motes drift against the pointer via a `MouseRegion` →
  origin offset fed into the painter); drifting arcane embers.
- **Send ritual** (`sendAffordance`): a **spinning rune ring** materializes
  around SEND while `isSending`; press flares a glyph + the existing scale
  bounce.
- **Success (2xx/3xx):** golden **sparkle shower** + a gold **shimmer sweep**
  across the screen ("spell lands") + a soft radial bloom.
- **Client error (4xx):** amber **warning sigil** flash + micro-shake.
- **Server error (5xx) / network:** crimson **runic crack** flash + a short
  screen **shake** + a dark vignette pulse ("you took damage").
- **Cancelled:** a smoke-puff fizzle (spell dispelled).

### 💧 LIQUID GLASS (loud, elegant)
- **Ambient** (enrich `_GlassMeshPainter`): **pointer-following specular sheen**
  (a soft highlight tracking the cursor across the wallpaper) + slow caustics
  shimmer.
- **Send ritual:** a **liquid ripple** expands from SEND on press; a gentle
  liquid shimmer over the button while `isSending`.
- **Success:** a clean concentric **ripple** sweep + a soft frost-clear **bloom**
  in the accent.
- **Client error (4xx):** brief frost-fog tint + soft shake.
- **Server error (5xx) / network:** the glass **cracks** — a thin crack-line
  snaps in and **heals/dissolves** in ~600ms with a faint chromatic edge.
- **Cancelled:** the ripple **implodes**.

### 🟥 BRUTALIST (loud, impact — background stays flat by design)
- **Send ritual:** the button **STAMPS** — an exaggerated hard-offset slam onto
  its shadow on press.
- **Success:** a giant **"200" ink-stamp** thuds onto the screen, then fades;
  hard-shadow flash.
- **Error (4xx/5xx):** **glitch-shake** + RGB-split flash + a bold red **bar
  slam** showing the code.
- **Cancelled:** a muted "CANCELLED" stamp.
- No ambient background motion (on-brand: brutalism is impact, not drift).

### 📄 CLASSIC · ✒️ EDITORIAL · 🧛 DRACULA (calm — the contrast; no background motion)
- **All three:** a slim **status-colored pulse bar** along the top edge on send;
  **success** = a quick green pulse + check; **error** = a soft red pulse + a
  *tiny* shake. `sendAffordance` = a gentle press + a subtle progress shimmer
  while `isSending`.
- **Editorial:** a refined hairline ink sweep; success draws a quiet underline.
- **Dracula:** a touch of personality — success = a soft purple/green glow
  pulse; error = a brief blood-red drip at the top edge.

### ✨ Theme-switch transition (cross-cutting)
When `settings.themeId` changes, a brief **overlay sweep/dissolve** plays
(flashier for loud themes, a quick crossfade for calm). Self-contained: a
top-level widget keyed on `themeId` that plays a one-shot transition on change.
Respects `reduceVisualEffects` (instant cut when reduced — matching the existing
`themeAnimationDuration: Duration.zero` decision in `main.dart`).

## Accessibility, performance, settings

### Accessibility / `reduceVisualEffects` (existing master toggle)
- When on: `reactionOverlay` → identity (no shake, no cracks, no sparkle
  shower), `sendAffordance` → minimal (no rune ring / liquid shimmer), ambient
  enrichments off, theme-switch transition → instant cut.
- Screen shake is the most sensitive effect — it *only* ever runs with effects
  enabled, and is small in amplitude even then.
- Threaded through builders exactly like today (`reduceEffects` param into each
  theme builder; the `_themeDataCache` key already includes it).

### Performance discipline (reuse the proven patterns)
- Single `AnimationController` per ambient layer; `RepaintBoundary`; reused
  `Paint` objects; frame-quantization; `WidgetsBindingObserver` lifecycle pause
  (don't animate when the app is hidden) — mirror `_RpgAnimatedBackground` /
  `GlassWallpaper`.
- Transient reaction effects (sparkle shower, crack, stamp, ripple) spawn a
  short-lived controller that **disposes itself on completion** — exactly like
  `RpgSparkle`'s per-burst controllers.
- Cursor-reactive effects are pointer-only (`MouseRegion`), no-op on touch, and
  cost only a `ValueNotifier<Offset>` + a shader origin.
- Web/CanvasKit is a target: keep particle counts modest, prefer shaders/paints
  over per-frame widget trees, and lean on the `reduceVisualEffects` escape
  hatch.

### Settings
- **`enableThemeSounds`** — new `SettingsModel` field at **`HiveField(27)`**
  (default `false`; next free becomes 28). Mirrors the existing settings
  plumbing: field on model + entity, `copyWith`, `toEntity`/`fromEntity`,
  `fromJson`/`toJson`, regen `.g.dart`, a new `UpdateEnableThemeSounds` event
  (saves + emits), and a toggle on the **APPEARANCE** tab of the settings
  dialog.
- No new toggle for visuals — they ride the existing `reduceVisualEffects`.

### Sound layer
- A web-safe **`ThemeSoundService`** (interface + `io`/`stub` split, mirroring
  `update_gate.dart`) so web builds and platforms without an audio backend just
  no-op. Plays short one-shot SFX keyed by `(themeId, ThemeReaction)`.
- Package: **`audioplayers`** (broad desktop + web support). **Risk:** Linux
  needs the GStreamer runtime; the service is defensive (try/catch → silent
  no-op) so a missing backend never breaks the app. Gated entirely behind
  `enableThemeSounds` (off by default), so zero cost unless opted in.
- Assets: a handful of tiny royalty-free cues per loud theme (send / success /
  error) under `assets/sounds/<theme>/`, registered in `pubspec.yaml`. Calm
  themes reuse a single subtle tick/chime. Sourcing CC0/royalty-free audio is an
  implementation task; if unavailable at build time, the feature degrades to
  visuals-only (service no-ops) without blocking.
- The `ThemeReactionListener` (or a small sibling sound listener) triggers
  playback off the same reaction stream.

## File inventory

**New:**
- `lib/core/theme/extensions/app_motion.dart` — the `AppMotion` extension.
- `lib/core/theme/motion/theme_reaction.dart` — `ThemeReaction` value type.
- `lib/core/theme/motion/theme_reaction_controller.dart` — the controller.
- `lib/features/home/presentation/widgets/theme_reaction_listener.dart`.
- `lib/core/theme/motion/theme_switch_transition.dart` — the switch overlay.
- Per-theme motion files, e.g. `themes/rpg/rpg_motion.dart`,
  `themes/glass/glass_motion.dart`, `themes/brutalist/brutalist_motion.dart`,
  and a shared `themes/_shared/calm_motion.dart` for Classic/Editorial/Dracula.
- `lib/core/audio/theme_sound_service.dart` (+ `_io.dart` / `_stub.dart`).
- `assets/sounds/...` + tests under `test/`.

**Edited:**
- `extensions/app_theme_access.dart` — add `context.appMotion`.
- All six theme builders — attach an `AppMotion`; enrich `scaffoldBackground`
  painters for RPG + Glass (shooting stars, parallax, sheen).
- `theme_registry.dart` — no signature change (motion rides the existing
  builder params).
- `main.dart` — mount `reactionOverlay` + theme-switch transition; provide the
  controller; wire the sound service.
- `url_bar.dart` (+ realtime control) — wrap SEND in `sendAffordance`.
- `main_screen.dart` — mount `ThemeReactionListener`.
- `tabs_bloc.dart` / `tabs_state.dart` / `request_tab_entity.dart` — transient
  reaction signal (not persisted).
- Settings model/entity/bloc/dialog — `enableThemeSounds`.
- `injection_container.dart` — register controller + sound service.
- `pubspec.yaml` — `audioplayers` + sound assets.

## Phasing (one spec, three buildable slices)

1. **Spine + loud themes:** `AppMotion`, `ThemeReaction`, controller, listener,
   bloc reaction signal; `reactionOverlay` + `sendAffordance` for Arcane / Glass
   / Brutalist (send ritual, success, error, cancel). Ships the headline "wow."
2. **Calm themes + ambient:** Classic/Editorial/Dracula restrained overlays;
   ambient enrichments (shooting stars, constellations, cursor parallax/sheen);
   theme-switch transition.
3. **Sound:** `ThemeSoundService` (+ io/stub), `enableThemeSounds` setting +
   APPEARANCE toggle, assets, playback wiring.

## Testing

- **Bloc:** `tabs_bloc` sets the correct transient reaction for each terminal
  transition (success 2xx/3xx, 4xx, 5xx, network failure, cancel); signal resets
  on `LoadTabs`; not present in the persisted model.
- **Listener:** `ThemeReactionListener` fires each reaction into the controller
  exactly once per token, across multiple tabs, including a request finishing on
  a non-active tab (mirror the `ChainingWriteBackListener` tests).
- **Reduced effects:** with `reduceVisualEffects: true`, `reactionOverlay` and
  `sendAffordance` resolve to identity and no controller is created for shake.
- **Sound:** `ThemeSoundService` no-ops when `enableThemeSounds` is false and on
  web (stub); does not throw when the backend is missing.
- **Theme-switch transition:** plays once on `themeId` change; instant under
  reduced effects.
- Full static stack (`fvm flutter analyze`, `custom_lint`, `bloc_lint`),
  `dart format`, and `fvm flutter test` all green per the project done-bar.

## Wiki sync

Update the **Themes** page (reactive effects per theme + the calm/loud contrast)
and the **Settings** page (new "theme sounds" toggle; note that visual reactions
ride the existing "reduce visual effects" toggle). Keep UI labels verbatim.

## Out of scope (explicitly)

- Persisted gamification: XP, levels, achievements, streaks, counters.
- Per-effect granular settings (one master visual toggle + one sound toggle is
  the whole surface).
- Reactive effects localized to specific widget rects (response panel, etc.) —
  reaction effects are screen-level; only the send ritual is button-local.

## Open risks

- **Audio on Linux** (GStreamer dependency) — mitigated by a defensive,
  no-op-on-failure service and off-by-default gating; worst case the feature is
  visuals-only on a given machine.
- **Web performance** of richer particle/shader effects — mitigated by modest
  counts, paint-based rendering, and the `reduceVisualEffects` escape hatch.
- **Audio asset sourcing** (royalty-free cues) — Phase 3 degrades gracefully to
  visuals-only if assets aren't ready.
