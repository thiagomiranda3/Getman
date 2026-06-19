# VM-A1 + VM-A2 — Latency-reactive effects & status-code micro-personalities — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every theme express the `statusCode` and `durationMs` already carried on each `ThemeReaction` — a live in-flight build-up + latency-scaled resolution (A1), and bespoke per-status micro-effects (A2) — without touching the bloc/reaction spine.

**Architecture:** Two new pure-Dart helpers in `lib/core/theme/motion/` — a `StatusReactionFlavor` classifier (`flavorFor`) and `latencyWeight`/`inFlightTension` scalars. Each theme's existing `*_motion.dart` consumes them: the `reactionOverlay` switches on the flavor and scales by latency; the `sendAffordance` runs a local 0→1 build controller off the existing `isSending` flag. Loud themes (Brutalist/Glass/Arcane) get full bespoke painters; the shared calm overlay gets restrained tint/blink/duration nuance only. `ThemeReactionKind`, `TabsBloc`, `TabsState`, `ThemeSoundService` are **untouched**.

**Tech Stack:** Flutter, `CustomPainter`, `AnimationController`/`Ticker`, `ThemeExtension` (`AppMotion`). Tests: `flutter_test` (`testWidgets` + plain `test`).

**Design spec:** `docs/superpowers/specs/2026-06-19-vm-a1-a2-latency-status-reactions-design.md`

## Global Constraints

- **Flutter SDK**: always invoke as `fvm flutter ...` / `fvm dart ...` (pinned via `.fvmrc`).
- **Imports**: `package:getman/...` absolute imports everywhere — no relative imports (`always_use_package_imports` + `directives_ordering`).
- **No hardcoded brand colors** outside `lib/core/theme/` (`custom_lint`: `avoid_hardcoded_brand_colors`). Theme-internal files under `lib/core/theme/themes/<name>/` MAY use that theme's own palette constants and effect literals.
- **`reduceEffects` is load-bearing**: every `<name>Motion(reduceEffects: true)` must return `const AppMotion()` (identity). A1/A2 add nothing to the reduced path.
- **Pure-Dart motion core**: files in `lib/core/theme/motion/` must not import Flutter (`theme_reaction.dart` is pure Dart for bloc_lint). Exception: `latency_weight.dart` may import `dart:math` only.
- **Done-bar (run before every commit; the `.githooks/pre-commit` hook enforces it):** `fvm flutter analyze` (0 issues) + `fvm dart run custom_lint` (0) + `fvm dart run bloc_tools:bloc lint lib` (0) + `fvm dart format lib test` clean + `fvm flutter test` green. The three analysis passes are independent — a clean analyze does NOT imply custom_lint/bloc_lint are clean.
- **Status codes with a bespoke flavor**: 201, 204, 304, 401, 403, 404, 408, 429, 500, 503. Everything else falls back to its class.
- **Latency thresholds** (module constants, tunable): fast ≈ 150 ms (→ weight 0), slow ≈ 3000 ms (→ weight 1).
- **Commit message format**: `type(scope): summary`, ending with the trailer lines:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z
  ```

---

## Task 1: `StatusReactionFlavor` classifier (shared core)

**Files:**
- Create: `lib/core/theme/motion/status_reaction_flavor.dart`
- Test: `test/core/theme/motion/status_reaction_flavor_test.dart`

**Interfaces:**
- Consumes: `ThemeReaction`, `ThemeReactionKind` from `lib/core/theme/motion/theme_reaction.dart`.
- Produces: `enum StatusReactionFlavor`; `StatusReactionFlavor flavorFor(ThemeReaction r)`.

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/motion/status_reaction_flavor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

ThemeReaction _http(int code) => ThemeReaction(
  kind: ThemeReaction.kindForStatus(code),
  statusCode: code,
);

void main() {
  group('flavorFor — mapped status codes', () {
    const cases = {
      201: StatusReactionFlavor.created,
      204: StatusReactionFlavor.noContent,
      304: StatusReactionFlavor.notModified,
      401: StatusReactionFlavor.unauthorized,
      403: StatusReactionFlavor.forbidden,
      404: StatusReactionFlavor.notFound,
      408: StatusReactionFlavor.timeout,
      429: StatusReactionFlavor.rateLimited,
      500: StatusReactionFlavor.serverCrash,
      503: StatusReactionFlavor.serviceUnavailable,
    };
    cases.forEach((code, flavor) {
      test('$code => $flavor', () => expect(flavorFor(_http(code)), flavor));
    });
  });

  group('flavorFor — class fallbacks', () {
    test('200 => ok', () => expect(flavorFor(_http(200)), StatusReactionFlavor.ok));
    test('301 => ok', () => expect(flavorFor(_http(301)), StatusReactionFlavor.ok));
    test('418 => clientError',
        () => expect(flavorFor(_http(418)), StatusReactionFlavor.clientError));
    test('502 => serverError',
        () => expect(flavorFor(_http(502)), StatusReactionFlavor.serverError));
    test('0 => networkError',
        () => expect(flavorFor(_http(0)), StatusReactionFlavor.networkError));
  });

  group('flavorFor — non-HTTP kinds', () {
    test('cancelled', () {
      expect(
        flavorFor(const ThemeReaction(kind: ThemeReactionKind.cancelled)),
        StatusReactionFlavor.cancelled,
      );
    });
    test('networkError', () {
      expect(
        flavorFor(const ThemeReaction(kind: ThemeReactionKind.networkError)),
        StatusReactionFlavor.networkError,
      );
    });
    test('null statusCode on success kind falls back to ok', () {
      expect(
        flavorFor(const ThemeReaction(kind: ThemeReactionKind.success)),
        StatusReactionFlavor.ok,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/status_reaction_flavor_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:getman/core/theme/motion/status_reaction_flavor.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/theme/motion/status_reaction_flavor.dart`:

```dart
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// Presentation-layer refinement of a [ThemeReaction] into a fine-grained
/// "flavor". The coarse [ThemeReactionKind] stays the bloc currency; this adds
/// the HTTP-status semantics once, in the theme layer, where the visual idiom
/// lives. Pure Dart (no Flutter import).
enum StatusReactionFlavor {
  ok,
  created,
  noContent,
  notModified,
  unauthorized,
  forbidden,
  notFound,
  timeout,
  rateLimited,
  clientError,
  serverCrash,
  serviceUnavailable,
  serverError,
  networkError,
  cancelled,
}

/// Classifies a terminal reaction. `sendStarted` is not a resolution; it maps
/// to [StatusReactionFlavor.ok] defensively (overlays never call this on it).
StatusReactionFlavor flavorFor(ThemeReaction r) {
  switch (r.kind) {
    case ThemeReactionKind.cancelled:
      return StatusReactionFlavor.cancelled;
    case ThemeReactionKind.networkError:
      return StatusReactionFlavor.networkError;
    case ThemeReactionKind.sendStarted:
      return StatusReactionFlavor.ok;
    case ThemeReactionKind.success:
    case ThemeReactionKind.clientError:
    case ThemeReactionKind.serverError:
      final code = r.statusCode;
      return code == null ? _fallbackForKind(r.kind) : _flavorForCode(code);
  }
}

StatusReactionFlavor _flavorForCode(int code) {
  switch (code) {
    case 201:
      return StatusReactionFlavor.created;
    case 204:
      return StatusReactionFlavor.noContent;
    case 304:
      return StatusReactionFlavor.notModified;
    case 401:
      return StatusReactionFlavor.unauthorized;
    case 403:
      return StatusReactionFlavor.forbidden;
    case 404:
      return StatusReactionFlavor.notFound;
    case 408:
      return StatusReactionFlavor.timeout;
    case 429:
      return StatusReactionFlavor.rateLimited;
    case 500:
      return StatusReactionFlavor.serverCrash;
    case 503:
      return StatusReactionFlavor.serviceUnavailable;
  }
  if (code >= 200 && code < 400) return StatusReactionFlavor.ok;
  if (code >= 400 && code < 500) return StatusReactionFlavor.clientError;
  if (code >= 500 && code < 600) return StatusReactionFlavor.serverError;
  return StatusReactionFlavor.networkError;
}

StatusReactionFlavor _fallbackForKind(ThemeReactionKind kind) => switch (kind) {
  ThemeReactionKind.clientError => StatusReactionFlavor.clientError,
  ThemeReactionKind.serverError => StatusReactionFlavor.serverError,
  ThemeReactionKind.success => StatusReactionFlavor.ok,
  ThemeReactionKind.sendStarted => StatusReactionFlavor.ok,
  ThemeReactionKind.networkError => StatusReactionFlavor.networkError,
  ThemeReactionKind.cancelled => StatusReactionFlavor.cancelled,
};
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/status_reaction_flavor_test.dart`
Expected: PASS (all cases green).

- [ ] **Step 5: Run the analysis gate**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test`
Expected: 0 issues from each; format reports 0 changed.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/motion/status_reaction_flavor.dart test/core/theme/motion/status_reaction_flavor_test.dart
git commit -m "feat(motion): add StatusReactionFlavor classifier (VM-A2 core)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 2: `latencyWeight` + `inFlightTension` scalars (shared core)

**Files:**
- Create: `lib/core/theme/motion/latency_weight.dart`
- Test: `test/core/theme/motion/latency_weight_test.dart`

**Interfaces:**
- Produces: `double latencyWeight(int? durationMs)` (0..1) and `double inFlightTension(int elapsedMs)` (0..1).

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/motion/latency_weight_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/latency_weight.dart';

void main() {
  group('latencyWeight', () {
    test('null => 0', () => expect(latencyWeight(null), 0));
    test('0 => 0', () => expect(latencyWeight(0), 0));
    test('fast (<=150ms) => 0', () => expect(latencyWeight(150), 0));
    test('slow (>=3000ms) => 1', () => expect(latencyWeight(3000), 1));
    test('very slow clamps to 1', () => expect(latencyWeight(10000), 1));
    test('always within [0,1]', () {
      for (final ms in [50, 200, 500, 1000, 2000, 2999]) {
        final w = latencyWeight(ms);
        expect(w, inInclusiveRange(0.0, 1.0), reason: 'ms=$ms');
      }
    });
    test('monotonic non-decreasing', () {
      var prev = -1.0;
      for (final ms in [150, 300, 600, 1200, 2400, 3000]) {
        final w = latencyWeight(ms);
        expect(w, greaterThanOrEqualTo(prev), reason: 'ms=$ms');
        prev = w;
      }
    });
  });

  group('inFlightTension', () {
    test('0 => 0', () => expect(inFlightTension(0), 0));
    test('full at 3000ms', () => expect(inFlightTension(3000), 1));
    test('beyond full clamps to 1', () => expect(inFlightTension(9000), 1));
    test('mid is between 0 and 1', () {
      final t = inFlightTension(1500);
      expect(t, greaterThan(0.0));
      expect(t, lessThan(1.0));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/latency_weight_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `lib/core/theme/motion/latency_weight.dart`:

```dart
import 'dart:math' as math;

/// Fast responses snap (weight 0); slow ones land heavy (weight 1).
const int kFastLatencyMs = 150;
const int kSlowLatencyMs = 3000;

/// Maps a response latency to a 0..1 "weight" used to scale resolution effects.
/// Log-perceptual between [kFastLatencyMs] and [kSlowLatencyMs]; clamped.
double latencyWeight(int? durationMs) {
  if (durationMs == null || durationMs <= kFastLatencyMs) return 0;
  if (durationMs >= kSlowLatencyMs) return 1;
  final lo = math.log(kFastLatencyMs.toDouble());
  final hi = math.log(kSlowLatencyMs.toDouble());
  return ((math.log(durationMs.toDouble()) - lo) / (hi - lo)).clamp(0.0, 1.0);
}

/// Full in-flight tension is reached after this many ms of waiting.
const int kTensionFullMs = 3000;

/// 0→1 build-up curve for the live wait, given elapsed ms. Linear, clamped.
double inFlightTension(int elapsedMs) {
  if (elapsedMs <= 0) return 0;
  if (elapsedMs >= kTensionFullMs) return 1;
  return (elapsedMs / kTensionFullMs).clamp(0.0, 1.0);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/latency_weight_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the analysis gate**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test`
Expected: 0 issues; format 0 changed.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/motion/latency_weight.dart test/core/theme/motion/latency_weight_test.dart
git commit -m "feat(motion): add latencyWeight + inFlightTension scalars (VM-A1 core)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 3: Brutalist — A1 (marching build-up + latency-scaled thud)

**Files:**
- Modify: `lib/core/theme/themes/brutalist/brutalist_motion.dart` (`brutalistMotion` send wiring; `_BrutalStampSend`; `_BrutalReactionOverlay._onReaction` + builder)
- Test: `test/core/theme/themes/brutalist_motion_test.dart`

**Interfaces:**
- Consumes: `latencyWeight` (Task 2).
- Produces: `_BrutalStampSend({required bool isSending, required Widget child})`; the overlay's effect duration/scale/shake now scale with latency.

- [ ] **Step 1: Write the failing test** (append to `test/core/theme/themes/brutalist_motion_test.dart`)

```dart
testWidgets('A1: send affordance build-up starts/stops cleanly', (tester) async {
  final motion = brutalistMotion(reduceEffects: false);
  late bool sending;
  await tester.pumpWidget(
    StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: motion.sendAffordance(
              context,
              isSending: sending = true,
              child: const Text('SEND'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text('SEND'), findsOneWidget);
  expect(tester.takeException(), isNull);
  // Rebuild with isSending=false to exercise the stop/reset path.
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: motion.sendAffordance(
            context,
            isSending: false,
            child: const Text('SEND'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
});

testWidgets('A1: slow success resolves without throwing', (tester) async {
  final motion = brutalistMotion(reduceEffects: false);
  final controller = ThemeReactionController();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.reactionOverlay(
            context,
            controller: controller,
            child: const Text('app'),
          ),
        ),
      ),
    ),
  );
  controller.fire(
    const ThemeReaction(
      kind: ThemeReactionKind.success,
      statusCode: 200,
      durationMs: 2800, // high latencyWeight
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('app'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
  controller.dispose();
});
```

Ensure the test file imports exist at the top (add any missing):

```dart
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/brutalist_motion_test.dart`
Expected: FAIL — `_BrutalStampSend` doesn't accept `isSending` (compile error), or the build-up test fails.

- [ ] **Step 3: Thread `isSending` + add the marching build-up**

In `lib/core/theme/themes/brutalist/brutalist_motion.dart`, change the send wiring:

```dart
    sendAffordance: (context, {required child, required isSending}) =>
        _BrutalStampSend(isSending: isSending, child: child),
```

Replace `_BrutalStampSend` with a version that keeps the press-slam AND adds a marching fill bar driven by a 0→1 build controller while sending:

```dart
/// SEND "STAMP": a hard downward slam on press + a marching fill bar along the
/// bottom edge while [isSending] (tension builds the longer the wait runs).
class _BrutalStampSend extends StatefulWidget {
  const _BrutalStampSend({required this.isSending, required this.child});
  final bool isSending;
  final Widget child;

  @override
  State<_BrutalStampSend> createState() => _BrutalStampSendState();
}

class _BrutalStampSendState extends State<_BrutalStampSend>
    with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  // 0→1 over kTensionFullMs, then holds at 1 while still sending.
  late final AnimationController _build = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kTensionFullMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSending) unawaited(_build.forward(from: 0));
  }

  @override
  void didUpdateWidget(_BrutalStampSend old) {
    super.didUpdateWidget(old);
    if (widget.isSending && !_build.isAnimating && _build.value == 0) {
      unawaited(_build.forward(from: 0));
    } else if (!widget.isSending && _build.value != 0) {
      _build
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _build.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.appPalette.statusSuccess;
    return Listener(
      onPointerDown: (_) => unawaited(_press.forward(from: 0)),
      onPointerUp: (_) => unawaited(_press.reverse()),
      child: AnimatedBuilder(
        animation: Listenable.merge([_press, _build]),
        child: widget.child,
        builder: (_, child) => Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(_press.value * 3, _press.value * 3),
              child: child,
            ),
            if (widget.isSending)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MarchingBarPainter(
                      tension: inFlightTension(
                        (_build.value * kTensionFullMs).round(),
                      ),
                      color: accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A hard fill bar along the bottom edge: width grows with tension; a marching
/// dash pattern conveys "working".
class _MarchingBarPainter extends CustomPainter {
  _MarchingBarPainter({required this.tension, required this.color});
  final double tension;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 4.0;
    final y = size.height - h;
    final w = size.width * (0.15 + 0.85 * tension);
    final paint = Paint()..color = color;
    const dash = 10.0;
    for (var x = 0.0; x < w; x += dash * 2) {
      canvas.drawRect(Rect.fromLTWH(x, y, dash, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MarchingBarPainter old) =>
      old.tension != tension || old.color != color;
}
```

Add the imports at the top of `brutalist_motion.dart` (keep them sorted):

```dart
import 'package:getman/core/theme/motion/latency_weight.dart';
```

(`context.appPalette` is already reachable — the file imports `app_theme.dart`.)

- [ ] **Step 4: Scale the resolution thud by latency**

In `_BrutalReactionOverlayState._onReaction`, compute the weight and store it; lengthen the controller for slow responses:

```dart
  double _weight = 0;

  void _onReaction(ThemeReaction r) {
    if (r.kind == ThemeReactionKind.sendStarted) return;
    _weight = latencyWeight(r.durationMs);
    final label = switch (r.kind) {
      ThemeReactionKind.cancelled => 'CANCELLED',
      ThemeReactionKind.networkError => 'FAILED',
      _ => '${r.statusCode ?? 0}',
    };
    final isError = r.isError;
    _stamp?.dispose();
    late final AnimationController c;
    c =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: 900 + (600 * _weight).round()),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed && mounted) {
            if (_stamp == c) {
              setState(() => _stamp = null);
              c.dispose();
            }
          }
        });
    setState(() {
      _label = label;
      _isError = isError;
      _stamp = c;
    });
    unawaited(c.forward());
  }
```

And scale the slam + shake in the builder — change the `scale` and `_shakeDx` lines:

```dart
                final scale =
                    (2.4 + 0.8 * _weight) -
                    (1.4 + 0.8 * _weight) * Curves.easeOutBack.transform(inT);
```

```dart
  double _shakeDx(double t) {
    if (!_isError) return 0;
    final decay = (1 - (t / 0.4)).clamp(0.0, 1.0);
    return math.sin(t * math.pi * 16) * (8 * (0.6 + 0.7 * _weight)) * decay;
  }
```

- [ ] **Step 5: Run the tests**

Run: `fvm flutter test test/core/theme/themes/brutalist_motion_test.dart`
Expected: PASS (all, including the pre-existing reduced/identity test).

- [ ] **Step 6: Analysis gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
git add lib/core/theme/themes/brutalist/brutalist_motion.dart test/core/theme/themes/brutalist_motion_test.dart
git commit -m "feat(theme): brutalist A1 — marching send build-up + latency-scaled stamp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 4: Brutalist — A2 (status-flavor stamp variants)

**Files:**
- Modify: `lib/core/theme/themes/brutalist/brutalist_motion.dart` (add `_StampSpec` + `stampSpecFor`; consume flavor in `_onReaction`/builder; new `_BarrierPainter`)
- Test: `test/core/theme/themes/brutalist_motion_test.dart`

**Interfaces:**
- Consumes: `StatusReactionFlavor`, `flavorFor` (Task 1).
- Produces: pure `_StampSpec stampSpecFor(StatusReactionFlavor)` (testable); stamp render reads it.

- [ ] **Step 1: Write the failing test** (append)

```dart
test('A2: stampSpecFor encodes the flavor matrix', () {
  expect(stampSpecFor(StatusReactionFlavor.notModified).doubled, isTrue);
  expect(stampSpecFor(StatusReactionFlavor.rateLimited).thuds, 3);
  expect(stampSpecFor(StatusReactionFlavor.timeout).sag, isTrue);
  expect(stampSpecFor(StatusReactionFlavor.serviceUnavailable).flicker, isTrue);
  expect(stampSpecFor(StatusReactionFlavor.notFound).scatter, isTrue);
  expect(stampSpecFor(StatusReactionFlavor.unauthorized).barrier, isTrue);
  expect(stampSpecFor(StatusReactionFlavor.forbidden).barrier, isTrue);
  expect(stampSpecFor(StatusReactionFlavor.ok).thuds, 1);
});

testWidgets('A2: overlay survives every mapped status code', (tester) async {
  final motion = brutalistMotion(reduceEffects: false);
  final controller = ThemeReactionController();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.reactionOverlay(
            context,
            controller: controller,
            child: const Text('app'),
          ),
        ),
      ),
    ),
  );
  for (final code in [201, 204, 304, 401, 403, 404, 408, 429, 500, 503]) {
    controller.fire(
      ThemeReaction(
        kind: ThemeReaction.kindForStatus(code),
        statusCode: code,
        durationMs: 500,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('app'), findsOneWidget, reason: 'code=$code');
  }
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
  controller.dispose();
});
```

Add the import: `import 'package:getman/core/theme/motion/status_reaction_flavor.dart';`

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/brutalist_motion_test.dart`
Expected: FAIL — `stampSpecFor`/`_StampSpec` undefined.

- [ ] **Step 3: Add the flavor spec (pure data)**

In `brutalist_motion.dart`, add (top-level):

```dart
/// How a flavor renders as a brutalist stamp. Pure data → unit-testable.
class _StampSpec {
  const _StampSpec({
    this.thuds = 1,
    this.doubled = false,
    this.sag = false,
    this.flicker = false,
    this.scatter = false,
    this.barrier = false,
    this.quiet = false,
  });
  final int thuds; // re-slam count (429 throttle)
  final bool doubled; // ghosted echo (304)
  final bool sag; // droops downward (408)
  final bool flicker; // brown-out (503)
  final bool scatter; // shatters apart (404)
  final bool barrier; // bar slammed across (401/403)
  final bool quiet; // smaller, no shake (204)
}

_StampSpec stampSpecFor(StatusReactionFlavor f) => switch (f) {
  StatusReactionFlavor.noContent => const _StampSpec(quiet: true),
  StatusReactionFlavor.notModified => const _StampSpec(doubled: true),
  StatusReactionFlavor.timeout => const _StampSpec(sag: true),
  StatusReactionFlavor.serviceUnavailable => const _StampSpec(flicker: true),
  StatusReactionFlavor.notFound => const _StampSpec(scatter: true),
  StatusReactionFlavor.unauthorized ||
  StatusReactionFlavor.forbidden => const _StampSpec(barrier: true),
  StatusReactionFlavor.rateLimited => const _StampSpec(thuds: 3),
  _ => const _StampSpec(),
};
```

- [ ] **Step 4: Consume the spec in the overlay**

In `_BrutalReactionOverlayState`, add `_StampSpec _spec = const _StampSpec();` and set it in `_onReaction` right after computing the weight:

```dart
    _spec = stampSpecFor(flavorFor(r));
```

In the builder, apply the spec to the stamp render. Replace the stamp `IgnorePointer(...)` subtree with this (handles doubled/sag/flicker/scatter/barrier/quiet; `thuds` re-pulses scale):

```dart
                final reps = _spec.thuds;
                final pulse = reps <= 1
                    ? inT
                    : Curves.easeOutBack.transform(
                        (((t * reps) % 1.0)).clamp(0.0, 1.0),
                      );
                final baseScale = _spec.thuds > 1
                    ? (2.4 + 0.8 * _weight) - (1.2) * pulse
                    : scale;
                final flickerA = _spec.flicker
                    ? (0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * math.pi * 14)))
                    : 1.0;
                final sagDy = _spec.sag ? Curves.easeIn.transform(t) * 60 : 0.0;
                final scatterK = _spec.scatter
                    ? Curves.easeOut.transform(t)
                    : 0.0;
                final stamp = IgnorePointer(
                  child: Opacity(
                    opacity: (alpha * flickerA).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, sagDy),
                      child: Transform.scale(
                        scale: baseScale * (1 + scatterK * 0.6),
                        child: Transform.rotate(
                          angle: -0.12,
                          child: _spec.barrier
                              ? _BarrierStamp(label: _label, color: color)
                              : _StampLabel(label: _label, color: color),
                        ),
                      ),
                    ),
                  ),
                );
                final ghost = _spec.doubled
                    ? IgnorePointer(
                        child: Opacity(
                          opacity: (alpha * 0.35).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: const Offset(10, 8),
                            child: Transform.scale(
                              scale: baseScale,
                              child: Transform.rotate(
                                angle: -0.12,
                                child: _StampLabel(label: _label, color: color),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
                return Transform.translate(
                  offset: Offset(_spec.quiet ? 0 : _shakeDx(t), 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [child!, ghost, stamp],
                  ),
                );
```

Add the barrier widget (a heavy bar slammed across the stamped code):

```dart
/// The status code with a thick bar slammed across it — "blocked".
class _BarrierStamp extends StatelessWidget {
  const _BarrierStamp({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _StampLabel(label: label, color: color),
        Transform.rotate(
          angle: 0.18,
          child: Container(width: 220, height: 18, color: color),
        ),
      ],
    );
  }
}
```

(For 204 `quiet`, `_isError` is false so `_shakeDx` already returns 0; the `quiet` guard also suppresses shake on the rare quiet-error case. The scatter for 404 reads as the label exploding outward + fading; refine the scatter visuals by eye in Step 6.)

- [ ] **Step 5: Run the tests**

Run: `fvm flutter test test/core/theme/themes/brutalist_motion_test.dart`
Expected: PASS.

- [ ] **Step 6: Visual check + analysis gate + commit**

Run the app and eyeball Brutalist reactions across a few codes (optional but recommended):
Run: `fvm flutter run -d macos` → switch to Brutalist → send requests returning 201/404/429/500/503 (e.g. via httpbin: `https://httpbin.org/status/429`). Tune painter literals by eye if needed.

Then:
```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
fvm flutter test
git add lib/core/theme/themes/brutalist/brutalist_motion.dart test/core/theme/themes/brutalist_motion_test.dart
git commit -m "feat(theme): brutalist A2 — per-status stamp micro-personalities

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 5: Glass — A1 (liquid-rise build-up + latency-scaled ripple)

**Files:**
- Modify: `lib/core/theme/themes/glass/glass_motion.dart` (`glassMotion` send wiring; `_GlassSendAffordance` gains `isSending` + a rising meniscus; `_GlassReactionOverlay._onReaction` scales by latency)
- Test: `test/core/theme/themes/glass_motion_test.dart`

**Interfaces:**
- Consumes: `latencyWeight`, `inFlightTension` (Task 2).
- Produces: `_GlassSendAffordance({required bool isSending, required Widget child})` with a liquid-fill build-up.

- [ ] **Step 1: Write the failing test** (append to `glass_motion_test.dart`)

```dart
testWidgets('A1: glass send shows a rising liquid level while sending', (
  tester,
) async {
  final motion = glassMotion(reduceEffects: false);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: motion.sendAffordance(
              context,
              isSending: true,
              child: const SizedBox(width: 100, height: 40, key: ValueKey('s')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byKey(const ValueKey('s')), findsOneWidget);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
});

testWidgets('A1: slow vs fast success both resolve cleanly', (tester) async {
  final motion = glassMotion(reduceEffects: false);
  final controller = ThemeReactionController();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.reactionOverlay(
            context,
            controller: controller,
            child: const Text('app'),
          ),
        ),
      ),
    ),
  );
  controller.fire(
    const ThemeReaction(
      kind: ThemeReactionKind.success,
      statusCode: 200,
      durationMs: 2900,
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('app'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
  controller.dispose();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/glass_motion_test.dart`
Expected: FAIL — `_GlassSendAffordance` doesn't accept `isSending`.

- [ ] **Step 3: Thread `isSending` + add the rising-liquid build-up**

In `glass_motion.dart`, update the send wiring:

```dart
    sendAffordance: (context, {required child, required isSending}) =>
        _GlassSendAffordance(isSending: isSending, child: child),
```

Update `_GlassSendAffordance` to keep the press ripple AND add a build controller (0→1 over `kTensionFullMs`) painting a rising meniscus while sending:

```dart
class _GlassSendAffordance extends StatefulWidget {
  const _GlassSendAffordance({required this.isSending, required this.child});
  final bool isSending;
  final Widget child;

  @override
  State<_GlassSendAffordance> createState() => _GlassSendAffordanceState();
}

class _GlassSendAffordanceState extends State<_GlassSendAffordance>
    with TickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final AnimationController _build = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kTensionFullMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSending) unawaited(_build.forward(from: 0));
  }

  @override
  void didUpdateWidget(_GlassSendAffordance old) {
    super.didUpdateWidget(old);
    if (widget.isSending && !_build.isAnimating && _build.value == 0) {
      unawaited(_build.forward(from: 0));
    } else if (!widget.isSending && _build.value != 0) {
      _build
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    _build.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).primaryColor;
    return Listener(
      onPointerDown: (_) {
        _ripple.reset();
        unawaited(_ripple.forward());
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([_ripple, _build]),
                builder: (_, child) => CustomPaint(
                  painter: _GlassSendPainter(
                    ripple: _ripple.value,
                    level: widget.isSending
                        ? inFlightTension((_build.value * kTensionFullMs).round())
                        : 0,
                    color: accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Press ripple + a translucent liquid that rises from the bottom with the
/// in-flight [level] (0..1).
class _GlassSendPainter extends CustomPainter {
  _GlassSendPainter({
    required this.ripple,
    required this.level,
    required this.color,
  });
  final double ripple;
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (level > 0) {
      final h = size.height * level;
      final fill = Paint()..color = color.withValues(alpha: 0.22);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - h, size.width, h),
        fill,
      );
      // Meniscus line.
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.5);
      canvas.drawLine(
        Offset(0, size.height - h),
        Offset(size.width, size.height - h),
        line,
      );
    }
    if (ripple > 0) {
      final center = size.center(Offset.zero);
      final r = Curves.easeOut.transform(ripple) * size.longestSide;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.5 * (1 - ripple)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassSendPainter old) =>
      old.ripple != ripple || old.level != level || old.color != color;
}
```

Delete the now-replaced `_ButtonRipplePainter` class (its logic moved into `_GlassSendPainter`).

Add the import: `import 'package:getman/core/theme/motion/latency_weight.dart';`

- [ ] **Step 4: Scale the resolution ripple by latency**

In `_GlassReactionOverlayState._onReaction`, store the weight and lengthen + enlarge slow successes:

```dart
  void _onReaction(ThemeReaction r) {
    final accent = Theme.of(context).primaryColor;
    final w = latencyWeight(r.durationMs);
    final controller = AnimationController(
      vsync: this,
      duration: r.isError
          ? const Duration(milliseconds: 700)
          : Duration(milliseconds: 900 + (500 * w).round()),
    );
    final effect = _GlassEffect(
      controller: controller,
      isError: r.isError,
      weight: w,
      color: r.isError ? Theme.of(context).colorScheme.error : accent,
    );
    controller.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _effects.remove(effect));
        controller.dispose();
      }
    });
    setState(() => _effects.add(effect));
    unawaited(controller.forward());
  }
```

Add `weight` to `_GlassEffect`:

```dart
class _GlassEffect {
  _GlassEffect({
    required this.controller,
    required this.isError,
    required this.weight,
    required this.color,
  });
  final AnimationController controller;
  final bool isError;
  final double weight;
  final Color color;
}
```

Pass `weight` into the ripple painter and use it to add rings + grow the bloom — change the painter construction in `build` and `_GlassRipplePainter`:

```dart
                    painter: e.isError
                        ? _GlassCrackPainter(t: e.controller.value, color: e.color)
                        : _GlassRipplePainter(
                            t: e.controller.value,
                            color: e.color,
                            weight: e.weight,
                          ),
```

```dart
class _GlassRipplePainter extends CustomPainter {
  _GlassRipplePainter({
    required this.t,
    required this.color,
    this.weight = 0,
  });
  final double t;
  final Color color;
  final double weight;
  // ... in paint(): rings = 3 + (weight * 2).round();  maxR *= (1 + 0.25 * weight);
```

Update the loop bound and `maxR` accordingly (`for (var i = 0; i < 3 + (weight * 2).round(); i++)`), and `shouldRepaint` to also compare `weight`.

- [ ] **Step 5: Run the tests**

Run: `fvm flutter test test/core/theme/themes/glass_motion_test.dart`
Expected: PASS.

- [ ] **Step 6: Analysis gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
git add lib/core/theme/themes/glass/glass_motion.dart test/core/theme/themes/glass_motion_test.dart
git commit -m "feat(theme): glass A1 — rising-liquid send build-up + latency-scaled ripple

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 6: Glass — A2 (status-flavor ripple/crack variants + barrier + dissolve)

**Files:**
- Modify: `lib/core/theme/themes/glass/glass_motion.dart` (add `_GlassSpec` + `glassSpecFor`; flavor-driven painter selection; new `_GlassBarrierPainter`, `_GlassShardPainter`)
- Test: `test/core/theme/themes/glass_motion_test.dart`

**Interfaces:**
- Consumes: `StatusReactionFlavor`, `flavorFor` (Task 1).
- Produces: pure `_GlassSpec glassSpecFor(StatusReactionFlavor)` selecting one of `{ripple, echo, barrier, shards, flicker}` + tint/repeat.

- [ ] **Step 1: Write the failing test** (append)

```dart
test('A2: glassSpecFor selects the right effect per flavor', () {
  expect(glassSpecFor(StatusReactionFlavor.created).style, GlassFx.ripple);
  expect(glassSpecFor(StatusReactionFlavor.notModified).style, GlassFx.echo);
  expect(glassSpecFor(StatusReactionFlavor.unauthorized).style, GlassFx.barrier);
  expect(glassSpecFor(StatusReactionFlavor.forbidden).style, GlassFx.barrier);
  expect(glassSpecFor(StatusReactionFlavor.notFound).style, GlassFx.shards);
  expect(glassSpecFor(StatusReactionFlavor.serviceUnavailable).style, GlassFx.flicker);
  expect(glassSpecFor(StatusReactionFlavor.serverCrash).style, GlassFx.crack);
});

testWidgets('A2: glass overlay survives every mapped status code', (
  tester,
) async {
  final motion = glassMotion(reduceEffects: false);
  final controller = ThemeReactionController();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.reactionOverlay(
            context,
            controller: controller,
            child: const Text('app'),
          ),
        ),
      ),
    ),
  );
  for (final code in [201, 204, 304, 401, 403, 404, 408, 429, 500, 503]) {
    controller.fire(
      ThemeReaction(
        kind: ThemeReaction.kindForStatus(code),
        statusCode: code,
        durationMs: 400,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('app'), findsOneWidget, reason: 'code=$code');
  }
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
  controller.dispose();
});
```

Add the import: `import 'package:getman/core/theme/motion/status_reaction_flavor.dart';`

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/glass_motion_test.dart`
Expected: FAIL — `glassSpecFor`/`GlassFx` undefined.

- [ ] **Step 3: Add the flavor spec + new painters**

In `glass_motion.dart`, add:

```dart
enum GlassFx { ripple, echo, barrier, shards, flicker, crack }

class _GlassSpec {
  const _GlassSpec(this.style, {this.repeat = 1, this.amplitude = 1.0});
  final GlassFx style;
  final int repeat; // 429 cooldown rings
  final double amplitude; // 204 small, 408 sluggish
}

_GlassSpec glassSpecFor(StatusReactionFlavor f) => switch (f) {
  StatusReactionFlavor.noContent => const _GlassSpec(GlassFx.ripple, amplitude: 0.4),
  StatusReactionFlavor.notModified => const _GlassSpec(GlassFx.echo),
  StatusReactionFlavor.unauthorized ||
  StatusReactionFlavor.forbidden => const _GlassSpec(GlassFx.barrier),
  StatusReactionFlavor.notFound => const _GlassSpec(GlassFx.shards),
  StatusReactionFlavor.timeout => const _GlassSpec(GlassFx.ripple, amplitude: 0.5),
  StatusReactionFlavor.rateLimited => const _GlassSpec(GlassFx.ripple, repeat: 3),
  StatusReactionFlavor.serviceUnavailable => const _GlassSpec(GlassFx.flicker),
  StatusReactionFlavor.serverCrash ||
  StatusReactionFlavor.serverError ||
  StatusReactionFlavor.clientError ||
  StatusReactionFlavor.networkError => const _GlassSpec(GlassFx.crack),
  _ => const _GlassSpec(GlassFx.ripple),
};
```

Store the spec on `_GlassEffect` (add `final _GlassSpec spec;` + constructor param; set it in `_onReaction` via `glassSpecFor(flavorFor(r))`), and pick the painter by `spec.style` in `build`:

```dart
                  builder: (_, child) => CustomPaint(
                    painter: switch (e.spec.style) {
                      GlassFx.crack => _GlassCrackPainter(t: e.controller.value, color: e.color),
                      GlassFx.barrier => _GlassBarrierPainter(t: e.controller.value, color: e.color),
                      GlassFx.shards => _GlassShardPainter(t: e.controller.value, color: e.color),
                      GlassFx.echo => _GlassRipplePainter(t: e.controller.value, color: e.color, weight: e.weight, echo: true),
                      GlassFx.flicker => _GlassRipplePainter(t: e.controller.value, color: e.color, weight: e.weight, flicker: true),
                      GlassFx.ripple => _GlassRipplePainter(t: e.controller.value, color: e.color, weight: e.weight, repeat: e.spec.repeat, amplitude: e.spec.amplitude),
                    },
                    child: child,
                  ),
```

Extend `_GlassRipplePainter` with `echo`/`flicker`/`repeat`/`amplitude` fields (default off): `echo` draws a second offset ghost ring; `flicker` modulates alpha by `sin`; `repeat` draws N ring-sets at staggered phases; `amplitude` scales `maxR`. Update `shouldRepaint`.

Add the two new painters:

```dart
/// A frosted pane that slams down from the top then settles — "blocked".
class _GlassBarrierPainter extends CustomPainter {
  _GlassBarrierPainter({required this.t, required this.color});
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final drop = Curves.easeOutBack.transform((t / 0.4).clamp(0.0, 1.0));
    final fade = (1 - (t - 0.5).clamp(0.0, 0.5) / 0.5).clamp(0.0, 1.0);
    final h = size.height * 0.5 * drop;
    final pane = Paint()..color = color.withValues(alpha: 0.16 * fade);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, h), pane);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.5 * fade);
    canvas.drawLine(Offset(0, h), Offset(size.width, h), edge);
  }
  @override
  bool shouldRepaint(covariant _GlassBarrierPainter old) =>
      old.t != t || old.color != color;
}

/// The surface fractures into a few triangular shards that drift and fade.
class _GlassShardPainter extends CustomPainter {
  _GlassShardPainter({required this.t, required this.color});
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(11);
    final center = size.center(Offset.zero);
    final fade = (1 - t).clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.5 * fade);
    for (var i = 0; i < 9; i++) {
      final a = i * (math.pi * 2 / 9) + rng.nextDouble() * 0.3;
      final dir = Offset(math.cos(a), math.sin(a));
      final drift = Curves.easeOut.transform(t) * size.shortestSide * 0.4;
      final p = center + dir * (20 + drift);
      final path = Path()
        ..moveTo(p.dx, p.dy)
        ..lineTo(p.dx + 12, p.dy + 6)
        ..lineTo(p.dx + 4, p.dy + 16)
        ..close();
      canvas.drawPath(path, paint);
    }
  }
  @override
  bool shouldRepaint(covariant _GlassShardPainter old) =>
      old.t != t || old.color != color;
}
```

- [ ] **Step 4: Run the tests**

Run: `fvm flutter test test/core/theme/themes/glass_motion_test.dart`
Expected: PASS.

- [ ] **Step 5: Visual check (optional) + analysis gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
fvm flutter test
git add lib/core/theme/themes/glass/glass_motion.dart test/core/theme/themes/glass_motion_test.dart
git commit -m "feat(theme): glass A2 — per-status ripple/echo/barrier/shards/flicker

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 7: Arcane (rpg) — A1 (rune-ring fill + latency-scaled sparkle/shake)

**Files:**
- Modify: `lib/core/theme/themes/rpg/rpg_motion.dart` (`_RpgSendAffordance` ring fills with tension; `_RpgReactionOverlay._onReaction` scales count/duration/shake by latency)
- Test: `test/core/theme/themes/rpg_motion_test.dart`

**Interfaces:**
- Consumes: `latencyWeight`, `inFlightTension` (Task 2).
- Produces: latency-scaled sparkle shower + a filling rune ring.

- [ ] **Step 1: Write the failing test** (append to `rpg_motion_test.dart`)

```dart
testWidgets('A1: rune ring build-up runs and tears down cleanly', (tester) async {
  final motion = rpgMotion(reduceEffects: false);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: motion.sendAffordance(
              context,
              isSending: true,
              child: const Text('SEND'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 800));
  expect(find.text('SEND'), findsOneWidget);
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
});

testWidgets('A1: slow error (5xx, high latency) shakes and resolves', (
  tester,
) async {
  final motion = rpgMotion(reduceEffects: false);
  final controller = ThemeReactionController();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.reactionOverlay(
            context,
            controller: controller,
            child: const Text('app'),
          ),
        ),
      ),
    ),
  );
  controller.fire(
    const ThemeReaction(
      kind: ThemeReactionKind.serverError,
      statusCode: 500,
      durationMs: 2900,
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('app'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
  controller.dispose();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/rpg_motion_test.dart`
Expected: the build-up test passes trivially today (ring already spins) but the latency scaling is not yet wired — proceed; the new assertions still guard regressions. If it already passes, treat Step 3/4 as the feature add (TDD here guards behavior, not a hard red).

- [ ] **Step 3: Make the rune ring FILL with tension**

In `rpg_motion.dart`, give `_RpgSendAffordanceState` a build controller in addition to `_spin`:

```dart
  late final AnimationController _build = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kTensionFullMs),
  );
```

Start/stop it alongside `_spin` in `initState`/`didUpdateWidget` (mirror the existing spin lifecycle: `_build.forward(from: 0)` when sending starts; `_build..stop()..value = 0` when it stops). Dispose it. Pass `fill: inFlightTension((_build.value * kTensionFullMs).round())` into `_RuneRingPainter`, merging `_spin` + `_build` in the `AnimatedBuilder.animation`. In `_RuneRingPainter`, add a `final double fill;` field and draw a progress arc over the ring proportional to `fill` (`canvas.drawArc(rect, -pi/2, 2*pi*fill, false, arcPaint)`), and light `(.fill * 12).round()` of the 12 ticks brighter. Update `shouldRepaint` to compare `fill`.

Add: `import 'package:getman/core/theme/motion/latency_weight.dart';`

- [ ] **Step 4: Scale the sparkle shower + shake by latency**

In `_RpgReactionOverlayState._onReaction`, compute `final w = latencyWeight(r.durationMs);`, store it on `_RpgEffect` (add `final double weight;`), lengthen the controller (`Duration(milliseconds: 900 + (500 * w).round())`), and use `weight` in `_SparkleShowerPainter` (sparkle count `36 + (w * 30).round()`) and in `_shakeDx` (multiply the `6` amplitude by `(0.6 + 0.7 * e.weight)`). Pass `weight` into the painter and bump `shouldRepaint`.

- [ ] **Step 5: Run the tests**

Run: `fvm flutter test test/core/theme/themes/rpg_motion_test.dart`
Expected: PASS.

- [ ] **Step 6: Analysis gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
git add lib/core/theme/themes/rpg/rpg_motion.dart test/core/theme/themes/rpg_motion_test.dart
git commit -m "feat(theme): arcane A1 — filling rune ring + latency-scaled sparkle/shake

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 8: Arcane (rpg) — A2 (status-flavor sparkle/rune variants + ward + scatter)

**Files:**
- Modify: `lib/core/theme/themes/rpg/rpg_motion.dart` (add `_RpgSpec` + `rpgSpecFor`; flavor-driven painter selection; new `_WardPainter`, `_MoteScatterPainter`, `_RuneEchoPainter`)
- Test: `test/core/theme/themes/rpg_motion_test.dart`

**Interfaces:**
- Consumes: `StatusReactionFlavor`, `flavorFor` (Task 1).
- Produces: pure `_RpgSpec rpgSpecFor(StatusReactionFlavor)` selecting `RpgFx { sparkle, echo, ward, scatter, crack }` + repeat/amplitude.

- [ ] **Step 1: Write the failing test** (append)

```dart
test('A2: rpgSpecFor selects the right effect per flavor', () {
  expect(rpgSpecFor(StatusReactionFlavor.created).style, RpgFx.sparkle);
  expect(rpgSpecFor(StatusReactionFlavor.notModified).style, RpgFx.echo);
  expect(rpgSpecFor(StatusReactionFlavor.unauthorized).style, RpgFx.ward);
  expect(rpgSpecFor(StatusReactionFlavor.forbidden).style, RpgFx.ward);
  expect(rpgSpecFor(StatusReactionFlavor.notFound).style, RpgFx.scatter);
  expect(rpgSpecFor(StatusReactionFlavor.serverCrash).style, RpgFx.crack);
  expect(rpgSpecFor(StatusReactionFlavor.rateLimited).repeat, 3);
});

testWidgets('A2: rpg overlay survives every mapped status code', (tester) async {
  final motion = rpgMotion(reduceEffects: false);
  final controller = ThemeReactionController();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.reactionOverlay(
            context,
            controller: controller,
            child: const Text('app'),
          ),
        ),
      ),
    ),
  );
  for (final code in [201, 204, 304, 401, 403, 404, 408, 429, 500, 503]) {
    controller.fire(
      ThemeReaction(
        kind: ThemeReaction.kindForStatus(code),
        statusCode: code,
        durationMs: 400,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('app'), findsOneWidget, reason: 'code=$code');
  }
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
  controller.dispose();
});
```

Add the import: `import 'package:getman/core/theme/motion/status_reaction_flavor.dart';`

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/rpg_motion_test.dart`
Expected: FAIL — `rpgSpecFor`/`RpgFx` undefined.

- [ ] **Step 3: Add the spec + painters**

In `rpg_motion.dart`, add:

```dart
enum RpgFx { sparkle, echo, ward, scatter, crack }

class _RpgSpec {
  const _RpgSpec(this.style, {this.repeat = 1, this.amplitude = 1.0});
  final RpgFx style;
  final int repeat;
  final double amplitude;
}

_RpgSpec rpgSpecFor(StatusReactionFlavor f) => switch (f) {
  StatusReactionFlavor.noContent => const _RpgSpec(RpgFx.sparkle, amplitude: 0.4),
  StatusReactionFlavor.notModified => const _RpgSpec(RpgFx.echo),
  StatusReactionFlavor.unauthorized ||
  StatusReactionFlavor.forbidden => const _RpgSpec(RpgFx.ward),
  StatusReactionFlavor.notFound => const _RpgSpec(RpgFx.scatter),
  StatusReactionFlavor.timeout => const _RpgSpec(RpgFx.sparkle, amplitude: 0.5),
  StatusReactionFlavor.rateLimited => const _RpgSpec(RpgFx.sparkle, repeat: 3),
  StatusReactionFlavor.serverCrash ||
  StatusReactionFlavor.serverError ||
  StatusReactionFlavor.clientError ||
  StatusReactionFlavor.networkError ||
  StatusReactionFlavor.serviceUnavailable => const _RpgSpec(RpgFx.crack),
  _ => const _RpgSpec(RpgFx.sparkle),
};
```

Store the spec on `_RpgEffect` (set via `rpgSpecFor(flavorFor(r))` in `_onReaction`; keep the existing `isError` field for the shake gate — note `serviceUnavailable` maps to `crack` but is not `isError`, so it won't shake, which is correct: a flicker, not a quake). Select the painter by `e.spec.style` in `build`:

```dart
                        painter: switch (e.spec.style) {
                          RpgFx.crack => _RunicCrackPainter(t: e.controller.value, seed: e.seed),
                          RpgFx.ward => _WardPainter(t: e.controller.value),
                          RpgFx.scatter => _MoteScatterPainter(t: e.controller.value, seed: e.seed),
                          RpgFx.echo => _RuneEchoPainter(t: e.controller.value),
                          RpgFx.sparkle => _SparkleShowerPainter(t: e.controller.value, seed: e.seed, weight: e.weight, repeat: e.spec.repeat, amplitude: e.spec.amplitude),
                        },
```

Add `repeat`/`amplitude` fields to `_SparkleShowerPainter` (count = `((36 + (weight*30).round()) * amplitude).round()`; for `repeat>1`, re-trigger the fall in `repeat` staggered waves by phasing `p` on `(t*repeat)%1`). Add the three new painters:

```dart
/// Hexagonal arcane ward that flares then fades — "blocked by magic".
class _WardPainter extends CustomPainter {
  _WardPainter({required this.t});
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final flare = math.sin((t.clamp(0.0, 1.0)) * math.pi).clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.32;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = RpgPalette.arcane.withValues(alpha: 0.8 * flare);
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * (math.pi * 2 / 6);
      final p = center + Offset(math.cos(a), math.sin(a)) * radius;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant _WardPainter old) => old.t != t;
}

/// Motes scatter outward and wink out — "vanished / not found".
class _MoteScatterPainter extends CustomPainter {
  _MoteScatterPainter({required this.t, required this.seed});
  final double t;
  final int seed;
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final center = size.center(Offset.zero);
    final fade = (1 - t).clamp(0.0, 1.0);
    final core = Paint();
    for (var i = 0; i < 28; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final dist = Curves.easeOut.transform(t) * size.shortestSide *
          (0.2 + rng.nextDouble() * 0.4);
      final p = center + Offset(math.cos(a), math.sin(a)) * dist;
      core.color = (rng.nextDouble() < 0.8 ? RpgPalette.gold : RpgPalette.arcane)
          .withValues(alpha: fade);
      canvas.drawCircle(p, 1.5 + rng.nextDouble() * 2, core);
    }
  }
  @override
  bool shouldRepaint(covariant _MoteScatterPainter old) => old.t != t;
}

/// A translucent rune doubles and drifts — déjà-vu (304 not-modified).
class _RuneEchoPainter extends CustomPainter {
  _RuneEchoPainter({required this.t});
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final fade = math.sin(t.clamp(0.0, 1.0) * math.pi).clamp(0.0, 1.0);
    for (var k = 0; k < 2; k++) {
      final r = size.shortestSide * (0.18 + k * 0.04);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = RpgPalette.arcane.withValues(alpha: (0.5 - k * 0.2) * fade);
      canvas.drawCircle(center + Offset(k * 10.0, 0), r, paint);
    }
  }
  @override
  bool shouldRepaint(covariant _RuneEchoPainter old) => old.t != t;
}
```

- [ ] **Step 4: Run the tests**

Run: `fvm flutter test test/core/theme/themes/rpg_motion_test.dart`
Expected: PASS.

- [ ] **Step 5: Visual check (optional) + analysis gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
fvm flutter test
git add lib/core/theme/themes/rpg/rpg_motion.dart test/core/theme/themes/rpg_motion_test.dart
git commit -m "feat(theme): arcane A2 — per-status sparkle/echo/ward/scatter

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 9: Calm (shared) — restrained A1 + A2

**Files:**
- Modify: `lib/core/theme/themes/shared/calm_motion.dart` (latency-scaled pulse + flavor tint/blink-count; no shake, no build-up)
- Test: `test/core/theme/themes/calm_motion_test.dart`

**Interfaces:**
- Consumes: `latencyWeight` (Task 2), `flavorFor` + `StatusReactionFlavor` (Task 1).
- Produces: pure `_CalmSpec calmSpecFor(StatusReactionFlavor, Color base, Color error)` returning `{Color color, int blinks}`; the bar opacity/duration scale with latency.

Calm themes get **no in-flight build-up** (they set no `sendAffordance`) — only the resolution pulse gains nuance, preserving the loud/calm contrast.

- [ ] **Step 1: Write the failing test** (append)

```dart
test('A2: calmSpecFor sets blink counts + tints', () {
  const base = Color(0xFF3355FF);
  const error = Color(0xFFFF3333);
  expect(calmSpecFor(StatusReactionFlavor.notModified, base, error).blinks, 2);
  expect(calmSpecFor(StatusReactionFlavor.rateLimited, base, error).blinks, 3);
  expect(calmSpecFor(StatusReactionFlavor.unauthorized, base, error).color, error);
  expect(calmSpecFor(StatusReactionFlavor.ok, base, error).blinks, 1);
});

testWidgets('A2: calm overlay survives every mapped status code', (tester) async {
  final motion = calmMotion(reduceEffects: false);
  final controller = ThemeReactionController();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.reactionOverlay(
            context,
            controller: controller,
            child: const Text('app'),
          ),
        ),
      ),
    ),
  );
  for (final code in [201, 204, 304, 401, 403, 404, 408, 429, 500, 503]) {
    controller.fire(
      ThemeReaction(
        kind: ThemeReaction.kindForStatus(code),
        statusCode: code,
        durationMs: 2500,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('app'), findsOneWidget, reason: 'code=$code');
  }
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
  controller.dispose();
});
```

Add imports for `StatusReactionFlavor`/`flavorFor` and `latencyWeight`.

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/calm_motion_test.dart`
Expected: FAIL — `calmSpecFor`/`_CalmSpec` undefined.

- [ ] **Step 3: Implement the spec + scaling**

In `calm_motion.dart`, add (top-level):

```dart
class _CalmSpec {
  const _CalmSpec({required this.color, this.blinks = 1});
  final Color color;
  final int blinks; // 304 = 2 (déjà-vu), 429 = 3 (throttle)
}

_CalmSpec calmSpecFor(StatusReactionFlavor f, Color base, Color error) {
  switch (f) {
    case StatusReactionFlavor.notModified:
      return _CalmSpec(color: base, blinks: 2);
    case StatusReactionFlavor.rateLimited:
      return _CalmSpec(color: error, blinks: 3);
    case StatusReactionFlavor.unauthorized:
    case StatusReactionFlavor.forbidden:
    case StatusReactionFlavor.notFound:
    case StatusReactionFlavor.clientError:
    case StatusReactionFlavor.timeout:
      return _CalmSpec(color: error);
    case StatusReactionFlavor.serverCrash:
    case StatusReactionFlavor.serviceUnavailable:
    case StatusReactionFlavor.serverError:
    case StatusReactionFlavor.networkError:
      return _CalmSpec(color: error);
    case StatusReactionFlavor.created:
    case StatusReactionFlavor.noContent:
    case StatusReactionFlavor.ok:
    case StatusReactionFlavor.cancelled:
      return _CalmSpec(color: base);
  }
}
```

In `_CalmReactionOverlayState`, store `int _blinks = 1;` and `double _weight = 0;`. In `_onReaction`, replace the color logic:

```dart
  void _onReaction(ThemeReaction r) {
    if (r.kind == ThemeReactionKind.sendStarted) return;
    final palette = Theme.of(context).extension<AppPalette>();
    final base = palette?.statusColor(r.statusCode ?? 200) ??
        Theme.of(context).colorScheme.primary;
    final error = Theme.of(context).colorScheme.error;
    final spec = calmSpecFor(flavorFor(r), base, error);
    _color = spec.color;
    _blinks = spec.blinks;
    _weight = latencyWeight(r.durationMs);
    unawaited(_c.forward(from: 0));
  }
```

In the `AnimatedBuilder` body, drive the alpha by `_blinks` and scale opacity by latency (still a thin 3px bar):

```dart
                  final t = _c.value;
                  // blink N times across the sweep, fading in/out each blink.
                  final phase = (t * _blinks) % 1.0;
                  final base = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
                  final a = (base * (0.5 + 0.5 * _weight)).clamp(0.0, 1.0);
                  return Container(
                    height: 3,
                    color: color.withValues(alpha: a),
                  );
```

(Optionally lengthen `_c.duration` for slow responses; keep it simple — the opacity scaling already reads as "heavier".) `AppPalette` is already imported in this file.

- [ ] **Step 4: Run the tests**

Run: `fvm flutter test test/core/theme/themes/calm_motion_test.dart`
Expected: PASS.

- [ ] **Step 5: Analysis gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
git add lib/core/theme/themes/shared/calm_motion.dart test/core/theme/themes/calm_motion_test.dart
git commit -m "feat(theme): calm A1/A2 — latency-scaled, per-status pulse (restrained)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Task 10: Full-suite verification + wiki sync

**Files:**
- Verify: whole repo.
- Modify (wiki, separate repo): the Themes page in `Getman.wiki.git`.

- [ ] **Step 1: Confirm the reduced-path regression test still holds globally**

The existing `test/core/theme/app_motion_test.dart` already asserts every theme's identity defaults. Confirm it passes (no change expected): A1/A2 live only inside the full overlays.

Run: `fvm flutter test test/core/theme/app_motion_test.dart`
Expected: PASS.

- [ ] **Step 2: Run the entire done-bar**

Run:
```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test
fvm flutter test
```
Expected: 0 issues from each analysis pass; format reports 0 changed; all tests green (count ≥ prior baseline + the new tests).

- [ ] **Step 3: Manual visual smoke (recommended)**

Run: `fvm flutter run -d macos`. For each loud theme (Brutalist, Glass, Arcane): send a slow request (e.g. `https://httpbin.org/delay/3`) and watch the in-flight build-up + the heavier resolution; then hit `https://httpbin.org/status/{201,404,429,500,503}` and confirm the distinct micro-personalities. Toggle **reduce visual effects** in Settings → APPEARANCE and confirm everything degrades to the bare child (no build-up, no flavor effects). Tune painter literals by eye where needed and re-commit if changed.

- [ ] **Step 4: Sync the wiki (CLAUDE.md §7)**

```bash
cd /tmp && rm -rf Getman.wiki && git clone https://github.com/thiagomiranda3/Getman.wiki.git
```
Edit the Themes page: add, per loud theme, a one-line "reacts to response latency (the wait builds tension; slow responses resolve heavier) and to notable status codes (201/204/304/401/403/404/408/429/500/503 each get a distinct cue)"; add the calm note ("a restrained status-tinted pulse that scales subtly with latency; 304 double-blinks, 429 triple-blinks"). Use verbatim UI labels.
```bash
cd /tmp/Getman.wiki && git add -A && git commit -m "docs(themes): document latency + status-code reactions (VM-A1/A2)" && git push origin master
```

- [ ] **Step 5: Final commit (if any tuning changed code)**

```bash
git add -A && git commit -m "chore(motion): visual tuning pass for VM-A1/A2 reactions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

## Self-Review (completed during plan authoring)

- **Spec coverage**: A1 build-up → Tasks 3/5/7 (+ calm excluded by design, Task 9). A1 resolution scaling → Tasks 3/5/7/9. A2 classifier → Task 1; A2 per-theme flavors → Tasks 4/6/8/9. `latencyWeight` → Task 2. `reduceVisualEffects` degradation → relies on `const AppMotion()` identity (unchanged) + Task 10 Step 1/Step 3 verification. Performance discipline → single build controller per affordance (Tasks 3/5/7), transient dispose-on-complete reused (existing). Test plan → each task's tests + Task 10. Wiki → Task 10 Step 4. VM-A3 deferral → already recorded in `docs/BACKLOG.md` (no task needed).
- **Placeholder scan**: no TBD/TODO; every code step shows code. The painter *visuals* are concrete, compiling reference implementations explicitly flagged as eye-tunable (Tasks 4/6/8 Step "visual check") — this is a real, runnable step, not a placeholder.
- **Type consistency**: `flavorFor`/`StatusReactionFlavor` (Task 1) used identically in Tasks 4/6/8/9. `latencyWeight`/`inFlightTension`/`kTensionFullMs` (Task 2) used identically in Tasks 3/5/7/9. Per-theme spec functions are named consistently per theme (`stampSpecFor`/`glassSpecFor`/`rpgSpecFor`/`calmSpecFor`) and only referenced within their own theme + test.

## Design refinement made at plan time (vs. spec §6)

The spec floated *shared* `_BarrierEffect`/`_DissolveEffect` painters across loud themes. At plan time this is intentionally **not** done: a brutalist bar, a glass frosted pane, and an arcane hex ward are identity-defining shapes, and forcing one painter would flatten each theme's voice and add a leaky `style`-enum branch. Each loud theme implements its own small flavor painters in its own self-contained `*_motion.dart` (matching how the codebase already organizes themes). The genuinely shared logic — flavor classification and latency scaling — *is* centralized (Tasks 1–2). Net effect, identical UX; cleaner decomposition.
