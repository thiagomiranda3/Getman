# Pluggable Themes Architecture — Design Spec

**Date:** 2026-04-20
**Status:** Draft for review
**Scope:** Replace the monolithic `NeoBrutalistTheme` with a pluggable theme architecture that lets us add full aesthetic variants (e.g., a future editorial / newspaper theme) with no churn in widget code. Each theme continues to support light/dark and normal/compact variants. User selects a theme via Settings and switches live, identical to the current dark-mode / compact-mode pattern.

---

## 1. Goals & Non-Goals

**Goals**
- Every theme-owned knob (colors, fonts, shape radii, shadow style, tap-interaction behavior, method/status accent colors) is defined inside a single theme module and reachable from widgets through one uniform API.
- Adding a new theme is a single new file under `lib/core/theme/themes/<name>/` plus one line in the registry. No widget edits.
- The brutalist theme's current aesthetic is preserved pixel-for-pixel after migration.
- Theme is live-switchable through Settings, same mechanism as dark-mode / compact-mode today.
- No hardcoded colors, font sizes, font weights, or border radii leak out of the theme module.

**Non-Goals**
- The second theme (editorial) is not implemented in this change. Architecture only.
- No settings-UI picker is shipped in this change. A one-screen addition later will wire the existing `themeId` field to a dropdown. Out of scope here because there is nothing to pick between yet.
- No cross-theme lerp animations. Theme swaps are instant (as they are today for dark/compact).

---

## 2. Architecture

### 2.1 Access pattern
Widgets read theme data through a single `BuildContext` extension:

```dart
context.appLayout        // AppLayout      — sizes, paddings, borders
context.appPalette       // AppPalette     — method colors, status colors, extras not in ColorScheme
context.appShape         // AppShape       — panel/button/input/dialog radii
context.appTypography    // AppTypography  — TextTheme, code font family, weights
context.appDecoration    // AppDecoration  — panelBox / tabShape / wrapInteractive closures
```

All five are `ThemeExtension` subclasses attached to `ThemeData`. Widgets never import a concrete theme.

### 2.2 File layout

```
lib/core/theme/
  app_theme.dart               # The 5 ThemeExtension classes + AppThemeAccess BuildContext ext
  theme_ids.dart               # const kBrutalistThemeId = 'brutalist'
  theme_registry.dart          # AppThemeBuilder typedef + appThemes map + defaultThemeId + resolveTheme()
  themes/
    brutalist/
      brutalist_theme.dart     # ThemeData brutalistTheme(Brightness, {isCompact}) — composes the 5 extensions + ThemeData
      brutalist_palette.dart   # All Color(0x…) constants (background/surface/text/border L+D, primary/secondary L+D, method colors, status colors, lightGray)
      brutalist_decorations.dart # panelBox / tabShape free functions used by AppDecoration closures
      brutalist_bounce.dart    # BrutalBounce widget — private to this theme, used by wrapInteractive closure
```

The existing `lib/core/theme/neo_brutalist_theme.dart` and `lib/core/utils/status_color.dart` are deleted.

### 2.3 The five extensions

**`AppLayout`** — rename of today's `LayoutExtension`. Fields unchanged. Still exposes `normal` and `compact` constants. `copyWith` and `lerp` match the current behavior.

**`AppPalette`** — holds color data that does not fit in Flutter's `ColorScheme`.
- `Map<String, Color> methodColors` — keyed by HTTP method (uppercase). Helper `Color methodColor(String method)` returns the entry or a fallback (grey).
- `Color statusSuccess`, `statusWarning`, `statusError`, `statusAccentSuccess`, `statusAccentWarning`, `statusAccentError`. Helpers `statusColor(int code)` and `statusAccent(int code)` classify the HTTP status code into the three bands.
- `Color codeBackground`, `Color mutedHover` — ad-hoc neutrals used in a couple of places today as `Colors.black` / `Colors.white` overlays.
- `copyWith` passes through each field; `lerp` lerps colors and merges maps key-by-key.

**`AppShape`** — `double panelRadius, buttonRadius, inputRadius, dialogRadius`. Brutalist defaults: `panel=4, button=4, input=4, dialog=8` (matches today's hardcoded values). `lerp` is numeric.

**`AppTypography`** — `TextTheme base`, `String codeFontFamily`, `FontWeight displayWeight, titleWeight, bodyWeight`. The theme factory pulls `baseTextTheme` from e.g. `GoogleFonts.lexendTextTheme()`. `codeFontFamily` is consumed by `re_editor` usages. `lerp` uses `TextTheme.lerp` for `base` and snaps everything else to `other`.

**`AppDecoration`** — holds behavior as closures:

```dart
final BoxDecoration Function(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) panelBox;

final BoxDecoration Function(BuildContext context, {required bool active}) tabShape;

final Widget Function({
  required Widget child,
  VoidCallback? onTap,
  double scaleDown,
}) wrapInteractive;
```

`copyWith` swaps closures that are provided, keeps the others. `lerp` returns `this` — closures do not interpolate; on a theme swap Flutter simply installs the new set. This is acceptable because theme swaps are user-initiated and instant.

### 2.4 Theme builder signature

```dart
typedef AppThemeBuilder = ThemeData Function(Brightness brightness, {bool isCompact});
```

Each concrete theme exports one function matching that typedef, e.g. `ThemeData brutalistTheme(Brightness b, {bool isCompact = false})`. Internally it:
1. Picks palette/text colors by brightness.
2. Picks `AppLayout` based on `isCompact`.
3. Builds `AppPalette`, `AppShape`, `AppTypography`, `AppDecoration` — `AppDecoration`'s closures reference `brutalBox` / `brutalTab` / `BrutalBounce` from that theme's folder.
4. Builds `ThemeData` (Material component themes read shape radii from the `AppShape` values and font sizes/weights from `AppTypography` — no literals in the builder body).
5. Returns `theme.copyWith(extensions: [appLayout, appPalette, appShape, appTypography, appDecoration])`.

### 2.5 Registry and resolution

```dart
// theme_registry.dart
const String defaultThemeId = kBrutalistThemeId;

const Map<String, AppThemeBuilder> appThemes = {
  kBrutalistThemeId: brutalistTheme,
};

AppThemeBuilder resolveTheme(String? themeId) =>
    appThemes[themeId] ?? appThemes[defaultThemeId]!;
```

A user landing on an unknown `themeId` (future downgrade, typo, etc.) falls back to the default without crashing.

---

## 3. Runtime flow

### 3.1 Settings model / entity

`SettingsEntity` gains `String themeId` (default `'brutalist'`). `SettingsModel` (Hive `typeId: 0`) gains `@HiveField(7, defaultValue: 'brutalist') String themeId;`. **typeId is not renumbered; the new field gets a fresh index.** Existing users' Hive rows read back with `themeId == 'brutalist'` via `defaultValue`, so no migration is needed. `toJson` / `fromJson` / `fromEntity` / `toEntity` / `copyWith` all gain the new field.

`dart run build_runner build --delete-conflicting-outputs` regenerates `settings_model.g.dart`.

### 3.2 Settings BLoC

New event `UpdateThemeId(String themeId)`. Handler saves to repository and emits new state — identical to existing `UpdateIsDarkMode`, `UpdateIsCompactMode` handlers.

### 3.3 main.dart

Replace

```dart
theme: NeoBrutalistTheme.theme(Brightness.light, isCompact: settings.isCompactMode),
darkTheme: NeoBrutalistTheme.theme(Brightness.dark, isCompact: settings.isCompactMode),
```

with

```dart
final builder = resolveTheme(settings.themeId);
// ...
theme: builder(Brightness.light, isCompact: settings.isCompactMode),
darkTheme: builder(Brightness.dark, isCompact: settings.isCompactMode),
```

The existing `themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light` is unchanged. Live switching is automatic: `SettingsBloc` emits, `BlocBuilder<SettingsBloc, SettingsState>` rebuilds `MaterialApp` with the new theme.

The `import 'core/theme/neo_brutalist_theme.dart'` line is removed.

### 3.4 Settings picker UI
Deferred. Not part of this spec. Once a second theme exists, the picker is a single `DropdownButton` backed by `appThemes.keys` in the settings screen.

---

## 4. Widget migration

Every hardcoded value currently leaking out of the theme module is replaced:

| Current pattern                                           | Replacement                                                   |
|----------------------------------------------------------|---------------------------------------------------------------|
| `NeoBrutalistTheme.brutalBox(context, offset: N)`         | `context.appDecoration.panelBox(context, offset: N)`          |
| `NeoBrutalistTheme.brutalTab(context, active: x)`         | `context.appDecoration.tabShape(context, active: x)`          |
| `NeoBrutalistTheme.getMethodColor(m)`                     | `context.appPalette.methodColor(m)`                           |
| `StatusColor.forCode(c)` / `StatusColor.forCodeAccent(c)` | `context.appPalette.statusColor(c)` / `.statusAccent(c)`      |
| `BrutalBounce(onTap: ..., child: ...)` at widget level    | `context.appDecoration.wrapInteractive(child: ..., onTap: ...)` |
| `BorderRadius.circular(4)` / `(8)` in widgets             | `BorderRadius.circular(context.appShape.panelRadius)` etc.    |
| `theme.extension<LayoutExtension>()!`                     | `context.appLayout`                                            |
| Hardcoded `fontSize: 12 / 13 / 14 / 18 / 20` in widgets   | Corresponding `context.appLayout.fontSize*` field             |
| Hardcoded `FontWeight.w900 / w600 / bold` in widgets      | `context.appTypography.displayWeight / titleWeight / bodyWeight` |
| `Colors.black` used as "on-primary text" in widgets       | `Theme.of(context).colorScheme.onPrimary`                     |
| `Colors.white` used as "over-primary-badge text"          | Same (`onPrimary`) or `context.appPalette.codeBackground` etc. |
| `Colors.red` for delete icon                              | `Theme.of(context).colorScheme.error`                         |

Files touched:
- `lib/features/tabs/presentation/widgets/request_view.dart`
- `lib/features/home/presentation/widgets/side_menu.dart`
- `lib/features/home/presentation/screens/main_screen.dart`
- `lib/core/ui/widgets/method_badge.dart`
- `lib/core/ui/widgets/splitter.dart`
- `test/widget_test.dart`

If a hardcoded font size has no matching `AppLayout.fontSize*` field (e.g., 13, 18), we add a new field on `AppLayout` (e.g., `fontSizeCode`, `fontSizeHeaderLarge`) with brutalist normal + compact values. No widget keeps a raw number.

`BrutalBounce` is no longer imported outside `lib/core/theme/themes/brutalist/`. Its public API (widget constructor) is unchanged but its package path moves.

---

## 5. Testing

Scaled per component. Green `fvm flutter analyze` and `fvm flutter test` are hard gates.

### 5.1 Extension unit tests (`test/core/theme/`)
- `app_layout_test.dart` — `copyWith` preserves non-overridden fields; `lerp(other, t)` interpolates numerics and snaps booleans/ints (`isCompact`, `tabTitleMaxLength`) to `other`.
- `app_palette_test.dart` — `methodColor('GET'|'POST'|'PUT'|'DELETE'|'PATCH')` returns the expected brutalist colors; unknown method returns the fallback (grey). `statusColor(204|301|404|500)` returns success/warning/error. `statusAccent` likewise.
- `app_shape_test.dart` — `copyWith` / `lerp` numeric correctness.
- `app_typography_test.dart` — `copyWith` / `lerp` (using `TextTheme.lerp` for `base`).
- `app_decoration_test.dart` — `copyWith` swaps the closures that are provided and keeps the others; `lerp` returns `this`.

### 5.2 Brutalist theme composition test (`test/core/theme/themes/brutalist_theme_test.dart`)
- `brutalistTheme(Brightness.light)` returns a `ThemeData` with all five extensions non-null.
- Same for `Brightness.dark` and for `isCompact: true` (asserts compact layout values are in `AppLayout`).
- `panelBox(ctx)` returns a `BoxDecoration` whose `boxShadow` has `blurRadius: 0` and an offset matching `AppLayout.borderHeavy` — the brutalist signature. Guards against future regressions that might soften the shadow by accident.
- `wrapInteractive` returns a widget that scales on tap-down. Pump a widget, fire a `TapDownDetails` via `tester.tap(...)`, find a `ScaleTransition` descendant, confirm the scale value decreases (replaces any implicit `BrutalBounce` behavior test).

### 5.3 Registry + fallback (`test/core/theme/theme_registry_test.dart`)
- `appThemes[defaultThemeId]` is non-null.
- `resolveTheme(null)`, `resolveTheme('unknown')`, `resolveTheme('brutalist')` all return a usable builder (unknowns fall back to default without throwing).

### 5.4 Settings model migration (`test/features/settings/data/models/settings_model_test.dart`)
- `SettingsModel.fromEntity(const SettingsEntity())` → `themeId == 'brutalist'`.
- JSON roundtrip (`toJson` → `fromJson`) preserves `themeId`.
- Entity roundtrip (`toEntity` → `fromEntity`) preserves `themeId`.
- `copyWith(themeId: 'x')` produces a model with `themeId == 'x'` and leaves other fields intact.

### 5.5 Updated existing tests
- `test/widget_test.dart` — swap `NeoBrutalistTheme.theme(...)` for `appThemes[kBrutalistThemeId]!(...)`. Swap `NeoBrutalistTheme.getMethodColor('GET')` assertion for the equivalent via `context.appPalette.methodColor('GET')` reached through a small test harness widget.

### 5.6 Manual verification
After implementation:
1. `fvm flutter analyze` → `No issues found!`
2. `fvm flutter test` → 100% green.
3. `fvm flutter run -d macos`. With only the brutalist theme registered and `themeId` left at its default, the app must look identical to the pre-migration build. Specifically: toggle dark mode (visual parity), toggle compact mode (visual parity), send a request, open the side menu, open a dialog, drag a tab, tap buttons (bounce still present).

---

## 6. Migration plan (step order)

Each step is a self-contained commit; analyze + tests green at the end of each.

1. **Scaffold new theme module** — create the five extensions in `app_theme.dart`, `theme_ids.dart`, `theme_registry.dart`, then the whole `themes/brutalist/` folder porting palette / decorations / bounce / theme factory from the old file. Register brutalist in the map. Write §5.1 and §5.2 tests. Old `neo_brutalist_theme.dart` still exists and is still used — both builders coexist briefly.

2. **Settings plumbing** — add `themeId` to `SettingsEntity` + `SettingsModel` with `HiveField(7, defaultValue: 'brutalist')`. Regenerate Hive adapter via `build_runner`. Add `UpdateThemeId` event + handler. Write §5.3 and §5.4 tests.

3. **Swap `main.dart`** to use `resolveTheme(settings.themeId)`. Remove import of the old file. App still looks identical.

4. **Migrate widgets** — all six files in §4. Remove `LayoutExtension` import usages in favor of `context.appLayout`. Remove `NeoBrutalistTheme.*` static calls. Remove `StatusColor.*` calls. Replace widget-level `BrutalBounce` with `wrapInteractive`. Add any missing `AppLayout` font size fields that the widgets need (e.g. `fontSizeCode = 13`, `fontSizeHeaderLarge = 18`). Update `test/widget_test.dart`.

5. **Delete dead code** — remove `lib/core/theme/neo_brutalist_theme.dart` and `lib/core/utils/status_color.dart`. Grep for `NeoBrutalistTheme`, `LayoutExtension`, `StatusColor`, `BrutalBounce` (outside `lib/core/theme/themes/brutalist/`) — expect zero hits.

6. **Final verification** — `fvm flutter analyze` clean, `fvm flutter test` green, run macOS app and perform the §5.6 checklist.

---

## 7. Risks

- **Hive field addition** — guarded by `defaultValue: 'brutalist'` on `HiveField(7)`. Existing Hive rows read the default. Verified this pattern is the one CLAUDE.md mandates in §3.
- **Closures on `ThemeExtension`** — unusual but supported. `lerp` returns `this` for closure fields; numeric/Color fields interpolate normally. Because theme swaps are instant in Getman (no `AnimatedTheme` wrapping `MaterialApp`), this is fine.
- **Visual regression during widget migration** — the decorations (`brutalBox`, `brutalTab`) are moved verbatim as free functions; only their call site (a closure stored in `AppDecoration`) changes. Shape radii and font sizes are pulled from extensions built with the same numeric values as before. Net visual delta should be zero. Manual macOS verification (§5.6) is the backstop.
- **Missing font size fields** — a handful of widget-level `fontSize: 13 / 18` literals don't map 1:1 to current `LayoutExtension` fields. Step 4 adds fields rather than letting widgets keep literals; this is the whole point of the refactor.
- **`BrutalBounce` relocation + rewrite** — there are 12 widget-level `BrutalBounce(...)` call sites today: 6 in `request_view.dart`, 4 in `side_menu.dart`, 2 in `main_screen.dart`. Every one of those is rewritten to `context.appDecoration.wrapInteractive(child: ..., onTap: ...)` as part of step 4 of the migration plan. `BrutalBounce` itself becomes an implementation detail of the brutalist `wrapInteractive` closure: the class definition moves to `lib/core/theme/themes/brutalist/brutalist_bounce.dart` and is imported only by `brutalist_theme.dart`. After step 5, `BrutalBounce` must have zero references outside `lib/core/theme/themes/brutalist/`. This is the load-bearing part of the refactor — if we keep widgets calling `BrutalBounce(...)` directly, a future editorial theme cannot change tap behavior.
