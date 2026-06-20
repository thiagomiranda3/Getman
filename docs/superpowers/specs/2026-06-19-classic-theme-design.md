# CLASSIC theme — design

**Date:** 2026-06-19
**Status:** Approved (design), ready for implementation plan

## Motivation

User feedback: the existing themes (Brutalist, Editorial, Arcane Quest, Dracula,
Liquid Glass) are all "too contrast and unusual, like 90s websites." The user
prefers native-to-platform styling — the calm, conventional look of Postman /
Bruno / VS Code: traditional UI elements, not flashy or pretentious, **without
heavy borders and huge paddings**, and lower overall contrast.

This adds one new theme, **CLASSIC**, and makes it the app's default for fresh
installs. Existing users keep their persisted theme (only first-run changes).

## Design decisions (locked with user)

- **Accent:** muted indigo — `#6366F1` (light), `#818CF8` (dark, for legibility).
- **Default:** CLASSIC becomes the app default (`defaultThemeId` + the
  `SettingsEntity`/`SettingsModel` `themeId` defaults). Existing users unaffected
  (theme is persisted in the `settings` Hive box).
- **Picker name:** `CLASSIC` (uppercase display, like the other themes).
- **Panels:** flat fill + 1px hairline border **plus a very subtle soft shadow**
  so panels read as native cards (not wireframes, not hard offset shadows).
- **Error/DELETE red:** stays a real red (conventional, legible).

## Architecture fit

Themes are self-contained. Adding one requires **no widget edits**: the picker
(`settings_dialog.dart`) and command palette already iterate `appThemes`. A theme
is a folder under `lib/core/theme/themes/<name>/` whose builder returns a
`ThemeData` carrying six `ThemeExtension`s:

- `AppLayout` (sizes/padding/borders) — start from `AppLayout.normal`/`.compact`
  and `.copyWith(...)` to reduce density.
- `AppPalette` (method/status/variable/diff colors + `codeBackground` +
  `selectorActive`).
- `AppShape` (panel/button/input/dialog/sheet radii).
- `AppTypography` (`TextTheme` + `codeFontFamily` + display/title/body weights).
- `AppDecoration` (`panelBox`, `tabShape`, `wrapInteractive`,
  `scaffoldBackground`; optional `frost`, `brandedTabIndicator`).
- `AppCopy` (`emptyResponse`).

Builder signature must match `AppThemeBuilder`:
`ThemeData classicTheme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false})`.

## Files

New:
- `lib/core/theme/themes/classic/classic_palette.dart` — color constants.
- `lib/core/theme/themes/classic/classic_decorations.dart` — `classicPanelBox`,
  `classicTabShape`, `classicScaffoldBackground` (identity/plain color).
- `lib/core/theme/themes/classic/classic_press.dart` — `ClassicPress`
  (subtle press feedback, honors `reduceEffects`).
- `lib/core/theme/themes/classic/classic_theme.dart` — the builder.
- `test/core/theme/themes/classic_theme_test.dart` — smoke test (mirrors
  `glass_theme_test.dart`).

Edited:
- `lib/core/theme/theme_ids.dart` — add `kClassicThemeId = 'classic'`.
- `lib/core/theme/theme_registry.dart` — register descriptor +
  `defaultThemeId = kClassicThemeId`.
- `lib/features/settings/domain/entities/settings_entity.dart` — `themeId`
  default → `kClassicThemeId`.
- `lib/features/settings/data/models/settings_model.dart` — constructor default
  + `fromJson` fallback → `kClassicThemeId`.
- `lib/features/settings/data/models/settings_model.g.dart` — **regenerated** via
  `dart run build_runner build --delete-conflicting-outputs` (string default
  becomes `'classic'`).
- `test/features/settings/data/models/settings_model_test.dart` — flip the
  `default themeId is brutalist` assertion to `classic`.

## Palette

| Role | Light | Dark |
|---|---|---|
| scaffold/canvas | `#F6F7F9` | `#1B1C1F` |
| surface/panel/card | `#FFFFFF` | `#232428` |
| text primary (onSurface) | `#1F2328` | `#E6E7EA` |
| text secondary | `#656D76` | `#9AA0A6` |
| divider/border | `#D6DAE0` | `#34353A` |
| accent (primary) | `#6366F1` | `#818CF8` |
| codeBackground | `#F6F8FA` | `#1A1B1E` |
| hover | onSurface @ ~4% | onSurface @ ~6% |

Method colors (one map, both brightnesses; `onColor` chooses legible text →
passes `contrast_test.dart` automatically):
- GET `#2EA043`, POST `#D97706`, PUT `#2563EB`, PATCH `#0891B2`, DELETE `#DC2626`.

Status: success `#2EA043`, warning `#D97706`, error `#DC2626`. Status accents
(text-on-surface variants) = slightly darker: success `#1A7F37`, warning
`#B45309`, error `#B91C1C`. Variable resolved = status success; unresolved =
status error. Diff added = success fg + 12% bg; removed = error fg + 12% bg.
`selectorActive` = accent.

## Typography

- UI font: **Inter** for everything (`GoogleFonts.interTextTheme()`).
- Code font: **JetBrains Mono** (`GoogleFonts.jetBrainsMono().fontFamily`).
- Weights (the main calm-lever — no black, no wide-tracked all-caps):
  `displayWeight: w600`, `titleWeight: w600`, `bodyWeight: w400`. Label
  `letterSpacing` ≈ 0 (vs editorial's 2.4–2.8).
- No widget string changes (surgical): literal-uppercase labels stay but render
  in a normal weight without shouty tracking.

## Shape (radii)

`panelRadius: 6, buttonRadius: 6, inputRadius: 6, dialogRadius: 10, sheetRadius: 12`.

## Density (`AppLayout.copyWith`, applied to both normal & compact)

- `pagePadding 24→16`, `sectionSpacing 24→16`.
- `buttonPaddingHorizontal 24→16`, `buttonPaddingVertical 16→10`.
- `inputPadding 16→12`.
- `headerPaddingVertical 20→12`, `headerFontSize 24→18`.
- `tabBarHeight 60→44`.
- `cardOffset 6→0` (no hard offset shadow).
- Borders thinned to hairlines: `borderThin 2→1`, `borderThick 3→1.5`,
  `borderHeavy 4→2`.
- Compact variant: proportional equivalents (e.g. `pagePadding 12→10`,
  `tabBarHeight 40→36`, same hairline borders).

(Exact compact numbers finalized during implementation; intent = uniformly
calmer/tighter than the shared defaults while staying usable.)

## Decorations / interaction

- `classicPanelBox`: `color ?? surface` fill + 1px hairline border (divider
  color) + soft shadow (`black @4%` light / `black @25%` dark, blur 6, offset
  `(0,1)`); `borderRadius ?? panelRadius`. No hard brutalist offset.
- `classicTabShape`: active = surface fill + 2px indigo bottom indicator;
  hovered = subtle onSurface bg tint; inactive = transparent. No per-column
  heavy rules.
- `ClassicPress` (`wrapInteractive`): ~120ms subtle opacity dim on press
  (optional tiny scale to 0.99); honors `scaleDown`; when `reduceEffects` is
  true the theme wires a plain `GestureDetector` (no animation).
- `classicScaffoldBackground`: identity — plain scaffold color (no dot grid, no
  sparkles).
- `frost`: identity (default). `brandedTabIndicator`: default (solid indigo
  segment reads as a normal selected control).
- `AppCopy.emptyResponse`: `'No response yet.'`

## ThemeData base (mirrors editorial structure, calmer values)

- `useMaterial3: true`, brightness-driven `ColorScheme` (primary=accent,
  surface=panel, onSurface=text, error=DELETE red).
- `appBarTheme`/`dialogTheme`/`cardTheme`/`inputDecorationTheme`/`tabBarTheme`/
  button themes: hairline borders (1px), small radii, Inter labels at normal
  weight, indigo focus border on inputs.
- `switchTheme`: reuse `accentSwitchTheme(thumbWhenOn:…, trackWhenOn: accent)`.

## Out of scope (YAGNI)

- No new `ThemeExtension` fields (everything maps onto existing knobs).
- No OS-native widget adoption (Cupertino/Fluent) — "native" here means the calm
  conventional desktop-tool aesthetic, consistent with the app's single
  cross-platform `ThemeData`.
- No changes to other themes.

## Verification

- `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0),
  `fvm dart run bloc_tools:bloc lint lib` (0), `fvm dart format` clean,
  `fvm flutter test` 100% green.
- `contrast_test.dart` auto-covers CLASSIC (method + status legibility);
  `onColor` guarantees ≥4.58:1.
- New `classic_theme_test.dart`: builds usable `ThemeData` for both brightnesses;
  asserts all six extensions present.
- Manual run (`fvm flutter run -d macos`): verify both light & dark, switch from
  another theme and back, check panels/tabs/inputs/buttons read calm.

## Docs (mandate)

Update the GitHub wiki Themes/Appearance page (`Getman.wiki.git`): add CLASSIC to
the theme list and note it is the new default for fresh installs.
