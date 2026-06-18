# Settings dialog redesign — tabbed, wider, better spacing

**Date:** 2026-06-17
**Status:** Approved design, ready for plan
**Scope:** `lib/features/settings/presentation/widgets/settings_dialog.dart` +
one `AppLayout` field + test adjustments. No new settings, no behavior changes.

---

## Problem

The Settings dialog is one long `SingleChildScrollView` → `Column` of ~15
controls separated by `Divider`s and two text sub-headers (`NETWORK`,
`COLLECTIONS`). It is cramped (`dialogWidth` = 400 / 320 compact), forces
scrolling to reach network/cookies/workspace controls, and several text-entry
rows (proxy, key passphrase, the numeric trailing fields) sit flush against
their neighbours with no consistent vertical rhythm.

## Goals

1. **Tabs.** Split the controls into four tabs so each concern is a single
   screenful.
2. **Wider.** Grow the dialog so a label + control row has room to breathe.
3. **Spacing.** A consistent vertical rhythm; text fields no longer glued to
   adjacent rows.

## Non-goals (YAGNI)

- No new settings, no changed defaults/limits, no changed persistence.
- No theme-registry / `ThemeData` changes beyond a single new `AppLayout` size
  field.
- No new shared atom unless it earns its place; the tab panes are private to the
  settings file.
- `dialogWidth` (shared by other dialogs) is **not** widened.

---

## Design

### Tab structure

A horizontal `BrandedTabBar` (the app's signature filled-indicator tab strip)
across the top, driven by a `TabController`, over a `TabBarView` with one
scrollable pane per tab. Mapping is 1:1 with today's divider groups:

| Tab (label) | Controls (unchanged) |
|---|---|
| **GENERAL** (default) | History limit · Save response · Always prettify large responses · Response history (per tab) · Save large responses in history |
| **APPEARANCE** | Dark mode · Theme · Compact mode · Reduce visual effects |
| **NETWORK** | Connect / Send / Receive timeouts · Follow redirects · Max redirects · Verify SSL · Proxy · Client certificate (`ClientCertificateTile`) · Cookies (MANAGE / CLEAR) |
| **WORKSPACE** | Workspace folder (`WorkspaceSettingsTile`) |

GENERAL stays first so the existing history-limit E2E (which doesn't switch
tabs) keeps working.

The tab bar uses `tabKeyPrefix: 'settingstab'` so each tab gets a stable
`ValueKey('settingstab_tab_<LABEL>')` (mirrors `reqtab_*` / `resptab_*` /
`menutab_*`), and `isScrollable: true` (matching `unified_request_panel` and
`request_config_section`) so the four labels never clip on a narrow full-screen
phone and never trigger a RenderFlex overflow on resize.

### Width, height & the modal/fullscreen split

The dialog keeps rendering through the existing `ResponsiveDialogScaffold`
(unchanged): a centered `AlertDialog` when `context.isDialogFullscreen` is false
(viewport > 700 px), a full-screen `Scaffold` page when it's true (≤ 700 px).

- **New layout fields:** add `settingsDialogWidth` (`600` normal / `480`
  compact) and `settingsDialogHeight` (`520` normal / `440` compact) to
  `AppLayout` (`lib/core/theme/extensions/app_layout.dart`) — added to the
  constructor, both static consts (`normal`, `compact`), `copyWith`, and `lerp`.
  (All 5 themes consume `AppLayout.normal` / `.compact`, so this is a
  single-file change.) Keeping both sizes in `AppLayout` follows the existing
  `dialogWidth` / `quickListMaxHeight` precedent and the "no hardcoded sizes"
  mandate. `dialogWidth` (400/320) is left alone.
- **Pane bounding (the one structural subtlety).** `TabBarView` needs a bounded
  height. The settings content is:

  ```
  Column(
    children: [
      BrandedTabBar(controller, labels, isScrollable: true,
                    tabKeyPrefix: 'settingstab'),
      Expanded(child: TabBarView(controller, children: [ ...4 panes ])),
    ],
  )
  ```

  - **Full-screen branch:** the Scaffold body is height-bounded, so
    `Expanded` fills it directly. No fixed height.
  - **Modal branch:** `AlertDialog` content is *not* height-bounded, so the
    Column is wrapped in a `SizedBox(width: settingsDialogWidth)` +
    `ConstrainedBox(maxHeight: min(layout.settingsDialogHeight, screenHeight *
    0.7))`. The width is additionally clamped to the available width
    (`min(settingsDialogWidth, MediaQuery.sizeOf(context).width)`) so the
    700–760 px modal band can't overflow; `AlertDialog`'s own inset padding is
    the backstop. `settingsDialogHeight` is a soft target, always capped by the
    70%-of-screen clamp, so it never clips on short windows; each pane scrolls
    internally when the content is taller than the cap.

- **Flush tab bar:** pass `contentPadding: EdgeInsets.zero` to
  `ResponsiveDialogScaffold` so the filled tab strip spans edge-to-edge (modal
  and full-screen alike); each pane applies its own horizontal inset
  (`layout.pagePadding`) internally. This is what gives the redesign its
  consistent left margin without the `AlertDialog` default content padding
  fighting the tab bar.

### Responsive options reviewed (the second ask)

- **`isDialogFullscreen` threshold (≤ 700):** unchanged — the tabbed layout
  works in both branches.
- **compactPhone (≤ 500) full-screen:** `isScrollable: true` tab bar handles the
  four labels; panes scroll vertically. No new breakpoint logic.
- **Density (`isCompact`) vs viewport tier:** orthogonal, as today — width comes
  from the density-driven `AppLayout` (600/480); the modal-vs-fullscreen split
  comes from the viewport tier. Both are respected.
- **Resize while open:** transitioning modal → full-screen (and back) must not
  overflow. The `Expanded`/`SizedBox` split above is exactly what keeps the
  `TabBarView` bounded in each branch; covered by the extended `responsive_test`
  (below).
- **No change needed** to `responsive.dart`, `ResponsiveDialogScaffold`, or any
  other dialog's width.

### Spacing / visual rhythm

Introduce a private `_SettingRow` helper in the settings file that standardizes
every control row:

- Title (display/title weight from `context.appTypography`) with an optional
  leading icon and optional subtitle, on the left.
- A control that is either **trailing** (short numeric fields: history limit,
  response history, timeouts, max redirects) or **stacked below** (full-width
  text fields: proxy, key passphrase).
- Uniform vertical padding per row and `layout.sectionSpacing` between logical
  sub-groups within a pane; this removes the "glued together" feel and
  de-duplicates the repeated
  `TextStyle(fontSize: fontSizeNormal, fontWeight: titleWeight)`.
- Numeric field boxes widen slightly (≈ 96 px) now that there's horizontal room.

All sizes/paddings/colors continue to come from `context.appLayout` /
`appTypography` / `appPalette` — no hardcoded values (the two new sizes,
`settingsDialogWidth` and `settingsDialogHeight`, live in `AppLayout`).

### Code organization & state

- `_SettingsDialogState` keeps owning the seven `TextEditingController`s and
  gains a `TabController` (add `SingleTickerProviderStateMixin`; dispose it).
  Centralized init/dispose, no cursor-jump on bloc rebuilds, and tab state
  survives switches.
- Each tab body is a focused private builder (`_buildGeneral`,
  `_buildAppearance`, `_buildNetwork`, `_buildWorkspace`) or small private
  widget; `ClientCertificateTile` and `WorkspaceSettingsTile` are reused as-is.
- The root `BlocBuilder` (`buildWhen: settings != settings`) is unchanged;
  controllers living in state means rebuilds don't reset them.

### Keys preserved

Every existing `ValueKey` is kept verbatim: `history_limit_field`,
`response_history_limit_field`, `receive_timeout_field`, `theme_dropdown`,
`save_large_responses_switch`, `reduce_effects_switch`, `cookies_manage_button`.
New keys added: the four `settingstab_tab_*` tab keys.

---

## Testing

### New E2E support helper

Add to `integration_test/support/actions.dart`:

```dart
/// Taps a Settings dialog tab by its [label]
/// (`GENERAL`/`APPEARANCE`/`NETWORK`/`WORKSPACE`). Assumes Settings is open.
Future<void> openSettingsTab(PatrolTester $, String label) async {
  await $(ValueKey('settingstab_tab_$label')).tap();
  await slowMo($);
}
```

### Shared helpers to ADJUST (fixes many flows at once)

`integration_test/support/actions.dart`:

1. **`setTheme`** — taps `theme_dropdown`, now under APPEARANCE. Insert
   `await openSettingsTab($, 'APPEARANCE');` after `openSettings($)` and before
   tapping the dropdown. Fixes all 9 `theme_stress_test` calls.
2. **`toggleSettingRow`** — taps a label (`DARK MODE` / `COMPACT MODE` /
   `REDUCE VISUAL EFFECTS`), all under APPEARANCE. Insert
   `await openSettingsTab($, 'APPEARANCE');` after `openSettings($)`. (Every
   current caller targets an APPEARANCE row; if a future caller needs another
   tab, give the helper an optional `tab` param.)

### Flow tests to ADJUST

1. **`flows/settings_test.dart`**
   - *switches the active theme*: the dialog opens on GENERAL, so `theme_dropdown`
     / `BRUTALIST` aren't visible until APPEARANCE is selected. Add
     `await openSettingsTab($, 'APPEARANCE');` before the first `BRUTALIST`
     expectation.
   - *toggles dark mode*: add `await openSettingsTab($, 'APPEARANCE');` after
     `openSettings($)` (DARK MODE is on APPEARANCE).
2. **`flows/settings_network_test.dart`**
   - *history limit trims*: **no change** — `history_limit_field` is on the
     default GENERAL tab.
   - *receive timeout aborts*: add `await openSettingsTab($, 'NETWORK');` before
     entering `receive_timeout_field`.
3. **`flows/theme_stress_test.dart`**
   - *LIQUID GLASS reduce-effects toggled repeatedly*: after `openSettings($)`,
     add `await openSettingsTab($, 'APPEARANCE');` before tapping
     `reduce_effects_switch`. (The `setTheme` / `toggleSettingRow` calls in this
     file are fixed by the helper change above.)
4. **`flows/extras_test.dart`** (clear-cookies flow)
   - After `openSettings($)`, add `await openSettingsTab($, 'NETWORK');` before
     locating the cookies `CLEAR` button. Keep the existing `ensureVisible`
     (the NETWORK pane scrolls). The "LAST 'CLEAR' is the confirm button" logic
     is unaffected (no client cert set → no second CLEAR).
5. **`flows/cookies_test.dart`**
   - After `openSettings($)`, add `await openSettingsTab($, 'NETWORK');` before
     `ensureVisible(cookies_manage_button)`.
6. **`flows/responsive_test.dart`** (*resizing while a dialog is open*) — EXTEND:
   assert the tab bar/pane survive the modal→full-screen→modal resize without
   overflow. After opening Settings add
   `expect($(const ValueKey('settingstab_tab_GENERAL')), findsWidgets);`, and
   after the shrink-to-phone resize assert a GENERAL control is still visible
   (e.g. `history_limit_field`). The existing "no RenderFlex overflow fails the
   test" guard then covers the bounded-height transition.

### New flow test to CREATE

`integration_test/flows/settings_tabs_test.dart` — the core new behavior:

- **navigates settings tabs**: open Settings; assert all four tab keys exist
  (`settingstab_tab_GENERAL/APPEARANCE/NETWORK/WORKSPACE`); GENERAL is active →
  `history_limit_field` visible; tap APPEARANCE → `theme_dropdown` visible; tap
  NETWORK → `receive_timeout_field` + `cookies_manage_button` visible; tap
  WORKSPACE → `WORKSPACE` / `CHOOSE FOLDER` visible. Close.
- **switches tabs at phone width (full-screen)**: boot at 640×920 (full-screen
  dialog), open Settings, tap NETWORK, assert `VERIFY SSL` visible — proves the
  scrollable tab bar + bounded `TabBarView` work in the Scaffold branch.

Register the new flow in the aggregator
`integration_test/all_flows_test.dart`: add
`import 'flows/settings_tabs_test.dart' as settings_tabs;` and call
`settings_tabs.main();` inside its `main()` (next to the existing `settings` /
`settings_network` calls). `run_macos.sh` runs the aggregator and also accepts
the flow name directly (`bash integration_test/run_macos.sh settings_tabs`), so
no script change is needed. Add a bullet under "Covered" in
`integration_test/BACKLOG.md`.

### Existing unit/widget tests

No changes expected — `settings_bloc_test`, `settings_model_test`,
`settings_repository_impl_test`, and `network_settings_listener_test` don't touch
the dialog widget. (Confirm green; no settings events/entities change.)

---

## Verification bar

Before "done": `fvm flutter analyze` (0), `fvm dart run custom_lint` (0),
`fvm dart run bloc_tools:bloc lint lib` (0), `fvm dart format` clean,
`fvm flutter test` green, and the macOS E2E settings/theme/responsive/cookies
flows green. Wiki: the Settings page must be updated to describe the four tabs
(per the "Keep the wiki in sync" mandate — labels verbatim).
