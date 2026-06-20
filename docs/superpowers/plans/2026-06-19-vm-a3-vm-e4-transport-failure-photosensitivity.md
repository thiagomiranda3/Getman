# VM-A3 + VM-E4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give client-side transport failures (timeout / refused / bad-cert) distinct themed reactions instead of one generic `networkError`, and add an enforced photosensitivity flash-rate guard with a documented policy.

**Architecture:** Split Dio's lossy `connection` failure type; thread a theme-local `TransportFailureKind` through the decoupled `ThemeReaction` so the presentation-layer `flavorFor` classifier can map timeouts → the existing `timeout` flavor and bad-cert → a new `badCertificate` flavor; each theme's spec function gets a `badCertificate` branch reusing existing fx. Separately, a pure `photosensitivity.dart` guard caps repeating flashes at 3 Hz (WCAG 2.3.1) and the calm overlay routes its blink count through it.

**Tech Stack:** Dart/Flutter, `flutter_bloc`, `dio`, `equatable`. Tests are `flutter_test` + `bloc_test`/`mocktail` (existing).

## Global Constraints

- Flutter via `fvm flutter ...` (never plain `flutter`).
- Imports are `package:getman/...` everywhere (no relative imports); directives ordered.
- The motion spine (`lib/core/theme/motion/`) is **pure Dart** — no Flutter imports, no `core/error` import. `ThemeReaction` stays the decoupled bloc currency.
- BLoCs must not import `package:flutter/foundation.dart` except the one justified `compute` ignore already in `tabs_bloc.dart`. Use `dart:developer` `log` for bloc logging.
- No hardcoded sizes/colors/radii/weights in widgets — pull from `context.app*`. (This work adds no widget literals.)
- Done bar (all must pass, all separate processes): `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0), `fvm dart run bloc_tools:bloc lint lib` (0), `fvm dart format lib test` clean, `fvm flutter test` 100% green.
- `analyze` can false-pass generic-variance issues — trust `fvm flutter test` (the CFE) as the compile check.
- Commit messages: `type(scope): summary`, ending with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- No Hive/persistence impact: `NetworkFailureType` is never serialized; no `@HiveType` change, no `build_runner`.

---

### Task 1: Split `NetworkFailureType.connection` into `connectionTimeout` + `connectionError`

**Files:**
- Modify: `lib/core/error/failures.dart:15-23` (enum)
- Modify: `lib/core/network/network_service.dart:106,124-164` (mapper + call site + `@visibleForTesting`)
- Test: `test/core/network/network_service_test.dart` (add a mapping group)
- Modify (compile fix): `test/features/tabs/domain/usecases/send_request_use_case_test.dart:153,180`, `test/features/tabs/presentation/bloc/tabs_bloc_test.dart:595,731,1115` — swap `NetworkFailureType.connection` → `NetworkFailureType.connectionError`

**Interfaces:**
- Produces: `NetworkFailureType` now has `connectionTimeout` and `connectionError` (no more `connection`); full set: `connectionTimeout, connectionError, sendTimeout, receiveTimeout, cancelled, badResponse, badCertificate, unknown`. `NetworkService.mapDioException(DioException e) → NetworkFailure` is now `@visibleForTesting` public.

- [ ] **Step 1: Write the failing test** — append to `test/core/network/network_service_test.dart` (add imports `package:dio/dio.dart` and `package:getman/core/error/failures.dart` at top):

```dart
  group('mapDioException — connection split', () {
    final svc = NetworkService(dio: Dio());
    DioException ex(DioExceptionType t) =>
        DioException(requestOptions: RequestOptions(path: '/'), type: t);

    test('connectionTimeout → NetworkFailureType.connectionTimeout', () {
      expect(
        svc.mapDioException(ex(DioExceptionType.connectionTimeout)).type,
        NetworkFailureType.connectionTimeout,
      );
    });
    test('connectionError → NetworkFailureType.connectionError', () {
      expect(
        svc.mapDioException(ex(DioExceptionType.connectionError)).type,
        NetworkFailureType.connectionError,
      );
    });
    test('sendTimeout → NetworkFailureType.sendTimeout', () {
      expect(
        svc.mapDioException(ex(DioExceptionType.sendTimeout)).type,
        NetworkFailureType.sendTimeout,
      );
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/network/network_service_test.dart`
Expected: FAIL — `mapDioException` undefined and/or `NetworkFailureType.connectionTimeout` undefined.

- [ ] **Step 3: Split the enum** — `lib/core/error/failures.dart`, replace the enum body:

```dart
enum NetworkFailureType {
  connectionTimeout,
  connectionError,
  sendTimeout,
  receiveTimeout,
  cancelled,
  badResponse,
  badCertificate,
  unknown,
}
```

- [ ] **Step 4: Update the mapper** — `lib/core/network/network_service.dart`. Make the method public for test (it already imports `package:flutter/foundation.dart` for `compute`/`debugPrint`, which re-exports `@visibleForTesting`). Rename `_mapDioException` → `mapDioException`, annotate it, update the single call site at line 106 (`throw mapDioException(e);`), and split the connection case:

```dart
  @visibleForTesting
  NetworkFailure mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const NetworkFailure(
          'Request cancelled',
          type: NetworkFailureType.cancelled,
        );
      case DioExceptionType.connectionTimeout:
        return NetworkFailure(
          e.message ?? 'Connection timed out',
          type: NetworkFailureType.connectionTimeout,
        );
      case DioExceptionType.connectionError:
        return NetworkFailure(
          e.message ?? 'Connection failed',
          type: NetworkFailureType.connectionError,
        );
      case DioExceptionType.sendTimeout:
        return NetworkFailure(
          e.message ?? 'Send timeout',
          type: NetworkFailureType.sendTimeout,
        );
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(
          e.message ?? 'Receive timeout',
          type: NetworkFailureType.receiveTimeout,
        );
      case DioExceptionType.badCertificate:
        return NetworkFailure(
          e.message ?? 'Bad certificate',
          type: NetworkFailureType.badCertificate,
        );
      case DioExceptionType.badResponse:
        return NetworkFailure(
          e.message ?? 'Bad response',
          type: NetworkFailureType.badResponse,
          statusCode: e.response?.statusCode,
        );
      case DioExceptionType.unknown:
        return NetworkFailure(
          e.message ?? e.toString(),
          type: NetworkFailureType.unknown,
        );
    }
  }
```

- [ ] **Step 5: Fix the broken `.connection` references in existing tests** — in `send_request_use_case_test.dart` (lines ~153, ~180) and `tabs_bloc_test.dart` (lines ~595, ~731, ~1115), replace every `NetworkFailureType.connection` with `NetworkFailureType.connectionError`. (These are generic "connection failed" simulations; `connectionError` preserves their meaning — `statusCode` 0, `networkError` kind.)

- [ ] **Step 6: Run the affected tests**

Run: `fvm flutter test test/core/network/network_service_test.dart test/features/tabs`
Expected: PASS (all).

- [ ] **Step 7: Full gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/core/error/failures.dart lib/core/network/network_service.dart test/core/network/network_service_test.dart test/features/tabs
git commit -m "refactor(network): split NetworkFailureType.connection into connectionTimeout + connectionError

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add `TransportFailureKind` + `transportFailure` to `ThemeReaction`

**Files:**
- Modify: `lib/core/theme/motion/theme_reaction.dart`
- Test: `test/core/theme/motion/theme_reaction_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum TransportFailureKind { timeout, badCertificate }`; `ThemeReaction` gains `final TransportFailureKind? transportFailure;` (named param `transportFailure`, in `props`).

- [ ] **Step 1: Write the failing test** — add to `test/core/theme/motion/theme_reaction_test.dart` inside `main()`:

```dart
  group('transportFailure field', () {
    test('defaults to null and is part of equality', () {
      const a = ThemeReaction(kind: ThemeReactionKind.networkError);
      expect(a.transportFailure, isNull);
      const b = ThemeReaction(
        kind: ThemeReactionKind.networkError,
        transportFailure: TransportFailureKind.timeout,
      );
      expect(a == b, isFalse);
      expect(b.transportFailure, TransportFailureKind.timeout);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/theme_reaction_test.dart`
Expected: FAIL — `TransportFailureKind` undefined / `transportFailure` named param undefined.

- [ ] **Step 3: Implement** — in `lib/core/theme/motion/theme_reaction.dart`, add the enum above `class ThemeReaction` and the field:

```dart
/// A transport-level (no HTTP status) failure, refined just enough for the
/// theme layer to pick a distinct flavor. Pure Dart; the bloc maps
/// NetworkFailureType → this so the motion spine never imports core/error.
enum TransportFailureKind { timeout, badCertificate }
```

Then update the constructor and `props`:

```dart
  const ThemeReaction({
    required this.kind,
    this.statusCode,
    this.durationMs,
    this.transportFailure,
  });

  final ThemeReactionKind kind;
  final int? statusCode;
  final int? durationMs;

  /// Set only on a [ThemeReactionKind.networkError] reaction, to distinguish
  /// timeout / bad-cert / generic transport failures. Null otherwise.
  final TransportFailureKind? transportFailure;
```

```dart
  @override
  List<Object?> get props => [kind, statusCode, durationMs, transportFailure];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/theme_reaction_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
fvm dart format lib test && fvm flutter analyze
git add lib/core/theme/motion/theme_reaction.dart test/core/theme/motion/theme_reaction_test.dart
git commit -m "feat(theme): add TransportFailureKind discriminator to ThemeReaction

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Add `badCertificate` flavor, refine `flavorFor`, branch all four themes

**Files:**
- Modify: `lib/core/theme/motion/status_reaction_flavor.dart` (enum + `flavorFor` networkError case)
- Modify: `lib/core/theme/themes/shared/calm_motion.dart:23-46` (`calmSpecFor`)
- Modify: `lib/core/theme/themes/rpg/rpg_motion.dart:26-43` (`rpgSpecFor`)
- Modify: `lib/core/theme/themes/brutalist/brutalist_motion.dart:32-42` (`stampSpecFor`)
- Modify: `lib/core/theme/themes/glass/glass_motion.dart:25-48` (`glassSpecFor`)
- Test: `test/core/theme/motion/status_reaction_flavor_test.dart`, `test/core/theme/themes/{calm,rpg,brutalist,glass}_motion_test.dart`

**Interfaces:**
- Consumes: `ThemeReaction.transportFailure`, `TransportFailureKind` (Task 2).
- Produces: `StatusReactionFlavor.badCertificate`. `flavorFor` returns `timeout` for `transportFailure == timeout`, `badCertificate` for `== badCertificate`, `networkError` for `null` (on a `networkError`-kind reaction).

> **Atomic task:** adding the enum value breaks `calmSpecFor`'s exhaustive switch (compile error) until its branch lands. rpg/brutalist/glass use a wildcard `_ =>` so they would silently fall through to a *success-ish* default — their explicit branches are mandatory and asserted by tests, not by the analyzer. Do all of this in one commit.

- [ ] **Step 1: Write the failing tests**

In `test/core/theme/motion/status_reaction_flavor_test.dart`, add a group:

```dart
  group('flavorFor — transport failures', () {
    ThemeReaction net(TransportFailureKind? t) => ThemeReaction(
      kind: ThemeReactionKind.networkError,
      transportFailure: t,
    );
    test('timeout transport → timeout flavor', () {
      expect(flavorFor(net(TransportFailureKind.timeout)),
          StatusReactionFlavor.timeout);
    });
    test('badCertificate transport → badCertificate flavor', () {
      expect(flavorFor(net(TransportFailureKind.badCertificate)),
          StatusReactionFlavor.badCertificate);
    });
    test('null transport → networkError flavor', () {
      expect(flavorFor(net(null)), StatusReactionFlavor.networkError);
    });
  });
```

In each theme spec test, add a `badCertificate` assertion:
- `rpg_motion_test.dart` (inside the `'A2: rpgSpecFor selects...'` test): `expect(rpgSpecFor(StatusReactionFlavor.badCertificate).style, RpgFx.ward);`
- `brutalist_motion_test.dart` (in its spec-fn test): `expect(stampSpecFor(StatusReactionFlavor.badCertificate).barrier, isTrue);`
- `glass_motion_test.dart` (in its spec-fn test): `expect(glassSpecFor(StatusReactionFlavor.badCertificate).style, GlassFx.barrier);`
- `calm_motion_test.dart` (in its `calmSpecFor` test): `expect(calmSpecFor(StatusReactionFlavor.badCertificate, base, error).color, error);` (reuse whatever `base`/`error` colors that test already constructs).

- [ ] **Step 2: Run tests to verify they fail**

Run: `fvm flutter test test/core/theme/motion/status_reaction_flavor_test.dart test/core/theme/themes`
Expected: FAIL — `StatusReactionFlavor.badCertificate` undefined.

- [ ] **Step 3a: Add the flavor + refine `flavorFor`** — `lib/core/theme/motion/status_reaction_flavor.dart`. Add `badCertificate` to the enum (after `networkError`):

```dart
  networkError,
  badCertificate,
  cancelled,
```

Replace the `networkError` case in `flavorFor`:

```dart
    case ThemeReactionKind.networkError:
      return switch (r.transportFailure) {
        TransportFailureKind.timeout => StatusReactionFlavor.timeout,
        TransportFailureKind.badCertificate =>
          StatusReactionFlavor.badCertificate,
        null => StatusReactionFlavor.networkError,
      };
```

- [ ] **Step 3b: calm branch** — `calm_motion.dart` `calmSpecFor`, add an explicit case (a distinct "rejected" double-tick; the count is flash-guarded in Task 6):

```dart
    case StatusReactionFlavor.badCertificate:
      return CalmSpec(color: error, blinks: 2);
```

- [ ] **Step 3c: rpg branch** — `rpg_motion.dart` `rpgSpecFor`, add **before** the `_ =>` wildcard (broken/rejected ward — the trust-barrier idiom):

```dart
  StatusReactionFlavor.badCertificate => const RpgSpec(RpgFx.ward),
```

- [ ] **Step 3d: brutalist branch** — `brutalist_motion.dart` `stampSpecFor`, add before the `_ =>` wildcard (a bar slammed across — rejected):

```dart
  StatusReactionFlavor.badCertificate => const StampSpec(barrier: true),
```

- [ ] **Step 3e: glass branch** — `glass_motion.dart` `glassSpecFor`, add before the `_ =>` wildcard:

```dart
  StatusReactionFlavor.badCertificate => const GlassSpec(GlassFx.barrier),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/core/theme`
Expected: PASS.

- [ ] **Step 5: Full gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/core/theme test/core/theme
git commit -m "feat(theme): badCertificate reaction flavor + transport-failure flavorFor mapping

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire the bloc — map `NetworkFailureType` → `TransportFailureKind` at the emit

**Files:**
- Modify: `lib/features/tabs/presentation/bloc/tabs_bloc.dart:562-568` (+ a private top-level helper)
- Test: `test/features/tabs/presentation/bloc/tabs_bloc_test.dart` (reaction-emission group, ~line 1107)

**Interfaces:**
- Consumes: `NetworkFailureType` (Task 1), `TransportFailureKind`/`ThemeReaction.transportFailure` (Task 2), `StatusReactionFlavor` mapping (Task 3).
- Produces: the `on NetworkFailure` error reaction now carries `transportFailure`.

- [ ] **Step 1: Write the failing tests** — in the `'reaction emission'` group of `tabs_bloc_test.dart`, (a) extend the **existing** networkError test (~1105, whose failure type Task 1 already changed to `connectionError`) with one new assertion line after the `statusCode` check, and (b) add two new tests right after it. They follow the group's established harness exactly (`loadWith`, `stubSend`, `emitsThrough`). `TransportFailureKind` comes from `package:getman/core/theme/motion/theme_reaction.dart` (already imported).

(a) In the existing networkError test, after `expect(reaction.statusCode, 0);` add:

```dart
        expect(reaction.transportFailure, isNull);
```

(b) Add these two tests:

```dart
    test(
      'receiveTimeout NetworkFailure → transportFailure timeout',
      () async {
        await loadWith([tab('a')]);
        final baseSeq = bloc.state.reactionSeq;

        stubSend(
          () async => throw const NetworkFailure(
            'receive timeout',
            type: NetworkFailureType.receiveTimeout,
          ),
        );

        bloc.add(const SendRequest(tabId: 'a'));
        await expectLater(
          bloc.stream,
          emitsThrough(predicate<TabsState>((s) => !s.tabs.single.isSending)),
        );

        final reaction = bloc.state.lastReaction!;
        expect(reaction.kind, ThemeReactionKind.networkError);
        expect(reaction.transportFailure, TransportFailureKind.timeout);
        expect(bloc.state.reactionSeq, baseSeq + 2);
      },
    );

    test(
      'badCertificate NetworkFailure → transportFailure badCertificate',
      () async {
        await loadWith([tab('a')]);

        stubSend(
          () async => throw const NetworkFailure(
            'bad cert',
            type: NetworkFailureType.badCertificate,
          ),
        );

        bloc.add(const SendRequest(tabId: 'a'));
        await expectLater(
          bloc.stream,
          emitsThrough(predicate<TabsState>((s) => !s.tabs.single.isSending)),
        );

        final reaction = bloc.state.lastReaction!;
        expect(reaction.kind, ThemeReactionKind.networkError);
        expect(
          reaction.transportFailure,
          TransportFailureKind.badCertificate,
        );
      },
    );
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `fvm flutter test test/features/tabs/presentation/bloc/tabs_bloc_test.dart --plain-name 'reaction emission'`
Expected: FAIL — `transportFailure` is null for the timeout/bad-cert cases (not yet wired).

- [ ] **Step 3: Implement** — in `tabs_bloc.dart`, update the `on NetworkFailure` reaction (the block at ~562) to pass the mapped discriminator:

```dart
      _fireReaction(
        emit,
        ThemeReaction(
          kind: ThemeReaction.kindForStatus(errorResponse.statusCode),
          statusCode: errorResponse.statusCode,
          transportFailure: _transportFailureFor(f.type),
        ),
      );
```

Add a private top-level helper at the bottom of the file (exhaustive over `NetworkFailureType`):

```dart
/// Maps a transport-level [NetworkFailureType] to the theme-layer
/// [TransportFailureKind]. Returns null for failures that carry (or imply) a
/// real HTTP status / generic reach failure — those keep the plain
/// networkError flavor. The motion spine never imports core/error, so this
/// mapping lives here, at the integration point.
TransportFailureKind? _transportFailureFor(NetworkFailureType t) => switch (t) {
  NetworkFailureType.sendTimeout ||
  NetworkFailureType.receiveTimeout ||
  NetworkFailureType.connectionTimeout => TransportFailureKind.timeout,
  NetworkFailureType.badCertificate => TransportFailureKind.badCertificate,
  NetworkFailureType.connectionError ||
  NetworkFailureType.badResponse ||
  NetworkFailureType.cancelled ||
  NetworkFailureType.unknown => null,
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/tabs/presentation/bloc/tabs_bloc_test.dart`
Expected: PASS.

- [ ] **Step 5: Full gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/features/tabs/presentation/bloc/tabs_bloc.dart test/features/tabs/presentation/bloc/tabs_bloc_test.dart
git commit -m "feat(theme): thread transport-failure kind from TabsBloc into the reaction (VM-A3)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Photosensitivity guard utility (VM-E4)

**Files:**
- Create: `lib/core/theme/motion/photosensitivity.dart`
- Test: `test/core/theme/motion/photosensitivity_test.dart`

**Interfaces:**
- Produces: `const int kMaxSafeFlashesPerSecond = 3;`, `const Duration kMinFlashPeriod;`, `int safeFlashCount(Duration sweep, int desired)` (clamps a flash/blink count so its rate ≤ `kMaxSafeFlashesPerSecond` over `sweep`; floors at 1).

- [ ] **Step 1: Write the failing test** — `test/core/theme/motion/photosensitivity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/photosensitivity.dart';

void main() {
  test('caps at 3 flashes per second', () {
    expect(kMaxSafeFlashesPerSecond, 3);
  });

  group('safeFlashCount', () {
    test('clamps an over-rate count down to the budget', () {
      // 700ms window allows floor(700*3/1000) = 2 flashes.
      expect(safeFlashCount(const Duration(milliseconds: 700), 3), 2);
    });
    test('passes an in-budget count through', () {
      // 1000ms allows 3.
      expect(safeFlashCount(const Duration(seconds: 1), 3), 3);
    });
    test('never returns less than 1', () {
      expect(safeFlashCount(const Duration(milliseconds: 100), 5), 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/photosensitivity_test.dart`
Expected: FAIL — file/symbols not found.

- [ ] **Step 3: Implement** — `lib/core/theme/motion/photosensitivity.dart`:

```dart
/// Photosensitivity (flash-safety) guard. WCAG 2.3.1 "general flash threshold":
/// content must not flash more than three times in any one-second period.
/// Pure Dart so the whole motion spine can use it.
library;

/// Maximum safe number of general flashes per second (WCAG 2.3.1).
const int kMaxSafeFlashesPerSecond = 3;

/// Shortest safe period between flash onsets (~333ms).
const Duration kMinFlashPeriod = Duration(
  milliseconds: 1000 ~/ kMaxSafeFlashesPerSecond,
);

/// Clamps a desired flash/blink count over [sweep] so the resulting rate never
/// exceeds [kMaxSafeFlashesPerSecond]. Always returns at least 1.
int safeFlashCount(Duration sweep, int desired) {
  final budget = sweep.inMilliseconds * kMaxSafeFlashesPerSecond ~/ 1000;
  final ceiling = budget < 1 ? 1 : budget;
  return desired.clamp(1, ceiling);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/photosensitivity_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test
git add lib/core/theme/motion/photosensitivity.dart test/core/theme/motion/photosensitivity_test.dart
git commit -m "feat(theme): photosensitivity flash-rate guard (kMaxSafeFlashesPerSecond, safeFlashCount)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Route calm blinks through the guard + document the policy (VM-E4)

**Files:**
- Modify: `lib/core/theme/themes/shared/calm_motion.dart:79-91` (`_onReaction`, the `_blinks` assignment)
- Modify: `docs/THEME_AUTHORING.md` (new policy subsection near §5 + a §3 checklist line)
- Test: `test/core/theme/themes/calm_motion_test.dart` (widget smoke: badCert reaction renders without throwing)

**Interfaces:**
- Consumes: `safeFlashCount` / `kMaxSafeFlashesPerSecond` (Task 5).

- [ ] **Step 1: Write the failing test** — add to `calm_motion_test.dart` a smoke test that the calm overlay handles a bad-cert (networkError + badCertificate transport) reaction without throwing:

```dart
  testWidgets('calm overlay survives a bad-certificate reaction', (
    tester,
  ) async {
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
    controller.fire(
      const ThemeReaction(
        kind: ThemeReactionKind.networkError,
        transportFailure: TransportFailureKind.badCertificate,
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
```

(Ensure `theme_reaction.dart` is imported in the test — it is, via existing imports; add if missing.)

- [ ] **Step 2: Run test to verify it fails or is red-for-the-right-reason**

Run: `fvm flutter test test/core/theme/themes/calm_motion_test.dart`
Expected: FAIL only if a symbol/import is missing; if it already passes (overlay is robust), proceed — the substantive change is the guard wiring below, and Step 4 re-confirms green.

- [ ] **Step 3: Route the blink count through the guard** — `calm_motion.dart`. Add the import:

```dart
import 'package:getman/core/theme/motion/photosensitivity.dart';
```

In `_onReaction`, clamp the blink count to the safe rate over the controller's sweep duration:

```dart
    final spec = calmSpecFor(flavorFor(r), base, error);
    _color = spec.color;
    _blinks = safeFlashCount(_c.duration, spec.blinks);
    _weight = latencyWeight(r.durationMs);
```

(`_c.duration` is 700ms → `rateLimited`'s nominal 3 blinks clamps to 2, ~2.9 Hz, below the cap. Single-blink errors are unaffected. The new bad-cert double-tick is already in budget.)

- [ ] **Step 4: Run test to verify it passes + calm suite green**

Run: `fvm flutter test test/core/theme/themes/calm_motion_test.dart`
Expected: PASS.

- [ ] **Step 5: Document the policy** — `docs/THEME_AUTHORING.md`. Add a subsection immediately after §5 (`reduceVisualEffects`):

```markdown
## 5b. Photosensitivity (flash safety) — mandatory

WCAG 2.3.1 (general flash threshold): nothing may flash more than **3 times per
second**. This is independent of `reduceVisualEffects` (a motion/vestibular
concern) — flash safety applies even at full effects.

- Any **repeating** flash/blink/strobe MUST cap its rate via
  `lib/core/theme/motion/photosensitivity.dart`: clamp the count with
  `safeFlashCount(sweep, desired)` or gate the period at `kMinFlashPeriod`.
  (See `shared/calm_motion.dart` `_onReaction` for the reference use.)
- **Large / full-screen** flashes are the real hazard — they MUST route through
  the guard *and* still degrade under `reduceVisualEffects`. Small-area
  one-shot fades/sweeps/sparkles are not "flashes" and need no clamp, but never
  let a count parameter scale them into a rapid full-screen strobe.
- Audited at this writing: calm's pulse-bar blink is guarded; rpg/brutalist/
  glass terminal effects are single-shot or small-area below the cap.
```

Then add a line to the §3 reactive checklist:

```markdown
- [ ] **Flash safety** — any repeating flash/blink respects
  `kMaxSafeFlashesPerSecond` via the photosensitivity guard (§5b).
```

- [ ] **Step 6: Full gate + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/core/theme/themes/shared/calm_motion.dart docs/THEME_AUTHORING.md test/core/theme/themes/calm_motion_test.dart
git commit -m "feat(theme): enforce 3Hz flash cap in calm overlay + document photosensitivity policy (VM-E4)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Backlog + memory bookkeeping; push

**Files:**
- Modify: `docs/BACKLOG.md` (drop VM-A3 and VM-E4 from the open list; update "Current state")

- [ ] **Step 1: Remove VM-A3 and VM-E4** from `docs/BACKLOG.md` (they're completed; this backlog tracks open work only). Update the "Current state" bullet to note VM-A3/VM-E4 shipped on `dev` with the commit range.

- [ ] **Step 2: Commit + push the whole branch**

```bash
git add docs/BACKLOG.md
git commit -m "docs: mark VM-A3 + VM-E4 shipped; drop from open backlog

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push origin dev
```

- [ ] **Step 3: Confirm push + clean state**

Run: `git status && git log origin/dev..dev --oneline`
Expected: clean tree; no unpushed commits.

---

## Notes for the executor

- **Wiki:** VM-A3/VM-E4 add no new user-facing control or label (internal motion polish over the existing "themes react to outcomes" behavior). No wiki edit required per the spec; if the bad-cert reaction feels worth surfacing, that's a one-line optional add to the Themes-and-Appearance page — confirm with the user, don't block on it.
- **Memory:** after the push, append/update a memory line for this session (the VM-A1/A2 memory file is the natural neighbor — link with `[[vm-a1-a2-latency-status-reactions]]`).
- **Order matters:** Tasks 1→2→3→4 are a dependency chain (enum → field → flavor+themes → bloc). Tasks 5→6 (VM-E4) are independent of 1–4 and can be done in parallel by a separate agent if desired, but 6 references the bad-cert reaction from Task 3 in its smoke test, so run 6 after 3.
