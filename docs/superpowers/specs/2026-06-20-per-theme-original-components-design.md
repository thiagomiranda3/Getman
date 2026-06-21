# Per-Theme Original Components (VM-F1) — Design

**Date:** 2026-06-20
**Status:** Approved (design) — pending spec review
**Backlog:** [`docs/BACKLOG.md`](../../BACKLOG.md) **VM-F1**
**Guide:** [`docs/THEME_AUTHORING.md`](../../THEME_AUTHORING.md) §10 (Components)
**Reference implementation:** `lib/core/theme/themes/auris/auris_components.dart`

---

## 1. Goal

AURIS proved the `AppComponents` seam: a theme can express itself through
*original widgets*, not just colours/shapes/motion — its panels, badges, log, and
switch read as a different *product*, not a re-skin. This work gives that same
treatment to the other themes so each feels **truly original** — "some even feel
like an entirely different structure for the same app."

**Per the approved scope (calm/loud contrast is intentional, THEME_AUTHORING §2):**

| Theme | Lane | Treatment |
|---|---|---|
| **Brutalist** | loud | Full bespoke set — **flagship, built + reviewed first** |
| **Arcane Quest** (rpg) | loud | Full bespoke set |
| **Liquid Glass** (glass) | loud | Full bespoke set |
| **Editorial** | calm | Genuinely original but **restrained** (no motion/glow) |
| **Dracula** | calm | Genuinely original but **restrained** |
| **Classic** | calm | **Unchanged — inherits `defaultAppComponents()`** (the quiet native default; preserves the contrast) |
| **AURIS** | loud | Already done — the reference |

---

## 2. The seam (no app-widget edits)

Each customized theme gets a new file:

```
lib/core/theme/themes/<name>/<name>_components.dart
  → AppComponents <name>Components() = defaultAppComponents().copyWith(...)
```

overriding only the high-personality slots and inheriting the rest. The theme
builder (`<name>_theme.dart`) attaches `<name>Components()` in its `extensions:`
list **instead of** `defaultAppComponents()`.

Every app consumer already reads `context.appComponents.<slot>` (verified:
`method_badge.dart`, `app_dropdown.dart`, `request_config_section.dart`,
`response_section.dart`, `unified_request_panel.dart`,
`response/response_headers_view.dart`, `response/response_cookies_view.dart`,
`settings_dialog.dart`, `update_settings_section.dart`, `realtime_panel.dart`).
**No widget edits are required.**

### The 10 slots

`surface`, `methodBadge`, `statusBadge`, `metric`, `toggle`, `logView`,
`dataRow`, `select`, `pendingIndicator`, `statusBanner`. (Signatures in
`lib/core/theme/extensions/app_components.dart`.)

**`select` is inherited by every theme in this work** — it is currently unwired
in the app (only `AppDropdown`, which no surface routes through yet — VM-F2).
Customizing it would be untestable in a real layout, so it stays on the default.

---

## 3. Hard constraints (carried from the AURIS lessons — apply to every theme)

These caused real `RenderFlex` overflows in AURIS and are non-negotiable:

1. **`surface` must fill.** It is called *without* a title from inside an
   `Expanded` (the four main panels). A fill-wanting child (e.g. a `TabBarView`)
   must still fill — forward the incoming (tight) constraints; never wrap the
   child in something that shrink-wraps. (See `auris_surface`'s `AurisContainer`
   note.)
2. **`logView` must size to available height.** It lives in an `Expanded`. Use a
   `LayoutBuilder`: when height is bounded, subtract any header/chrome height
   (floored) so the total widget fills without overflowing; unbounded → a sane
   default. (See `auris_components.dart` `_kTerminalChrome`.)
3. **`metric` must stay a compact inline chip.** It sits in the response-metadata
   horizontal `Wrap` alongside the status badge. A large tile overflows/dwarfs
   the row. Intrinsically-sized chip only; fold any `delta`/`unit` into the value
   text so no info is lost.
4. **`reduceEffects` degrades every animation to static.** Any builder that
   animates (pendingIndicator, liquid switch squish, summoning ring, block-press
   shimmer, edge glow pulse) must read the theme's `reduceEffects` path and
   render a still variant. Themes already thread `reduceEffects` into their
   builder; pass it into `<name>Components(reduceEffects: ...)` where a slot needs
   it (see §6).
5. **Flash safety (WCAG 2.3.1).** Any *repeating* blink/flash caps at
   `kMaxSafeFlashesPerSecond` (3 Hz) via
   `lib/core/theme/motion/photosensitivity.dart`. The Dracula blinking cursor
   runs at a single ≤1.5 Hz cursor blink (well under the cap) and is the only
   repeating flash introduced.

### Lint / architecture rules

- Files live under `lib/core/theme/themes/<name>/`, so
  `avoid_hardcoded_brand_colors` (scoped to *outside* `lib/core/theme/`) does
  **not** apply — theme-internal files may use the theme's own palette constants
  and effect literals (THEME_AUTHORING §1). Still prefer pulling shared values
  from `context.app*` where one exists.
- No `data/` imports, no `GetIt`/`sl`, no BLoC imports in these files (same as
  the defaults).
- `package:getman/...` absolute imports; `dart format` clean.

---

## 4. Per-theme creative directions

For each theme below: the **structural concept** (what makes it feel like a
different app) and the **slot overrides**. Loud themes override the full
high-personality set (`surface`, `methodBadge`, `statusBadge`, `metric`,
`toggle`, `logView`, `dataRow`, `pendingIndicator`, `statusBanner`); calm themes
override the same set but render restrained. `select` is inherited everywhere.

### 4.1 🟥 Brutalist — "ink-press / risograph print shop" (flagship)

Everything looks printed/stamped with hard ink: thick borders, hard offset drop
shadows (the signature brutalist shadow), uppercase, monospace accents.

- **`surface`** — slab panel. When titled, a stuck-on header **label** (an
  offset, hard-shadowed tag bearing the title) sits on the slab; untitled → a
  bare hard slab that fills.
- **`methodBadge` / `statusBadge`** — **ink stamps**: thick border + hard offset
  shadow, uppercase, a faint mis-registration tint (a 1–2px colour-offset ghost).
  Status keeps the `statusColor` mapping + the small "STATUS" label.
- **`metric`** — compact **mono ticker chip**: hard border, *no* shadow (inline-
  safe in the `Wrap`), tiny-caps label + monospace value.
- **`toggle`** — **chunky physical switch**: a square thumb that *snaps* across a
  hard-bordered track (hard offset shadow on the thumb), `ON`/`OFF` text. The
  snap (a short position tween) reads as a clunk; instant under `reduceEffects`.
- **`logView`** — **fanfold line-printer feed**: a left tractor-feed hole margin,
  a `▲`/`▼` direction glyph per row, alternating row tint (fanfold paper), mono
  payload, hard row rules. Sizes to height per constraint #2.
- **`dataRow`** — printed row: key in a hard-bordered tag on the left, mono value,
  hard bottom rule.
- **`pendingIndicator`** — hard **block-shimmer** reading as a press run (a band
  sweeping across hard blocks), label "PRINTING…"; static blocks under
  `reduceEffects`.
- **`statusBanner`** — full-width **stamped bar** (hard border, status colour,
  uppercase message).

### 4.2 🟪 Arcane Quest (rpg) — "spellbook / RPG screen"

Parchment, runes, gems, illuminated borders, scroll frames — a fantasy
inventory/quest UI.

- **`surface`** — **runic-framed parchment panel**: parchment-tinted fill, a
  `CustomPainter` border with rune/flourish **corner ornaments**; titled → an
  engraved quest-header banner with flanking flourishes.
- **`methodBadge`** — heraldic **rune plate** (method colour as the plate gem).
- **`statusBadge`** — **faceted gem** (`CustomPainter` polygon + facet highlight):
  emerald (2xx), topaz/amber (4xx), ruby (5xx), sapphire (3xx).
- **`metric`** — engraved **runestone** chip (small stone tablet, inline-safe).
- **`toggle`** — **enchanted lever**: pulls up/down; a rune glow when on (static
  glow under `reduceEffects`).
- **`logView`** — **grimoire scroll**: a rune bullet per line, parchment ground,
  display-weight labels + mono payload, a scroll-edge frame. Sizes to height.
- **`dataRow`** — quest-ledger row (rune bullet, engraved small-caps key, mono
  value, parchment rule).
- **`pendingIndicator`** — **summoning ring**: a rotating rune ring / channeling
  bar reusing the rpg rune motifs; static ring under `reduceEffects`.
- **`statusBanner`** — heraldic **ribbon banner**.

### 4.3 🟦 Liquid Glass (glass) — "visionOS frosted HUD"

Builds on the theme's existing real backdrop blur (`glassFrost`) and specular
edges.

- **`surface`** — **frosted glass tile**: reuses the theme's `frost` decoration
  (identity under `reduceEffects` — so blur auto-degrades), hairline specular
  edge, generous rounding; titled → a floating translucent title chip on the
  glass. Must fill (constraint #1).
- **`methodBadge` / `statusBadge`** — **translucent lozenges**: pill shape, method
  /status colour at low alpha, specular top highlight.
- **`metric`** — compact **frosted lozenge** (inline-safe).
- **`toggle`** — **liquid-glass switch**: frosted track, glossy thumb with a
  specular highlight; a subtle squish/wobble on toggle under full effects, plain
  glossy thumb under `reduceEffects`.
- **`logView`** — **blurred terminal pane**: frosted scroll surface, translucent
  direction pills per row, mono payload, frosted header. Sizes to height.
- **`dataRow`** — glass row with a hairline divider (accent-tinted key).
- **`pendingIndicator`** — soft frosted **ripple/shimmer**; static frosted
  placeholder under `reduceEffects`.
- **`statusBanner`** — **frosted notification capsule** (blur + accent glow).

### 4.4 📰 Editorial — "print magazine" (calm, restrained)

Serif headings, whitespace, hairline rules, footnote typography. **No animation
or glow** — restrained on purpose, but a clearly different *reading* structure.

- **`surface`** — **article panel**: a thin hairline-rule frame, a serif section-
  heading title with an underline rule, generous internal whitespace.
- **`methodBadge` / `statusBadge`** — quiet **typographic tags**: small-caps
  serif label in a hairline box, muted tint (status keeps the colour mapping but
  desaturated).
- **`metric`** — **footnote metric**: small-caps label + oldstyle/figure value, a
  thin vertical rule separator (inline-safe).
- **`toggle`** — minimal **outlined switch** (thin track, no clunk/glow).
- **`logView`** — **dispatch log**: each row reads like a news dispatch — a small-
  caps source label (`OUT`/`IN`/`OPEN`/`CLOSE`/`ERROR`) + mono payload, hairline
  dividers, airy leading. Sizes to height.
- **`dataRow`** — **references-list row**: small-caps serif key, readable value,
  hairline rule between.
- **`pendingIndicator`** — quiet **galley-proof** placeholder (thin static lines;
  minimal/no motion).
- **`statusBanner`** — ruled **editorial note** bar.

### 4.5 🧛 Dracula — "neon dev-console" (calm, restrained)

The iconic Dracula palette as a developer terminal. Restrained motion (no shake/
heavy animation), but a clearly different "dev console" identity.

- **`surface`** — **console panel**: softly rounded, a *subtle static* purple
  edge-glow, a `// title` comment-style header in the code font.
- **`methodBadge` / `statusBadge`** — **neon capsules**: rounded pills in the
  Dracula accents, subtle glow (method colours from the palette; status: green
  2xx / cyan 3xx / orange 4xx / red 5xx).
- **`metric`** — **terminal chip**: `time: 123ms` in the code font with a colour-
  accented key (inline-safe).
- **`toggle`** — **console toggle**: rounded track, accent-coloured + subtle glow
  when on.
- **`logView`** — **dev console** (the headline slot): `→`/`←`/`✓`/`✗` colour-
  coded prefixes per kind, monospace payload, REPL-style. Sizes to height.
- **`dataRow`** — **console kv row**: `key:` in an accent colour + mono value.
- **`pendingIndicator`** — **blinking-cursor** "awaiting response…" console line
  (a single block cursor blinking ≤1.5 Hz — under the 3 Hz cap; a steady cursor
  under `reduceEffects`).
- **`statusBanner`** — **console status line** (`[OK]`/`[ERR]` prefix).

### 4.6 ⬜ Classic — unchanged

Classic keeps `defaultAppComponents()`. No new file, no slot overrides. It is the
quiet native default and the baseline the defaults were modeled on; leaving it
on defaults preserves the calm/loud contrast (the user's explicit choice).

---

## 5. `reduceEffects` plumbing

Where a slot animates, the theme's `<name>Components(...)` builder must accept and
honour `reduceEffects`. AURIS's `aurisComponents()` takes no flag because its
animated slot (`pendingIndicator`) loops harmlessly and the theme degrades blur
via the `frost`/glow path; for the themes here that introduce *new* animation
(Brutalist press-shimmer + switch snap, Arcane summoning ring + lever glow, Glass
switch squish + ripple, Dracula cursor blink) the builder signature becomes:

```dart
AppComponents <name>Components({bool reduceEffects = false}) =>
    defaultAppComponents().copyWith(/* slots, passing reduceEffects where needed */);
```

and the theme builder calls `<name>Components(reduceEffects: reduceEffects)`. Glass
slots that rely on blur can read `context.appDecoration.frost` (already identity
under `reduceEffects`) instead of threading the flag. Editorial introduces no
animation, so `editorialComponents()` needs no flag.

`reduceEffects` is part of the `_themeDataCache` key (theme_registry.dart), so a
flagged builder produces correctly-distinct cache entries automatically.

---

## 6. Testing

Per customized theme, `test/core/theme/themes/<name>/<name>_components_test.dart`:

1. **Per-slot smoke**: pump each overridden slot via `context.appComponents`
   under `<name>Theme(Brightness.dark)` (and a light-mode case for surface/
   badges) — assert no exception and the expected bespoke widget/marker renders.
2. **Under-theme overflow guard** (the AURIS-proven check): pump the real
   `ResponseSection` (metadata row + a responded tab) and `RealtimePanel` under
   the theme; assert no `RenderFlex` overflow (no exceptions, `tester.takeException()`
   is null). This is what caught the AURIS metric/log overflows.
3. **`reduceEffects` degradation**: for themes with animated slots, pump the
   animated slot under `<name>Theme(..., reduceEffects: true)` and assert it
   renders the static variant (e.g. no running `AnimationController` / a static
   marker) without throwing.

The generic `test/core/theme/theme_has_components_test.dart` already asserts every
theme attaches `AppComponents` (it iterates `appThemes`) — no change needed.

---

## 7. Implementation order

Per the approved "flagship first, then roll out" sequencing:

1. **Brutalist** — full bespoke set + tests. **Stop for user review of real
   output** before proceeding.
2. **Arcane Quest** (rpg)
3. **Liquid Glass** (glass)
4. **Editorial**
5. **Dracula**

Each theme is an independent unit (its own `<name>_components.dart` + test + a
one-line builder swap). Classic requires no work.

**Done-bar per theme** (CLAUDE.md §5 / THEME_AUTHORING §8.6): `fvm flutter
analyze` + `fvm dart run custom_lint` + `fvm dart run bloc_tools:bloc lint lib`
all 0 issues, `fvm dart format` clean, `fvm flutter test` green.

---

## 8. Out of scope

- **`select` slot** customization (unwired — VM-F2).
- **New `AppComponents` slots** — work within the existing 10; no app-widget edits.
- **Classic** changes.
- **Sound / motion** changes (separate extensions; this is components only).
- **Wiki sync** — the Themes wiki page should note each theme now has bespoke
  components; done as the closing step after all themes land (CLAUDE.md §7).

---

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Custom `surface`/`logView` overflow in real layout | Under-theme render test (#6.2) per theme — the AURIS-proven guard |
| `metric` dwarfs the metadata `Wrap` | Compact inline chip only (constraint #3); the render test asserts no overflow |
| Animated slot ignores `reduceEffects` | Flagged builder (§5) + degradation test (#6.3) |
| Repeating flash exceeds 3 Hz | Only Dracula's cursor blinks; held ≤1.5 Hz (constraint #5) |
| A theme drifts loud when it should stay calm | Editorial/Dracula explicitly restrained (no motion/glow beyond a static glow + a sub-1.5 Hz cursor); Classic untouched |
| `CustomPainter` per-frame cost (Arcane corners/ring) | Static painters for ornaments; the one animated ring is a single transient/looping controller with `RepaintBoundary`, static under `reduceEffects` (THEME_AUTHORING §6) |
