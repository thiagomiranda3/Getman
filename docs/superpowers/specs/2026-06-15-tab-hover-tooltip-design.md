# Tab hover tooltip (name + URL) — design

**Date:** 2026-06-15
**Status:** Approved (pending spec review)
**Area:** `tabs` feature — tab strip chrome (`lib/features/home/presentation/widgets/tab_widget.dart`)

## Goal

When the user hovers the mouse over a tab in the tab strip and holds it there for a
brief moment, show a tooltip (Postman-style) containing:

- **Line 1 — name:** the tab's display title (the name saved in the collection when
  linked, otherwise `NEW REQUEST` / the URL fallback).
- **Line 2 — URL:** the request URL, in a lighter/muted color below the name.

The tooltip must appear only after a short delay (~500 ms) so it does not flash while
the pointer passes quickly across the tab strip.

## Background / current behavior

- `TabWidget` (`_TabWidgetState`) already wraps its chrome in a `MouseRegion` with
  `onEnter`/`onExit` that toggle `_isHovered` (drives the hovered tab decoration).
  There is no tooltip today.
- `tab.displayTitle` (extension `HttpRequestTabDisplay`) =
  `collectionName ?? (config.url.isEmpty ? 'NEW REQUEST' : config.url)`.
- The request URL is `tab.config.url`.
- There are **no** `Tooltip` widgets anywhere in the app. The app is strictly themed
  (brutalist / editorial / rpg / dracula) — colors, weights, radii, paddings come from
  the `context.appLayout` / `appPalette` / `appTypography` / `appDecoration` extensions,
  never hardcoded literals.
- There is a directly reusable pattern: `lib/core/ui/widgets/variable_hover_popover.dart`
  drives a themed hover card via an `OverlayEntry` + a hide `Timer`, uses
  `context.appDecoration.panelBox(context)` for its surface, a bounded
  `BoxConstraints(maxWidth: 320)`, and expresses a muted line as
  `theme.colorScheme.onSurface.withValues(alpha: 0.6)`.

## Decisions (resolved with the user)

1. **Unsaved tab content:** the tooltip's name line mirrors `displayTitle` exactly — for
   an unsaved tab that is `NEW REQUEST` (empty URL) or the URL itself. The URL line is
   `tab.config.url`, **omitted entirely when the URL is empty** (so a fresh
   `NEW REQUEST` tab shows a single line, no blank muted row).
2. **Appearance:** match the active app theme (panel chrome via `panelBox`), not a stock
   Material tooltip.
3. **Delay:** ~500 ms before the tooltip appears.

## Approach

A custom themed hover overlay implemented as a private helper inside `tab_widget.dart`
(tab-specific, so it is **not** promoted to `core/ui/widgets/`). It mirrors the
established `variable_hover_popover.dart` overlay/timer pattern.

Rejected alternative: stock Flutter `Tooltip` + `richMessage`. Less code and free
delay/positioning, but `Tooltip` has no max-width and cannot wrap a spaceless URL, so a
long URL renders an absurdly wide bubble unless the URL string is truncated — less
faithful to Postman and less themeable.

## Detailed behavior

### Trigger & timing

- Add to `_TabWidgetState`:
  - `Timer? _tooltipTimer;`
  - `OverlayEntry? _tooltipEntry;`
  - a file-level `const Duration _tabTooltipDelay = Duration(milliseconds: 500);`
    (durations are not part of the theme extensions; this matches the existing
    hardcoded `Duration`s already in this file — the 300 ms / 200 ms animations).
- `MouseRegion.onEnter`: keep setting `_isHovered = true`, and additionally start
  `_tooltipTimer = Timer(_tabTooltipDelay, () => _showTooltip(context, tab))`.
- `MouseRegion.onExit`: keep setting `_isHovered = false`, and additionally call
  `_hideTooltip()` (cancels the pending timer and removes the overlay entry).
- `GestureDetector.onTap` (the existing `widget.onTap` path) and the start of a
  context-menu / reorder drag: call `_hideTooltip()` so the card never lingers after a
  click or while dragging.
- `dispose()`: call `_hideTooltip()` before disposing the animation controller.
- Re-entrancy: `_showTooltip` is a no-op if `!mounted` or an entry already exists;
  `_hideTooltip` cancels the timer, removes + disposes any entry, and nulls both fields.

### Positioning

- In `_showTooltip`, resolve the tab's `RenderBox` (via the `State`'s `context`) to get
  its global top-left and size; convert into the `Overlay`'s coordinate space (mirroring
  `VariableHoverController`).
- Place the card just below the tab: `top = tabBottom + small gap`,
  `left = tabLeft`, clamped so the `maxWidth` card + a gutter stays on-screen at the
  right edge (same clamp shape as `VariableHoverController`).

### Content & styling

A `Material(type: transparency)` → `Container` with:

- `decoration: context.appDecoration.panelBox(context)`
- `constraints: const BoxConstraints(maxWidth: 360)`
- `padding`: `EdgeInsets.all(layout.isCompact ? 8 : 12)` (matching the hover popover)
- a `Column(mainAxisSize: min, crossAxisAlignment: start)` containing:
  - **Name** — `Text(tab.displayTitle, maxLines: 1, overflow: ellipsis)` styled with
    `fontWeight: context.appTypography.titleWeight`, `fontSize: layout.fontSizeNormal`,
    `color: theme.colorScheme.onSurface`.
  - **URL** — only if `tab.config.url.isNotEmpty`: a `SizedBox(height: layout.tabSpacing)`
    then `Text(tab.config.url, maxLines: 2, overflow: ellipsis)` styled with
    `fontSize: layout.fontSizeSmall`,
    `color: theme.colorScheme.onSurface.withValues(alpha: 0.6)`.

No hardcoded sizes/colors/weights — all pulled from the theme extensions, matching the
mandate and the `variable_hover_popover.dart` precedent.

### Accessibility

Wrap the tab's interactive child in `Semantics(tooltip: <name + url string>, …)` so the
information is still announced to screen readers even though the visual card is a custom
overlay rather than a stock `Tooltip`.

## Out of scope

- No change to the phone/unified tab chip or the tab switcher sheet — desktop tab strip
  only (where a mouse hover exists).
- No new theme-extension field (delay stays a local const; no design discussion needed
  to add a `Duration` to `AppLayout`).

## Verification

- `fvm flutter analyze` — 0 issues
- `fvm dart run custom_lint` — 0 issues (watch `avoid_hardcoded_brand_colors`)
- `fvm dart run bloc_tools:bloc lint lib` — 0 issues
- `fvm dart format` clean
- `fvm flutter test` — green; add/adjust a `TabWidget` widget test that pumps a hover,
  advances past the delay, and asserts the name + URL render (and that the URL line is
  absent for an empty-URL tab).

## Follow-up

- Update the GitHub wiki **Tabs** page to mention the hover tooltip (name + URL), per the
  "Keep the wiki in sync" mandate. (Separate `Getman.wiki.git` repo.)
