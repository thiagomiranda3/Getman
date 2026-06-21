# Theme Motion Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five themed-motion moments — in-flight panel frame (VM-B1), tab/panel transition choreography (VM-B2), tree drag-drop juice (VM-B3), interactive ambient (VM-C1), and session-rhythm ambient (VM-C2) — built on the existing reactive-motion spine.

**Architecture:** Approach C (hybrid). Discrete identity-default hooks on `AppMotion` drive the event-in-time features (B1/B2/B3); one shared `AmbientSignals` object threaded once into each `scaffoldBackground` painter drives the ambient features (C1/C2), fed by a new `WorkspacePulseController`. Loud themes (Arcane/Glass/Brutalist/AURIS) get full effects; calm themes (Classic/Editorial/Dracula) inherit identity for free. New ambient painters are authored for Brutalist + AURIS (they have none today).

**Tech Stack:** Flutter, `flutter_bloc`, `get_it`, `provider` (`ChangeNotifierProvider`), `CustomPainter`/`AnimationController` motion, `very_good_analysis` + project `custom_lint` + `bloc_lint`. Invoke Flutter as `fvm flutter ...`.

**Design doc:** [`docs/superpowers/specs/2026-06-20-theme-motion-expansion-design.md`](../specs/2026-06-20-theme-motion-expansion-design.md)

## Global Constraints

- **Flutter via `fvm`** — `fvm flutter ...`, never bare `flutter`.
- **Done-bar (every task ends green):** `fvm flutter analyze` = 0 issues, `fvm dart run custom_lint` = 0 issues, `fvm dart run bloc_tools:bloc lint lib` = 0 issues, `fvm dart format lib test` clean, `fvm flutter test` 100% green. These are independent passes — a clean analyze does NOT imply custom_lint/bloc_lint are clean.
- **Theme adherence:** never hardcode sizes/colors/radii/weights — pull from `context.appLayout/appPalette/appShape/appTypography/appDecoration`. Theme-internal files under `lib/core/theme/themes/<name>/` may use that theme's own palette constants. `Colors.white`/`Colors.black` are allowed ONLY under `lib/core/theme/` (exempt from `avoid_hardcoded_brand_colors`).
- **`reduceVisualEffects` is mandatory degradation:** every new `AppMotion` hook returns the child unchanged when the theme is built with `reduceEffects: true`; ambient uses its static variant (no controller, no signals, no pointer subscription); transitions become instant cuts. No exceptions.
- **Photosensitivity (WCAG 2.3.1, independent of reduceEffects):** any *repeating* flash/blink ≤ 3 Hz via `safeFlashCount`/`kMaxSafeFlashesPerSecond` in `lib/core/theme/motion/photosensitivity.dart`. Prefer continuous motion over flashing.
- **Performance discipline:** one `AnimationController` per always-on ambient layer; `RepaintBoundary` around painters; pause on `AppLifecycleState`; reuse `Paint` objects (mutate `.color`/`.shader`), build `Path`s once; transient effects self-dispose on `AnimationStatus.completed` with double-dispose guards; child-hoist (`AnimatedBuilder(child: ...)`) so the app subtree never rebuilds per frame.
- **Imports are `package:getman/...`** everywhere (no relative imports). Files end with a trailing newline; run `fvm dart format` before every commit.
- **Touch gating:** C1 pointer/click effects are desktop/web-pointer only (`MouseRegion`/`Listener`), no-op on touch.
- **Calm/loud contrast:** do NOT give calm themes (Classic/Editorial/Dracula) any of these effects. They stay at identity by design.

---

## File Structure

**New files:**
- `lib/core/theme/motion/workspace_pulse_controller.dart` — the C2 activity/idle signal (`ChangeNotifier`).
- `lib/core/theme/motion/ambient_signals.dart` — `AmbientSignals` + `AmbientImpulse` value types (C1/C2 painter input).
- `lib/core/theme/themes/brutalist/brutalist_ambient.dart` — Brutalist animated + static `scaffoldBackground` + painter.
- `lib/core/theme/themes/auris/auris_ambient.dart` — AURIS animated + static `scaffoldBackground` + painter.
- Tests mirroring each (under `test/core/theme/...`).

**Modified files:**
- `lib/core/theme/extensions/app_motion.dart` — add `inFlightFrame`, `contentTransition`, `tabChipTransition`, and tree hooks (identity defaults).
- `lib/core/di/injection_container.dart` — register `WorkspacePulseController` singleton.
- `lib/main.dart` — provide `WorkspacePulseController`.
- `lib/features/home/presentation/widgets/theme_reaction_listener.dart` — `pulse.bump()` on each reaction.
- `lib/features/tabs/presentation/screens/request_view.dart` — mount `inFlightFrame` (B1).
- `lib/features/home/presentation/widgets/tab_content_stack.dart` — mount `contentTransition` (B2).
- `lib/features/home/presentation/screens/main_screen.dart` — tab-strip `tabChipTransition` (B2).
- `lib/features/collections/presentation/widgets/collection_node_row.dart` — tree hooks (B3).
- The four loud-theme dirs: `<name>_motion.dart` (B1/B2/B3 effects) and `<name>_theme.dart` (wire ambient for brutalist/auris); `rpg_decorations.dart` + `glass_decorations.dart` (extend painters for C1/C2).

---

## Task 1: New `AppMotion` hooks (identity defaults)

**Files:**
- Modify: `lib/core/theme/extensions/app_motion.dart`
- Test: `test/core/theme/extensions/app_motion_test.dart`

**Interfaces:**
- Produces — new typedefs + `AppMotion` fields (all identity-default):
  - `InFlightFrameBuilder = Widget Function(BuildContext, {required Widget child, required bool isSending})`
  - `ContentTransitionBuilder = Widget Function(BuildContext, {required Widget child, required String transitionKey})`
  - `TabChipTransitionBuilder = Widget Function(BuildContext, {required Widget child, required Animation<double> animation})`
  - `TreeDragFeedbackBuilder = Widget Function(BuildContext, {required Widget child})`
  - `TreeDropHighlightBuilder = Widget Function(BuildContext, {required Widget child, required bool active})`
  - `TreeExpandFlourishBuilder = Widget Function(BuildContext, {required Widget child, required bool expanded})`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/extensions/app_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

void main() {
  testWidgets('default AppMotion hooks are identity (return child unchanged)', (
    tester,
  ) async {
    const m = AppMotion();
    const marker = SizedBox(key: ValueKey('m'));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      identical(m.inFlightFrame(ctx, child: marker, isSending: true), marker),
      isTrue,
    );
    expect(
      identical(
        m.contentTransition(ctx, child: marker, transitionKey: 'a'),
        marker,
      ),
      isTrue,
    );
    expect(
      identical(
        m.tabChipTransition(
          ctx,
          child: marker,
          animation: const AlwaysStoppedAnimation<double>(1),
        ),
        marker,
      ),
      isTrue,
    );
    expect(
      identical(m.treeDragFeedback(ctx, child: marker), marker),
      isTrue,
    );
    expect(
      identical(m.treeDropHighlight(ctx, child: marker, active: true), marker),
      isTrue,
    );
    expect(
      identical(m.treeExpandFlourish(ctx, child: marker, expanded: true), marker),
      isTrue,
    );
  });

  test('copyWith overrides only the supplied hooks', () {
    Widget custom(BuildContext c, {required Widget child, required bool isSending}) =>
        const SizedBox(key: ValueKey('custom'));
    const base = AppMotion();
    final copy = base.copyWith(inFlightFrame: custom);
    expect(identical(copy.inFlightFrame, custom), isTrue);
    expect(identical(copy.reactionOverlay, base.reactionOverlay), isTrue);
    expect(identical(copy.contentTransition, base.contentTransition), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/extensions/app_motion_test.dart`
Expected: FAIL — `inFlightFrame`/`contentTransition`/etc. not defined on `AppMotion`.

- [ ] **Step 3: Add the typedefs, identity functions, fields, and copyWith entries**

Append the typedefs (after the existing `SendAffordanceBuilder`) and identity functions, then extend the class. Full new content for `app_motion.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// Wraps the whole app: may Transform the child (e.g. screen shake) and Stack
/// transient effects above it. Subscribes to [controller] for reactions.
typedef ReactionOverlayBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required ThemeReactionController controller,
    });

/// Wraps the SEND control: plays the theme's send ritual and renders its
/// "charging" state while [isSending].
typedef SendAffordanceBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required bool isSending,
    });

/// VM-B1: wraps the request+response panel area; renders a themed frame while
/// [isSending] (the displayed tab's send is in flight).
typedef InFlightFrameBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required bool isSending,
    });

/// VM-B2: wraps the active tab/panel content; plays a themed transition when
/// [transitionKey] changes (keyed on "$activePanelId/$activeTabId").
typedef ContentTransitionBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required String transitionKey,
    });

/// VM-B2: transition builder for tab-strip chips entering/leaving (used as an
/// AnimatedSwitcher/AnimatedList transitionBuilder; [animation] is 0→1 enter).
typedef TabChipTransitionBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required Animation<double> animation,
    });

/// VM-B3: themed widget shown under the cursor while dragging a tree node.
typedef TreeDragFeedbackBuilder =
    Widget Function(BuildContext context, {required Widget child});

/// VM-B3: wraps a folder drop target; [active] is true while a draggable hovers
/// over it (themed highlight + an absorb cue on accept).
typedef TreeDropHighlightBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required bool active,
    });

/// VM-B3: a brief flourish wrapped around a node's expand/collapse toggle;
/// [expanded] is the post-toggle state. NOT a height animation (the TreeView
/// row extent is fixed) — an icon/glow flourish or short overlay only.
typedef TreeExpandFlourishBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required bool expanded,
    });

Widget _identityReactionOverlay(
  BuildContext context, {
  required Widget child,
  required ThemeReactionController controller,
}) => child;

Widget _identitySendAffordance(
  BuildContext context, {
  required Widget child,
  required bool isSending,
}) => child;

Widget _identityInFlightFrame(
  BuildContext context, {
  required Widget child,
  required bool isSending,
}) => child;

Widget _identityContentTransition(
  BuildContext context, {
  required Widget child,
  required String transitionKey,
}) => child;

Widget _identityTabChipTransition(
  BuildContext context, {
  required Widget child,
  required Animation<double> animation,
}) => child;

Widget _identityTreeDragFeedback(
  BuildContext context, {
  required Widget child,
}) => child;

Widget _identityTreeDropHighlight(
  BuildContext context, {
  required Widget child,
  required bool active,
}) => child;

Widget _identityTreeExpandFlourish(
  BuildContext context, {
  required Widget child,
  required bool expanded,
}) => child;

/// Event-driven motion hooks for a theme. All default to identity, so a theme
/// that supplies no motion is completely unaffected (mirrors
/// AppDecoration.frost). Closures don't lerp — copyWith/lerp follow the
/// AppDecoration pattern.
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    this.reactionOverlay = _identityReactionOverlay,
    this.sendAffordance = _identitySendAffordance,
    this.inFlightFrame = _identityInFlightFrame,
    this.contentTransition = _identityContentTransition,
    this.tabChipTransition = _identityTabChipTransition,
    this.treeDragFeedback = _identityTreeDragFeedback,
    this.treeDropHighlight = _identityTreeDropHighlight,
    this.treeExpandFlourish = _identityTreeExpandFlourish,
  });

  final ReactionOverlayBuilder reactionOverlay;
  final SendAffordanceBuilder sendAffordance;
  final InFlightFrameBuilder inFlightFrame;
  final ContentTransitionBuilder contentTransition;
  final TabChipTransitionBuilder tabChipTransition;
  final TreeDragFeedbackBuilder treeDragFeedback;
  final TreeDropHighlightBuilder treeDropHighlight;
  final TreeExpandFlourishBuilder treeExpandFlourish;

  @override
  AppMotion copyWith({
    ReactionOverlayBuilder? reactionOverlay,
    SendAffordanceBuilder? sendAffordance,
    InFlightFrameBuilder? inFlightFrame,
    ContentTransitionBuilder? contentTransition,
    TabChipTransitionBuilder? tabChipTransition,
    TreeDragFeedbackBuilder? treeDragFeedback,
    TreeDropHighlightBuilder? treeDropHighlight,
    TreeExpandFlourishBuilder? treeExpandFlourish,
  }) => AppMotion(
    reactionOverlay: reactionOverlay ?? this.reactionOverlay,
    sendAffordance: sendAffordance ?? this.sendAffordance,
    inFlightFrame: inFlightFrame ?? this.inFlightFrame,
    contentTransition: contentTransition ?? this.contentTransition,
    tabChipTransition: tabChipTransition ?? this.tabChipTransition,
    treeDragFeedback: treeDragFeedback ?? this.treeDragFeedback,
    treeDropHighlight: treeDropHighlight ?? this.treeDropHighlight,
    treeExpandFlourish: treeExpandFlourish ?? this.treeExpandFlourish,
  );

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) => this;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/extensions/app_motion_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test
git add lib/core/theme/extensions/app_motion.dart test/core/theme/extensions/app_motion_test.dart
git commit -m "feat(motion): add identity-default AppMotion hooks for B1/B2/B3"
```

---

## Task 2: `WorkspacePulseController` (C2 signal) + DI + provider + feed

**Files:**
- Create: `lib/core/theme/motion/workspace_pulse_controller.dart`
- Modify: `lib/core/di/injection_container.dart` (register singleton next to `ThemeReactionController`)
- Modify: `lib/main.dart` (provide via `ChangeNotifierProvider.value`, beside `ThemeReactionController` at ~line 198)
- Modify: `lib/features/home/presentation/widgets/theme_reaction_listener.dart` (call `pulse.bump()`)
- Test: `test/core/theme/motion/workspace_pulse_controller_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `WorkspacePulseController extends ChangeNotifier` with `double get activityLevel` (0..1), `double get idleFactor` (0..1), `void bump()`, `void touch()`, `@visibleForTesting void tick()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/motion/workspace_pulse_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

void main() {
  test('starts idle-free and inactive', () {
    final c = WorkspacePulseController();
    expect(c.activityLevel, 0);
    expect(c.idleFactor, 0);
    c.dispose();
  });

  test('bump raises activity (clamped to 1) and resets idle', () {
    final c = WorkspacePulseController();
    // Build up some idle first.
    for (var i = 0; i < 40; i++) {
      c.tick();
    }
    expect(c.idleFactor, 1);
    c.bump();
    expect(c.activityLevel, greaterThan(0));
    expect(c.idleFactor, 0);
    // Many bumps clamp at 1.
    for (var i = 0; i < 20; i++) {
      c.bump();
    }
    expect(c.activityLevel, 1);
    c.dispose();
  });

  test('tick decays activity toward 0 and raises idleFactor', () {
    final c = WorkspacePulseController();
    c.bump();
    final afterBump = c.activityLevel;
    c.tick();
    expect(c.activityLevel, lessThan(afterBump));
    // Enough ticks fully decays activity and saturates idle.
    for (var i = 0; i < 60; i++) {
      c.tick();
    }
    expect(c.activityLevel, 0);
    expect(c.idleFactor, 1);
    c.dispose();
  });

  test('touch resets idle without changing activity', () {
    final c = WorkspacePulseController();
    for (var i = 0; i < 40; i++) {
      c.tick();
    }
    expect(c.idleFactor, 1);
    c.touch();
    expect(c.idleFactor, 0);
    expect(c.activityLevel, 0);
    c.dispose();
  });

  test('notifies listeners on bump', () {
    final c = WorkspacePulseController();
    var notified = 0;
    c.addListener(() => notified++);
    c.bump();
    expect(notified, greaterThan(0));
    c.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/workspace_pulse_controller_test.dart`
Expected: FAIL — file/class does not exist.

- [ ] **Step 3: Create the controller**

```dart
// lib/core/theme/motion/workspace_pulse_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

/// App-wide "session rhythm" signal for VM-C2: ambient backgrounds read it to
/// intensify on a burst of sends ([activityLevel]) and to calm down after
/// inactivity ([idleFactor]).
///
/// Logic lives here (unit-tested in isolation) so the painters stay logic-free
/// and just read two doubles. A low-frequency timer drives decay/idle; it only
/// runs while something is listening (started in [addListener], cancelled when
/// the last listener leaves), so it never wakes the app when no animated
/// ambient is mounted (e.g. reduceEffects or a calm theme).
class WorkspacePulseController extends ChangeNotifier {
  WorkspacePulseController({
    Duration tickInterval = const Duration(seconds: 1),
  }) : _tickInterval = tickInterval;

  final Duration _tickInterval;
  Timer? _timer;

  // 0..1 recent-send intensity; multiplicative decay per tick.
  double _activity = 0;
  // 0..1 idle ramp; rises one step per tick, resets on activity/touch.
  double _idle = 0;

  static const double _bumpAmount = 0.34; // each send
  static const double _decayPerTick = 0.85; // ~6 ticks to near-zero
  static const double _idleStep = 1 / 30; // ~30 ticks (≈30s) to fully idle

  double get activityLevel => _activity;
  double get idleFactor => _idle;

  /// A request reaction happened — intensify and clear idle.
  void bump() {
    _activity = (_activity + _bumpAmount).clamp(0.0, 1.0);
    _idle = 0;
    notifyListeners();
  }

  /// User interacted (pointer/click) — clear idle only.
  void touch() {
    if (_idle == 0) return;
    _idle = 0;
    notifyListeners();
  }

  /// One decay/idle step. Driven by the internal timer; exposed for tests.
  @visibleForTesting
  void tick() {
    final before = _activity;
    final beforeIdle = _idle;
    _activity *= _decayPerTick;
    if (_activity < 0.01) _activity = 0;
    _idle = (_idle + _idleStep).clamp(0.0, 1.0);
    if (_activity != before || _idle != beforeIdle) notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _timer ??= Timer.periodic(_tickInterval, (_) => tick());
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/workspace_pulse_controller_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Register in DI**

In `lib/core/di/injection_container.dart`, find the `ThemeReactionController` registration (search `ThemeReactionController`) and add directly below it:

```dart
sl.registerLazySingleton<WorkspacePulseController>(
  WorkspacePulseController.new,
);
```

Add the import at the top (alphabetical, package import):
```dart
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
```

- [ ] **Step 6: Provide it in main.dart**

In `lib/main.dart`, find the `ChangeNotifierProvider<ThemeReactionController>.value(...)` (~line 198) and add a sibling in the same providers list:

```dart
ChangeNotifierProvider<WorkspacePulseController>.value(
  value: di.sl<WorkspacePulseController>(),
),
```

Add the import:
```dart
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
```

- [ ] **Step 7: Feed it from the reaction listener**

In `lib/features/home/presentation/widgets/theme_reaction_listener.dart`, inside the `listener:` callback, after `context.read<ThemeReactionController>().fire(reaction);` add:

```dart
context.read<WorkspacePulseController>().bump();
```

Add the import:
```dart
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
```

- [ ] **Step 8: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/core/theme/motion/workspace_pulse_controller.dart lib/core/di/injection_container.dart lib/main.dart lib/features/home/presentation/widgets/theme_reaction_listener.dart test/core/theme/motion/workspace_pulse_controller_test.dart
git commit -m "feat(motion): add WorkspacePulseController session-rhythm signal + wiring"
```

---

## Task 3: `AmbientSignals` + `AmbientImpulse` value types

**Files:**
- Create: `lib/core/theme/motion/ambient_signals.dart`
- Test: `test/core/theme/motion/ambient_signals_test.dart`

**Interfaces:**
- Consumes: `WorkspacePulseController` (Task 2).
- Produces:
  - `AmbientImpulse({required Offset position, required int bornAtMs})` — `position` is normalized 0..1; immutable + `==`/`hashCode`.
  - `AmbientSignals({required ValueListenable<Offset> pointer, required ValueListenable<List<AmbientImpulse>> impulses, required WorkspacePulseController pulse, required bool isDark})`. Painters merge `[pointer, impulses, pulse]` into their `repaint:` and read `pulse.activityLevel`/`pulse.idleFactor`. The ambient widget builds this only in animated mode; the static path passes `null` so nothing subscribes.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/motion/ambient_signals_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/ambient_signals.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

void main() {
  test('AmbientImpulse value equality', () {
    const a = AmbientImpulse(position: Offset(0.2, 0.3), bornAtMs: 1000);
    const b = AmbientImpulse(position: Offset(0.2, 0.3), bornAtMs: 1000);
    const c = AmbientImpulse(position: Offset(0.2, 0.3), bornAtMs: 2000);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });

  test('AmbientSignals holds its listenables + pulse', () {
    final pointer = ValueNotifier<Offset>(Offset.zero);
    final impulses = ValueNotifier<List<AmbientImpulse>>(const []);
    final pulse = WorkspacePulseController();
    final s = AmbientSignals(
      pointer: pointer,
      impulses: impulses,
      pulse: pulse,
      isDark: true,
    );
    expect(s.pointer, same(pointer));
    expect(s.impulses, same(impulses));
    expect(s.pulse, same(pulse));
    expect(s.isDark, isTrue);
    pointer.dispose();
    impulses.dispose();
    pulse.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/ambient_signals_test.dart`
Expected: FAIL — file/types do not exist.

- [ ] **Step 3: Create the value types**

```dart
// lib/core/theme/motion/ambient_signals.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset;
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';

/// A transient pointer-click ripple seed (VM-C1). [position] is normalized
/// (0..1) over the ambient surface; [bornAtMs] is the widget-owned monotonic
/// timestamp the painter uses to age the ripple out (self-disposing).
@immutable
class AmbientImpulse {
  const AmbientImpulse({required this.position, required this.bornAtMs});

  final Offset position;
  final int bornAtMs;

  @override
  bool operator ==(Object other) =>
      other is AmbientImpulse &&
      other.position == position &&
      other.bornAtMs == bornAtMs;

  @override
  int get hashCode => Object.hash(position, bornAtMs);
}

/// The shared input bundle threaded into a theme's ambient `scaffoldBackground`
/// painter (VM-C1 + VM-C2). Plumbed ONCE per painter; C1 (pointer/impulses) and
/// C2 (pulse) are just fields read off it. Built only in animated mode — the
/// reduced-effects static variant passes `null` so nothing subscribes.
@immutable
class AmbientSignals {
  const AmbientSignals({
    required this.pointer,
    required this.impulses,
    required this.pulse,
    required this.isDark,
  });

  /// Normalized pointer position (theme-specific convention: rpg uses -1..1 from
  /// centre, glass uses 0..1). The owning widget keeps its existing convention.
  final ValueListenable<Offset> pointer;

  /// Active click ripples; the owning widget drops aged entries.
  final ValueListenable<List<AmbientImpulse>> impulses;

  /// Session rhythm (activityLevel / idleFactor). Also a `Listenable`, so merge
  /// it into the painter's `repaint:`.
  final WorkspacePulseController pulse;

  final bool isDark;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/ambient_signals_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test
git add lib/core/theme/motion/ambient_signals.dart test/core/theme/motion/ambient_signals_test.dart
git commit -m "feat(motion): add AmbientSignals + AmbientImpulse painter-input types"
```

---

## Task 4: Mount `inFlightFrame` in the request/response area (B1 wiring)

**Files:**
- Modify: `lib/features/tabs/presentation/screens/request_view.dart`
- Test: `test/features/tabs/in_flight_frame_mount_test.dart`

**Interfaces:**
- Consumes: `AppMotion.inFlightFrame` (Task 1); `TabsBloc` state (`state.tabs.byId(tabId)?.isSending`).
- Produces: the request+response `Flex` is wrapped by `context.appMotion.inFlightFrame(child:, isSending:)`, driven by the displayed tab's `isSending`.

- [ ] **Step 1: Write the failing test**

This test asserts the mount calls the hook with the live `isSending` by installing a probe theme whose `inFlightFrame` records its `isSending` argument. Keep it light — render just the wrapped `Flex` via a small harness is impractical, so test the hook contract at the unit level: a probe `AppMotion` wrapping a child reflects `isSending`.

```dart
// test/features/tabs/in_flight_frame_mount_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

void main() {
  testWidgets('inFlightFrame hook receives isSending and wraps the child', (
    tester,
  ) async {
    bool? sawSending;
    final motion = const AppMotion().copyWith(
      inFlightFrame: (context, {required child, required isSending}) {
        sawSending = isSending;
        return DecoratedBox(
          key: const ValueKey('frame'),
          decoration: const BoxDecoration(),
          child: child,
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => motion.inFlightFrame(
            context,
            isSending: true,
            child: const Text('panes'),
          ),
        ),
      ),
    );
    expect(sawSending, isTrue);
    expect(find.byKey(const ValueKey('frame')), findsOneWidget);
    expect(find.text('panes'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails (it should compile-fail only if hook missing)**

Run: `fvm flutter test test/features/tabs/in_flight_frame_mount_test.dart`
Expected: PASS already (Task 1 added the hook). This test guards the contract the mount relies on — keep it. If Task 1 is incomplete it FAILs to compile.

- [ ] **Step 3: Wrap the request/response Flex in `request_view.dart`**

In `lib/features/tabs/presentation/screens/request_view.dart`, locate the `Flex` that lays out `requestPane` + `splitter` + `responsePane` (inside the `LayoutBuilder` → `ValueListenableBuilder`, around lines 248–267). Wrap the returned `Flex` with the hook, reading the displayed tab's `isSending`. Add a `BlocSelector` so only `isSending` changes rebuild the frame:

```dart
// import at top (if not present):
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:getman/core/theme/app_theme.dart';
// import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
// import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

// Replace `return <Flex>(...);` with:
final flex = Flex(
  direction: settings.isVerticalLayout ? Axis.vertical : Axis.horizontal,
  children: [
    Flexible(child: requestPane),
    splitter,
    Flexible(child: responsePane),
  ],
);
return BlocSelector<TabsBloc, TabsState, bool>(
  selector: (state) => state.tabs.byId(widget.tabId)?.isSending ?? false,
  builder: (context, isSending) =>
      context.appMotion.inFlightFrame(context, isSending: isSending, child: flex),
);
```

> If `byId` is not in scope, use `state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId)?.isSending ?? false` (the codebase's standard lookup; import `package:collection/collection.dart`).

- [ ] **Step 4: Run the test + a quick app-level smoke**

Run: `fvm flutter test test/features/tabs/in_flight_frame_mount_test.dart`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/features/tabs/presentation/screens/request_view.dart test/features/tabs/in_flight_frame_mount_test.dart
git commit -m "feat(motion): mount inFlightFrame around the request/response panes (B1)"
```

---

## Task 5: Loud-theme in-flight frame effects (B1)

Implement `inFlightFrame` in each loud theme's `<name>_motion.dart` and wire it into the `<name>Motion(...)` return. Identity stays for calm themes and under `reduceEffects` (the `if (reduceEffects) return const AppMotion();` guard already covers it).

**Files:**
- Modify: `lib/core/theme/themes/glass/glass_motion.dart`, `rpg/rpg_motion.dart`, `brutalist/brutalist_motion.dart`, `auris/auris_motion.dart`
- Test: `test/core/theme/themes/in_flight_frame_themes_test.dart`

**Interfaces:**
- Consumes: `AppMotion.inFlightFrame` (Task 1).
- Produces: each loud theme's `*Motion(reduceEffects:false)` now returns an `AppMotion` whose `inFlightFrame` renders a continuous (non-flashing) themed frame while `isSending`.

**Idiom per theme** (continuous motion — NOT flashing; degrade to identity under reduceEffects via the existing guard):
- **Glass** (`glass_motion.dart`) — the frame edge frost "breathes": a soft animated border glow pulsing in opacity (≤ slow, not a strobe). Reference the child-hoist pattern in `_GlassReactionOverlay`.
- **Arcane** (`rpg_motion.dart`) — a runic circuit-trace travelling the border (a dash-offset animated stroke).
- **Brutalist** (`brutalist_motion.dart`) — a marching ink loading-bar along the top edge (translating stripes; must not strobe).
- **AURIS** (`auris_motion.dart`) — a HUD scanline sweep around the frame; colors from `AurisScheme` (read via `Theme.of(context).extension<AurisScheme>()`).

**Reference implementation (Glass — copy this shape, then adapt per theme):**

```dart
// In glass_motion.dart, add to glassMotion(...) return:
//   inFlightFrame: (context, {required child, required isSending}) =>
//       _GlassInFlightFrame(isSending: isSending, child: child),

class _GlassInFlightFrame extends StatefulWidget {
  const _GlassInFlightFrame({required this.isSending, required this.child});
  final bool isSending;
  final Widget child;

  @override
  State<_GlassInFlightFrame> createState() => _GlassInFlightFrameState();
}

class _GlassInFlightFrameState extends State<_GlassInFlightFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600), // slow breathe, well under 3 Hz
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSending) unawaited(_c.repeat(reverse: true));
  }

  @override
  void didUpdateWidget(_GlassInFlightFrame old) {
    super.didUpdateWidget(old);
    // Edge-detect (THEME_AUTHORING §3 restart guard).
    if (widget.isSending && !old.isSending) {
      unawaited(_c.repeat(reverse: true));
    } else if (!widget.isSending && old.isSending) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).primaryColor;
    // Child hoisted out of per-frame rebuilds.
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        if (!widget.isSending) return child!;
        final glow = 0.15 + 0.35 * _c.value;
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      context.appShape.panelRadius,
                    ),
                    border: Border.all(
                      color: accent.withValues(alpha: glow),
                      width: context.appLayout.borderThin * 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

(`unawaited` needs `import 'dart:async';`; `context.appShape`/`context.appLayout` need `package:getman/core/theme/app_theme.dart` — both likely already imported in the motion file.)

- [ ] **Step 1: Write the failing test (all four themes)**

```dart
// test/core/theme/themes/in_flight_frame_themes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

Future<void> _pumpFrame(WidgetTester tester, AppMotion motion) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: motion.inFlightFrame(
            context,
            isSending: true,
            child: const SizedBox(
              key: ValueKey('panes'),
              width: 300,
              height: 300,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  expect(find.byKey(const ValueKey('panes')), findsOneWidget);
  expect(tester.takeException(), isNull);
  // Toggle off — frame must tear down cleanly.
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('glass in-flight frame renders child + survives toggle', (t) async {
    await _pumpFrame(t, glassMotion(reduceEffects: false));
  });
  testWidgets('rpg in-flight frame renders child + survives toggle', (t) async {
    await _pumpFrame(t, rpgMotion(reduceEffects: false));
  });
  testWidgets('brutalist in-flight frame renders child + survives toggle', (t) async {
    await _pumpFrame(t, brutalistMotion(reduceEffects: false));
  });
  testWidgets('auris in-flight frame renders child + survives toggle', (t) async {
    await _pumpFrame(t, aurisMotion(reduceEffects: false));
  });

  testWidgets('reduceEffects keeps inFlightFrame identity', (tester) async {
    const marker = SizedBox(key: ValueKey('m'));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: (c) { ctx = c; return const SizedBox(); })),
    );
    for (final m in [
      glassMotion(reduceEffects: true),
      rpgMotion(reduceEffects: true),
      brutalistMotion(reduceEffects: true),
      aurisMotion(reduceEffects: true),
    ]) {
      expect(identical(m.inFlightFrame(ctx, child: marker, isSending: true), marker), isTrue);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/in_flight_frame_themes_test.dart`
Expected: FAIL on the four full-effect cases (hook still identity → renders child but the test's intent is the effect; it will PASS the `findsOneWidget` but you have not added effects). To make the test meaningful as a TDD gate, first add an effect-presence assertion: after pumping, assert a frame layer exists, e.g. `expect(find.byType(DecoratedBox), findsWidgets);` only once you've implemented. Keep Step 1's test as the survival/identity guard; add per-theme effect-presence asserts as you implement each.

- [ ] **Step 3: Implement Glass frame (reference above), then Arcane, Brutalist, AURIS**

For each theme: add the private `_<Name>InFlightFrame` widget to its `<name>_motion.dart` and add the `inFlightFrame:` entry to the `<name>Motion(...)` return (inside the `if (reduceEffects) return const AppMotion();` ... full branch). Follow the theme's idiom (above) and reuse its existing palette/decoration accessors. Honor the restart guard (edge-detect on `old.isSending`) and child-hoist.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/themes/in_flight_frame_themes_test.dart`
Expected: PASS (all five).

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test && fvm flutter test
git add lib/core/theme/themes/*/*_motion.dart test/core/theme/themes/in_flight_frame_themes_test.dart
git commit -m "feat(motion): loud-theme in-flight panel frames (B1)"
```

---

## Task 6: Mount `contentTransition` on the tab content stack (B2 wiring)

**Files:**
- Modify: `lib/features/home/presentation/widgets/tab_content_stack.dart`
- Test: `test/features/home/content_transition_mount_test.dart`

**Interfaces:**
- Consumes: `AppMotion.contentTransition` (Task 1); active tab id (`_reconcile()` → `activeId`) and active panel id from `TabsBloc` state (`state.activePanelId`).
- Produces: the returned `Stack(Offstage…)` is wrapped by `context.appMotion.contentTransition(child:, transitionKey: "$activePanelId/$activeId")`.

- [ ] **Step 1: Write the failing test (hook contract: plays on key change)**

```dart
// test/features/home/content_transition_mount_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

void main() {
  testWidgets('contentTransition hook receives the composite key', (tester) async {
    final seenKeys = <String>[];
    final motion = const AppMotion().copyWith(
      contentTransition: (context, {required child, required transitionKey}) {
        seenKeys.add(transitionKey);
        return child;
      },
    );
    Widget build(String key) => MaterialApp(
      home: Builder(
        builder: (context) =>
            motion.contentTransition(context, transitionKey: key, child: const Text('c')),
      ),
    );
    await tester.pumpWidget(build('p1/t1'));
    await tester.pumpWidget(build('p1/t2'));
    expect(seenKeys, contains('p1/t1'));
    expect(seenKeys, contains('p1/t2'));
    expect(find.text('c'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails/compiles**

Run: `fvm flutter test test/features/home/content_transition_mount_test.dart`
Expected: PASS (hook exists from Task 1). Guards the contract.

- [ ] **Step 3: Wrap the Stack in `tab_content_stack.dart`**

In the `build` method, after computing `activeId` (the `_reconcile()` result) and reading the active panel id from the bloc, wrap the returned `Stack`:

```dart
// Read the active panel id (the widget already has TabsBloc state in scope via
// a BlocBuilder/selector — if not, add: final panelId = context.select<TabsBloc, String>((b) => b.state.activePanelId);)
final transitionKey = '$panelId/$activeId';
final stack = Stack(
  fit: StackFit.expand,
  children: [ /* existing Offstage children */ ],
);
return context.appMotion.contentTransition(
  context,
  transitionKey: transitionKey,
  child: stack,
);
```

> Imports: `package:getman/core/theme/app_theme.dart` for `context.appMotion`; `package:flutter_bloc/flutter_bloc.dart` + the tabs bloc/state if not already imported.

- [ ] **Step 4: Run the test**

Run: `fvm flutter test test/features/home/content_transition_mount_test.dart`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/features/home/presentation/widgets/tab_content_stack.dart test/features/home/content_transition_mount_test.dart
git commit -m "feat(motion): mount contentTransition on the tab content stack (B2)"
```

---

## Task 7: Loud-theme content transitions (B2)

**Files:**
- Modify: the four `<name>_motion.dart`
- Test: `test/core/theme/themes/content_transition_themes_test.dart`

**Interfaces:**
- Consumes: `AppMotion.contentTransition` (Task 1).
- Produces: each loud theme's `contentTransition` plays a one-shot themed sweep when `transitionKey` changes, instant under reduceEffects (identity guard).

**Mechanism (mirror `ThemeSwitchTransition` — `lib/core/theme/motion/theme_switch_transition.dart`):** a `StatefulWidget` holding a 350–450 ms controller; `didUpdateWidget` forwards from 0 when `transitionKey` changes; `build` does `AnimatedBuilder(child: widget.child, builder: …)` stacking a themed sweep painter over the hoisted child (panel-switch keys — different prefix before `/` — may use a directional swipe; tab-switch keys use the theme's signature swap).

**Idiom:** Glass frost-dissolve, Arcane scroll-unfurl, Brutalist slam-in, AURIS HUD wipe. Reuse each theme's accent (`Theme.of(context).primaryColor`) / palette.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/content_transition_themes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';

Future<void> _swap(WidgetTester tester, AppMotion motion) async {
  Widget build(String key) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: motion.contentTransition(
          context,
          transitionKey: key,
          child: const SizedBox(key: ValueKey('content'), width: 200, height: 200),
        ),
      ),
    ),
  );
  await tester.pumpWidget(build('p1/t1'));
  await tester.pumpWidget(build('p1/t2')); // tab switch
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byKey(const ValueKey('content')), findsOneWidget);
  await tester.pumpWidget(build('p2/t9')); // panel switch
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('content')), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final entry in {
    'glass': glassMotion,
    'rpg': rpgMotion,
    'brutalist': brutalistMotion,
    'auris': aurisMotion,
  }.entries) {
    testWidgets('${entry.key} content transition plays + keeps child', (t) async {
      await _swap(t, entry.value(reduceEffects: false));
    });
  }

  testWidgets('reduceEffects content transition is identity', (tester) async {
    const marker = SizedBox(key: ValueKey('m'));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: (c) { ctx = c; return const SizedBox(); })),
    );
    for (final m in [
      glassMotion(reduceEffects: true),
      rpgMotion(reduceEffects: true),
      brutalistMotion(reduceEffects: true),
      aurisMotion(reduceEffects: true),
    ]) {
      expect(
        identical(m.contentTransition(ctx, child: marker, transitionKey: 'x'), marker),
        isTrue,
      );
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/content_transition_themes_test.dart`
Expected: FAIL on full-effect cases until you implement (the identity cases pass).

- [ ] **Step 3: Implement per theme**

For each `<name>_motion.dart`: add a private `_<Name>ContentTransition` StatefulWidget (mirroring `ThemeSwitchTransition`) and add `contentTransition:` to the full-effects `AppMotion(...)`. Child-hoist + self-stopping controller.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/themes/content_transition_themes_test.dart`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test && fvm flutter test
git add lib/core/theme/themes/*/*_motion.dart test/core/theme/themes/content_transition_themes_test.dart
git commit -m "feat(motion): loud-theme content-swap transitions (B2)"
```

---

## Task 8: Tab-strip chip enter/exit (B2)

**Files:**
- Modify: `lib/features/home/presentation/screens/main_screen.dart` (the `ReorderableListView.builder` itemBuilder, ~lines 546–573)
- Modify: the four `<name>_motion.dart` (add `tabChipTransition`)
- Test: `test/core/theme/themes/tab_chip_transition_themes_test.dart`

**Interfaces:**
- Consumes: `AppMotion.tabChipTransition` (Task 1).
- Produces: each tab chip is wrapped so it animates in on insert / out on remove using the theme's `tabChipTransition`; calm/reduce use the default fast fade.

**Mechanism:** wrap each `TabWidget` in an `AnimatedSwitcher`-style enter using a keyed `KeyedSubtree`, OR simplest: wrap the `TabWidget` returned by `itemBuilder` so that its first build animates `tabChipTransition(animation: …)`. Because `ReorderableListView` does not provide enter/exit animations, use a per-chip `_ChipEntrance` wrapper that runs a 0→1 controller on first mount and feeds it to `context.appMotion.tabChipTransition`. (Tab close already plays a `SizeTransition` in `tab_widget.dart` — leave that; this adds the themed *enter*.)

```dart
// In main_screen.dart itemBuilder, wrap the TabWidget:
return _ChipEntrance(
  key: ValueKey('tab_${tab.tabId}'),
  child: TabWidget(/* existing args, but move the key to _ChipEntrance */),
);

// Add this private widget in main_screen.dart:
class _ChipEntrance extends StatefulWidget {
  const _ChipEntrance({required this.child, super.key});
  final Widget child;
  @override
  State<_ChipEntrance> createState() => _ChipEntranceState();
}

class _ChipEntranceState extends State<_ChipEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) =>
      context.appMotion.tabChipTransition(context, animation: _c, child: widget.child);
}
```

**Idiom for `tabChipTransition`:** Glass = scale+fade frost-in; Arcane = unfurl (scaleX); Brutalist = slam (slight overshoot + fade); AURIS = HUD fade-in. Default (calm/reduce) returns child unchanged (no entrance).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/tab_chip_transition_themes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';

void main() {
  for (final entry in {
    'glass': glassMotion,
    'rpg': rpgMotion,
    'brutalist': brutalistMotion,
    'auris': aurisMotion,
  }.entries) {
    testWidgets('${entry.key} tabChipTransition wraps + renders child', (t) async {
      final motion = entry.value(reduceEffects: false);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: motion.tabChipTransition(
                context,
                animation: const AlwaysStoppedAnimation<double>(0.5),
                child: const Text('chip'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('chip'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/tab_chip_transition_themes_test.dart`
Expected: PASS for child-presence even with identity, so add an effect-presence assert per theme as you implement (e.g. a `FadeTransition`/`ScaleTransition` present). The real regression guard is the app builds + no exception.

- [ ] **Step 3: Implement `tabChipTransition` in each `<name>_motion.dart` + the `_ChipEntrance` wiring in main_screen.dart**

- [ ] **Step 4: Run the test + full suite (main_screen change is broad)**

Run: `fvm flutter test test/core/theme/themes/tab_chip_transition_themes_test.dart && fvm flutter test`
Expected: PASS; existing tab/main_screen tests still green.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/features/home/presentation/screens/main_screen.dart lib/core/theme/themes/*/*_motion.dart test/core/theme/themes/tab_chip_transition_themes_test.dart
git commit -m "feat(motion): themed tab-strip chip entrance (B2)"
```

---

## Task 9: Tree drag/drop/expand hooks wiring (B3)

**Files:**
- Modify: `lib/features/collections/presentation/widgets/collection_node_row.dart`
- Test: `test/core/theme/themes/tree_motion_themes_test.dart` (created in Task 10; this task is wiring + identity-safety)

**Interfaces:**
- Consumes: `AppMotion.treeDragFeedback`, `treeDropHighlight`, `treeExpandFlourish` (Task 1).
- Produces: the existing `Draggable.feedback`, the folder `DragTarget.builder` (with `_isDragOver`), and the expand toggle are wrapped by the corresponding hooks. Default themes/`reduceEffects` get identity (unchanged current behavior).

- [ ] **Step 1: Wrap the Draggable feedback**

In `collection_node_row.dart`, the `Draggable<String>.feedback:` currently builds a `Material(Container(... node.name ...))`. Wrap that feedback child with the hook so themes can restyle it:

```dart
feedback: context.appMotion.treeDragFeedback(
  context,
  child: Material(
    color: Colors.transparent,
    child: Container(/* existing feedback content */),
  ),
),
```

- [ ] **Step 2: Wrap the folder drop target**

The folder `DragTarget<String>.builder` returns `folderInner` and tracks `_isDragOver`. Wrap `folderInner`:

```dart
builder: (context, candidateData, rejectedData) =>
    context.appMotion.treeDropHighlight(context, active: _isDragOver, child: folderInner),
```

- [ ] **Step 3: Wrap the expand/collapse toggle**

The folder toggle `Icon(isExpanded ? down : right)` (and the examples toggle) — wrap the icon:

```dart
context.appMotion.treeExpandFlourish(
  context,
  expanded: isExpanded,
  child: Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, /* … */),
)
```

- [ ] **Step 4: Add `import 'package:getman/core/theme/app_theme.dart';`** if not present (for `context.appMotion`).

- [ ] **Step 5: Run the full collections suite (identity = no behavior change)**

Run: `fvm flutter test test/features/collections`
Expected: PASS — wrapping with identity hooks must not change existing behavior.

- [ ] **Step 6: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
git add lib/features/collections/presentation/widgets/collection_node_row.dart
git commit -m "feat(motion): wire tree drag/drop/expand hooks (B3 wiring)"
```

---

## Task 10: Loud-theme tree juice (B3)

**Files:**
- Modify: the four `<name>_motion.dart`
- Test: `test/core/theme/themes/tree_motion_themes_test.dart`

**Interfaces:**
- Consumes: the three tree hooks.
- Produces: each loud theme renders a themed drag feedback, a drop highlight that intensifies while `active` + a short self-disposing absorb on accept, and an expand flourish. Fixed-extent constraint: the flourish must NOT change the row's height — it's an icon glow/overlay only.

**Idiom:** Arcane glow-pull (drop) + rune drag chip; Glass ripple-in (drop) + frosted drag chip; Brutalist slam (drop) + ink-stamp drag chip; AURIS lock-on (drop) + HUD drag chip.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/tree_motion_themes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';

void main() {
  for (final entry in {
    'glass': glassMotion,
    'rpg': rpgMotion,
    'brutalist': brutalistMotion,
    'auris': aurisMotion,
  }.entries) {
    testWidgets('${entry.key} tree hooks render under each state', (t) async {
      final m = entry.value(reduceEffects: false);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  m.treeDragFeedback(context, child: const Text('drag')),
                  m.treeDropHighlight(context, active: true, child: const Text('drop')),
                  m.treeDropHighlight(context, active: false, child: const Text('drop2')),
                  m.treeExpandFlourish(context, expanded: true, child: const Icon(Icons.add)),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 120));
      expect(find.text('drag'), findsOneWidget);
      expect(find.text('drop'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
```

- [ ] **Step 2: Run to verify it fails / guards**

Run: `fvm flutter test test/core/theme/themes/tree_motion_themes_test.dart`
Expected: PASS for presence with identity; add per-theme effect-presence asserts as you implement.

- [ ] **Step 3: Implement the three hooks in each `<name>_motion.dart`**

Drop-absorb on accept is a transient: the `treeDropHighlight` widget can run a short controller when `active` flips true→false-with-accept; simplest is a self-disposing pulse keyed on `active`. Keep the row height fixed.

- [ ] **Step 4: Run test + collections suite**

Run: `fvm flutter test test/core/theme/themes/tree_motion_themes_test.dart && fvm flutter test test/features/collections`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test && fvm flutter test
git add lib/core/theme/themes/*/*_motion.dart test/core/theme/themes/tree_motion_themes_test.dart
git commit -m "feat(motion): loud-theme tree drag/drop/expand juice (B3)"
```

---

## Task 11: Brutalist ambient background

**Files:**
- Create: `lib/core/theme/themes/brutalist/brutalist_ambient.dart`
- Modify: `lib/core/theme/themes/brutalist/brutalist_theme.dart` (set `scaffoldBackground`)
- Test: `test/core/theme/themes/brutalist/brutalist_ambient_test.dart`

**Interfaces:**
- Consumes: `AmbientSignals`/`AmbientImpulse` (Task 3), `WorkspacePulseController` (Task 2; read from context in animated mode).
- Produces:
  - `Widget brutalistScaffoldBackgroundAnimated(BuildContext, {required Widget child})` (the new animated wallpaper)
  - `Widget brutalistStaticScaffoldBackground(BuildContext, {required Widget child})`
  - A private `_BrutalistAmbient` StatefulWidget + `_HalftonePainter` taking an `AmbientSignals?` (null in static mode), built to the rpg/glass discipline (one controller, RepaintBoundary, reused Paint, lifecycle pause, MouseRegion+Listener only in animated mode).

> **Important:** today `brutalist_theme.dart` sets `scaffoldBackground: brutalistScaffoldBackground` (a single, non-reactive function). Replace it with the reduceEffects branch like rpg/glass:
> ```dart
> scaffoldBackground: reduceEffects
>     ? brutalistStaticScaffoldBackground
>     : brutalistScaffoldBackgroundAnimated,
> ```
> If a `brutalistScaffoldBackground` already exists and is referenced elsewhere, keep it as the static one (rename calls) — verify with a grep before editing.

**Concept (this task wires C1/C2 inputs but may noop them visually until Tasks 13/14; build the painter to *accept* `AmbientSignals` now):** a slow risograph/halftone dot grid (monochrome + one accent from `BrutalistPalette`), with slight registration ghosting. Static variant = a single flat grain frame.

- [ ] **Step 1: Write the failing smoke test**

```dart
// test/core/theme/themes/brutalist/brutalist_ambient_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_ambient.dart';

void main() {
  testWidgets('animated brutalist ambient paints + renders child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => brutalistScaffoldBackgroundAnimated(
            context,
            child: const Text('app'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('app'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('static brutalist ambient paints one frame + renders child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              brutalistStaticScaffoldBackground(context, child: const Text('app')),
        ),
      ),
    );
    expect(find.text('app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/brutalist/brutalist_ambient_test.dart`
Expected: FAIL — file/functions don't exist.

- [ ] **Step 3: Implement `brutalist_ambient.dart`**

Model it on `glass_decorations.dart`'s `GlassWallpaper` + `_GlassMeshPainter` (read in this codebase): a `_BrutalistAmbient` StatefulWidget that owns a long-loop `AnimationController` (only running in animated mode), a `ValueNotifier<Offset> _pointer`, a `ValueNotifier<List<AmbientImpulse>> _impulses`, reads `WorkspacePulseController` from context in animated mode, bundles them into `AmbientSignals` and passes to `_HalftonePainter` (or `null` in static mode). The painter draws the dot grid with a reused `Paint`. Add `MouseRegion(onHover:)` + `Listener(onPointerDown:)` only in animated mode (touch no-op naturally — desktop pointer). Drop aged impulses inside the painter-frame callback / a periodic prune.

- [ ] **Step 4: Wire into `brutalist_theme.dart`** (the `scaffoldBackground` branch above) and run the theme's existing tests.

Run: `fvm flutter test test/core/theme/themes/brutalist`
Expected: PASS (ambient smoke + existing brutalist tests).

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test && fvm flutter test
git add lib/core/theme/themes/brutalist/brutalist_ambient.dart lib/core/theme/themes/brutalist/brutalist_theme.dart test/core/theme/themes/brutalist/brutalist_ambient_test.dart
git commit -m "feat(theme): brutalist animated ambient background (C1/C2 base)"
```

---

## Task 12: AURIS ambient background

**Files:**
- Create: `lib/core/theme/themes/auris/auris_ambient.dart`
- Modify: `lib/core/theme/themes/auris/auris_theme.dart` (set `scaffoldBackground`)
- Test: `test/core/theme/themes/auris/auris_ambient_test.dart`

**Interfaces:** same shape as Task 11, named `aurisScaffoldBackgroundAnimated` / `aurisStaticScaffoldBackground`. **Must read HUD colors from `AurisScheme`** via `Theme.of(context).extension<AurisScheme>()` (it is preserved by the `...base.extensions.values` spread in `auris_theme.dart` — do not introduce hardcoded colors).

> Verify AURIS's current `scaffoldBackground`: grep `auris_theme.dart` for `scaffoldBackground`. If AURIS currently has none set (uses the default), add `scaffoldBackground:` to its `AppDecoration(...)` with the reduceEffects branch.

**Concept:** a scanning HUD grid with a slow radar sweep / drifting telemetry ticks. Static variant = a still grid.

- [ ] **Step 1: Write the failing smoke test** (mirror Task 11's two tests, but pump under the AURIS theme so `AurisScheme` is present):

```dart
// test/core/theme/themes/auris/auris_ambient_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/auris/auris_ambient.dart';

void main() {
  testWidgets('animated auris ambient paints under AURIS theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) =>
              aurisScaffoldBackgroundAnimated(context, child: const Text('app')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('app'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('static auris ambient paints one frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
        home: Builder(
          builder: (context) =>
              aurisStaticScaffoldBackground(context, child: const Text('app')),
        ),
      ),
    );
    expect(find.text('app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

> Confirm the `appThemes[id].builder(brightness)` call shape against `theme_registry.dart` (the AURIS motion test uses `appThemes[kAurisThemeId]!.builder(Brightness.dark)`).

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/auris/auris_ambient_test.dart`
Expected: FAIL — file/functions don't exist.

- [ ] **Step 3: Implement `auris_ambient.dart`** (same discipline as Task 11; colors from `AurisScheme`).

- [ ] **Step 4: Wire into `auris_theme.dart` + run AURIS tests**

Run: `fvm flutter test test/core/theme/themes/auris`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test && fvm flutter test
git add lib/core/theme/themes/auris/auris_ambient.dart lib/core/theme/themes/auris/auris_theme.dart test/core/theme/themes/auris/auris_ambient_test.dart
git commit -m "feat(theme): AURIS animated HUD ambient background (C1/C2 base)"
```

---

## Task 13: Wire C1 (cursor force + click ripple) into all four painters

**Files:**
- Modify: `lib/core/theme/themes/rpg/rpg_decorations.dart`, `glass/glass_decorations.dart`, `brutalist/brutalist_ambient.dart`, `auris/auris_ambient.dart`
- Test: `test/core/theme/themes/ambient_interaction_test.dart`

**Interfaces:**
- Consumes: `AmbientSignals.pointer` + `AmbientSignals.impulses`.
- Produces: each animated ambient widget adds a `Listener(onPointerDown:)` that appends an `AmbientImpulse` (normalized position, monotonic ms via a `Stopwatch` the widget owns) to its `_impulses` notifier; the painter renders a force displacement near `pointer` and an expanding ripple per active impulse, aging them out. Touch = no-op (pointer-only). Reduced-effects path unchanged (no Listener, no signals).

> rpg/glass already capture `_pointer`. For C1, ADD an `_impulses` notifier + `Listener`, and upgrade the painter from passive parallax/sheen to an active force near the pointer. Brutalist/AURIS were built in Tasks 11/12 to accept signals — add their `Listener` + force logic here.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/ambient_interaction_test.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_ambient.dart';
import 'package:getman/core/theme/themes/glass/glass_decorations.dart';

void main() {
  testWidgets('glass ambient handles a click without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              glassScaffoldBackground(context, child: const SizedBox.expand()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(200, 200));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
  });

  testWidgets('brutalist ambient handles a click without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              brutalistScaffoldBackgroundAnimated(context, child: const SizedBox.expand()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(150, 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails (or that clicks are inert)**

Run: `fvm flutter test test/core/theme/themes/ambient_interaction_test.dart`
Expected: PASS for "no throw" even before changes (clicks are currently inert). Add an effect-presence signal: expose a `@visibleForTesting` impulse count on the ambient State, or assert the painter receives a non-empty impulses list. Implement so a click produces a ripple.

- [ ] **Step 3: Implement the `Listener` + impulse plumbing + painter force/ripple in each file**

Each widget: own a `final Stopwatch _clock = Stopwatch()..start();` for monotonic ms; on `onPointerDown`, append `AmbientImpulse(position: normalized, bornAtMs: _clock.elapsedMilliseconds)`; prune aged impulses. Painter merges `impulses` into `repaint:` and draws an easing ripple; force = displace elements toward/away from `pointer`.

- [ ] **Step 4: Run the test + each theme's ambient suite**

Run: `fvm flutter test test/core/theme/themes`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test && fvm flutter test
git add lib/core/theme/themes/rpg/rpg_decorations.dart lib/core/theme/themes/glass/glass_decorations.dart lib/core/theme/themes/brutalist/brutalist_ambient.dart lib/core/theme/themes/auris/auris_ambient.dart test/core/theme/themes/ambient_interaction_test.dart
git commit -m "feat(theme): interactive ambient — cursor force + click ripple (C1)"
```

---

## Task 14: Wire C2 (idle dim + send-burst intensify) into all four painters

**Files:**
- Modify: the four ambient files (as in Task 13)
- Test: `test/core/theme/themes/ambient_rhythm_test.dart`

**Interfaces:**
- Consumes: `AmbientSignals.pulse` (`activityLevel`, `idleFactor`).
- Produces: each painter reads `pulse.activityLevel` (multiplier on density/speed) and `pulse.idleFactor` (multiplier dimming brightness/slowing drift), merging `pulse` into `repaint:`. No behavior under reduced effects (static path passes no signals).

- [ ] **Step 1: Write the failing test (rhythm affects paint params via a probe)**

Since painter internals are private, test at the seam: pump an animated ambient inside a widget that also exposes a `WorkspacePulseController`, bump it, and assert no throw + a frame is produced. The substantive assertion is that the ambient widget reads the provided controller (provide one and verify `hasListeners` becomes true after mount).

```dart
// test/core/theme/themes/ambient_rhythm_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/core/theme/themes/glass/glass_decorations.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('animated glass ambient subscribes to WorkspacePulseController', (tester) async {
    final pulse = WorkspacePulseController();
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkspacePulseController>.value(
        value: pulse,
        child: MaterialApp(
          home: Builder(
            builder: (context) =>
                glassScaffoldBackground(context, child: const SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(pulse.hasListeners, isTrue,
        reason: 'animated ambient must listen to the pulse for C2');
    pulse.bump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    // After teardown the ambient unsubscribed.
    expect(pulse.hasListeners, isFalse);
    pulse.dispose();
  });
}
```

> The animated ambient widgets must `context.read<WorkspacePulseController>()` (or `Provider.of`, listen:false) and pass it into `AmbientSignals.pulse`, and the painter must add it to `repaint:` (that subscription is what flips `hasListeners`). If the controller isn't found (e.g. a theme preview without the provider), guard with `Provider.of<WorkspacePulseController?>(context, listen: false)` and skip C2 when null so previews don't crash.

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/theme/themes/ambient_rhythm_test.dart`
Expected: FAIL — `hasListeners` is false until the painter subscribes.

- [ ] **Step 3: Implement pulse read + painter multipliers in each ambient file**

- [ ] **Step 4: Run the test + theme suite**

Run: `fvm flutter test test/core/theme/themes/ambient_rhythm_test.dart && fvm flutter test test/core/theme/themes`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test && fvm flutter test
git add lib/core/theme/themes/rpg/rpg_decorations.dart lib/core/theme/themes/glass/glass_decorations.dart lib/core/theme/themes/brutalist/brutalist_ambient.dart lib/core/theme/themes/auris/auris_ambient.dart test/core/theme/themes/ambient_rhythm_test.dart
git commit -m "feat(theme): session-rhythm ambient — idle dim + send-burst (C2)"
```

---

## Task 15: Under-theme overflow guards, docs & wiki sync, final done-bar

**Files:**
- Test: `test/features/tabs/response_section_under_themes_test.dart` (overflow guard)
- Modify: `docs/THEME_AUTHORING.md` (add reactive-checklist rows)
- Wiki: `Getman.wiki.git` → `Themes-and-Appearance.md`

**Interfaces:** none new — verification + documentation.

- [ ] **Step 1: Add an under-theme overflow guard (the AURIS lesson)**

```dart
// test/features/tabs/response_section_under_themes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  // Render a representative panel + the in-flight frame under each loud theme at
  // a realistic size and assert no RenderFlex overflow. Replace _Harness with a
  // minimal pump of ResponseSection/RequestView if a lighter harness exists in
  // the repo's existing tests (grep test/ for an existing ResponseSection pump).
  for (final id in [kGlassThemeId, kRpgThemeId, kBrutalistThemeId, kAurisThemeId]) {
    testWidgets('no overflow under $id with motion wrappers', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: appThemes[id]!.builder(Brightness.dark),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  }
}
```

> Strengthen this by pumping the real `ResponseSection`/`RequestView` if the repo already has a harness for them (grep `test/` for `ResponseSection(`). The key assertion is zero `RenderFlex overflowed` exceptions under each loud theme with the new wrappers mounted.

- [ ] **Step 2: Run the full suite**

Run: `fvm flutter test`
Expected: PASS (all, including this guard).

- [ ] **Step 3: Update `docs/THEME_AUTHORING.md`**

In §3 (the reactive checklist), add rows for the new moments so future themes address them:
- **In-flight frame** — does the panel area react while sending? (`AppMotion.inFlightFrame`)
- **Transitions** — tab/panel content swap + tab-chip entrance? (`contentTransition`/`tabChipTransition`)
- **Tree juice** — drag feedback / drop-absorb / expand flourish? (tree hooks)
- **Interactive ambient (C1)** — cursor force + click ripple? (`AmbientSignals`)
- **Session rhythm (C2)** — idle dim + send-burst? (`WorkspacePulseController`)

Also note in §4 that loud themes now author an ambient even if they had none (Brutalist/AURIS shipped here).

- [ ] **Step 4: Sync the wiki (CLAUDE.md §7 mandate)**

```bash
cd /tmp && git clone https://github.com/thiagomiranda3/Getman.wiki.git getman-wiki
# edit getman-wiki/Themes-and-Appearance.md: describe the in-flight frame, tab/panel
# transitions, tree drag-drop juice, and the interactive + session-rhythm ambient
# (incl. the new Brutalist halftone & AURIS HUD backgrounds); note all are loud-theme
# only and fully disabled by Reduce Visual Effects.
cd getman-wiki && git add -A && git commit -m "docs: theme motion expansion (B1/B2/B3 + C1/C2)" && git push origin master
```

- [ ] **Step 5: Final full done-bar**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test && fvm flutter test
```
Expected: all four analysis passes 0 issues, format clean, tests 100% green.

- [ ] **Step 6: Commit**

```bash
git add docs/THEME_AUTHORING.md test/features/tabs/response_section_under_themes_test.dart
git commit -m "docs(theme): document motion expansion + under-theme overflow guards"
```

---

## Self-Review notes (for the executor)

- **Spec coverage:** Task 1 (hooks) + Tasks 4–10 cover B1/B2/B3; Tasks 11–12 (new ambient) + 13 (C1) + 14 (C2) cover C1/C2 across all four loud themes; Task 2/3 are the shared infra (`WorkspacePulseController`, `AmbientSignals`). Task 15 covers degradation guards + docs/wiki.
- **reduceEffects** is verified per feature (identity assertions in Tasks 1/5/7 and the static-ambient tests in 11/12).
- **Effect-presence vs survival:** several tests pass on child-presence even with identity hooks — each implementing step says to ADD a per-theme effect-presence assertion as you implement, so the TDD red→green is real. Don't skip that.
- **Grep-before-edit flags:** Task 11 (existing `brutalistScaffoldBackground` name), Task 12 (AURIS current `scaffoldBackground`), Task 4 (`byId` vs `firstWhereOrNull`), Task 6 (active panel id selector), Task 15 (existing ResponseSection test harness). Verify each against the live code before editing.
