# Tone Down Theme Effects — Design

**Date:** 2026-06-23
**Status:** Approved (design); pending spec review → implementation plan
**Branch target:** `dev`

## Goal

Make Getman feel **professional and calm** by heavily reducing the theme
"juice". Remove every sound effect, all status-code reaction effects (screen
shake, RPG star-shower, stamp slams, pulse bars), the per-click background
"water ripple", the request-viewer swap transition, the SEND ritual, the
in-flight panel frame, and tab open/close transitions. Tame the button
press to a single subtle effect. **Keep** the autonomous background motion
(moving stars, AURIS HUD, Brutalist halftone, Liquid Glass frost/blur),
collections-tree drag/drop juice, and the theme-switch crossfade.

This is **Approach 2 (surgical removal)**: delete the loud effects *and* their
now-orphaned supporting code, rather than leaving a dormant subsystem behind.

## Scope

### A. Remove — Sounds (entirely)

- Delete `lib/core/audio/theme_sound_service.dart` and
  `lib/core/audio/theme_sound_service_audioplayers.dart` (the whole `audio/`
  dir).
- Remove the `audioplayers` dependency from `pubspec.yaml` and the
  `assets/sounds/` asset declaration + directory.
- Remove the DI registration of `ThemeSoundService`
  (`injection_container.dart`) and any `RepositoryProvider`/wiring in
  `main.dart`.
- Remove the **THEME SOUNDS** toggle from `settings_dialog.dart` and the
  `enableThemeSounds` field everywhere: `SettingsEntity`, `SettingsModel`
  (`@HiveField(27)`), `UpdateEnableThemeSounds` event + bloc handler.
  Regenerate Hive (`fvm dart run build_runner build --delete-conflicting-outputs`).

### B. Remove — Status-code reactions + the whole reaction spine

The app-wide `reactionOverlay` (Brutalist status-stamp + screen-shake, RPG
star-shower, calm pulse-bar, etc.) is removed. With it gone, its entire
supporting spine is dead code and is deleted:

- `lib/core/theme/motion/theme_reaction_controller.dart` (`ThemeReactionController`)
- `lib/core/theme/motion/reaction_stage.dart` (`ReactionStage`)
- `lib/core/theme/motion/status_reaction_flavor.dart` (`flavorFor`, `StatusReactionFlavor`)
- `lib/core/theme/motion/latency_weight.dart` (`latencyWeight`, `inFlightTension`)
- `lib/core/theme/motion/photosensitivity.dart` (`safeFlashCount`, `kMaxSafeFlashesPerSecond`)
- `lib/core/theme/motion/theme_reaction.dart` (`ThemeReaction`, `ThemeReactionKind`, `TransportFailureKind`)
- `lib/features/home/presentation/widgets/theme_reaction_listener.dart` (`ThemeReactionListener`)
- In `TabsBloc` / `TabsState`: `reactionSeq`, `lastReaction`, `_fireReaction`,
  `_transportFailureFor`, `ThemeReaction.kindForStatus` usage, and all 5
  `_fireReaction(...)` call sites. Remove the `reactionOverlay(...)` wrap and
  the `ThemeReactionController` provider/DI registration in `main.dart`.

(These helpers are confirmed to be consumed **only** by the removed effects —
verified by repo-wide grep.)

### C. Remove — Per-click background "water ripple"

In each animated background (`brutalist_ambient.dart`, `auris_ambient.dart`,
`glass_decorations.dart`, `rpg_decorations.dart`):

- Drop the click-ripple `AmbientImpulse` mechanism: the `_impulses`
  `ValueNotifier`, the `_addImpulse` impulse seeding, the `onPointerDown`
  ripple seed, and the impulse-rendering loop in each painter. Remove the
  `impulses` field from `AmbientSignals` and `AmbientImpulse` itself
  (`ambient_signals.dart`).
- **Keep** `onPointerDown` calling `_pulse?.touch()` (presence/idle reset) so
  the background still "wakes" on interaction.
- **Keep** the autonomous drift ticker, the cursor-parallax `pointer`
  `MouseRegion`, and the `WorkspacePulseController` idle breathing.

### D. Remove — SEND ritual + in-flight frame

- Remove `sendAffordance` (themed SEND charging ritual) from every theme + the
  call site in `url_bar.dart`. The SEND button keeps its **existing
  `CircularProgressIndicator`** + the send↔cancel `AnimatedSwitcher`.
- Remove `inFlightFrame` (themed border around the request/response panel)
  from every theme + the call site in `request_view.dart`.

### E. Remove — Tab open/close transition

- Remove `tabChipTransition` from every theme + the call site in
  `main_screen.dart` (`_TabChipEntrance`).

### F. Remove — Request-viewer swap transition

- Remove `contentTransition` from every theme + the call site in
  `tab_content_stack.dart`.

### G. Tame — Button press/bounce → uniform subtle press

- `wrapInteractive` becomes a single **subtle** press across **all** themes:
  ~1% scale-down + a slight opacity dim on tap (the existing `ClassicPress`
  behavior). The pronounced Brutalist 5% bounce is removed.
- Promote `ClassicPress` to a shared widget (e.g.
  `lib/core/theme/themes/shared/subtle_press.dart`) and point every theme's
  `wrapInteractive` at it. Delete `brutalist_bounce.dart` (`BrutalBounce`).
- `wrapInteractive` must still forward `onTap`/`scaleDown` so all ~32 call
  sites are unaffected behaviorally.

### H. Remove — REDUCE VISUAL EFFECTS setting

- Remove the **REDUCE VISUAL EFFECTS** toggle from `settings_dialog.dart`,
  the `reduceVisualEffects` field (`SettingsEntity`, `SettingsModel`
  `@HiveField(22)`), and `UpdateReduceVisualEffects` event + handler.
- **Keep** the `reduceEffects` *parameter* plumbed through `resolveThemeData`
  → theme builders / ambient widgets (avoids a 7-theme + ~40-test signature
  refactor). Hardwire it to `false` at the single call site in `main.dart`
  so backgrounds stay animated. This dormant-but-`false` param is a deliberate
  choice; the static-ambient code path and its tests remain valid.

### Behavioral change — response stays visible during re-send

`response_section.dart` currently returns `pendingIndicator(context)` whenever
`tab.isSending`. Change to gate on **no previous response**:

```dart
final response = tab.response;
if (tab.isSending && response == null) {
  return context.appComponents.pendingIndicator(context); // empty → loading OK
}
if (response == null) { /* empty state */ }
return Column(/* previous/current response stays visible */);
```

So a re-send keeps the prior response on screen; the only in-flight cue is the
SEND-button spinner. When there is **no** prior response, the themed
`pendingIndicator` still shows (per user confirmation).

## What is KEPT (explicitly)

- Autonomous ambient backgrounds: moving stars (RPG/AURIS), Brutalist
  halftone, AURIS HUD sweep, Liquid Glass frost/blur — animated (reduceEffects
  hardwired `false`).
- Cursor-parallax `pointer` signal + `WorkspacePulse` presence/idle breathing
  (decoupled from request outcomes — `bump()` removed, `touch()` kept).
- Collections-tree drag/drop juice (`treeDragFeedback`, `treeDropHighlight`,
  `treeExpandFlourish`).
- Theme-switch crossfade (`ThemeSwitchTransition`).
- SEND-button spinner + send↔cancel switcher.

## Per-theme motion files

Each `<name>_motion.dart` (`brutalist`, `rpg`, `glass`, `auris`) is reduced to
**only** the three tree-juice hooks; the calm builder (`calm_motion.dart`,
used by `classic`/`editorial`/`dracula`) sets no hooks at all and returns
`const AppMotion()`. Delete the now-unused private widgets/painters/specs
(`_*ReactionOverlay`, `_*Send`, `_*InFlightFrame`, `_*ContentTransition`,
chip-entrance builders, `StampSpec`/`stampSpecFor`, `CalmSpec`/`calmSpecFor`,
etc.).

`AppMotion` keeps `reactionOverlay`/`sendAffordance`/`inFlightFrame`/
`contentTransition`/`tabChipTransition` as identity-default fields **or** they
are removed from the extension. Decision: **remove these five fields from
`AppMotion`** along with their identity defaults and call sites, since nothing
sets them anymore (cleaner extension). Keep the three tree-juice fields.

## Data model / Hive

- `SettingsModel`: remove `@HiveField(22) reduceVisualEffects` and
  `@HiveField(27) enableThemeSounds`. **Do not reuse field numbers 22 or 27.**
  Next free HiveField stays **28**. Regenerate `settings_model.g.dart`.
- Old persisted settings with fields 22/27 are ignored on read (Hive tolerates
  unknown fields); fresh writes omit them. No migration needed.

## Testing

- Delete/trim tests for removed subsystems: `*_motion_test.dart` reaction
  assertions, reaction-spine unit tests (`status_reaction_flavor`,
  `latency_weight`, `photosensitivity`, `reaction_stage`,
  `theme_reaction_controller`, `theme_reaction`), sound-service tests,
  `theme_reaction_listener` tests, and `<name>_components_test.dart` only where
  they assert removed motion.
- Update `tabs_bloc`/`tabs_state` tests that assert `reactionSeq`/`lastReaction`.
- Update `settings` tests/dialog tests for the two removed toggles + fields.
- Add/keep: `response_section` test proving a prior response stays visible while
  `isSending` (and that the empty case still shows `pendingIndicator`); a
  `wrapInteractive` test proving the subtle (non-bounce) press; ambient tests
  proving **no** click ripple is seeded but drift/`touch()` still run.
- Full done-bar: `fvm flutter analyze`, `fvm dart run custom_lint`,
  `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format`, `fvm flutter test`
  all clean/green.

## Docs

- **Wiki sync** (mandate): update the Settings page (drop THEME SOUNDS +
  REDUCE VISUAL EFFECTS) and the Themes/motion page (sounds removed; reactions,
  click ripple, send ritual, tab/content transitions, button bounce removed;
  backgrounds + tree juice + theme-switch retained).
- Update `CLAUDE.md` §3 (settings HiveField table: drop 22 & 27, note next
  free 28), the §1 stack bullet (remove `audioplayers`), §2 `updates`/audio
  references, the §4.8 theming/motion notes, and `docs/THEME_AUTHORING.md`
  (remove the reactive-motion checklist sections that no longer apply; note the
  surviving hooks).

## Risks / non-goals

- **Risk:** broad test churn across theme/motion/settings/bloc suites — the
  done-bar gate is the net.
- **Risk:** `AppMotion` field removal touches every theme builder + the call
  sites in `main.dart`/`url_bar.dart`/`request_view.dart`/`main_screen.dart`/
  `tab_content_stack.dart`.
- **Non-goal:** removing tree-drag juice, the theme-switch crossfade, cursor
  parallax, or the ambient backgrounds (explicitly kept).
- **Non-goal:** removing the `reduceEffects` parameter plumbing (kept dormant,
  hardwired `false`).
```
