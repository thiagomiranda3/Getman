# Glass-theme frosted-card dialog blur

**Status:** Design approved (2026-06-24) — ready for implementation planning.
**Branch:** `fix/glass-modal-opacity` (off `master`).

## Problem

In the Liquid Glass theme, modal dialogs (e.g. Settings) render with a far-too-
transparent background. The dialog surface uses the theme's `panel` color
(`GlassPalette.panelLight = 0x6BFFFFFF` ≈ white 42%, `panelDark = 0x66282A3A` ≈
charcoal 40%). That translucency is designed for **in-app panels that sit on a
real backdrop blur**; a plain Material `AlertDialog` has **no blur**, so the
~40% panel reads as see-through over the animated wallpaper, hurting legibility.

## Goal

Give glass-theme dialogs a **frosted-card** look: a real backdrop blur clipped to
the dialog's rounded rectangle, with the existing ~40% translucent panel painted
on top. The panel opacity stays unchanged — the blur (not opacity) restores
readability. Non-glass themes and all existing dialog call sites are unaffected.

## Locked decisions (from brainstorming)

1. **Blur style:** frosted **card** — blur clipped to the dialog card only; the
   rest of the screen keeps the current dim barrier. (Not a whole-screen blur.)
2. **Panel opacity:** **unchanged (~40%)** — readability comes from the blur.
3. **Scope:** glass theme **dialogs** only. Modal bottom sheets are out of scope.

## Architecture

The blur is driven by a new per-theme hook so only glass opts in; every other
theme's dialog path is byte-for-byte unchanged (lowest regression risk).

```
ResponsiveDialogScaffold (shared chokepoint: settings, export, confirm, name-prompt)
  ├─ fullscreen branch → unchanged (Scaffold page)
  └─ centered branch:
       dialogSurface != null ?  → frosted card (glass, full effects)
                              :  → AlertDialog (all other themes; glass reduceEffects)
```

### New hook on `AppDecoration`

`lib/core/theme/extensions/app_decoration.dart`:

```dart
/// Per-theme frosted dialog surface. When non-null, ResponsiveDialogScaffold
/// renders the centered dialog as a custom card built from this (clip + blur +
/// translucent fill), instead of a plain AlertDialog. Null for themes that use
/// an opaque dialog (every theme except glass at full effects).
final Widget Function(
  BuildContext context, {
  required Widget child,
  required BorderRadius borderRadius,
})? dialogSurface;
```

- Defaults to `null` (added to the const constructor + `copyWith`, mirroring the
  existing nullable `brandedTabIndicator` hook).
- `dialogSurface` owns clip + blur + translucent fill + hairline border, so the
  fill color (`panel`) stays inside the glass theme where it's defined — the
  shared widget never needs the glass panel color.

### Glass theme wiring

`lib/core/theme/themes/glass/`:

- New builder `glassDialogSurface(context, {required child, required borderRadius})`
  in `glass_decorations.dart`: `ClipRRect(borderRadius)` → `BackdropFilter`
  (`ImageFilter.blur(kGlassBlurSigma, kGlassBlurSigma)`) → `Container`
  (translucent `panel` fill + `border` hairline) → `child`. Reuses the existing
  `kGlassBlurSigma`.
- `glass_theme.dart`: assign `dialogSurface: reduceEffects ? null :
  glassDialogSurface` on the `AppDecoration` (alongside the existing
  `frost`/`brandedTabIndicator` assignment).
- New opaque dialog color in `GlassPalette` (`dialogLight`/`dialogDark`, full
  alpha — a solid frost tint, e.g. `panel` blended over the wallpaper base) used
  as `dialogTheme.backgroundColor`. This is the **reduceEffects fallback**: with
  no blur, the AlertDialog path needs a readable opaque background. (Also a safe
  default for any direct `AlertDialog` not routed through ResponsiveDialogScaffold.)

### `ResponsiveDialogScaffold` change

`lib/core/ui/widgets/responsive_dialog.dart`, centered (`!isDialogFullscreen`)
branch only:

```dart
final surface = context.appDecoration.dialogSurface;
if (surface == null) {
  return AlertDialog(...);   // unchanged — all non-glass themes + glass reduceEffects
}
// Frosted-card path (glass, full effects): reuse the base Dialog widget for
// identical centering / inset / min-width sizing to AlertDialog, but transparent
// so our frosted surface is the only visible card.
return Dialog(
  backgroundColor: Colors.transparent,
  elevation: 0,
  child: surface(
    context,
    borderRadius: BorderRadius.circular(context.appShape.dialogRadius),
    child: _DialogBody(title: title, content: content, actions: actions,
                        contentPadding: contentPadding),
  ),
);
```

Using the base `Dialog` (not a hand-rolled `Center`/`Padding`/`ConstrainedBox`)
inherits `AlertDialog`'s default `insetPadding`
(`EdgeInsets.symmetric(horizontal: 40, vertical: 24)`) and min-width, so card
width/placement matches the `AlertDialog` path with no magic numbers.

`_DialogBody` (private to `responsive_dialog.dart`) reproduces `AlertDialog`'s
structure so content doesn't reflow: a `Column` of `title` →
`Flexible(SingleChildScrollView(content))` → an `actions` `Row`, with
title/content/action paddings from `AppLayout` / the passed `contentPadding`.
The content is scrollable so tall dialogs (settings) behave like `AlertDialog`.

## Degradation (reduceEffects)

| State | Dialog surface | Background |
|---|---|---|
| Glass, full effects | frosted card (`dialogSurface`) | translucent `panel` (~40%) + blur |
| Glass, reduceEffects | `AlertDialog` (hook null) | opaque `dialog*` color, no blur |
| Non-glass (any) | `AlertDialog` (hook null) | each theme's existing opaque color |

## Testing

`test/core/theme/themes/glass_theme_test.dart` + `responsive_dialog` widget test:

- `glassTheme(full).extension<AppDecoration>()!.dialogSurface` is non-null;
  `glassTheme(reduceEffects: true)` → null; every non-glass theme → null.
- Glass full effects: pumping a `ResponsiveDialogScaffold` (non-fullscreen)
  renders a `BackdropFilter` behind the card.
- Glass reduceEffects: no `BackdropFilter`; an `AlertDialog` is present and its
  resolved background color has full/near-full alpha (the opaque `dialog*` color).
- Non-glass (brutalist): `ResponsiveDialogScaffold` still returns a plain
  `AlertDialog`, no `BackdropFilter` — regression guard.
- `GlassPalette.dialogLight`/`dialogDark` alpha is `0xFF` (or ≥ ~`0xF0`).
- Full gate: `fvm flutter analyze`, `fvm dart run custom_lint`,
  `fvm dart run bloc_tools:bloc lint lib` all 0; `fvm dart format` clean;
  `fvm flutter test` green.

## Out of scope

- Modal **bottom sheets** (action sheets, tab switcher) — same translucency,
  separate follow-up.
- Whole-screen backdrop blur (the rejected brainstorm alternative).
- Any change to non-glass themes or to panel opacity.

## Global constraints

- `fvm` for all Flutter/Dart commands.
- No hardcoded sizes/colors/radii in widgets beyond the documented AlertDialog-
  default inset; pull radius/paddings from `context.appShape`/`context.appLayout`.
- `package:getman/...` imports only.
- Heavy effects must degrade to identity/opaque under `reduceEffects`.
