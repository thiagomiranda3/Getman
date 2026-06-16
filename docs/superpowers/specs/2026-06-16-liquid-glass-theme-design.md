# Liquid Glass theme + global visual-effects toggle — design

**Date:** 2026-06-16
**Status:** Approved design, pre-implementation
**Branch target:** `dev`

## 1. Goal

Add a fifth registered theme, **LIQUID GLASS** (id `glass`), that closely follows
Apple's Liquid Glass design language: translucent frosted surfaces with **real
backdrop blur**, generous corner rounding, hairline "specular" highlight edges,
soft ambient shadows, and the Apple system-blue accent. It ships a light "Clear"
variant and a dark "Smoked" variant in one theme (like every existing theme).

Because real blur is GPU-costly, the work also adds a **global, user-facing
"reduce visual effects" setting**. When effects are full (the default), the glass
theme frosts everything (panels, tree rows, tabs, overlays) and animates its
wallpaper; when reduced, it drops all `BackdropFilter`s and animation for a
cheap, still-glassy translucent look. The setting is intentionally global and
threaded into every theme builder so future work can gate effects/animations in
the other themes too (today it also gates RPG's animated background + sparkles).

## 2. Out of scope

- No new theme-authoring framework. This follows the existing
  `ThemeDescriptor` + five `ThemeExtension`s pattern exactly.
- No redesign of any other theme. Other builders accept the new flag but are
  visually unchanged in v1 except RPG (which gates its existing animations).
- No animated wallpapers for non-glass themes yet (future work, enabled by the
  threaded flag).

## 3. Architecture

### 3.1 The one new theme hook: `frost`

Panels today render as `Container(decoration: context.appDecoration.panelBox(...))`.
`panelBox` returns a `BoxDecoration`, which cannot host the `BackdropFilter`
*widget* that real frosting requires. So `AppDecoration` (`lib/core/theme/
extensions/app_decoration.dart`) gains one field:

```dart
typedef FrostWrapper =
    Widget Function(
      BuildContext context, {
      required Widget child,
      BorderRadius? borderRadius,
    });

// In AppDecoration: new field with a compile-time-constant identity default,
// so the four existing theme builders need ZERO edits and render identically.
final FrostWrapper frost;
// constructor: this.frost = _identityFrost
```

- **Default (`_identityFrost`)**: returns `child` unchanged — a top-level function
  used as the constructor default. Non-glass themes are byte-for-byte identical.
- **Glass (`glassFrost`)**: `ClipRRect(borderRadius ?? panelRadius) → BackdropFilter(
  ImageFilter.blur(kGlassBlurSigma)) → child`, where `child` is the existing
  translucent `panelBox` container. When the active theme is built in reduced
  mode, the glass builder installs `_identityFrost` instead, so coverage flips
  globally with no per-call-site logic.

Call sites wrap their existing container:

```dart
context.appDecoration.frost(
  context,
  borderRadius: BorderRadius.circular(context.appShape.panelRadius),
  child: Container(
    decoration: context.appDecoration.panelBox(context, offset: 0),
    child: <existing content>,
  ),
)
```

### 3.2 The global effects flag threaded through the theme builders

`AppThemeBuilder` and the builder signatures gain a named, defaulted param:

```dart
typedef AppThemeBuilder =
    ThemeData Function(Brightness brightness, {bool isCompact, bool reduceEffects});

ThemeData glassTheme(Brightness brightness,
    {bool isCompact = false, bool reduceEffects = false}) { ... }
```

`resolveThemeData` (`theme_registry.dart`) gains the param and a 4th cache-key
dimension `(resolvedId, brightness, isCompact, reduceEffects)`. The cache stays
bounded (~themes × 2 × 2 × 2); update the cache-size comment accordingly.

`main.dart` passes `reduceEffects: settings.reduceVisualEffects` into both the
light and dark `resolveThemeData` calls. The root
`BlocBuilder<SettingsBloc>`'s `buildWhen` adds `reduceVisualEffects` to its
existing gate (`themeId` / `isDarkMode` / `isCompactMode`) so a toggle rebuilds
`MaterialApp` but ordinary settings keystrokes still don't.

Defaulting the param to `false` keeps all existing builder/test call sites valid.

### 3.3 What the flag gates per theme (v1)

| Theme | Full effects (default) | Reduced |
|---|---|---|
| **glass** | `glassFrost` on every panel/row/tab/overlay; animated mesh wallpaper; scale+highlight press | `_identityFrost` (no `BackdropFilter`); static wallpaper; instant press. Still translucent over the wallpaper. |
| **rpg** | animated `rpgScaffoldBackground`; sparkle bursts in `RpgSparkle` | static background fallback; sparkle bursts disabled (cheap scale press kept) |
| brutalist / editorial / dracula | unchanged | unchanged (flag accepted, no-op in v1) |

RPG gating is internal to the RPG theme's own files: the builder installs a
static `scaffoldBackground` and a sparkle-disabled `wrapInteractive` when
`reduceEffects` is true (add an `animate`/`enableSparkles` flag to those rpg
widgets).

## 4. The new setting

Per the domain table in CLAUDE.md (§3), `SettingsModel`'s highest `HiveField`
is 21; **next free is 22**.

- `SettingsModel` (typeId 0, `settings` box): `bool reduceVisualEffects` at
  `@HiveField(22)`, mapped with `?? false` on read; `next free: 23`.
- `SettingsEntity`: `final bool reduceVisualEffects` (default `false`) +
  `copyWith` support.
- Model `toEntity`/`fromEntity`/`copyWith` carry the field.
- Run `dart run build_runner build --delete-conflicting-outputs` after the
  `@HiveField` change.

**Event + handler:** `UpdateReduceVisualEffects(bool value)` on `SettingsBloc`;
the handler saves and emits immediately (matching every other `Update*`, §4.5).
No `LoadSettings` change — boot already reads settings synchronously.

**Settings UI:** a switch in the Settings screen, e.g. label
**"REDUCE VISUAL EFFECTS"** with a one-line hint ("Disables backdrop blur &
animations for performance"). Dispatches `UpdateReduceVisualEffects`.

**Default:** `false` (full effects on every platform, per decision). Web users
who see stutter can switch it on.

## 5. The glass theme files

New self-contained directory `lib/core/theme/themes/glass/`:

- **`glass_palette.dart`** — all raw colors as static consts (light "Clear" +
  dark "Smoked" sets), mirroring `dracula_palette.dart`'s structure.
- **`glass_decorations.dart`** — `glassPanelBox` (translucent fill + hairline
  highlight border + soft shadow + inner top highlight), `glassTabShape`
  (translucent rounded pill, blue active fill), `glassScaffoldBackground`
  (mesh-gradient wallpaper widget; animated when effects full, static when
  reduced), `glassFrost` / `_identityFrost`, and the `kGlassBlurSigma` constant.
- **`glass_press.dart`** — `GlassPress` interactive wrapper: gentle scale-down
  (~0.98) + brief highlight; instant (no animation) when reduced.
- **`glass_theme.dart`** — `ThemeData glassTheme(Brightness, {isCompact,
  reduceEffects})` wiring all five (six incl. `AppCopy`) extensions, the
  `ColorScheme`, and the Material component themes (buttons/inputs/dialog/tabs/
  cards/list tiles), following `dracula_theme.dart` as the structural template.

Registration: `kGlassThemeId = 'glass'` in `theme_ids.dart`; a `ThemeDescriptor`
(`id: glass`, `displayName: 'LIQUID GLASS'`, `builder: glassTheme`) in
`theme_registry.dart`'s `appThemes` map.

### 5.1 Palette

- **Light "Clear":** wallpaper = soft blue→pink→mint pastel mesh; panel fill
  `white @ ~0.42`; text near-black; border `white @ ~0.7` hairline.
- **Dark "Smoked":** wallpaper = indigo→violet→teal deep mesh; panel fill
  `~#282A3A @ ~0.40`; text near-white; border `white @ ~0.14` hairline.
- **Accent:** Apple blue — `#007AFF` (light) / `#0A84FF` (dark).
- **Methods (Apple system colors):** GET `#34C759`, POST `#0A84FF`,
  PUT `#FF9F0A`, PATCH `#AF52DE`, DELETE `#FF3B30`; method fallback grey.
- **Status:** success green / warning orange / error red (system values);
  accents mirror them.
- **Variables:** resolved green / unresolved red, tuned for the translucent
  surface.
- **Code background:** translucent so the editor area reads as glass (the
  `re_editor` text paints on top; no `codeTheme` is set — colors come from
  `jsonHighlightSpanBuilder`, unchanged).

### 5.2 Shape (rounder than any existing theme)

`AppShape(panelRadius: 20, buttonRadius: 14, inputRadius: 14, dialogRadius: 24,
sheetRadius: 28)`.

### 5.3 Typography

Body font **Inter** (`GoogleFonts.interTextTheme()`) — closest free analogue to
Apple's SF; code font JetBrains Mono (unchanged). Weights: display `w700`, title
`w600`, body `w400`.

## 6. Surfaces routed through `frost`

Wrap these existing `panelBox` containers (and the easy custom overlays) in
`appDecoration.frost(...)`. With the identity default, all are no-ops for the
other four themes:

- `request_config_section.dart` (main request panel)
- `response_section.dart` (main response panel)
- `url_bar.dart` (URL toolbar)
- `unified_request_panel.dart` (phone unified panel)
- `realtime_panel.dart`
- `environments_dialog.dart` (panel inside the dialog)
- `variable_hover_popover.dart` (floating popover)
- `tab_widget.dart` (the floating tab **tooltip** popover — not the tab chrome,
  which is styled by `tabShape`)
- Custom overlay containers: `tab_switcher_sheet.dart`, `node_action_sheet.dart`,
  and the command palette.

NOTE (corrected from initial framing): the `panelBox` use in
`collection_node_row.dart` is the **drag-feedback chip** (solid `primaryColor`,
transient, one at a time) — frost would be invisible over an opaque fill, so it
is intentionally left unfrosted. There is no always-visible tree-row/tab
`panelBox` to worry about; the real tab chrome uses `tabShape` (a `BoxDecoration`,
not frostable). So all frosted sites are panels/floating overlays — no
"dozens-on-screen" cost. Frost is still globally gated: the glass builder
installs `_identityFrost` in reduced mode, so every site stops blurring at once
with no per-site branching.

Desktop `AlertDialog`s (built by Material via `DialogTheme`) get translucent
glass styling; where a dialog renders through `ResponsiveDialogScaffold` (a
shared `Scaffold`) the body shows the wallpaper. Real `BackdropFilter` blur on
the `AlertDialog` chrome itself is not attempted in v1 (Material builds its own
Material surface); this is a deliberate, documented limit.

## 7. Performance

- One tunable `kGlassBlurSigma`; moderate radius.
- `RepaintBoundary` around frosted, always-visible panels to isolate repaints.
- Animated wallpaper runs only when effects are full.
- The reduce-effects toggle is the user's escape hatch; default is full.
- Aligns with the existing perf-audit stance that theme blur is a known,
  accepted cost.

## 8. Testing

- **`glass_theme_test.dart`** (mirrors existing theme tests): builds light & dark
  × full & reduced; asserts all six extensions are present and the `ColorScheme`
  brightness matches; asserts `frost` is identity in reduced mode and wrapping in
  full mode; asserts `displayName`/registration resolves.
- **AppDecoration default test:** the `frost` default is identity (other themes
  unaffected) — guard against regressions.
- **Settings test:** `reduceVisualEffects` round-trips through
  `SettingsModel.toEntity`/`fromEntity`/`copyWith`; `UpdateReduceVisualEffects`
  saves + emits.
- **Existing theme tests** stay green (defaulted param keeps call sites valid).

## 9. Wiki (keep-in-sync mandate)

In the separate `Getman.wiki.git` repo: add **LIQUID GLASS** to the Themes page
(both variants, the Apple-blue accent, the frost), and document the new
**REDUCE VISUAL EFFECTS** setting on the Settings page (what it does, default).

## 10. Verification bar (done-definition)

All green before "done":

- `fvm flutter analyze` — 0 issues
- `fvm dart run custom_lint` — 0 issues (watch `avoid_hardcoded_brand_colors`:
  all glass colors live under `lib/core/theme/`, so literals are allowed there;
  `Colors.white`/`black` used as deliberate glass tints stay inside the theme
  package)
- `fvm dart run bloc_tools:bloc lint lib` — 0 issues
- `fvm dart format` clean
- `fvm flutter test` — 100% green
- `dart run build_runner build --delete-conflicting-outputs` run after the Hive
  field change

## 11. File-change summary

**New:**
- `lib/core/theme/themes/glass/glass_theme.dart`
- `lib/core/theme/themes/glass/glass_palette.dart`
- `lib/core/theme/themes/glass/glass_decorations.dart`
- `lib/core/theme/themes/glass/glass_press.dart`
- `test/core/theme/themes/glass_theme_test.dart` (alongside the existing
  `dracula_theme_test.dart` / `brutalist_theme_test.dart`)

**Edited (guarded / additive):**
- `lib/core/theme/theme_ids.dart` (+`kGlassThemeId`)
- `lib/core/theme/theme_registry.dart` (register descriptor; `reduceEffects`
  param + cache dimension; typedef)
- `lib/core/theme/extensions/app_decoration.dart` (+`frost` field, typedef,
  identity default)
- all five `*_theme.dart` builders (add `reduceEffects` named param; rpg gates
  its animations; others no-op)
- `lib/core/theme/themes/rpg/` (gate animated background + sparkles on the flag)
- `lib/main.dart` (pass `reduceEffects`; extend root `buildWhen`)
- `SettingsModel` + `SettingsEntity` + settings bloc/event + settings screen
  (the new toggle) + regenerated `*.g.dart`
- ~10 panel/overlay call sites (wrap in `frost`)
- Wiki: Themes + Settings pages
