# Theming — extensions, registry, component slots, motion

> Deep-dive for the theme system (the 8 `ThemeExtension`s, the theme registry, per-theme component slots, and motion). Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md. **When creating or changing a theme, read [`docs/THEME_AUTHORING.md`](../THEME_AUTHORING.md) first.**

## Resolution

The active `ThemeData` is produced by `resolveTheme(settings.themeId)(brightness, isCompact)` from `lib/core/theme/theme_registry.dart`. Seven themes are registered (`classic`, `brutalist`, `editorial`, `rpg`, `dracula`, `glass`, `auris`), each as a `ThemeDescriptor` (id + display name + builder). `classic` is the default for fresh installs.

## The theme extensions

Every theme builder attaches these base `ThemeExtension`s:

- **`AppLayout`** — sizes (`treeRowExtent`, split ratios, dialog widths, …).
- **`AppPalette`** — method/status colors + `codeBackground` + variable token colors (`variableResolved` / `variableUnresolved`).
- **`AppShape`** — panel/button/input/dialog/**sheet** radii (`sheetRadius` is the modal bottom-sheet top-corner radius).
- **`AppTypography`** — `TextTheme`, `codeFontFamily`, and three weights.
- **`AppDecoration`** — closures for `panelBox`, `tabShape`, `wrapInteractive`, `scaffoldBackground`.
- **`AppCopy`** (6th) — user-facing strings.
- **`AppMotion`** (7th) — collections-tree drag/drop motion hooks (`treeDragFeedback` / `treeDropHighlight` / `treeExpandFlourish`), plus optional animated `scaffoldBackground` ambient and a theme-switch transition.
- **`AppComponents`** (8th, `lib/core/theme/extensions/app_components.dart`, read via `context.appComponents`) — per-theme widget builders for slottable UI atoms: `surface / methodBadge / statusBadge / metric / toggle / logView / dataRow / select / pendingIndicator / statusBanner`.

## Component slots (`AppComponents`)

A shared `defaultAppComponents()` (`app_components_defaults.dart`) reproduces the standard rendering. **Every theme except Classic ships its own bespoke `<name>Components()` = `defaultAppComponents().copyWith(...)`** — it overrides the high-personality slots and inherits the rest (`select` is inherited everywhere, per VM-F2):

- **AURIS** composes the external `auris` sci-fi-HUD kit (`auris_components.dart`).
- **Brutalist** ink-press slabs/stamps/fanfold-log (`brutalist_components.dart`).
- **Arcane Quest** runic panels/gem badge/grimoire-log (`rpg_components.dart`).
- **Liquid Glass** frosted tiles/lozenges/liquid-switch (`glass_components.dart`).
- **Editorial** static magazine article-panels/typographic-tags/dispatch-log (`editorial_components.dart`).
- **Dracula** neon dev-console panels/capsules/REPL-log (`dracula_components.dart`).
- **Classic** stays on `defaultAppComponents()` by design (the calm native default).

Three rules apply to every bespoke set (learned from AURIS): `surface` must fill (it lives in an `Expanded`); `logView` sizes to a bounded height; `metric` is a compact inline chip (it sits in the metadata `Wrap`). Animated slots (rpg summoning-ring, glass ripple, dracula blinking-cursor) build the painter once + drive it via `CustomPainter(repaint:)` (no per-frame alloc) and degrade to static under `reduceEffects`. Each theme has a `<name>_components_test.dart` (per-slot smoke + ResponseSection/RealtimePanel overflow guards). Widgets consume slots uniformly — adding a theme needs no widget edits.

`AppDropdown<T>` (`core/ui/widgets/`) wraps the non-generic `select` slot; currently built but unwired (see BACKLOG VM-F2).

## Reading the theme from widgets

**Never hardcode sizes, colors, radii, weights, or interaction behavior in widgets.** Pull from the per-theme extensions via `BuildContext` accessors defined in `extension AppThemeAccess on BuildContext` (`lib/core/theme/app_theme.dart`): `context.appLayout`, `context.appPalette`, `context.appShape`, `context.appTypography`, `context.appDecoration` (and `context.appComponents`). If a value isn't in an extension, add a field to that extension rather than hardcoding.

### Colors

Method badges use `context.appPalette.methodColor(method)`; status-code bands use `context.appPalette.statusColor(code)` / `.statusAccent(code)`. Text on branded backgrounds (primary, method colors) → `Theme.of(context).colorScheme.onPrimary`. Error/destructive affordances → `colorScheme.error` / `colorScheme.onError`. Never use `Colors.black`/`Colors.red`/`Colors.white` literals for themeable surfaces (`avoid_hardcoded_brand_colors` enforces this); `Colors.white` is only acceptable as deliberate contrast on a variable-colored status badge.

### Typography

`context.appTypography.displayWeight` (brutalist = `w900`) for headlines/buttons/badges; `.titleWeight` (`w700` / `FontWeight.bold`) for titles and dialog actions; `.bodyWeight` (`w500`) for body text. Widget-specific weights that aren't display/title/body (e.g. a one-off `w600`) may stay as literals. Code editors read `context.appTypography.codeFontFamily` and `context.appPalette.codeBackground`.

### Decorations

- `context.appDecoration.panelBox(context, {color, borderWidth, offset, borderRadius})` — brutalist hard shadow / thick border panel.
- `context.appDecoration.tabShape(context, {required active, required hovered, required isFirst})` — per-tab chrome. All three flags are mandatory; `isFirst` drives the leftmost tab's extra left border.
- `context.appDecoration.wrapInteractive(child: …, onTap: …, scaleDown: …)` — tap animation wrapper; a single uniform `SubtlePress` (~1% scale + slight opacity dim) across all themes (`lib/core/theme/themes/shared/subtle_press.dart`). `BrutalBounce` no longer exists.

The brutalist theme intentionally makes a handful of Material component text sizes responsive to compact mode (buttons, dialog title, dialog content, app bar), marked with single-line comments in `brutalist_theme.dart` — don't "fix" them back to const without a design discussion.

## Shared chrome atoms

The filled-indicator tab strip is `BrandedTabBar` (`core/ui/widgets/`) — used by the request panel, unified phone panel, response panel, and side menu. Snackbars go through `showAppSnackBar(context, message)` — never construct styled `SnackBar`s inline (use `showAppSnackBarVia(messenger, …)` with a captured `ScaffoldMessenger` after an `await`/dialog dismissal). Irreversible actions confirm through `ConfirmDialog.show(...)`. `NamePromptDialog.show(...)` is the single-line text prompt (pass `allowEmpty: true` + `multiline: true` for clearable free-text).

## Motion

A theme also has a personality in motion. `AppMotion` carries the three collections-tree drag/drop hooks, plus an optional animated `scaffoldBackground` ambient and a theme-switch transition. There are **no** status-code reactions, send ritual, click ripple, tab/content transitions, or sound effects.

Surviving helpers in `lib/core/theme/motion/`: `ambient_signals.dart`, `theme_switch_transition.dart`, `workspace_pulse_controller.dart` (cursor parallax/idle breathing). Shared helpers in `lib/core/theme/themes/shared/`: `calm_motion.dart` + `subtle_press.dart`.

## Adding a theme

Mechanically: drop `<name>_theme.dart` (+ `<name>_palette.dart` / `<name>_decorations.dart` / `<name>_motion.dart`, and optionally `<name>_components.dart`) under `lib/core/theme/themes/<name>/`, export `ThemeData <name>Theme(Brightness, {bool isCompact, bool reduceEffects})` attaching all extensions (incl. `<name>Motion(reduceEffects:)` and either `defaultAppComponents()` or your own `<name>Components()`), and register a `ThemeDescriptor` in `theme_registry.dart`'s `appThemes` map with a new ID constant in `theme_ids.dart`. A theme may compose an external Material kit as its base `ThemeData` (AURIS composes `AurisTheme.dark()/.light()` and spreads `...base.extensions.values` so the kit's own extension survives `copyWith`). No widget edits are required. Full authoring guidance: [`docs/THEME_AUTHORING.md`](../THEME_AUTHORING.md).
