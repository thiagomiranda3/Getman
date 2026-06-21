# AURIS theme + per-theme component-slot system — Design

**Date:** 2026-06-20
**Status:** Approved (brainstorming) — ready for implementation plan
**Branch target:** `dev`

---

## 1. Goal

Add a seventh theme, **AURIS**, built on the [`auris`](https://pub.dev/packages/auris)
Flutter package — an "augmentation-era sci-fi HUD" UI kit (amber-on-near-black,
chamfered corners, glowing brackets, technical mono fonts). The theme must use
**auris's actual widgets** (`AurisPanel`, `AurisBadge`, `AurisTerminal`,
`AurisSwitch`, …) wherever a Getman surface maps to one, to match the auris look
as closely as possible.

This requires a new piece of architecture: **a per-theme component-slot system**
that lets *any* theme supply its own widget implementations for key UI atoms.
AURIS is the first consumer; the other six themes keep their current look via a
shared default. A follow-up (backlog) will give the other themes bespoke widgets
through the same system.

**Guiding principle (from the user):** *different widgets/components per theme is
desirable — it gives themes personality, and personality takes priority over
implementation convenience.* Implementation difficulty is not a reason to water
down a theme's identity.

---

## 2. Background — how Getman themes work today

A theme is a `ThemeData` + **7** `ThemeExtension`s (`AppLayout`, `AppPalette`,
`AppShape`, `AppTypography`, `AppDecoration`, `AppCopy`, `AppMotion`), read in
widgets via `context.app*` accessors (`lib/core/theme/extensions/app_theme_access.dart`).
Builders have the signature:

```dart
ThemeData <name>Theme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false})
```

and are registered in `lib/core/theme/theme_registry.dart` (`appThemes`) with an
id constant in `theme_ids.dart`. Adding a theme requires **no widget edits**.

Crucially, today's customization hooks are **decoration** hooks: `AppDecoration`
exposes `panelBox`/`tabShape` that return `BoxDecoration` (rounded-rect only) and
`wrapInteractive`/`scaffoldBackground`/`frost` that return widget *wrappers*.
None of them can return a *whole replacement widget* with its own structure — so
they cannot host `AurisPanel`/`AurisBadge`/`AurisTerminal`. That is the gap this
design fills.

### auris package facts that constrain the design

- API: `package:auris/auris.dart` (`AurisTheme.dark/light({Color? accent, double
  bevelScale = 1, double glowScale = 1})`, `AurisScheme` ThemeExtension) and
  `package:auris/auris_widgets.dart` (the widgets).
- auris widgets read `Theme.of(context).extension<AurisScheme>()!` — a **force
  unwrap**. They throw if `AurisScheme` is absent. ⇒ auris widgets are only safe
  to render when the AURIS `ThemeData` (which carries `AurisScheme`) is active.
  Because each theme supplies its *own* slot implementations, the auris-widget
  slots are only ever attached by the AURIS theme, so the unwrap is always safe.
- Bundled fonts (Rajdhani, Exo 2, Share Tech Mono) and Material component theming
  come from the auris `ThemeData`. ⇒ the AURIS builder must **compose** that
  `ThemeData` as its base, not build one from scratch.
- Version is pre-1.0 (`^0.2.0` at time of writing) — pin and accept API churn
  risk. Zero runtime deps beyond Flutter (web-safe in principle; verify the web
  build).

---

## 3. Architecture — `AppComponents`, the 8th ThemeExtension

New file `lib/core/theme/extensions/app_components.dart` defining
`class AppComponents extends ThemeExtension<AppComponents>`. It holds **closures
that return widgets** (one per slot). Pattern mirrors `AppDecoration` exactly:
closures as fields, `copyWith` per field, `lerp` returns `this` (closures don't
interpolate — this is the established precedent).

Add the accessor to `app_theme_access.dart`:

```dart
AppComponents get appComponents => Theme.of(this).extension<AppComponents>()!;
```

### 3.1 Slot definitions (the first cut)

Signatures are indicative; finalize types during implementation. Every slot
takes `BuildContext` first.

| Slot | Signature (sketch) | Getman surface | auris widget |
|---|---|---|---|
| `surface` | `Widget Function(BuildContext, {required Widget child, String? title, String? code, bool accent})` | the 4 main panels | `AurisPanel` (when `title != null`) / `AurisContainer` |
| `methodBadge` | `Widget Function(BuildContext, {required String method})` | HTTP method pill | `AurisBadge` |
| `statusBadge` | `Widget Function(BuildContext, {required int statusCode})` | response status chip | `AurisBadge` (variant by class) |
| `metric` | `Widget Function(BuildContext, {required String label, required String value, String? unit, String? delta})` | response STATUS / TIME / SIZE | `AurisStatCard` |
| `toggle` | `Widget Function(BuildContext, {required bool value, required ValueChanged<bool> onChanged, String? label})` | settings switches + secret lock | `AurisSwitch` |
| `logView` | `Widget Function(BuildContext, {required List<AppLogLine> lines, String? title, ScrollController? controller})` | realtime WS/SSE frame log | `AurisTerminal` |
| `dataRow` | `Widget Function(BuildContext, {required String label, required String value, bool highlight})` | response **headers** + **cookies** rows | `AurisDataRow` |
| `select` | `Widget Function(BuildContext, AppSelectSpec spec)` | method dropdown, panel selector | `AurisSelect` |
| `pendingIndicator` | `Widget Function(BuildContext, {String? label})` | response-loading shimmer | `AurisProgressBar.animated` (indeterminate scan) |
| `statusBanner` | `Widget Function(BuildContext, {required AppBannerState state, required String message})` | realtime CONNECTED/DISCONNECTED banner | `AurisNotification` |

Neutral helper types live beside the extension (theme-agnostic, no auris import):

```dart
class AppLogLine { final String text; final AppLogLineKind kind; }          // kind: outgoing | incoming | ok | warning | error
enum AppLogLineKind { outgoing, incoming, ok, warning, error }

class AppSelectSpec {                                                        // non-generic on purpose (fields can't be generic)
  final String? placeholder;
  final List<AppSelectItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
}
class AppSelectItem { final String label; final Widget? leading; }

enum AppBannerState { info, success, warning, error }
```

### 3.2 Generic dropdown indirection

Because a `ThemeExtension` field cannot be generic, `select` operates on the
non-generic `AppSelectSpec` (index-based). A thin public widget
`AppDropdown<T>` (`lib/core/ui/widgets/app_dropdown.dart`) is the consumer-facing
API: it takes `List<T>` + a `labelOf`/`leadingOf` mapper + `value` + `onChanged`,
builds the index-based `AppSelectSpec`, calls `context.appComponents.select(...)`,
and maps the chosen index back to `T`. Consumers use `AppDropdown<T>`; the slot
stays non-generic. AURIS's `select` returns `AurisSelect`; the default returns
Getman's current dropdown/popup.

### 3.3 The shared default — other themes are untouched

A single top-level factory `AppComponents.defaults()` (const where possible)
returns closures that reproduce **today's** rendering for every slot:

- `surface` → `Container(decoration: context.appDecoration.panelBox(context, …))`
- `methodBadge`/`statusBadge` → the current `MethodBadge` / status-chip body
- `metric` → the current `ResponseMetadataItem` body
- `toggle` → Material `Switch` (+ optional label row)
- `logView` → the current realtime monospace `_FrameRow` list
- `dataRow` → the current header/cookie row
- `select` → the current dropdown/popup-menu
- `pendingIndicator` → the current `Shimmer` skeleton
- `statusBanner` → the current realtime status banner

All six existing theme builders attach `AppComponents.defaults()` in their
`extensions: [...]` list (one line each). **No visual change to any existing
theme**, verified by widget/golden-ish tests.

### 3.4 Consumer refactor

The concrete widgets stop hardcoding and delegate to the slot. Each keeps its
public widget identity but its `build` calls `context.appComponents.<slot>(…)`:

- `lib/core/ui/widgets/method_badge.dart` → `methodBadge`
- `lib/features/tabs/.../response/response_metadata_item.dart` → `statusBadge` (status) + `metric` (time/size)
- the 4 panel sites (`response_section.dart`, `request_config_section.dart`,
  `unified_request_panel.dart`, `realtime_panel.dart`) → `surface`
- `realtime_panel.dart` frame list → `logView`; status banner → `statusBanner`
- `response_headers_view.dart` / `response_cookies_view.dart` → `dataRow`
- settings switches + `key_value_list_editor.dart` secret lock → `toggle`
- method dropdown (`url_bar.dart`), `panel_selector.dart` → `AppDropdown<T>`
- `response_section.dart` pending shimmer → `pendingIndicator`

Small popovers/autocomplete dropdowns stay on `panelBox` for now (out of scope,
§8). Where a default closure needs the *old widget body*, extract that body into
a private helper the closure calls, so behavior is identical.

---

## 4. The AURIS theme

Files under `lib/core/theme/themes/auris/`:
`auris_palette.dart`, `auris_components.dart` (the auris-widget slot impls),
`auris_decorations.dart` (scaffold ambient + press), `auris_motion.dart`,
`auris_theme.dart` (the builder).

### 4.1 Builder composition

```dart
ThemeData aurisTheme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false}) {
  final base = brightness == Brightness.dark
      ? AurisTheme.dark(glowScale: reduceEffects ? 0.0 : 1.0)
      : AurisTheme.light(glowScale: reduceEffects ? 0.0 : 1.0);
  final scheme = base.extension<AurisScheme>()!;            // source Getman colors FROM auris tokens
  // … build AppLayout/AppShape/AppPalette/AppTypography/AppDecoration/AppMotion/AppCopy/AppComponents …
  return base.copyWith(
    extensions: <ThemeExtension>[
      ...base.extensions.values,                            // PRESERVE AurisScheme (+ any auris extensions)
      layout, palette, shape, typography, decoration,
      aurisMotion(reduceEffects: reduceEffects),
      const AppCopy(emptyResponse: '// NO SIGNAL'),
      aurisComponents(),                                    // the auris-widget slots
    ],
  );
}
```

`base.extensions.values` must be spread in so `AurisScheme` survives the
`copyWith` (it replaces the whole set otherwise) — this is what keeps auris
widgets from throwing.

### 4.2 Palette / typography / shape (sourced from `AurisScheme`)

- **Palette:** amber primary; HTTP methods mapped onto auris's amber/gold/slate/
  success/danger family; status: 2xx=success, 3xx=gold, 4xx=amber, 5xx=danger;
  `codeBackground` = auris near-black panel surface; `variableResolved/Unresolved`
  = scheme success/danger; diff colors from success/danger.
- **Typography:** inherit `base.textTheme` (Rajdhani/Exo 2); `codeFontFamily` =
  auris mono (Share Tech Mono); display/title/body weights tuned to Rajdhani.
- **Shape:** small radii (~2–4) since auris widgets self-chamfer; generic Material
  surfaces inherit auris's own shapes from the base `ThemeData`.

### 4.3 Motion personality — **LOUD HUD** (`auris_motion.dart`)

Follow `docs/THEME_AUTHORING.md` §3 checklist and the `glass_motion.dart`
child-hoist pattern. `aurisMotion(reduceEffects: true)` returns `const AppMotion()`
(identity).

- **send / in-flight (`sendStarted`):** SEND becomes a charging targeting-reticle
  (`AurisScanBracket` pulse) + glow that builds with `inFlightTension(elapsed)`;
  build-controller restart guard edge-detects on `old.isSending`.
- **success (2xx/3xx):** teal "link established" scanline sweep down the response
  panel; status badge pops to success variant; intensity scaled by
  `latencyWeight(durationMs)`.
- **clientError (4xx):** soft amber bracket flash.
- **serverError (5xx) / networkError:** red HUD alarm — small shake
  (**gated by `reduceEffects`**) + red bracket flash + glitch line; transport
  failures rendered per `TransportFailureKind` (timeout = slow red pulse,
  badCertificate = lock-glyph flash, generic = static burst). Use `flavorFor` for
  status-code personalities — do not re-derive HTTP semantics.
- **cancelled:** reticle disengage / reverse fizzle.
- **ambient (`scaffoldBackground` in `auris_decorations.dart`):** animated
  scanlines + drifting `AurisHexOrnament` cluster; **separate static variant**
  under `reduceEffects` (no controller, no per-frame paint).
- **press (`wrapInteractive`):** auris glow/press feedback; identity-ish under
  `reduceEffects`.
- **theme-switch in:** generic `ThemeSwitchTransition` (bespoke CRT power-on
  optional, not in scope).
- **sound:** off by default; `assets/sounds/auris/{send,success,error}.mp3`
  placeholder dir registered in `pubspec.yaml` (service no-ops if absent).
- **flash safety (mandatory, independent of `reduceEffects`):** every *repeating*
  scanline/alarm flash clamps its rate via `safeFlashCount` /
  `kMaxSafeFlashesPerSecond` (`photosensitivity.dart`). Full-screen flashes route
  through the guard *and* degrade under `reduceEffects`.

### 4.4 Registry

- `theme_ids.dart`: `const String kAurisThemeId = 'auris';`
- `theme_registry.dart`: register `ThemeDescriptor(id: kAurisThemeId,
  displayName: 'AURIS', builder: aurisTheme)`.
- **Not** the default — `defaultThemeId` stays `kClassicThemeId`.
- Dark **and** light both supported (auris ships both).

---

## 5. Dependencies

- Add `auris: ^0.2.0` to `pubspec.yaml` dependencies.
- Register `assets/sounds/auris/` (optional sounds) under `flutter: assets:`.
- auris bundles its own fonts; no `google_fonts` entry needed for AURIS.

---

## 6. Safety / feasibility notes

- **`AurisScheme` unwrap:** safe because auris-widget slots are attached only by
  the AURIS theme (§4.1). The `defaults()` closures never instantiate auris
  widgets, so the other six themes never touch `AurisScheme`. Add a guard test:
  rendering each non-auris theme does not construct any auris widget.
- **Pre-1.0 dependency:** pin `^0.2.0`; if the API differs from this spec's
  sketch (e.g. `AurisScheme` token names), adapt the AURIS-internal files only —
  the slot interfaces are auris-agnostic and won't change.
- **Web build:** verify `fvm flutter build web` succeeds with auris (fonts +
  CanvasKit). If a widget misbehaves on web, fall back that slot to the default
  for web only (last resort; note in code).
- **`reduceEffects`:** lowers `glowScale` to 0, returns identity `AppMotion`,
  uses the static ambient, no shake/scan animation. Part of the `_themeDataCache`
  key already.
- **`isCompact`:** thread into `AppLayout` paddings like the other themes.

---

## 7. Testing (done-bar)

- `app_components_defaults_test.dart` — `AppComponents.defaults()` builds and each
  slot renders without throwing.
- Per-existing-theme guard: the six existing themes render the key surfaces
  (method badge, panel, switch, log) **without constructing any auris widget**
  and without visual change (pump + find current widget types).
- `auris_theme_test.dart` — builder attaches all 8 extensions incl. `AurisScheme`
  and `AppComponents`, dark+light+compact+reduceEffects all build.
- `auris_motion_test.dart` — reduced ⇒ identity; full ⇒ overlay renders child and
  survives a success and an error/transport reaction without throwing.
- `auris_components_test.dart` — each auris slot renders its `Auris*` widget under
  the AURIS theme without throwing.
- Ambient smoke test (animated background pumps + disposes cleanly).
- Full gate: `fvm flutter analyze` + `fvm dart run custom_lint` +
  `fvm dart run bloc_tools:bloc lint lib` all 0 issues, `fvm dart format` clean,
  `fvm flutter test` green. After any nonexistent `@HiveType` change — none here.

---

## 8. Out of scope (backlog follow-ups)

- Giving the **other six themes** bespoke component implementations through
  `AppComponents` (the user's stated follow-up). Add a `docs/BACKLOG.md` item.
- Slotting small popovers / variable-autocomplete dropdowns, JSON-tree row
  theming, key/value editable inputs (covered by auris base `ThemeData`),
  `AurisRadio`/`AurisStepIndicator` (no current Getman surface),
  snackbar→`AurisNotification` routing.
- Bespoke AURIS theme-switch entrance (CRT power-on).
- Sourcing real AURIS sound assets.

---

## 9. Wiki

Update the GitHub wiki **Themes** page (separate `Getman.wiki.git` repo): add
AURIS with its look *and* reactive behavior, and note it supports light + dark.
Per CLAUDE.md §7, this ships with the work, not deferred.
