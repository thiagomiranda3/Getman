# VM-A3 + VM-E4 — Transport-failure sub-personalities & photosensitivity guardrails

- **Date**: 2026-06-19
- **Branch**: `dev` (unmerged, like the rest of the reactive-motion line)
- **Backlog items**: `VM-A3` (transport-failure reactions) and `VM-E4`
  (photosensitivity guardrails), both under **🎨 Themes, Visuals & Motion**.
- **Builds on**: the reactive-motion spine (`lib/core/theme/motion/`, `AppMotion`)
  and VM-A1/A2 (`StatusReactionFlavor` classifier + `flavorFor`,
  `latencyWeight`/`inFlightTension`).
- **Authoring rules**: follow `docs/THEME_AUTHORING.md` (this work also *edits* it).

---

## 1. Background & problem

### 1.1 VM-A3

The send pipeline uses Dio with `validateStatus: (_) => true`, so every real HTTP
status — including `408 Request Timeout` — flows through the **success** path in
`TabsBloc._onSendRequest` and is classified by `flavorFor` from its status code.
Only genuine **transport** failures (no HTTP status) throw `NetworkFailure` and
reach the `on NetworkFailure` path.

In that path the bloc builds an `errorResponse` with `statusCode: f.statusCode ?? 0`
and fires:

```dart
ThemeReaction(kind: ThemeReaction.kindForStatus(errorResponse.statusCode),
              statusCode: errorResponse.statusCode)
```

For transport failures `statusCode` is `0`, so `kindForStatus(0)` returns
`networkError` and `flavorFor` can only ever return `StatusReactionFlavor.networkError`.
**Result: a client-side timeout, a refused connection, and a bad TLS certificate all
feel identical.** VM-A3 gives transport failures distinct themed personalities.

### 1.2 VM-E4

`THEME_AUTHORING.md` mandates `reduceVisualEffects` degradation (§5, a
vestibular/motion concern) but says nothing about **flash rate** — the
photosensitivity / seizure axis (WCAG 2.3.1, the "general flash threshold": no more
than **3 general flashes** within any 1-second period). Today's flashing effects
(calm's multi-blink pulse bar, rpg sparkles) are all *small-area* and not a real
seizure risk, but there is **no shared guard** to keep future or large-area effects
safe, and no documented policy. VM-E4 formalizes a guard + audits existing effects
+ documents the policy so future effects (including VM-A3's new bad-cert effect)
inherit it.

---

## 2. VM-A3 — design

### 2.1 Failure → flavor taxonomy (three buckets)

The smallest set of buckets that is meaningfully distinct:

| Transport failure (`NetworkFailureType`)            | `StatusReactionFlavor` | Feel                                   | Per-theme cost |
|-----------------------------------------------------|------------------------|----------------------------------------|----------------|
| `sendTimeout`, `receiveTimeout`, `connectionTimeout`| `timeout` (exists)     | "ran out of time" (brutalist `sag`, rpg sparkle, glass dim) | **free** — themes already handle `timeout` |
| `connectionError`, `unknown`                        | `networkError` (exists)| generic "couldn't reach"               | free |
| `badCertificate`                                    | **`badCertificate`** (NEW) | "broken trust / rejected ward"      | one branch per theme spec fn (4) |

Only **one new flavor** (`badCertificate`). Client timeouts reuse the existing
`timeout` flavor, which already has distinct per-theme treatments from VM-A2.

### 2.2 Split `NetworkFailureType.connection`

`_mapDioException` currently maps **both** `DioExceptionType.connectionTimeout` and
`DioExceptionType.connectionError` to a single `NetworkFailureType.connection` — a
lossy merge. Split it so the two map to distinct types:

- `DioExceptionType.connectionTimeout` → `NetworkFailureType.connectionTimeout`
- `DioExceptionType.connectionError`   → `NetworkFailureType.connectionError`

This lets a connection *timeout* join the "ran out of time" bucket while a
connection *refusal/DNS error* stays in the generic "couldn't reach" bucket, exactly
as the backlog intends. Dio already distinguishes them, so this only de-merges
existing information.

**Ripple:** `lib/core/error/failures.dart` (replace `connection` with the two new
cases), `lib/core/network/network_service.dart` (`_mapDioException`), and 3 test
references that use `NetworkFailureType.connection` as a sample failure
(`send_request_use_case_test.dart` ×2, `tabs_bloc_test.dart` ×3 — update to
`connectionError` or `connectionTimeout` as appropriate). No Hive/persistence
impact (`NetworkFailureType` is never serialized).

### 2.3 Threading the discriminator (spine change)

`ThemeReaction` is the decoupled bloc currency (pure Dart, no Flutter, no
`core/error` import). Keep that property by introducing a **theme-local** enum
rather than importing `NetworkFailureType` into the motion layer:

```dart
// lib/core/theme/motion/theme_reaction.dart
enum TransportFailureKind { timeout, badCertificate }
```

Add an optional field to `ThemeReaction`:

```dart
const ThemeReaction({
  required this.kind,
  this.statusCode,
  this.durationMs,
  this.transportFailure,   // NEW — only set for networkError-kind transport fails
});
final TransportFailureKind? transportFailure;
// added to props
```

`TabsBloc` already catches `NetworkFailure` and has `f.type` in scope. It maps
`NetworkFailureType → TransportFailureKind?` at the emit site in the
`on NetworkFailure` path (the only place transport failures originate):

```dart
TransportFailureKind? _transportFailureFor(NetworkFailureType t) => switch (t) {
  NetworkFailureType.sendTimeout
      || NetworkFailureType.receiveTimeout
      || NetworkFailureType.connectionTimeout => TransportFailureKind.timeout,
  NetworkFailureType.badCertificate => TransportFailureKind.badCertificate,
  NetworkFailureType.connectionError
      || NetworkFailureType.unknown
      || NetworkFailureType.badResponse
      || NetworkFailureType.cancelled => null,   // generic / not a transport flavor
};
```

`transportFailure` is attached to the fired reaction unconditionally, but
`flavorFor` only consults it on the **`networkError`** kind (§2.4). So a rare
`badResponse` with a real HTTP status produces a `clientError`/`serverError` kind
and the status-based path wins regardless — which is also why `_transportFailureFor`
returns `null` for `badResponse`. The `cancelled` case is handled by its
early-return branch and never reaches this mapping. The catch-all `on Object` path
keeps firing a bare `networkError` (a true unknown).

### 2.4 `flavorFor` refinement

`flavorFor` reads the new field only on the `networkError` kind:

```dart
case ThemeReactionKind.networkError:
  return switch (r.transportFailure) {
    TransportFailureKind.timeout => StatusReactionFlavor.timeout,
    TransportFailureKind.badCertificate => StatusReactionFlavor.badCertificate,
    null => StatusReactionFlavor.networkError,
  };
```

(`_fallbackForKind` keeps `networkError` for safety.)

### 2.5 Per-theme `badCertificate` handling

`StatusReactionFlavor` switches are **exhaustive** — adding `badCertificate` forces
a branch in all four spec functions (the analyzer flags any omission, which is the
safety net):

- **calm** (`calmSpecFor`, `shared/calm_motion.dart`): restrained — `CalmSpec(color: error)`
  (optionally `blinks: 2` to read as a distinct "rejected" double-tick, subject to
  the VM-E4 guard).
- **brutalist** (`stampSpecFor`): a distinct stamp — reuse an existing error stamp
  treatment with a "rejected/void" connotation (no new asset).
- **rpg** (`rpgSpecFor`): a "broken ward" — a low-amplitude themed fx (reuse an
  existing `RpgFx`, e.g. a darker scatter/shake), not a brand-new painter.
- **glass** (`glassSpecFor`): a "cracked/frosted-over" `GlassSpec` distinct from the
  plain network-error treatment.

These reuse existing fx vocab — no new painters. Exact visual tuning is an
implementation detail; the contract is "visibly distinct from generic networkError,
respects `reduceEffects`, obeys the VM-E4 flash guard."

---

## 3. VM-E4 — design

### 3.1 Shared guard

New `lib/core/theme/motion/photosensitivity.dart` (pure Dart):

```dart
/// WCAG 2.3.1 general flash threshold: no more than 3 general flashes / second.
const int kMaxSafeFlashesPerSecond = 3;

/// Shortest safe period between flash onsets.
const Duration kMinFlashPeriod =
    Duration(milliseconds: 1000 ~/ kMaxSafeFlashesPerSecond); // ~333ms

/// Clamp a desired flash/blink count over [sweep] so the rate never exceeds
/// [kMaxSafeFlashesPerSecond]. Always returns at least 1.
int safeFlashCount(Duration sweep, int desired) {
  final maxByRate = (sweep.inMilliseconds * kMaxSafeFlashesPerSecond) ~/ 1000;
  return desired.clamp(1, maxByRate < 1 ? 1 : maxByRate);
}
```

### 3.2 Audit + route existing effects

Route every flash-rate-bearing effect through the guard so none can exceed 3 Hz:

- **calm** `_CalmReactionOverlay`: its `_blinks` (up to 3 over a 700ms sweep ≈ 4.3 Hz
  nominal) clamps via `safeFlashCount(_c.duration, spec.blinks)`. Small-area today,
  but this makes the cap explicit and survives future duration changes.
- **rpg / brutalist / glass**: audit each motion file; any repeating
  flash/blink/strobe routes its count/period through the guard. Single-shot
  fades/sweeps (most effects) are not flashes and need no change — document which
  were reviewed and why they're exempt.

No effect should *increase* in intensity from this work; the guard is a ceiling.

### 3.3 Documentation

- Add a **"Photosensitivity (flash safety)"** subsection to `THEME_AUTHORING.md`
  (near §5 `reduceVisualEffects`): state the 3 Hz cap, point to
  `photosensitivity.dart`, require large/full-screen flashes to route through
  `safeFlashCount`/`kMinFlashPeriod` **and** degrade under `reduceVisualEffects`.
- Add a checklist line under §3 ("reactive checklist"): *"Any repeating flash/blink
  respects `kMaxSafeFlashesPerSecond` via the photosensitivity guard."*

---

## 4. Files touched

**VM-A3**
- `lib/core/error/failures.dart` — split `connection` → `connectionTimeout` + `connectionError`.
- `lib/core/network/network_service.dart` — `_mapDioException` split.
- `lib/core/theme/motion/theme_reaction.dart` — `TransportFailureKind` enum + `transportFailure` field + props.
- `lib/core/theme/motion/status_reaction_flavor.dart` — `badCertificate` flavor + `networkError`-kind refinement.
- `lib/features/tabs/presentation/bloc/tabs_bloc.dart` — map `NetworkFailureType → TransportFailureKind` at the `on NetworkFailure` emit.
- `lib/core/theme/themes/shared/calm_motion.dart`, `themes/brutalist/brutalist_motion.dart`, `themes/rpg/rpg_motion.dart`, `themes/glass/glass_motion.dart` — `badCertificate` branch.

**VM-E4**
- `lib/core/theme/motion/photosensitivity.dart` — NEW guard.
- `lib/core/theme/themes/shared/calm_motion.dart` (+ any loud theme with a repeating flash) — route through guard.
- `docs/THEME_AUTHORING.md` — policy section + checklist line.

---

## 5. Testing

- **`flavorFor`** (unit): `networkError` + each `transportFailure` → expected flavor;
  null → `networkError`; `timeout` flavor still reached via HTTP 408 unchanged.
- **`TabsBloc`** (bloc test): each `NetworkFailureType` on the send path fires a
  `ThemeReaction` with the expected `transportFailure` (timeout for the three
  timeouts, badCertificate for bad cert, null for connectionError/unknown);
  `cancelled` still early-returns; existing tests updated for the enum split.
- **`network_service`**: `connectionTimeout` vs `connectionError` Dio exceptions map
  to the two new `NetworkFailureType`s.
- **`safeFlashCount`** (unit): clamps above-rate counts, floors at 1, passes
  in-budget counts through.
- **Exhaustiveness**: the new flavor forces all four theme spec functions to compile
  with a `badCertificate` branch (analyze is the gate).

## 6. Done bar

`fvm flutter analyze` + `fvm dart run custom_lint` + `fvm dart run bloc_tools:bloc lint lib`
all 0 issues, `fvm dart format` clean, `fvm flutter test` 100% green. Wiki:
VM-A3/E4 are internal motion polish with no new user-facing control or label, so the
wiki's behavior description ("themes react to outcomes") already covers it — a wiki
edit is **not** required (confirm during implementation; add a line to the
Themes-and-Appearance page only if the bad-cert reaction is worth calling out).

## 7. Out of scope

- New flavors beyond `badCertificate` (e.g. a bespoke "connection refused" flavor
  separate from generic `networkError`) — YAGNI; the three buckets cover it.
- New effect painters — all `badCertificate` treatments reuse existing fx vocab.
- A 3-state effects tier (that's VM-E2) and runtime flash *detection* — the guard is
  an authoring-time ceiling, not a runtime analyzer.
