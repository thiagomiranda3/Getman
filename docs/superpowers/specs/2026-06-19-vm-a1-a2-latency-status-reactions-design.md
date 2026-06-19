# VM-A1 + VM-A2 — Latency-reactive effects & status-code micro-personalities

- **Date**: 2026-06-19
- **Branch**: `dev`
- **Backlog items**: `docs/BACKLOG.md` → 🎨 Themes, Visuals & Motion → **VM-A1**, **VM-A2**
- **Status**: design approved; ready for implementation plan

## 1. Summary

The reactive-motion spine already carries the exact `statusCode` and `durationMs`
of every request into each theme's `reactionOverlay` (`ThemeReaction`), but the
overlays only branch on a coarse success/4xx/5xx/network split and ignore latency
entirely. This work makes the themes *express the data we already capture*:

- **A1 — Latency-reactive effects.** The wait itself becomes expressive (a live
  build-up on the SEND control while in-flight), and the resolution effect scales
  by how long the response took — a 20 ms response snaps crisply; a 3 s response
  lands as heavy relief/triumph.
- **A2 — Status-code micro-personalities.** Notable codes get a bespoke
  micro-reaction in each theme's own idiom (201 spawn, 204 quiet poof, 304
  déjà-vu, 401/403 barrier, 404 dissolve, 408 sag, 429 throttle, 500 crash, 503
  brown-out). Unmapped codes fall back to today's coarse effect.

Both are orthogonal and share one seam (the `ThemeReaction` already on the
controller). **No bloc/spine change**: `ThemeReactionKind`, `TabsBloc`,
`TabsState`, and `ThemeSoundService` are untouched.

## 2. Scope

**Themes covered** (per the agreed coverage decision):

- **Loud — full bespoke treatment**: Brutalist, Glass (Liquid Glass), Arcane (rpg).
- **Calm — restrained treatment**: Classic / Editorial / Dracula via the shared
  `calm_motion.dart`. Tint/blink/duration nuance only — still a single thin
  top-edge pulse bar, no shake, no particles, no ambient. The loud/calm contrast
  is deliberate (THEME_AUTHORING.md §2).

**Status codes with a bespoke flavor** (agreed "backlog set + a few more"): 201,
204, 304, 401, 403, 404, 408, 429, 500, 503. Everything else falls back to its
class (`ok` / `clientError` / `serverError` / `networkError`).

**Out of scope (deferred — see §9):**

- Client-side *transport* timeout (Dio `sendTimeout`/`receiveTimeout`/
  `connectionTimeout`) as its own personality. Server-sent **HTTP 408** *is*
  covered (it arrives via the success path with a real status). A client-side
  timeout surfaces today as a bare `networkError` with no status; giving it a
  distinct personality needs a small spine addition.
- App-wide in-flight treatment beyond the SEND control (that is **VM-B1**).
- Sound cues for the new flavors (that is **VM-E1**; the `assets/sounds/<theme>/`
  dirs are still empty and the service no-ops).

## 3. Key facts that make this cheap

- `NetworkService` sets `validateStatus: (_) => true`, so **every HTTP status —
  including 401/403/404/429/500/503 — returns through the success path** carrying
  its real `statusCode` and `durationMs`. The error path
  (`TabsBloc._onSendRequest` `on NetworkFailure`) is only for transport failures
  (connection/timeout/cancel, no HTTP status). ⇒ A2 status personalities and A1
  latency scaling both work uniformly for error codes with no plumbing change.
- `ThemeReactionKind.sendStarted` already fires through the controller at send
  start, and `durationMs` already rides the success-path reaction. ⇒ A1 needs no
  controller/bloc change; the in-flight build-up is driven locally from
  `AppMotion.sendAffordance`'s existing `isSending` flag.

## 4. Architecture (Decision 1c + 2a)

Three new **pure-Dart** files under `lib/core/theme/motion/` (Flutter-free,
unit-testable, no `ThemeReaction`/bloc edits):

### 4.1 `status_reaction_flavor.dart` — the classifier (Decision 1c)

```dart
enum StatusReactionFlavor {
  ok, created, noContent, notModified,                                  // 2xx/3xx
  unauthorized, forbidden, notFound, timeout, rateLimited, clientError, // 4xx
  serverCrash, serviceUnavailable, serverError,                         // 5xx
  networkError, cancelled,                                              // transport
}

/// Maps a terminal reaction to a presentation-layer flavor. Coarse
/// ThemeReactionKind stays the bloc currency; this adds the fine HTTP
/// semantics once, in the presentation layer, where the visual idiom lives.
StatusReactionFlavor flavorFor(ThemeReaction r);
```

Mapping: `cancelled` kind → `cancelled`; `networkError` kind → `networkError`;
`sendStarted` → `ok` (never used for a resolution); success/clientError/
serverError → classify by `statusCode`:
201→created, 204→noContent, 304→notModified, 401→unauthorized, 403→forbidden,
404→notFound, 408→timeout, 429→rateLimited, 500→serverCrash, 503→serviceUnavailable;
else 200–399→`ok`, 400–499→`clientError`, 500–599→`serverError`, otherwise
→`networkError`. A `null` `statusCode` on a success/error kind falls back to that
kind's class.

### 4.2 `latency_weight.dart` — the A1 scalars

```dart
/// 0.0 for a crisp/fast response (≤ ~150 ms) → 1.0 for a heavy/slow one
/// (≥ ~3 s). Log-perceptual curve, clamped to [0,1]. null → 0.
double latencyWeight(int? durationMs);

/// 0→1 build-up curve for the live in-flight wait, given elapsed ms.
double inFlightTension(int elapsedMs);
```

Pure functions; both loud and calm code multiply effect intensity/duration by
`latencyWeight`. (Thresholds — `fastMs ≈ 150`, `slowMs ≈ 3000` — are module
constants, tuned during implementation.)

### 4.3 Consumption

Each theme's existing `<name>_motion.dart` calls `flavorFor(r)` in its
`reactionOverlay` and `latencyWeight(r.durationMs)` to scale. No new wiring; the
extensions are already consumed uniformly by the app.

## 5. A1 — mechanics

### 5.1 Build-up (Decision 2a: local ticker in each loud `sendAffordance`)

On `isSending` → true, start a `Stopwatch` + a single `Ticker`/
`AnimationController`; render rising tension via `inFlightTension(elapsedMs)`; on
`isSending` → false, stop, reset, play a short release. One controller per
affordance, started/stopped in `initState`/`didUpdateWidget` and disposed in
`dispose` (mirrors `_RpgSendAffordance`'s existing spin lifecycle).

- **Arcane**: the rune ring *fills* (an accumulating arc / lit ticks) and spins
  slightly faster as tension rises. (Today it only spins.)
- **Glass**: a liquid meniscus *rises* inside the SEND button. (Today Glass has
  **no** sending state — only a press ripple; `isSending` is currently ignored.)
- **Brutalist**: a hard **marching fill bar** creeps along the button edge.
  (Today only a press-slam; `isSending` is currently ignored.)

Note: Brutalist and Glass `sendAffordance` builders must be updated to thread
`isSending` into their state widgets (currently dropped).

### 5.2 Resolution scaling (in each `reactionOverlay`, multiply by `latencyWeight`)

- **Arcane**: sparkle count + shower duration + (error) shake amplitude scale.
- **Glass**: ripple ring count + bloom radius + duration scale.
- **Brutalist**: the stamp "thud" — initial scale, hold time, and shake scale
  (slow = heavier slam; fast = light quick stamp).
- **Calm**: pulse-bar opacity + duration scale *subtly* — still a thin bar.

The two halves are independent widgets (build-up = `sendAffordance`; resolution =
`reactionOverlay`), matching the existing structure; no shared state.

## 6. A2 — per-theme flavor matrix

Effects are **parameter-driven over each theme's existing painter vocabulary**
(color / count / repeat / doubling / scatter / flicker + `latencyWeight`), plus a
small number of genuinely new painters where the meaning demands it: a **barrier**
(401/403) and a **dissolve/scatter** (404), each shared across the loud themes and
fed that theme's palette/idiom. Brutalist gets A2 nearly free — it already stamps
the status-code number.

| Flavor | Brutalist (stamp) | Glass (ripple) | Arcane (sparkle/rune) | Calm (pulse) |
|---|---|---|---|---|
| **created** 201 | green stamp + "+1" pop | bright birth-bloom disc | summoning spark-burst | success tint |
| **noContent** 204 | smaller quiet stamp, no shake | single tiny quick ripple | small mote puff | thinner/shorter pulse |
| **notModified** 304 | doubled/ghosted stamp (offset) | doubled echo ring (ghost trail) | translucent rune echo | double-blink pulse |
| **unauthorized** 401 | heavy bar across code (barrier) | frosted pane slams down (barrier) | hex ward/shield flash (barrier) | sharp amber pulse |
| **forbidden** 403 | barred stamp + lock (barrier) | barrier + lock tint | rune-lock (barrier) | sharp red pulse |
| **notFound** 404 | stamp shatters/scatters (dissolve) | surface fractures into shards (dissolve) | motes scatter & vanish (dissolve) | quick dim pulse |
| **timeout** 408 | stamp sags/drips (slow) | sluggish low-amp ripple | slow mana-drain | slow lingering pulse |
| **rateLimited** 429 | stamp re-thuds 2–3× | repeated cooldown rings | cooldown rune pulses ×3 | triple-blink pulse |
| **serverCrash** 500 | biggest stamp + strongest glitch-shake | deepest full crack | heaviest runic crack + max shake | strongest (thin) red pulse |
| **serviceUnavailable** 503 | stamp flickers (brown-out) | glass flickers/dims | arcane flicker | flickering pulse |
| *fallback* | today's coarse stamp | today's coarse ripple/crack | today's coarse sparkle/crack | today's coarse pulse |

Design rules:

- **Shared painters** for the two new shapes (`_BarrierEffect`, `_DissolveEffect`)
  — ~2 new painters' worth of work per theme, not per-flavor.
- **Doubling / repeat / flicker / scatter** flavors are *parameters* on each
  theme's existing success/error painter (repeat count, offset, opacity-flutter,
  scatter factor) — cheap.
- **Calm stays calm**: every calm treatment is still a single thin top-edge bar;
  only tint, blink-count, and duration change.

## 7. `reduceVisualEffects` degradation (mandatory — THEME_AUTHORING.md §5)

- A1/A2 add **nothing** to the reduced path. Each `<name>Motion(reduceEffects:
  true)` already returns `const AppMotion()` (identity overlay + send), so the
  build-up ticker, latency scaling, and every flavor painter live only inside the
  full overlays and never instantiate when reduced.
- `flavorFor` / `latencyWeight` are pure and safe regardless, but are gated by
  construction (never reached in the reduced path) — asserted by test.

## 8. Performance discipline (reuse proven patterns)

- A1 build-up: **one** ticker/controller per `sendAffordance`, started on
  `isSending` and stopped/reset on resolution; disposed in `dispose`.
- Resolution effects stay transient controllers that dispose on
  `AnimationStatus.completed`; `latencyWeight` only adjusts their parameters/
  duration, not their lifecycle.
- New painters build any reusable `Path` once, reuse `Paint` objects (mutate
  `.color`/`.shader`), no per-element allocation in `paint`, `shouldRepaint` on
  `t` only, `RepaintBoundary` around added painters.
- Modest particle counts (web/CanvasKit is a target).

## 9. Deferred (added to `docs/BACKLOG.md`)

- **VM-A3 (new)** — *Client-side timeout / network-failure sub-personalities.*
  Give transport timeouts (and optionally connection vs. cert failures) their own
  themed reaction, distinct from the generic `networkError`. Needs a small spine
  addition (thread the `NetworkFailureType` / a finer kind through `ThemeReaction`
  + `TabsBloc`). Server-sent HTTP 408 is already handled by A2's classifier.
- VM-B1 (app-wide in-flight) and VM-E1 (themed sound for new flavors) already
  exist in the backlog and are explicitly *not* part of this work.

## 10. Implementation staging

A2 is the bulk; stage it theme-by-theme so each lands as an independently
shippable, fully-green increment:

1. **Shared core** — `status_reaction_flavor.dart` + `latency_weight.dart` + their
   unit tests.
2. **Brutalist** — A1 (marching build-up + thud scaling) + A2 (stamp variants;
   nearly free since it already shows the code).
3. **Glass** — A1 (liquid-rise build-up + ripple scaling) + A2 (incl. shared
   barrier/dissolve painters).
4. **Arcane** — A1 (rune-ring fill + sparkle scaling) + A2 (shield/scatter/echo).
5. **Calm (shared)** — restrained A1 (subtle latency scaling) + A2 (tint /
   blink-count nuance).
6. **Backlog** — record VM-A3; **wiki sync** — Themes page note per theme.

## 11. Test plan

1. `status_reaction_flavor_test.dart` — table test: every listed code → flavor;
   boundary/fallback (200→ok, 418→clientError, 502→serverError, 0→networkError);
   `cancelled`/`networkError` kinds.
2. `latency_weight_test.dart` — monotonic, clamped [0,1], fast→~0 / slow→~1,
   `null`→0; `inFlightTension` monotonic 0→1.
3. Per-theme motion tests (extend existing `*_motion_test.dart`): full overlay
   renders the child and survives `success`, `404`, `429`, `500`, and a
   `sendStarted→success` cycle without throwing; reduced ⇒ identity (child only).
4. `sendAffordance` build-up: pump `isSending: true` then `false` → starts/stops
   cleanly, disposes its ticker (no pending-timer failures).
5. Done-bar: `fvm flutter analyze` + `fvm dart run custom_lint` +
   `fvm dart run bloc_tools:bloc lint lib` all 0 issues, `fvm dart format` clean,
   `fvm flutter test` green.

## 12. Wiki sync (CLAUDE.md §7)

The Themes wiki page gains a short "reacts to response latency and notable status
codes" note per loud theme + the calm note — done as part of the work, not
deferred (`Getman.wiki.git`).
