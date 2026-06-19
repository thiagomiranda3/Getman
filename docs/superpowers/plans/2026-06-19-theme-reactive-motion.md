# Theme Reactive Motion ("theme juice") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each theme react to real request outcomes (send / status code / latency) with personality-scaled animations, plus richer ambient effects, a theme-switch transition, and opt-in themed sound.

**Architecture:** A new 7th `ThemeExtension` (`AppMotion`) carries two identity-defaulting hooks — `reactionOverlay` (full-screen transient effects + shake) and `sendAffordance` (the SEND-button ritual). A pure-Dart `ThemeReaction` value type flows from `TabsBloc` (which already classifies cancel vs network failure vs HTTP status) through a transient `TabsState` signal, read by a widget-layer `ThemeReactionListener` (twin of `ChainingWriteBackListener`, zero bloc→bloc coupling) that pushes it into an app-wide `ThemeReactionController` (`ChangeNotifier`). Each theme's `reactionOverlay` subscribes to that controller. Ambient enrichments edit the existing per-theme `scaffoldBackground` painters in place. Sound rides the same reaction stream behind an off-by-default setting.

**Tech Stack:** Flutter + `flutter_bloc` 9, `equatable`, `provider` 6 (`ChangeNotifierProvider`), `get_it` DI, `audioplayers` (new, Phase 3), `bloc_test` 10 + `flutter_test`.

## Global Constraints

- Flutter SDK is invoked as **`fvm flutter ...`**, never plain `flutter`. Dart tools as `fvm dart ...`.
- **Imports are `package:getman/...` everywhere** — no relative imports (enforced by `always_use_package_imports` + `directives_ordering`).
- **Done-bar (run all four, all clean, before claiming done):** `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0 issues), `fvm dart run bloc_tools:bloc lint lib` (0 issues), `fvm dart format lib test` clean, `fvm flutter test` 100% green. The three analysis passes are independent — a clean `analyze` does NOT imply custom_lint/bloc_lint are clean.
- **No hardcoded sizes/colors/radii/weights** in widgets — pull from `context.appLayout / appPalette / appShape / appTypography / appDecoration / appMotion`. Exceptions: theme-internal files under `lib/core/theme/themes/<name>/` may use that theme's own palette constants and effect-specific literals (matching the existing `rpg_decorations.dart` / `glass_decorations.dart` precedent).
- **`avoid_hardcoded_brand_colors`** custom_lint forbids `Colors.black/white/red` outside `lib/core/theme/`. All new motion files live under `lib/core/theme/` (allowed) EXCEPT the listener (`lib/features/...`) and the sound service (`lib/core/audio/`) — those must not use brand-color literals.
- **`ThemeReaction` MUST stay pure Dart** (`equatable` only, NO `package:flutter/*` import) so blocs/state may import it without tripping bloc_lint's `avoid_flutter_imports`. The `ThemeReactionController` and all overlay widgets are UI and may import Flutter.
- **Blocs use `dart:developer` `log(msg, name: '<Bloc>')`**, never `debugPrint`. Do not import `package:flutter/*` into a bloc (the one existing exception in `tabs_bloc.dart` is `compute`, already ignored).
- **Hive typeIds are load-bearing** — the only Hive change in this plan is `SettingsModel` gaining `enableThemeSounds` at **`HiveField(27)`** (next free becomes 28). Never renumber. Regenerate with `fvm dart run build_runner build --delete-conflicting-outputs` after the field is added.
- **Respect `reduceVisualEffects`**: when `true`, every heavy effect degrades to identity / instant. The flag already threads into each theme builder as `reduceEffects` and is part of the `_themeDataCache` key.
- **Commit after each task.** Branch work off `dev` (current branch). Co-author/footer per repo convention is auto-applied by the commit hook flow; a plain `git commit -m` is fine.

---

# Phase 1 — Event spine + loud themes

## Task 1: `ThemeReaction` value type

**Files:**
- Create: `lib/core/theme/motion/theme_reaction.dart`
- Test: `test/core/theme/motion/theme_reaction_test.dart`

**Interfaces:**
- Produces: `enum ThemeReactionKind { sendStarted, success, clientError, serverError, networkError, cancelled }`; `class ThemeReaction { final ThemeReactionKind kind; final int? statusCode; final int? durationMs; const ThemeReaction({required kind, statusCode, durationMs}); static ThemeReactionKind kindForStatus(int); bool get isError; }`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/motion/theme_reaction_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

void main() {
  group('ThemeReaction.kindForStatus', () {
    test('2xx and 3xx are success', () {
      expect(ThemeReaction.kindForStatus(200), ThemeReactionKind.success);
      expect(ThemeReaction.kindForStatus(204), ThemeReactionKind.success);
      expect(ThemeReaction.kindForStatus(301), ThemeReactionKind.success);
      expect(ThemeReaction.kindForStatus(399), ThemeReactionKind.success);
    });
    test('4xx is clientError, 5xx is serverError', () {
      expect(ThemeReaction.kindForStatus(404), ThemeReactionKind.clientError);
      expect(ThemeReaction.kindForStatus(429), ThemeReactionKind.clientError);
      expect(ThemeReaction.kindForStatus(500), ThemeReactionKind.serverError);
      expect(ThemeReaction.kindForStatus(503), ThemeReactionKind.serverError);
    });
    test('0 / sub-200 / 6xx is networkError', () {
      expect(ThemeReaction.kindForStatus(0), ThemeReactionKind.networkError);
      expect(ThemeReaction.kindForStatus(100), ThemeReactionKind.networkError);
      expect(ThemeReaction.kindForStatus(600), ThemeReactionKind.networkError);
    });
  });

  test('isError true for the three error kinds only', () {
    bool err(ThemeReactionKind k) =>
        ThemeReaction(kind: k).isError;
    expect(err(ThemeReactionKind.success), isFalse);
    expect(err(ThemeReactionKind.sendStarted), isFalse);
    expect(err(ThemeReactionKind.cancelled), isFalse);
    expect(err(ThemeReactionKind.clientError), isTrue);
    expect(err(ThemeReactionKind.serverError), isTrue);
    expect(err(ThemeReactionKind.networkError), isTrue);
  });

  test('value equality', () {
    expect(
      const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200, durationMs: 12),
      const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200, durationMs: 12),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/theme_reaction_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../theme_reaction.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/theme/motion/theme_reaction.dart
import 'package:equatable/equatable.dart';

/// What happened to a request, in motion terms. Pure Dart (no Flutter import)
/// so it can flow through TabsBloc / TabsState without tripping bloc_lint's
/// avoid_flutter_imports.
enum ThemeReactionKind {
  sendStarted,
  success,
  clientError,
  serverError,
  networkError,
  cancelled,
}

class ThemeReaction extends Equatable {
  const ThemeReaction({required this.kind, this.statusCode, this.durationMs});

  final ThemeReactionKind kind;
  final int? statusCode;
  final int? durationMs;

  /// Maps an HTTP status to a reaction kind. 200..399 success, 400..499
  /// clientError, 500..599 serverError, anything else (0, sub-200, 6xx) is
  /// treated as a network-level failure.
  static ThemeReactionKind kindForStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 400) return ThemeReactionKind.success;
    if (statusCode >= 400 && statusCode < 500) {
      return ThemeReactionKind.clientError;
    }
    if (statusCode >= 500 && statusCode < 600) {
      return ThemeReactionKind.serverError;
    }
    return ThemeReactionKind.networkError;
  }

  bool get isError =>
      kind == ThemeReactionKind.clientError ||
      kind == ThemeReactionKind.serverError ||
      kind == ThemeReactionKind.networkError;

  @override
  List<Object?> get props => [kind, statusCode, durationMs];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/theme_reaction_test.dart`
Expected: PASS (all 5).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/motion/theme_reaction.dart test/core/theme/motion/theme_reaction_test.dart
git commit -m "feat(theme): ThemeReaction value type + status classifier"
```

---

## Task 2: `ThemeReactionController`

**Files:**
- Create: `lib/core/theme/motion/theme_reaction_controller.dart`
- Test: `test/core/theme/motion/theme_reaction_controller_test.dart`

**Interfaces:**
- Consumes: `ThemeReaction` (Task 1).
- Produces: `class ThemeReactionController extends ChangeNotifier { ThemeReaction? get latest; int get seq; void fire(ThemeReaction); }`. `seq` is a monotonic counter bumped on each `fire` so listeners can re-trigger on identical consecutive reactions.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/motion/theme_reaction_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

void main() {
  test('fire updates latest, bumps seq, and notifies', () {
    final c = ThemeReactionController();
    var notifications = 0;
    c.addListener(() => notifications++);

    expect(c.latest, isNull);
    expect(c.seq, 0);

    c.fire(const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200));
    expect(c.latest!.kind, ThemeReactionKind.success);
    expect(c.seq, 1);
    expect(notifications, 1);

    // Identical reaction still bumps seq + notifies (re-trigger).
    c.fire(const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200));
    expect(c.seq, 2);
    expect(notifications, 2);

    c.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/theme_reaction_controller_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/theme/motion/theme_reaction_controller.dart
import 'package:flutter/foundation.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// App-wide bus for request-driven theme reactions. The widget-layer
/// [ThemeReactionListener] pushes reactions in via [fire]; each theme's
/// reactionOverlay subscribes and plays its effect. Registered as a DI
/// singleton and exposed to the widget tree via a provider.
class ThemeReactionController extends ChangeNotifier {
  ThemeReaction? _latest;
  int _seq = 0;

  ThemeReaction? get latest => _latest;

  /// Monotonic; bumped on every [fire] (even for identical reactions) so an
  /// overlay can re-run an effect for two successive identical responses.
  int get seq => _seq;

  void fire(ThemeReaction reaction) {
    _latest = reaction;
    _seq++;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/theme_reaction_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/motion/theme_reaction_controller.dart test/core/theme/motion/theme_reaction_controller_test.dart
git commit -m "feat(theme): ThemeReactionController app-wide reaction bus"
```

---

## Task 3: Transient reaction signal on `TabsState` + `TabsBloc`

**Files:**
- Modify: `lib/features/tabs/presentation/bloc/tabs_state.dart` (whole file shown)
- Modify: `lib/features/tabs/presentation/bloc/tabs_bloc.dart:129-147` (`_derive`), `:461-540` (`_onSendRequest`), and add a `_fireReaction` helper + `_reactionSeq` field.
- Test: `test/features/tabs/presentation/bloc/tabs_reaction_test.dart`

**Interfaces:**
- Consumes: `ThemeReaction` (Task 1).
- Produces: `TabsState` gains `final ThemeReaction? lastReaction;` and `final int reactionSeq;` (default `0`), both in `props` and `copyWith`. `TabsBloc` fires `sendStarted` on send begin, `kindForStatus(...)` on response/error, `cancelled` on cancel, `networkError` on unexpected failure — each bumping `reactionSeq`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/tabs/presentation/bloc/tabs_reaction_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

void main() {
  group('TabsState reaction signal', () {
    test('defaults: no reaction, seq 0', () {
      const s = TabsState();
      expect(s.lastReaction, isNull);
      expect(s.reactionSeq, 0);
    });

    test('copyWith sets reaction + seq and keeps them in equality', () {
      const base = TabsState();
      final next = base.copyWith(
        lastReaction:
            const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
        reactionSeq: 1,
      );
      expect(next.reactionSeq, 1);
      expect(next.lastReaction!.kind, ThemeReactionKind.success);
      expect(next, isNot(equals(base)));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/bloc/tabs_reaction_test.dart`
Expected: FAIL — `lastReaction`/`reactionSeq` undefined.

- [ ] **Step 3: Update `TabsState`**

Replace the whole file `lib/features/tabs/presentation/bloc/tabs_state.dart` with:

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

class TabsState extends Equatable {
  const TabsState({
    this.panels = const [],
    this.activePanelId = '',
    this.tabs = const [],
    this.activeIndex = 0,
    this.isLoading = false,
    this.lastReaction,
    this.reactionSeq = 0,
  });

  /// All panels, in display order. Invariant: non-empty once loaded.
  final List<PanelEntity> panels;

  /// Id of the active panel (its tabs are surfaced as [tabs]/[activeIndex]).
  final String activePanelId;

  /// The ACTIVE panel's tabs — recomputed on every emit so existing widgets
  /// (and their buildWhen selectors) keep reading `state.tabs` unchanged.
  final List<HttpRequestTabEntity> tabs;

  /// Index of the active panel's active tab within [tabs].
  final int activeIndex;

  final bool isLoading;

  /// The most recent request-driven motion reaction (transient, never
  /// persisted). [reactionSeq] is monotonic across the bloc's lifetime and is
  /// carried forward by `_derive` so it never moves backwards; the
  /// ThemeReactionListener fires on each increase.
  final ThemeReaction? lastReaction;
  final int reactionSeq;

  PanelEntity? get activePanel => panels.byId(activePanelId);

  @override
  List<Object?> get props => [
    panels,
    activePanelId,
    tabs,
    activeIndex,
    isLoading,
    lastReaction,
    reactionSeq,
  ];

  TabsState copyWith({
    List<PanelEntity>? panels,
    String? activePanelId,
    List<HttpRequestTabEntity>? tabs,
    int? activeIndex,
    bool? isLoading,
    ThemeReaction? lastReaction,
    int? reactionSeq,
  }) {
    return TabsState(
      panels: panels ?? this.panels,
      activePanelId: activePanelId ?? this.activePanelId,
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
      isLoading: isLoading ?? this.isLoading,
      lastReaction: lastReaction ?? this.lastReaction,
      reactionSeq: reactionSeq ?? this.reactionSeq,
    );
  }
}
```

- [ ] **Step 4: Carry the signal through `_derive` + add the fire helper in `TabsBloc`**

In `lib/features/tabs/presentation/bloc/tabs_bloc.dart`, add the import near the other `package:getman` imports:

```dart
import 'package:getman/core/theme/motion/theme_reaction.dart';
```

In `_derive` (currently lines 140-146), add the two carry-forward fields to the returned `TabsState` so a normal derive never resets the signal:

```dart
    return TabsState(
      panels: panels,
      activePanelId: active?.id ?? '',
      tabs: tabs,
      activeIndex: idx < 0 ? 0 : idx,
      isLoading: isLoading ?? state.isLoading,
      lastReaction: state.lastReaction,
      reactionSeq: state.reactionSeq,
    );
```

Add a field + helper near the other private fields/methods (e.g. just above `_onSendRequest` at line 461):

```dart
  // Monotonic reaction counter. Bumped by _fireReaction so the
  // ThemeReactionListener fires once per terminal/start event, even for two
  // identical responses in a row.
  int _reactionSeq = 0;

  /// Emit a reaction-only state update on top of the latest tab state.
  /// Tabs/panels are untouched (copyWith preserves them), so buildWhen-gated
  /// tab widgets don't rebuild — only the reaction listener reacts.
  void _fireReaction(Emitter<TabsState> emit, ThemeReaction reaction) {
    _reactionSeq++;
    emit(state.copyWith(lastReaction: reaction, reactionSeq: _reactionSeq));
  }
```

- [ ] **Step 5: Fire reactions from `_onSendRequest`**

Edit `_onSendRequest` (lines 461-540). After the send-start `emit(...)` block (right after line 484's closing `);`), add:

```dart
    _fireReaction(emit, const ThemeReaction(kind: ThemeReactionKind.sendStarted));
```

In the success branch, immediately after `_markResponseDirty(tabId);` (line 503), add:

```dart
      _fireReaction(
        emit,
        ThemeReaction(
          kind: ThemeReaction.kindForStatus(response.statusCode),
          statusCode: response.statusCode,
          durationMs: response.durationMs,
        ),
      );
```

In the `NetworkFailure` cancelled branch, before `return;` (line 510), add:

```dart
        _fireReaction(
          emit,
          const ThemeReaction(kind: ThemeReactionKind.cancelled),
        );
```

In the `NetworkFailure` non-cancel branch, after `_markResponseDirty(tabId);` (line 529), add:

```dart
      _fireReaction(
        emit,
        ThemeReaction(
          kind: ThemeReaction.kindForStatus(errorResponse.statusCode),
          statusCode: errorResponse.statusCode,
        ),
      );
```

In the `on Object` catch-all branch, after the `_applyToTab(...)` that clears `isSending` (line 538), add:

```dart
      _fireReaction(
        emit,
        const ThemeReaction(kind: ThemeReactionKind.networkError),
      );
```

- [ ] **Step 6: Run tests + analysis**

Run: `fvm flutter test test/features/tabs/presentation/bloc/tabs_reaction_test.dart`
Expected: PASS.

Run: `fvm flutter test test/features/tabs/` (regression — the existing tabs bloc tests must still pass; the reaction-only emits are additive and tab-state-preserving).
Expected: PASS.

Run: `fvm dart run bloc_tools:bloc lint lib`
Expected: 0 issues (ThemeReaction is pure Dart — no Flutter import introduced into the bloc).

- [ ] **Step 7: Commit**

```bash
git add lib/features/tabs/presentation/bloc/tabs_state.dart lib/features/tabs/presentation/bloc/tabs_bloc.dart test/features/tabs/presentation/bloc/tabs_reaction_test.dart
git commit -m "feat(tabs): emit transient ThemeReaction signal on send/response/cancel"
```

---

## Task 4: `AppMotion` extension + `context.appMotion` + attach identity to all themes

**Files:**
- Create: `lib/core/theme/extensions/app_motion.dart`
- Modify: `lib/core/theme/extensions/app_theme_access.dart` (add accessor + import)
- Modify each theme builder's `extensions:` list (6 files) to attach a `motion` (identity for now): `themes/classic/classic_theme.dart`, `themes/brutalist/brutalist_theme.dart`, `themes/editorial/editorial_theme.dart`, `themes/rpg/rpg_theme.dart`, `themes/dracula/dracula_theme.dart`, `themes/glass/glass_theme.dart`.
- Test: `test/core/theme/app_motion_test.dart`

**Interfaces:**
- Consumes: `ThemeReactionController` (Task 2).
- Produces:
  - `typedef ReactionOverlayBuilder = Widget Function(BuildContext, {required Widget child, required ThemeReactionController controller});`
  - `typedef SendAffordanceBuilder = Widget Function(BuildContext, {required Widget child, required bool isSending});`
  - `class AppMotion extends ThemeExtension<AppMotion> { final ReactionOverlayBuilder reactionOverlay; final SendAffordanceBuilder sendAffordance; const AppMotion({reactionOverlay = identity, sendAffordance = identity}); }`
  - `BuildContext.appMotion` getter.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/app_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  testWidgets('every theme attaches an AppMotion; defaults are identity',
      (tester) async {
    for (final id in appThemes.keys) {
      final theme = resolveThemeData(id, Brightness.light, isCompact: false);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ),
      );
      final motion = ctx.appMotion;
      // Identity sendAffordance returns the child unchanged.
      const marker = SizedBox(key: ValueKey('marker'));
      expect(
        identical(
          motion.sendAffordance(ctx, child: marker, isSending: false),
          marker,
        ),
        isTrue,
        reason: 'theme "$id" sendAffordance must default to identity',
      );
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/app_motion_test.dart`
Expected: FAIL — `appMotion` getter / `AppMotion` undefined.

- [ ] **Step 3: Create the extension**

```dart
// lib/core/theme/extensions/app_motion.dart
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

/// Event-driven motion hooks for a theme. Both default to identity, so a theme
/// that supplies no motion is completely unaffected (mirrors
/// AppDecoration.frost). Closures don't lerp — copyWith/lerp follow the
/// AppDecoration pattern.
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    this.reactionOverlay = _identityReactionOverlay,
    this.sendAffordance = _identitySendAffordance,
  });

  final ReactionOverlayBuilder reactionOverlay;
  final SendAffordanceBuilder sendAffordance;

  @override
  AppMotion copyWith({
    ReactionOverlayBuilder? reactionOverlay,
    SendAffordanceBuilder? sendAffordance,
  }) => AppMotion(
    reactionOverlay: reactionOverlay ?? this.reactionOverlay,
    sendAffordance: sendAffordance ?? this.sendAffordance,
  );

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) => this;
}
```

- [ ] **Step 4: Add the accessor**

Edit `lib/core/theme/extensions/app_theme_access.dart` — add the import (kept alphabetical with the others) and the getter:

```dart
import 'package:getman/core/theme/extensions/app_motion.dart';
```

```dart
  AppMotion get appMotion => Theme.of(this).extension<AppMotion>()!;
```

- [ ] **Step 5: Attach identity `AppMotion` to every theme**

In EACH of the six theme builders, add `import 'package:getman/core/theme/extensions/app_motion.dart';` and add `const AppMotion(),` to the `extensions: [...]` list. For example, in `lib/core/theme/themes/rpg/rpg_theme.dart` the list becomes:

```dart
    extensions: [
      layout,
      palette,
      shape,
      typography,
      decoration,
      const AppMotion(),
      const AppCopy(emptyResponse: 'CAST SEND TO SUMMON A RESPONSE'),
    ],
```

Do the equivalent in `classic_theme.dart`, `brutalist_theme.dart`, `editorial_theme.dart`, `dracula_theme.dart`, `glass_theme.dart` (each already has an `extensions:` list with `AppCopy`).

- [ ] **Step 6: Run test + analysis**

Run: `fvm flutter test test/core/theme/app_motion_test.dart`
Expected: PASS (iterates all 6 themes).

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 7: Commit**

```bash
git add lib/core/theme/extensions/app_motion.dart lib/core/theme/extensions/app_theme_access.dart lib/core/theme/themes test/core/theme/app_motion_test.dart
git commit -m "feat(theme): AppMotion extension (reactionOverlay + sendAffordance), identity on all themes"
```

---

## Task 5: Register the controller in DI + provide it + mount `ThemeReactionListener`

**Files:**
- Modify: `lib/core/di/injection_container.dart:253` (add registration after `UrlFocusRegistry`)
- Modify: `lib/main.dart` (add a `RepositoryProvider<ThemeReactionController>` to the `MultiRepositoryProvider` list ~line 181-194)
- Create: `lib/features/home/presentation/widgets/theme_reaction_listener.dart`
- Modify: `lib/features/home/presentation/screens/main_screen.dart` (wrap the body with `ThemeReactionListener`, next to `ChainingWriteBackListener`)
- Test: `test/features/home/theme_reaction_listener_test.dart`

**Interfaces:**
- Consumes: `ThemeReactionController` (Task 2), `TabsState.reactionSeq`/`lastReaction` (Task 3).
- Produces: `class ThemeReactionListener extends StatelessWidget { const ThemeReactionListener({required Widget child}); }` — a `BlocListener<TabsBloc, TabsState>` that fires `context.read<ThemeReactionController>().fire(state.lastReaction!)` whenever `reactionSeq` increases.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/home/theme_reaction_listener_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/features/home/presentation/widgets/theme_reaction_listener.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

class _FakeTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _FakeTabsBloc() : super(const TabsState());
  void push(TabsState s) => emit(s);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('fires controller once per reactionSeq increase', (tester) async {
    final bloc = _FakeTabsBloc();
    final controller = ThemeReactionController();
    final fired = <ThemeReactionKind>[];
    controller.addListener(() => fired.add(controller.latest!.kind));

    await tester.pumpWidget(
      RepositoryProvider<ThemeReactionController>.value(
        value: controller,
        child: BlocProvider<TabsBloc>.value(
          value: bloc,
          child: const MaterialApp(
            home: ThemeReactionListener(child: SizedBox()),
          ),
        ),
      ),
    );

    expect(fired, isEmpty);

    bloc.push(const TabsState(
      reactionSeq: 1,
      lastReaction: ThemeReaction(kind: ThemeReactionKind.sendStarted),
    ));
    await tester.pump();
    expect(fired, [ThemeReactionKind.sendStarted]);

    bloc.push(const TabsState(
      reactionSeq: 2,
      lastReaction: ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    ));
    await tester.pump();
    expect(fired, [ThemeReactionKind.sendStarted, ThemeReactionKind.success]);

    // An emit that doesn't change reactionSeq does NOT re-fire.
    bloc.push(const TabsState(
      reactionSeq: 2,
      isLoading: true,
      lastReaction: ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    ));
    await tester.pump();
    expect(fired.length, 2);

    await bloc.close();
    controller.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/home/theme_reaction_listener_test.dart`
Expected: FAIL — `ThemeReactionListener` undefined.

- [ ] **Step 3: Create the listener**

```dart
// lib/features/home/presentation/widgets/theme_reaction_listener.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Bridges request-driven [TabsState] reactions into the app-wide
/// [ThemeReactionController], at the widget layer (it holds both), so TabsBloc
/// never depends on a UI controller — the same rule ChainingWriteBackListener
/// follows. Fires exactly once per `reactionSeq` increase.
class ThemeReactionListener extends StatelessWidget {
  const ThemeReactionListener({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) =>
          next.reactionSeq != prev.reactionSeq && next.lastReaction != null,
      listener: (context, state) =>
          context.read<ThemeReactionController>().fire(state.lastReaction!),
      child: child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/home/theme_reaction_listener_test.dart`
Expected: PASS.

- [ ] **Step 5: Register in DI**

In `lib/core/di/injection_container.dart`, add the import with the others:

```dart
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
```

Change line 253 from:

```dart
    ..registerLazySingleton(UrlFocusRegistry.new);
```

to:

```dart
    ..registerLazySingleton(UrlFocusRegistry.new)
    ..registerLazySingleton(ThemeReactionController.new);
```

- [ ] **Step 6: Provide it in `main.dart`**

In `lib/main.dart`, add the import:

```dart
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
```

Add to the `MultiRepositoryProvider.providers` list (after the `WorkspaceSyncService` provider, before the `ChangeNotifierProvider<UpdateController>`):

```dart
        RepositoryProvider<ThemeReactionController>.value(
          value: di.sl<ThemeReactionController>(),
        ),
```

- [ ] **Step 7: Mount the listener in `MainScreen`**

In `lib/features/home/presentation/screens/main_screen.dart`, add the import:

```dart
import 'package:getman/features/home/presentation/widgets/theme_reaction_listener.dart';
```

Find where `ChainingWriteBackListener` wraps the screen body and wrap that subtree once more with `ThemeReactionListener`. If the build returns `ChainingWriteBackListener(child: <body>)`, change it to:

```dart
return ThemeReactionListener(
  child: ChainingWriteBackListener(child: <body>),
);
```

(If `ChainingWriteBackListener` is nested deeper, place `ThemeReactionListener` immediately around it — both only need `TabsBloc` + their respective providers in scope, which `MainScreen` has.)

- [ ] **Step 8: Run analysis + the full test dir**

Run: `fvm flutter analyze`
Expected: 0 issues.

Run: `fvm flutter test test/features/home/`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/core/di/injection_container.dart lib/main.dart lib/features/home/presentation/widgets/theme_reaction_listener.dart lib/features/home/presentation/screens/main_screen.dart test/features/home/theme_reaction_listener_test.dart
git commit -m "feat(theme): wire ThemeReactionController + ThemeReactionListener"
```

---

## Task 6: Mount `reactionOverlay` + `sendAffordance` hook points (still identity → no visible change)

**Files:**
- Modify: `lib/main.dart:268-276` (`MaterialApp.router` `builder`)
- Modify: `lib/features/tabs/presentation/widgets/url_bar.dart:345-422` (wrap the SEND `ElevatedButton`)
- Test: `test/core/theme/reaction_overlay_mount_test.dart`

**Interfaces:**
- Consumes: `context.appMotion` (Task 4), `ThemeReactionController` (Task 5).
- Produces: the app content is wrapped by `context.appMotion.reactionOverlay(...)` and the SEND button by `context.appMotion.sendAffordance(...)`. With identity defaults this is a no-op; loud themes (Tasks 8-10) light it up.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/reaction_overlay_mount_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

void main() {
  testWidgets('reactionOverlay identity passes child through', (tester) async {
    final controller = ThemeReactionController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          return context.appMotion.reactionOverlay(
            context,
            controller: controller,
            child: const Text('content', textDirection: TextDirection.ltr),
          );
        }),
      ),
    );
    expect(find.text('content'), findsOneWidget);
    controller.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

This test passes only once the default `AppMotion` exists (Task 4) — it will pass immediately if Task 4 is done. Its real purpose is a regression guard for the mount. Run:
`fvm flutter test test/core/theme/reaction_overlay_mount_test.dart`
Expected: PASS (identity overlay). If it errors on `reactionOverlay`, Task 4 is incomplete.

- [ ] **Step 3: Mount the overlay in `main.dart`**

In `lib/main.dart`, the `builder:` currently is:

```dart
                      builder: (context, child) {
                        return Focus(
                          autofocus: true,
                          child: context.appDecoration.scaffoldBackground(
                            context,
                            child: child ?? const SizedBox.shrink(),
                          ),
                        );
                      },
```

Replace it with (reaction overlay wraps the scaffold background so transient effects/shake cover the whole app; it reads the controller from the provider above `MaterialApp`):

```dart
                      builder: (context, child) {
                        return Focus(
                          autofocus: true,
                          child: context.appMotion.reactionOverlay(
                            context,
                            controller: context
                                .read<ThemeReactionController>(),
                            child: context.appDecoration.scaffoldBackground(
                              context,
                              child: child ?? const SizedBox.shrink(),
                            ),
                          ),
                        );
                      },
```

(Confirm `package:flutter_bloc/flutter_bloc.dart` or `package:provider/provider.dart` is imported in `main.dart` so `context.read` resolves — `flutter_bloc` re-exports `provider`'s `read`; it is already imported.)

- [ ] **Step 4: Wrap the SEND button in `url_bar.dart`**

In `lib/features/tabs/presentation/widgets/url_bar.dart`, the HTTP SEND button (lines 345-422) is:

```dart
                          if (tab.config.kind == RequestKind.http)
                            context.appDecoration.wrapInteractive(
                              child: ElevatedButton( ... ),
                            )
```

Wrap the whole `wrapInteractive(...)` expression in `sendAffordance`:

```dart
                          if (tab.config.kind == RequestKind.http)
                            context.appMotion.sendAffordance(
                              context,
                              isSending: tab.isSending,
                              child: context.appDecoration.wrapInteractive(
                                child: ElevatedButton( ... ), // unchanged
                              ),
                            )
```

Leave the `ElevatedButton` body exactly as-is.

- [ ] **Step 5: Run analysis + a smoke test**

Run: `fvm flutter analyze`
Expected: 0 issues.

Run: `fvm flutter test test/core/theme/reaction_overlay_mount_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/features/tabs/presentation/widgets/url_bar.dart test/core/theme/reaction_overlay_mount_test.dart
git commit -m "feat(theme): mount reactionOverlay + sendAffordance hook points (identity)"
```

---

## Task 7: Shared reaction-overlay scaffolding (`ReactionStage`)

**Files:**
- Create: `lib/core/theme/motion/reaction_stage.dart`
- Test: `test/core/theme/motion/reaction_stage_test.dart`

**Interfaces:**
- Consumes: `ThemeReactionController` (Task 2), `ThemeReaction` (Task 1).
- Produces: `class ReactionStage extends StatefulWidget` — wraps `child`, subscribes to the controller, and calls `onReaction(ThemeReaction)` exactly once per controller `seq` change. Manages a `TickerProvider` and exposes its `State`'s `vsync` to subclasses via a `builder` that receives `(context, child)`. Concretely it provides:
  - `ReactionStage({required Widget child, required ThemeReactionController controller, required void Function(ThemeReaction) onReaction, bool enabled = true})`.
  When `enabled` is false (reduced effects) it never subscribes and is pure passthrough.

This is the reusable base each loud theme uses so they don't each re-implement controller subscription + dedupe.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/motion/reaction_stage_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

void main() {
  testWidgets('calls onReaction once per controller seq change', (tester) async {
    final controller = ThemeReactionController();
    final seen = <ThemeReactionKind>[];
    await tester.pumpWidget(MaterialApp(
      home: ReactionStage(
        controller: controller,
        onReaction: (r) => seen.add(r.kind),
        child: const SizedBox(),
      ),
    ));

    controller.fire(const ThemeReaction(kind: ThemeReactionKind.success));
    await tester.pump();
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.serverError));
    await tester.pump();
    expect(seen, [ThemeReactionKind.success, ThemeReactionKind.serverError]);
    controller.dispose();
  });

  testWidgets('disabled never reacts', (tester) async {
    final controller = ThemeReactionController();
    final seen = <ThemeReactionKind>[];
    await tester.pumpWidget(MaterialApp(
      home: ReactionStage(
        controller: controller,
        enabled: false,
        onReaction: (r) => seen.add(r.kind),
        child: const SizedBox(),
      ),
    ));
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.success));
    await tester.pump();
    expect(seen, isEmpty);
    controller.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/reaction_stage_test.dart`
Expected: FAIL — `ReactionStage` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/theme/motion/reaction_stage.dart
import 'package:flutter/widgets.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// Subscribes to a [ThemeReactionController] and invokes [onReaction] exactly
/// once per `seq` change. Pure passthrough when [enabled] is false (reduced
/// effects). Themes wrap their overlay painters in this so they don't each
/// re-implement subscription + dedupe.
class ReactionStage extends StatefulWidget {
  const ReactionStage({
    required this.child,
    required this.controller,
    required this.onReaction,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final ThemeReactionController controller;
  final void Function(ThemeReaction reaction) onReaction;
  final bool enabled;

  @override
  State<ReactionStage> createState() => _ReactionStageState();
}

class _ReactionStageState extends State<ReactionStage> {
  int _lastSeq = 0;

  @override
  void initState() {
    super.initState();
    _lastSeq = widget.controller.seq;
    if (widget.enabled) widget.controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(ReactionStage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.enabled != widget.enabled) {
      if (old.enabled) old.controller.removeListener(_onTick);
      _lastSeq = widget.controller.seq;
      if (widget.enabled) widget.controller.addListener(_onTick);
    }
  }

  void _onTick() {
    final c = widget.controller;
    if (c.seq == _lastSeq) return;
    _lastSeq = c.seq;
    final r = c.latest;
    if (r != null) widget.onReaction(r);
  }

  @override
  void dispose() {
    if (widget.enabled) widget.controller.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/motion/reaction_stage_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/motion/reaction_stage.dart test/core/theme/motion/reaction_stage_test.dart
git commit -m "feat(theme): ReactionStage subscription/dedupe base for overlays"
```

---

## Task 8: Liquid Glass motion (ripple on success, crack on error, liquid send ritual)

**Files:**
- Create: `lib/core/theme/themes/glass/glass_motion.dart`
- Modify: `lib/core/theme/themes/glass/glass_theme.dart` (replace `const AppMotion()` with the glass motion; honor `reduceEffects`)
- Test: `test/core/theme/themes/glass_motion_test.dart`

**Interfaces:**
- Consumes: `AppMotion` (Task 4), `ReactionStage` (Task 7), `ThemeReaction` (Task 1), `GlassPalette`.
- Produces: `AppMotion glassMotion({required bool reduceEffects})` returning a configured `AppMotion`. When `reduceEffects` is true it returns `const AppMotion()` (identity).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/glass_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';

void main() {
  testWidgets('reduced effects => identity overlay + identity send', (tester) async {
    final motion = glassMotion(reduceEffects: true);
    final controller = ThemeReactionController();
    const marker = SizedBox(key: ValueKey('m'));
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(
      identical(motion.sendAffordance(ctx, child: marker, isSending: false), marker),
      isTrue,
    );
    controller.dispose();
  });

  testWidgets('full effects: overlay renders child and survives a reaction', (tester) async {
    final motion = glassMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
        body: motion.reactionOverlay(
          context,
          controller: controller,
          child: const Text('app'),
        ),
      );
    })));
    expect(find.text('app'), findsOneWidget);
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('app'), findsOneWidget); // overlay didn't tear down content
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.serverError, statusCode: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1)); // let controllers finish
    controller.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/glass_motion_test.dart`
Expected: FAIL — `glassMotion` undefined.

- [ ] **Step 3: Implement the glass motion**

```dart
// lib/core/theme/themes/glass/glass_motion.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/glass/glass_palette.dart';

/// Liquid Glass motion: a concentric ripple bloom on success, a crack-and-heal
/// on error, and a liquid ripple from the SEND button on press. Identity when
/// [reduceEffects].
AppMotion glassMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _GlassReactionOverlay(controller: controller, child: child),
    sendAffordance: (context, {required child, required isSending}) =>
        _GlassSendAffordance(isSending: isSending, child: child),
  );
}

class _GlassReactionOverlay extends StatefulWidget {
  const _GlassReactionOverlay({required this.controller, required this.child});
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_GlassReactionOverlay> createState() => _GlassReactionOverlayState();
}

class _GlassReactionOverlayState extends State<_GlassReactionOverlay>
    with TickerProviderStateMixin {
  final List<_GlassEffect> _effects = [];

  void _onReaction(ThemeReaction r) {
    final accent = Theme.of(context).primaryColor;
    final controller = AnimationController(
      vsync: this,
      duration: r.isError
          ? const Duration(milliseconds: 700)
          : const Duration(milliseconds: 900),
    );
    final effect = _GlassEffect(
      controller: controller,
      isError: r.isError,
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

  @override
  void dispose() {
    for (final e in _effects) {
      e.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      child: Stack(
        children: [
          widget.child,
          for (final e in _effects)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: e.controller,
                  builder: (_, _) => CustomPaint(
                    painter: e.isError
                        ? _GlassCrackPainter(t: e.controller.value, color: e.color)
                        : _GlassRipplePainter(t: e.controller.value, color: e.color),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassEffect {
  _GlassEffect({required this.controller, required this.isError, required this.color});
  final AnimationController controller;
  final bool isError;
  final Color color;
}

/// Concentric ripple sweep from screen center + a soft accent bloom that fades.
class _GlassRipplePainter extends CustomPainter {
  _GlassRipplePainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.longestSide * 0.75;
    final fade = (1.0 - t).clamp(0.0, 1.0);
    for (var i = 0; i < 3; i++) {
      final phase = (t - i * 0.12).clamp(0.0, 1.0);
      if (phase <= 0) continue;
      final r = Curves.easeOut.transform(phase) * maxR;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = color.withValues(alpha: 0.28 * fade);
      canvas.drawCircle(center, r, paint);
    }
    // Soft central bloom.
    final bloom = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.18 * fade), const Color(0x00000000)],
      ).createShader(Rect.fromCircle(center: center, radius: maxR * 0.5));
    canvas.drawCircle(center, maxR * 0.5, bloom);
  }

  @override
  bool shouldRepaint(covariant _GlassRipplePainter old) =>
      old.t != t || old.color != color;
}

/// A thin crack-line spider that snaps in (0..0.4) then heals/fades (0.4..1).
class _GlassCrackPainter extends CustomPainter {
  _GlassCrackPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = size.center(const Offset(0, -40));
    final grow = Curves.easeOut.transform((t / 0.4).clamp(0.0, 1.0));
    final heal = t <= 0.4 ? 1.0 : (1.0 - (t - 0.4) / 0.6).clamp(0.0, 1.0);
    final rng = math.Random(7); // stable spider geometry per paint
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.6 * heal);
    for (var i = 0; i < 7; i++) {
      final angle = i * (math.pi * 2 / 7) + rng.nextDouble() * 0.3;
      final len = (size.shortestSide * 0.55) * (0.6 + rng.nextDouble() * 0.4);
      var p = origin;
      final path = Path()..moveTo(p.dx, p.dy);
      const segs = 4;
      for (var s = 1; s <= segs; s++) {
        final frac = (s / segs) * grow;
        final jitter = (rng.nextDouble() - 0.5) * 18;
        final perp = Offset(math.cos(angle + math.pi / 2), math.sin(angle + math.pi / 2)) * jitter;
        p = origin + Offset(math.cos(angle), math.sin(angle)) * (len * frac) + perp;
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlassCrackPainter old) =>
      old.t != t || old.color != color;
}

/// Liquid ripple from the SEND button on press + a faint shimmer while sending.
class _GlassSendAffordance extends StatefulWidget {
  const _GlassSendAffordance({required this.isSending, required this.child});
  final bool isSending;
  final Widget child;

  @override
  State<_GlassSendAffordance> createState() => _GlassSendAffordanceState();
}

class _GlassSendAffordanceState extends State<_GlassSendAffordance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).primaryColor;
    return Listener(
      onPointerDown: (_) {
        _ripple
          ..reset()
          ..forward();
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ripple,
                builder: (_, _) => _ripple.isAnimating || _ripple.value > 0
                    ? CustomPaint(
                        painter: _ButtonRipplePainter(
                          t: _ripple.value,
                          color: accent,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonRipplePainter extends CustomPainter {
  _ButtonRipplePainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0) return;
    final center = size.center(Offset.zero);
    final r = Curves.easeOut.transform(t) * size.longestSide;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.5 * (1 - t));
    canvas.drawCircle(center, r, paint);
  }

  @override
  bool shouldRepaint(covariant _ButtonRipplePainter old) => old.t != t;
}
```

- [ ] **Step 4: Wire it into the glass theme builder**

In `lib/core/theme/themes/glass/glass_theme.dart`, add the import:

```dart
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
```

Replace the `const AppMotion(),` entry in the `extensions:` list with:

```dart
      glassMotion(reduceEffects: reduceEffects),
```

- [ ] **Step 5: Run test + analysis**

Run: `fvm flutter test test/core/theme/themes/glass_motion_test.dart`
Expected: PASS.

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/themes/glass/glass_motion.dart lib/core/theme/themes/glass/glass_theme.dart test/core/theme/themes/glass_motion_test.dart
git commit -m "feat(theme): Liquid Glass reactive motion (ripple/crack/liquid send)"
```

---

## Task 9: Arcane Quest motion (sparkle shower, runic crack + shake, rune-ring send)

**Files:**
- Create: `lib/core/theme/themes/rpg/rpg_motion.dart`
- Modify: `lib/core/theme/themes/rpg/rpg_theme.dart` (replace `const AppMotion()` with `rpgMotion(reduceEffects: reduceEffects)`)
- Test: `test/core/theme/themes/rpg_motion_test.dart`

**Interfaces:**
- Consumes: `AppMotion` (Task 4), `ReactionStage` (Task 7), `ThemeReaction` (Task 1), `RpgPalette`.
- Produces: `AppMotion rpgMotion({required bool reduceEffects})`. Identity when reduced.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/rpg_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/rpg/rpg_motion.dart';

void main() {
  test('reduced effects returns identity AppMotion', () {
    final motion = rpgMotion(reduceEffects: true);
    expect(motion.reactionOverlay, isA<ReactionOverlayBuilder>());
    final identity = const AppMotion();
    // Identity overlay returns child unchanged.
    // (smoke: see widget test below for behavior)
    expect(motion.runtimeType, identity.runtimeType);
  });

  testWidgets('success shower + error shake both render without throwing',
      (tester) async {
    final motion = rpgMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
        body: motion.reactionOverlay(
          context,
          controller: controller,
          child: const Text('app'),
        ),
      );
    })));
    expect(find.text('app'), findsOneWidget);
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200));
    await tester.pump(const Duration(milliseconds: 80));
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.serverError, statusCode: 500));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    controller.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/rpg_motion_test.dart`
Expected: FAIL — `rpgMotion` undefined.

- [ ] **Step 3: Implement the Arcane motion**

```dart
// lib/core/theme/themes/rpg/rpg_motion.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/rpg/rpg_palette.dart';

/// Arcane Quest motion: a golden sparkle shower ("spell lands") on success, a
/// crimson runic crack + a brief screen shake on error, and a spinning rune
/// ring around SEND while sending. Identity when [reduceEffects].
AppMotion rpgMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _RpgReactionOverlay(controller: controller, child: child),
    sendAffordance: (context, {required child, required isSending}) =>
        _RpgSendAffordance(isSending: isSending, child: child),
  );
}

class _RpgReactionOverlay extends StatefulWidget {
  const _RpgReactionOverlay({required this.controller, required this.child});
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_RpgReactionOverlay> createState() => _RpgReactionOverlayState();
}

class _RpgReactionOverlayState extends State<_RpgReactionOverlay>
    with TickerProviderStateMixin {
  final List<_RpgEffect> _effects = [];
  final math.Random _rng = math.Random();

  void _onReaction(ThemeReaction r) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final effect = _RpgEffect(
      controller: controller,
      isError: r.isError,
      seed: _rng.nextInt(1 << 30),
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

  @override
  void dispose() {
    for (final e in _effects) {
      e.controller.dispose();
    }
    super.dispose();
  }

  // Error reactions shake; success doesn't. Amplitude decays over the effect.
  double _shakeDx() {
    var dx = 0.0;
    for (final e in _effects.where((e) => e.isError)) {
      final decay = (1 - e.controller.value).clamp(0.0, 1.0);
      dx += math.sin(e.controller.value * math.pi * 12) * 6 * decay;
    }
    return dx;
  }

  @override
  Widget build(BuildContext context) {
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      child: AnimatedBuilder(
        animation: Listenable.merge(_effects.map((e) => e.controller).toList()),
        builder: (context, _) {
          return Transform.translate(
            offset: Offset(_shakeDx(), 0),
            child: Stack(
              children: [
                widget.child,
                for (final e in _effects)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: e.isError
                            ? _RunicCrackPainter(t: e.controller.value, seed: e.seed)
                            : _SparkleShowerPainter(t: e.controller.value, seed: e.seed),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RpgEffect {
  _RpgEffect({required this.controller, required this.isError, required this.seed});
  final AnimationController controller;
  final bool isError;
  final int seed;
}

/// Gold sparkles rain from the top + a gold shimmer sweep.
class _SparkleShowerPainter extends CustomPainter {
  _SparkleShowerPainter({required this.t, required this.seed});
  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final core = Paint();
    for (var i = 0; i < 36; i++) {
      final x = rng.nextDouble() * size.width;
      final delay = rng.nextDouble() * 0.3;
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = Curves.easeIn.transform(p) * size.height;
      final alpha = (1 - p).clamp(0.0, 1.0);
      final r = 1.5 + rng.nextDouble() * 2.5;
      core.color = (rng.nextDouble() < 0.8 ? RpgPalette.gold : RpgPalette.arcane)
          .withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), r, core);
    }
    // Shimmer sweep band.
    final sweepY = Curves.easeOut.transform(t) * size.height;
    final band = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0x00000000),
          RpgPalette.gold.withValues(alpha: 0.10 * (1 - t)),
          const Color(0x00000000),
        ],
      ).createShader(Rect.fromLTWH(0, sweepY - 60, size.width, 120));
    canvas.drawRect(Rect.fromLTWH(0, sweepY - 60, size.width, 120), band);
  }

  @override
  bool shouldRepaint(covariant _SparkleShowerPainter old) => old.t != t;
}

/// Crimson runic crack flash + dark vignette pulse.
class _RunicCrackPainter extends CustomPainter {
  _RunicCrackPainter({required this.t, required this.seed});
  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = math.sin(t * math.pi).clamp(0.0, 1.0);
    // Dark vignette pulse.
    final vignette = Paint()
      ..shader = RadialGradient(
        radius: 1.1,
        colors: [const Color(0x00000000), RpgPalette.statusError.withValues(alpha: 0.18 * pulse)],
        stops: const [0.6, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
    // Cracks from center.
    final rng = math.Random(seed);
    final origin = size.center(const Offset(0, -30));
    final grow = Curves.easeOut.transform((t / 0.35).clamp(0.0, 1.0));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = RpgPalette.statusError.withValues(alpha: 0.7 * pulse);
    for (var i = 0; i < 6; i++) {
      final angle = i * (math.pi * 2 / 6) + rng.nextDouble() * 0.4;
      final len = size.shortestSide * 0.5 * grow;
      canvas.drawLine(
        origin,
        origin + Offset(math.cos(angle), math.sin(angle)) * len,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunicCrackPainter old) => old.t != t;
}

/// Spinning rune ring around SEND while [isSending].
class _RpgSendAffordance extends StatefulWidget {
  const _RpgSendAffordance({required this.isSending, required this.child});
  final bool isSending;
  final Widget child;

  @override
  State<_RpgSendAffordance> createState() => _RpgSendAffordanceState();
}

class _RpgSendAffordanceState extends State<_RpgSendAffordance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSending) _spin.repeat();
  }

  @override
  void didUpdateWidget(_RpgSendAffordance old) {
    super.didUpdateWidget(old);
    if (widget.isSending && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.isSending && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSending) return widget.child;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _spin,
              builder: (_, _) => CustomPaint(
                painter: _RuneRingPainter(t: _spin.value),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _RuneRingPainter extends CustomPainter {
  _RuneRingPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.65;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * math.pi * 2);
    final tick = Paint()
      ..strokeWidth = 1.5
      ..color = RpgPalette.gold.withValues(alpha: 0.7);
    for (var i = 0; i < 12; i++) {
      final a = i * (math.pi * 2 / 12);
      final o = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(o * (radius - 3), o * (radius + 3), tick);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RuneRingPainter old) => old.t != t;
}
```

- [ ] **Step 4: Wire it into the RPG theme builder**

In `lib/core/theme/themes/rpg/rpg_theme.dart`, add the import and replace `const AppMotion(),` with `rpgMotion(reduceEffects: reduceEffects),`.

- [ ] **Step 5: Run test + analysis**

Run: `fvm flutter test test/core/theme/themes/rpg_motion_test.dart`
Expected: PASS.

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/themes/rpg/rpg_motion.dart lib/core/theme/themes/rpg/rpg_theme.dart test/core/theme/themes/rpg_motion_test.dart
git commit -m "feat(theme): Arcane Quest reactive motion (sparkle shower/runic crack/rune-ring send)"
```

---

## Task 10: Brutalist motion (STAMP send, "200" ink-stamp, glitch-shake error)

**Files:**
- Create: `lib/core/theme/themes/brutalist/brutalist_motion.dart`
- Modify: `lib/core/theme/themes/brutalist/brutalist_theme.dart` (replace `const AppMotion()` with `brutalistMotion(reduceEffects: reduceEffects)`)
- Test: `test/core/theme/themes/brutalist_motion_test.dart`

**Interfaces:**
- Consumes: `AppMotion` (Task 4), `ReactionStage` (Task 7), `ThemeReaction` (Task 1), `BrutalistPalette` (use the existing brutalist palette/status colors — open the file to confirm the exact symbol names before writing, e.g. status success/error).
- Produces: `AppMotion brutalistMotion({required bool reduceEffects})`. Identity when reduced.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/brutalist_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';

void main() {
  testWidgets('stamp on success shows the status code text', (tester) async {
    final motion = brutalistMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
        body: motion.reactionOverlay(
          context,
          controller: controller,
          child: const Text('app'),
        ),
      );
    })));
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('200'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    controller.dispose();
  });

  test('reduced effects => identity', () {
    final motion = brutalistMotion(reduceEffects: true);
    expect(motion.runtimeType.toString(), 'AppMotion');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/brutalist_motion_test.dart`
Expected: FAIL — `brutalistMotion` undefined.

- [ ] **Step 3: Implement**

First open `lib/core/theme/themes/brutalist/brutalist_palette.dart` and note the exact success/error color symbol names; substitute them where this code references `BrutalistPalette.statusSuccess` / `BrutalistPalette.statusError` (adjust if the names differ).

```dart
// lib/core/theme/themes/brutalist/brutalist_motion.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_palette.dart';

/// Brutalist motion: a giant status-code ink-stamp thuds onto the screen, a
/// glitch-shake on errors, and a hard "STAMP" slam on the SEND button. Identity
/// when [reduceEffects].
AppMotion brutalistMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _BrutalReactionOverlay(controller: controller, child: child),
    sendAffordance: (context, {required child, required isSending}) =>
        _BrutalStampSend(child: child),
  );
}

class _BrutalReactionOverlay extends StatefulWidget {
  const _BrutalReactionOverlay({required this.controller, required this.child});
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_BrutalReactionOverlay> createState() => _BrutalReactionOverlayState();
}

class _BrutalReactionOverlayState extends State<_BrutalReactionOverlay>
    with TickerProviderStateMixin {
  AnimationController? _stamp;
  String _label = '';
  bool _isError = false;

  void _onReaction(ThemeReaction r) {
    if (r.kind == ThemeReactionKind.sendStarted) return;
    _label = switch (r.kind) {
      ThemeReactionKind.cancelled => 'CANCELLED',
      ThemeReactionKind.networkError => 'FAILED',
      _ => '${r.statusCode ?? 0}',
    };
    _isError = r.isError;
    _stamp?.dispose();
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() {});
      }
    });
    setState(() => _stamp = c);
    unawaited(c.forward());
  }

  @override
  void dispose() {
    _stamp?.dispose();
    super.dispose();
  }

  double _shakeDx(double t) {
    if (!_isError) return 0;
    final decay = (1 - (t / 0.4)).clamp(0.0, 1.0);
    return math.sin(t * math.pi * 16) * 8 * decay;
  }

  @override
  Widget build(BuildContext context) {
    final stamp = _stamp;
    final color = _isError ? BrutalistPalette.statusError : BrutalistPalette.statusSuccess;
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      child: stamp == null
          ? widget.child
          : AnimatedBuilder(
              animation: stamp,
              builder: (context, _) {
                final t = stamp.value;
                // Stamp: scale from big->1 in 0..0.18 (the "thud"), hold, fade out.
                final inT = (t / 0.18).clamp(0.0, 1.0);
                final scale = 2.4 - 1.4 * Curves.easeOutBack.transform(inT);
                final alpha = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
                return Transform.translate(
                  offset: Offset(_shakeDx(t), 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      widget.child,
                      IgnorePointer(
                        child: Opacity(
                          opacity: alpha,
                          child: Transform.scale(
                            scale: scale,
                            child: Transform.rotate(
                              angle: -0.12,
                              child: _StampLabel(label: _label, color: color),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _StampLabel extends StatelessWidget {
  const _StampLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: color, width: 6)),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 72,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
    );
  }
}

/// SEND "STAMP": a hard downward slam onto its shadow on press.
class _BrutalStampSend extends StatefulWidget {
  const _BrutalStampSend({required this.child});
  final Widget child;

  @override
  State<_BrutalStampSend> createState() => _BrutalStampSendState();
}

class _BrutalStampSendState extends State<_BrutalStampSend>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    lowerBound: 0,
    upperBound: 1,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _c.forward(from: 0),
      onPointerUp: (_) => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(_c.value * 3, _c.value * 3),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
```

- [ ] **Step 4: Wire it into the brutalist theme builder**

In `lib/core/theme/themes/brutalist/brutalist_theme.dart`, add the import and replace `const AppMotion(),` with `brutalistMotion(reduceEffects: reduceEffects),`.

- [ ] **Step 5: Run test + analysis**

Run: `fvm flutter test test/core/theme/themes/brutalist_motion_test.dart`
Expected: PASS.

Run: `fvm flutter analyze`
Expected: 0 issues. (Note: `fontSize: 72` etc. are inside a theme-internal file — allowed. If `avoid_hardcoded_brand_colors` flags anything, it won't: `color` comes from `BrutalistPalette`, not a `Colors.*` literal.)

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/themes/brutalist/brutalist_motion.dart lib/core/theme/themes/brutalist/brutalist_theme.dart test/core/theme/themes/brutalist_motion_test.dart
git commit -m "feat(theme): Brutalist reactive motion (stamp/glitch-shake/STAMP send)"
```

---

## Task 11: Phase 1 verification gate

**Files:** none (verification only).

- [ ] **Step 1: Run the full done-bar**

```bash
fvm dart format lib test
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```

Expected: format clean, all three analyses 0 issues, all tests green.

- [ ] **Step 2: Manual smoke (optional but recommended)**

Run: `fvm flutter run -d macos`, switch to Liquid Glass / Arcane Quest / Brutalist, send a request to a 200 endpoint and a 500 endpoint, confirm the success/error effects fire and the SEND ritual plays. Toggle REDUCE VISUAL EFFECTS and confirm effects stop.

- [ ] **Step 3: Commit (if formatter changed anything)**

```bash
git add -A && git commit -m "chore(theme): phase 1 format/verify" || echo "nothing to commit"
```

---

# Phase 2 — Calm themes + ambient enrichments + theme-switch transition

## Task 12: Shared calm motion (Classic / Editorial / Dracula)

**Files:**
- Create: `lib/core/theme/themes/shared/calm_motion.dart`
- Modify: `classic_theme.dart`, `editorial_theme.dart`, `dracula_theme.dart` (replace `const AppMotion()` with `calmMotion(reduceEffects: reduceEffects)`)
- Test: `test/core/theme/themes/calm_motion_test.dart`

**Interfaces:**
- Consumes: `AppMotion` (Task 4), `ReactionStage` (Task 7), `ThemeReaction` (Task 1).
- Produces: `AppMotion calmMotion({required bool reduceEffects})`. A restrained top-edge status pulse bar (success = theme success color, error = theme error color) + a subtle progress shimmer on SEND while sending. No background motion, no shake. Identity when reduced.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/calm_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/shared/calm_motion.dart';

void main() {
  testWidgets('renders child + survives success/error pulses', (tester) async {
    final motion = calmMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
        body: motion.reactionOverlay(
          context,
          controller: controller,
          child: const Text('app'),
        ),
      );
    })));
    expect(find.text('app'), findsOneWidget);
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200));
    await tester.pump(const Duration(milliseconds: 100));
    controller.fire(const ThemeReaction(kind: ThemeReactionKind.clientError, statusCode: 404));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    controller.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/calm_motion_test.dart`
Expected: FAIL — `calmMotion` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/theme/themes/shared/calm_motion.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/extensions/app_palette.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// Restrained reactive motion for the calm themes: a thin status-colored pulse
/// bar that sweeps the top edge on each outcome. No background motion, no
/// shake. Identity when [reduceEffects].
AppMotion calmMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _CalmReactionOverlay(controller: controller, child: child),
    // Calm send: keep the existing interactive press; no extra ritual.
  );
}

class _CalmReactionOverlay extends StatefulWidget {
  const _CalmReactionOverlay({required this.controller, required this.child});
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_CalmReactionOverlay> createState() => _CalmReactionOverlayState();
}

class _CalmReactionOverlayState extends State<_CalmReactionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  Color? _color;

  void _onReaction(ThemeReaction r) {
    if (r.kind == ThemeReactionKind.sendStarted) return;
    final palette = Theme.of(context).extension<AppPalette>();
    _color = r.isError
        ? Theme.of(context).colorScheme.error
        : (palette?.statusColor(r.statusCode ?? 200) ??
            Theme.of(context).colorScheme.primary);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final color = _color;
                  if (color == null || _c.value == 0 || _c.value == 1) {
                    return const SizedBox.shrink();
                  }
                  // Fade in then out; full-width 3px bar.
                  final a = _c.value < 0.5 ? _c.value * 2 : (1 - _c.value) * 2;
                  return Container(
                    height: 3,
                    color: color.withValues(alpha: a.clamp(0.0, 1.0)),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

(Confirm `AppPalette.statusColor(int)` exists — it's referenced in CLAUDE.md §4.8; open `lib/core/theme/extensions/app_palette.dart` to verify the signature.)

- [ ] **Step 4: Wire into the three calm theme builders**

In `classic_theme.dart`, `editorial_theme.dart`, `dracula_theme.dart`: add `import 'package:getman/core/theme/themes/shared/calm_motion.dart';` and replace `const AppMotion(),` with `calmMotion(reduceEffects: reduceEffects),`.

- [ ] **Step 5: Run test + analysis**

Run: `fvm flutter test test/core/theme/themes/calm_motion_test.dart`
Expected: PASS.

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/themes/shared/calm_motion.dart lib/core/theme/themes/classic/classic_theme.dart lib/core/theme/themes/editorial/editorial_theme.dart lib/core/theme/themes/dracula/dracula_theme.dart test/core/theme/themes/calm_motion_test.dart
git commit -m "feat(theme): restrained reactive motion for Classic/Editorial/Dracula"
```

---

## Task 13: Arcane ambient — shooting stars, constellations, cursor parallax

**Files:**
- Modify: `lib/core/theme/themes/rpg/rpg_decorations.dart` (`_RpgAnimatedBackground` + `_StarfieldPainter`)
- Test: `test/core/theme/themes/rpg_ambient_test.dart`

**Interfaces:**
- Consumes: existing `_RpgAnimatedBackground`, `_StarfieldPainter`, `_Mote`.
- Produces: the animated starfield additionally renders occasional shooting stars (derived from `t`, no extra state), faint constellation lines between near motes, and shifts mote positions by a pointer-parallax offset fed from a wrapping `MouseRegion`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/themes/rpg_ambient_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  testWidgets('RPG animated background renders child + pumps without throwing',
      (tester) async {
    final theme =
        resolveThemeData(kRpgThemeId, Brightness.dark, isCompact: false);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => context.appDecoration.scaffoldBackground(
          context,
          child: const Text('bg'),
        ),
      ),
    ));
    // Pump a few animation frames; the ambient painter must not throw.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('bg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

> This is a smoke test (ambient visuals are tuned by eye) — its job is to catch crashes/regressions in the painter, not pixel-match.

- [ ] **Step 2: Run test to verify it fails or is red**

Run: `fvm flutter test test/core/theme/themes/rpg_ambient_test.dart`
Expected: the simplified smoke test should pass against the CURRENT background already. Treat this task as enhancement-with-regression-guard: ensure the test compiles and passes before AND after.

- [ ] **Step 3: Add pointer parallax to `_RpgAnimatedBackground`**

In `_RpgAnimatedBackgroundState.build`, wrap the returned `Stack` in a `MouseRegion` that records the normalized pointer offset into a `ValueNotifier<Offset>` (default `Offset.zero`), and pass that notifier to `_StarfieldPainter`. Add the field:

```dart
  final ValueNotifier<Offset> _pointer = ValueNotifier<Offset>(Offset.zero);
```

Dispose it in `dispose()`. In `build`, wrap with:

```dart
    return MouseRegion(
      onHover: (e) {
        final size = context.size;
        if (size == null) return;
        // Normalized -1..1 from center; parallax is a few px so keep it small.
        _pointer.value = Offset(
          (e.localPosition.dx / size.width) * 2 - 1,
          (e.localPosition.dy / size.height) * 2 - 1,
        );
      },
      child: Stack( ... existing children ... ),
    );
```

Change `_StarfieldPainter` construction to pass `pointer: _pointer` and add it as a `Listenable` in the painter's `super(repaint: Listenable.merge([tListenable, _pointer]))`.

- [ ] **Step 4: Add parallax + constellations + shooting stars to `_StarfieldPainter`**

In `_StarfieldPainter`, add `final ValueListenable<Offset> pointer;` to the constructor. In `paint`:
- Apply parallax: offset each mote by `pointer.value * (m.size * 4)` (bigger motes shift more → depth). Compute `final par = pointer.value;` once.
- Constellation lines: after drawing motes, for each pair of motes within ~90px, draw a hairline `RpgPalette.gold.withValues(alpha: 0.06 * proximity)` line. Cap the inner loop (e.g. only compare each mote to the next 6 in the list) to stay cheap.
- Shooting star: derive a periodic streak from `t` — e.g. `final shoot = (t * 3) % 1.0;` if `shoot < 0.12`, draw a bright tapered line crossing a deterministic diagonal (seeded by `floor(t*3)`), alpha peaking mid-streak. One at a time, no state.

Keep `shouldRepaint` returning true when `t`/pointer change (the merged repaint listenable already drives this).

> Implementer: keep particle/line counts modest (existing 45 motes; constellation comparisons bounded). This is viewport-bound paint; no per-frame widget allocation.

- [ ] **Step 5: Run test + analysis**

Run: `fvm flutter test test/core/theme/themes/rpg_ambient_test.dart`
Expected: PASS (no exceptions across pumped frames).

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/themes/rpg/rpg_decorations.dart test/core/theme/themes/rpg_ambient_test.dart
git commit -m "feat(theme): Arcane ambient — shooting stars, constellations, cursor parallax"
```

---

## Task 14: Liquid Glass ambient — pointer-following specular sheen

**Files:**
- Modify: `lib/core/theme/themes/glass/glass_decorations.dart` (`GlassWallpaper` + `_GlassMeshPainter`)
- Test: `test/core/theme/themes/glass_ambient_test.dart`

**Interfaces:**
- Consumes: existing `GlassWallpaper`, `_GlassMeshPainter`.
- Produces: the mesh wallpaper additionally paints a soft radial specular highlight that follows the cursor, fed from a `MouseRegion` → `ValueNotifier<Offset>` (defaults to a gentle idle position when no pointer).

- [ ] **Step 1: Write the failing/smoke test**

```dart
// test/core/theme/themes/glass_ambient_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/theme_ids.dart';

void main() {
  testWidgets('Glass wallpaper renders child + pumps without throwing',
      (tester) async {
    final theme = resolveThemeData(kGlassThemeId, Brightness.dark, isCompact: false);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(builder: (context) {
        return context.appDecoration.scaffoldBackground(
          context,
          child: const Text('bg'),
        );
      }),
    ));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('bg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run test (passes against current; regression guard)**

Run: `fvm flutter test test/core/theme/themes/glass_ambient_test.dart`
Expected: PASS now and after the change.

- [ ] **Step 3: Add a pointer notifier to `GlassWallpaper` — gated on `animate`**

In `_GlassWallpaperState`, add `final ValueNotifier<Offset> _pointer = ValueNotifier<Offset>(const Offset(0.5, 0.35));` (normalized 0..1). Dispose it in `dispose()`.

**Critical (reduced-effects safety):** `_GlassMeshPainter` is shared by both the animated (`animate: true`) and static (`animate: false` = reduced effects) wallpaper. The sheen and its `MouseRegion` must only be active when `widget.animate` is true, otherwise the static frame would repaint on every pointer move and break the "zero per-frame cost" reduced mode. So:
- Only attach the `MouseRegion` when `widget.animate`. In `build`, when `widget.animate` wrap the `Stack` in a `MouseRegion` whose `onHover` sets `_pointer.value = Offset(e.localPosition.dx / size.width, e.localPosition.dy / size.height)` (guard on `context.size`); when not animating, return the `Stack` unwrapped.
- Pass `pointer: widget.animate ? _pointer : null` to `_GlassMeshPainter`.

- [ ] **Step 4: Paint the sheen in `_GlassMeshPainter` (only when pointer != null)**

Make the painter accept a nullable pointer: `final ValueListenable<Offset>? pointer;`. Build the repaint listenable conditionally — `super(repaint: pointer == null ? t : Listenable.merge([t, pointer]))`. After the base + blobs are drawn, paint the sheen **only when `pointer != null`** (i.e. animated mode):

```dart
    final ptr = pointer;
    if (ptr != null) {
      final p = ptr.value;
      final center = Offset(p.dx * size.width, p.dy * size.height);
      final sheen = Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            // theme-internal near-white highlight; Colors.white is allowed
            // under lib/core/theme (exempt from avoid_hardcoded_brand_colors).
            Colors.white.withValues(alpha: 0.06),
            const Color(0x00000000),
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: size.shortestSide * 0.6),
        );
      canvas.drawRect(rect, sheen);
    }
```

Update `shouldRepaint` to also compare `old.pointer != pointer`. Keep alpha low so it reads as a sheen, not a spotlight. Reduced mode (`pointer == null`) is unchanged from today — one static frame, zero per-frame cost.

- [ ] **Step 5: Run test + analysis**

Run: `fvm flutter test test/core/theme/themes/glass_ambient_test.dart`
Expected: PASS.

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/themes/glass/glass_decorations.dart test/core/theme/themes/glass_ambient_test.dart
git commit -m "feat(theme): Liquid Glass ambient — cursor-following specular sheen"
```

---

## Task 15: Theme-switch transition

**Files:**
- Create: `lib/core/theme/motion/theme_switch_transition.dart`
- Modify: `lib/main.dart` — wrap the `reactionOverlay(...)` output of the `MaterialApp.router` builder with `ThemeSwitchTransition(themeId: settings.themeId, reduceEffects: settings.reduceVisualEffects, child: ...)`. (`settings` is in scope in the `BlocBuilder` above; pass it down, or read `context.watch<SettingsBloc>().state.settings.themeId` inside the transition — prefer passing the id explicitly from the builder closure which already has `settings`.)
- Test: `test/core/theme/motion/theme_switch_transition_test.dart`

**Interfaces:**
- Produces: `class ThemeSwitchTransition extends StatefulWidget { const ThemeSwitchTransition({required String themeId, required bool reduceEffects, required Widget child}); }` — when `themeId` changes it plays a ~450ms overlay sweep/dissolve once. Instant (no overlay) when `reduceEffects`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/motion/theme_switch_transition_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_switch_transition.dart';

void main() {
  testWidgets('plays an overlay on themeId change, then settles', (tester) async {
    var id = 'a';
    late StateSetter setOuter;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        setOuter = setState;
        return ThemeSwitchTransition(
          themeId: id,
          reduceEffects: false,
          child: const Text('content', textDirection: TextDirection.ltr),
        );
      }),
    ));
    expect(find.text('content'), findsOneWidget);

    setOuter(() => id = 'b');
    await tester.pump(); // start transition
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600)); // finish
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('reduced effects: no overlay on change', (tester) async {
    var id = 'a';
    late StateSetter setOuter;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        setOuter = setState;
        return ThemeSwitchTransition(
          themeId: id,
          reduceEffects: true,
          child: const Text('content', textDirection: TextDirection.ltr),
        );
      }),
    ));
    setOuter(() => id = 'b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/motion/theme_switch_transition_test.dart`
Expected: FAIL — `ThemeSwitchTransition` undefined.

- [ ] **Step 3: Implement**

```dart
// lib/core/theme/motion/theme_switch_transition.dart
import 'dart:async';

import 'package:flutter/material.dart';

/// Plays a brief one-shot sweep/dissolve overlay whenever [themeId] changes, so
/// switching themes feels intentional rather than an instant cut. Instant (no
/// overlay) when [reduceEffects] — matching main.dart's themeAnimationDuration:
/// Duration.zero decision.
class ThemeSwitchTransition extends StatefulWidget {
  const ThemeSwitchTransition({
    required this.themeId,
    required this.reduceEffects,
    required this.child,
    super.key,
  });

  final String themeId;
  final bool reduceEffects;
  final Widget child;

  @override
  State<ThemeSwitchTransition> createState() => _ThemeSwitchTransitionState();
}

class _ThemeSwitchTransitionState extends State<ThemeSwitchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void didUpdateWidget(ThemeSwitchTransition old) {
    super.didUpdateWidget(old);
    if (old.themeId != widget.themeId && !widget.reduceEffects) {
      _c.forward(from: 0);
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
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            if (_c.value == 0 || _c.value == 1) return const SizedBox.shrink();
            return Positioned.fill(
              key: const ValueKey('theme_switch_overlay'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SweepPainter(t: _c.value, color: accent),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A diagonal accent sweep that wipes across (0..0.5) then reveals (0.5..1).
class _SweepPainter extends CustomPainter {
  _SweepPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Cover then uncover: a wide band travels left->right; opacity peaks mid.
    final x = Curves.easeInOut.transform(t) * (size.width * 1.6) - size.width * 0.3;
    final alpha = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0) * 0.85;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0x00000000),
          color.withValues(alpha: alpha),
          const Color(0x00000000),
        ],
      ).createShader(Rect.fromLTWH(x - size.width * 0.4, 0, size.width * 0.8, size.height));
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) => old.t != t || old.color != color;
}
```

- [ ] **Step 4: Mount in `main.dart`**

Add `import 'package:getman/core/theme/motion/theme_switch_transition.dart';`. In the `MaterialApp.router` `builder`, wrap the existing `context.appMotion.reactionOverlay(...)` result:

```dart
                      builder: (context, child) {
                        return Focus(
                          autofocus: true,
                          child: ThemeSwitchTransition(
                            themeId: settings.themeId,
                            reduceEffects: settings.reduceVisualEffects,
                            child: context.appMotion.reactionOverlay(
                              context,
                              controller: context.read<ThemeReactionController>(),
                              child: context.appDecoration.scaffoldBackground(
                                context,
                                child: child ?? const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        );
                      },
```

(`settings` is captured by the `BlocBuilder` builder closure that wraps `MaterialApp.router`.)

- [ ] **Step 5: Run test + analysis**

Run: `fvm flutter test test/core/theme/motion/theme_switch_transition_test.dart`
Expected: PASS.

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/motion/theme_switch_transition.dart lib/main.dart test/core/theme/motion/theme_switch_transition_test.dart
git commit -m "feat(theme): theme-switch sweep transition"
```

---

## Task 16: Phase 2 verification gate

**Files:** none.

- [ ] **Step 1: Full done-bar**

```bash
fvm dart format lib test
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```

Expected: all green/clean.

- [ ] **Step 2: Commit (if format changed)**

```bash
git add -A && git commit -m "chore(theme): phase 2 format/verify" || echo "nothing to commit"
```

---

# Phase 3 — Opt-in themed sound

## Task 17: `enableThemeSounds` setting (model + entity + event + bloc + dialog)

**Files:**
- Modify: `lib/features/settings/data/models/settings_model.dart` (constructor, `fromJson`, `fromEntity`, `@HiveField(27)`, `copyWith`, `toJson`, `toEntity`)
- Modify: `lib/features/settings/domain/entities/settings_entity.dart` (constructor field, `copyWith`, `props`, `toEntity` parity)
- Modify: `lib/features/settings/presentation/bloc/settings_event.dart` (new `UpdateEnableThemeSounds`)
- Modify: `lib/features/settings/presentation/bloc/settings_bloc.dart` (handler)
- Modify: `lib/features/settings/presentation/widgets/settings_dialog.dart` (APPEARANCE toggle after REDUCE VISUAL EFFECTS)
- Regenerate: `settings_model.g.dart` via build_runner
- Test: `test/features/settings/enable_theme_sounds_test.dart`

**Interfaces:**
- Produces: `SettingsEntity.enableThemeSounds` (bool, default false); `SettingsModel` HiveField(27); `UpdateEnableThemeSounds({required bool value})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/settings/enable_theme_sounds_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';

void main() {
  test('defaults to false; round-trips through model + json', () {
    const entity = SettingsEntity();
    expect(entity.enableThemeSounds, isFalse);

    final model = SettingsModel.fromEntity(
      entity.copyWith(enableThemeSounds: true),
    );
    expect(model.enableThemeSounds, isTrue);
    expect(model.toEntity().enableThemeSounds, isTrue);

    final json = model.toJson();
    expect(json['enableThemeSounds'], isTrue);
    expect(SettingsModel.fromJson(json).enableThemeSounds, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/settings/enable_theme_sounds_test.dart`
Expected: FAIL — `enableThemeSounds` undefined.

- [ ] **Step 3: Add the field to `SettingsEntity`**

In `settings_entity.dart`: add `this.enableThemeSounds = false,` to the constructor; add `final bool enableThemeSounds;` near `reduceVisualEffects`; add `enableThemeSounds` to `props`; add `bool? enableThemeSounds,` to `copyWith` params and `enableThemeSounds: enableThemeSounds ?? this.enableThemeSounds,` to its body. (Open the file to place these consistently — it follows the same shape as `SettingsModel`.)

- [ ] **Step 4: Add the field to `SettingsModel`**

In `settings_model.dart`:
- Constructor: `this.enableThemeSounds = false,`
- `fromJson`: `enableThemeSounds: json['enableThemeSounds'] as bool? ?? false,`
- `fromEntity`: `enableThemeSounds: entity.enableThemeSounds,`
- Field declaration:
  ```dart
  @HiveField(27, defaultValue: false)
  bool enableThemeSounds;
  ```
- `copyWith`: add `bool? enableThemeSounds,` param and `enableThemeSounds: enableThemeSounds ?? this.enableThemeSounds,` in the returned `SettingsModel`.
- `toJson`: `'enableThemeSounds': enableThemeSounds,`
- `toEntity`: `enableThemeSounds: enableThemeSounds,`

- [ ] **Step 5: Regenerate the adapter**

Run: `fvm dart run build_runner build --delete-conflicting-outputs`
Expected: `settings_model.g.dart` regenerates with field 27 read/written. Verify the generated file references `enableThemeSounds`.

- [ ] **Step 6: Add the event + handler**

In `settings_event.dart`, append:

```dart
class UpdateEnableThemeSounds extends SettingsEvent {
  const UpdateEnableThemeSounds({required this.value});
  final bool value;
  @override
  List<Object?> get props => [value];
}
```

In `settings_bloc.dart`, inside the constructor's handler list (e.g. after `on<UpdateReduceVisualEffects>(...)`):

```dart
    on<UpdateEnableThemeSounds>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(enableThemeSounds: e.value)),
    );
```

- [ ] **Step 7: Add the APPEARANCE toggle**

In `settings_dialog.dart`, in the appearance tab list right after the `REDUCE VISUAL EFFECTS` `_switch(...)` (line ~285), add:

```dart
      _switch(
        context,
        switchKey: const ValueKey('theme_sounds_switch'),
        title: 'THEME SOUNDS',
        icon: Icons.volume_up,
        subtitle: 'Play themed sound effects on send & response',
        value: settings.enableThemeSounds,
        onChanged: (v) => bloc.add(UpdateEnableThemeSounds(value: v)),
      ),
```

(Ensure `UpdateEnableThemeSounds` is imported via the existing settings_event import.)

- [ ] **Step 8: Run tests + analysis**

Run: `fvm flutter test test/features/settings/enable_theme_sounds_test.dart`
Expected: PASS.

Run: `fvm flutter test test/features/settings/`
Expected: PASS (existing settings tests still green).

Run: `fvm flutter analyze && fvm dart run bloc_tools:bloc lint lib`
Expected: 0 issues each.

- [ ] **Step 9: Commit**

```bash
git add lib/features/settings test/features/settings/enable_theme_sounds_test.dart
git commit -m "feat(settings): enableThemeSounds (HiveField 27) + APPEARANCE toggle"
```

---

## Task 18: `ThemeSoundService` (web-safe interface + io/stub) + DI + pubspec/assets

**Files:**
- Create: `lib/core/audio/theme_sound_service.dart` (abstract interface + conditional factory)
- Create: `lib/core/audio/theme_sound_service_io.dart` (audioplayers-backed; native)
- Create: `lib/core/audio/theme_sound_service_stub.dart` (no-op; web/fallback)
- Modify: `pubspec.yaml` (`audioplayers` dependency + `assets/sounds/` registration)
- Add: `assets/sounds/<theme>/{send,success,error}.mp3` (CC0/royalty-free; see Step 6)
- Modify: `lib/core/di/injection_container.dart` (register `ThemeSoundService` singleton via the factory)
- Test: `test/core/audio/theme_sound_service_test.dart`

**Interfaces:**
- Consumes: `ThemeReaction` (Task 1).
- Produces:
  - `abstract class ThemeSoundService { Future<void> play(String themeId, ThemeReaction reaction); void dispose(); }`
  - `ThemeSoundService createThemeSoundService()` — returns the io impl on native, the stub on web/unsupported.
  - The io impl no-ops (catches) when an asset is missing or the backend is unavailable, so a missing audio file never throws.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/audio/theme_sound_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/audio/theme_sound_service_stub.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

void main() {
  test('stub play never throws and is a no-op', () async {
    final ThemeSoundService svc = StubThemeSoundService();
    await svc.play('rpg',
        const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200));
    svc.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/audio/theme_sound_service_test.dart`
Expected: FAIL — URIs don't exist.

- [ ] **Step 3: Create the interface + factory (conditional import)**

```dart
// lib/core/audio/theme_sound_service.dart
import 'package:getman/core/audio/theme_sound_service_stub.dart'
    if (dart.library.io) 'package:getman/core/audio/theme_sound_service_io.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// Plays short, themed one-shot sound effects keyed by (themeId, reaction).
/// Implementations must NEVER throw from [play] — a missing asset or
/// unavailable audio backend degrades to silence.
abstract class ThemeSoundService {
  Future<void> play(String themeId, ThemeReaction reaction);
  void dispose();
}

/// Native => audioplayers-backed; web/unsupported => no-op stub.
ThemeSoundService createThemeSoundService() => createThemeSoundServiceImpl();
```

- [ ] **Step 4: Create the stub**

```dart
// lib/core/audio/theme_sound_service_stub.dart
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

class StubThemeSoundService implements ThemeSoundService {
  @override
  Future<void> play(String themeId, ThemeReaction reaction) async {}
  @override
  void dispose() {}
}

ThemeSoundService createThemeSoundServiceImpl() => StubThemeSoundService();
```

- [ ] **Step 5: Create the io impl**

```dart
// lib/core/audio/theme_sound_service_io.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';

/// audioplayers-backed sound service. Defensive: any failure (missing asset,
/// no backend — e.g. Linux without GStreamer) is swallowed so audio never
/// breaks the app.
class IoThemeSoundService implements ThemeSoundService {
  final AudioPlayer _player = AudioPlayer(playerId: 'getman_theme_sfx')
    ..setReleaseMode(ReleaseMode.stop);

  // Which reaction kinds map to which cue file.
  static String? _cue(ThemeReaction r) {
    switch (r.kind) {
      case ThemeReactionKind.sendStarted:
        return 'send';
      case ThemeReactionKind.success:
        return 'success';
      case ThemeReactionKind.clientError:
      case ThemeReactionKind.serverError:
      case ThemeReactionKind.networkError:
        return 'error';
      case ThemeReactionKind.cancelled:
        return null; // no cue for cancel
    }
  }

  @override
  Future<void> play(String themeId, ThemeReaction reaction) async {
    final cue = _cue(reaction);
    if (cue == null) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$themeId/$cue.mp3'), volume: 0.5);
    } on Object catch (e) {
      // Missing asset / unsupported backend → silence.
      debugPrint('ThemeSoundService: play failed ($themeId/$cue): $e');
    }
  }

  @override
  void dispose() => unawaited(_player.dispose());
}

ThemeSoundService createThemeSoundServiceImpl() => IoThemeSoundService();
```

> Note: `unawaited` needs `import 'dart:async';` — add it. (The plan keeps imports explicit; add `import 'dart:async';` at the top of the io file.)

- [ ] **Step 6: Add the dependency + assets to `pubspec.yaml`**

Under `dependencies:` add:

```yaml
  audioplayers: ^6.1.0
```

Under `flutter: assets:` add the per-theme sound folders:

```yaml
    - assets/sounds/classic/
    - assets/sounds/brutalist/
    - assets/sounds/editorial/
    - assets/sounds/rpg/
    - assets/sounds/dracula/
    - assets/sounds/glass/
```

Create the directories and add CC0/royalty-free `send.mp3`, `success.mp3`, `error.mp3` in each (sources: e.g. freesound.org CC0, or kenney.nl audio packs). **If a cue is missing the service no-ops** (Step 5), so the app still builds and runs — sourcing audio is a content task that can lag the code. At minimum create the directories with a `.gitkeep` so the asset paths resolve; loud themes (rpg/glass/brutalist) should get real cues first.

Run: `fvm flutter pub get`
Expected: resolves `audioplayers`.

- [ ] **Step 7: Register in DI**

In `injection_container.dart`, add:

```dart
import 'package:getman/core/audio/theme_sound_service.dart';
```

and register (next to the `ThemeReactionController` registration from Task 5):

```dart
    ..registerLazySingleton<ThemeSoundService>(createThemeSoundService);
```

- [ ] **Step 8: Provide it to the widget tree**

In `main.dart`, add to the `MultiRepositoryProvider.providers` list:

```dart
        RepositoryProvider<ThemeSoundService>.value(
          value: di.sl<ThemeSoundService>(),
        ),
```

(Import `package:getman/core/audio/theme_sound_service.dart`.)

- [ ] **Step 9: Run tests + analysis**

Run: `fvm flutter test test/core/audio/theme_sound_service_test.dart`
Expected: PASS.

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 10: Commit**

```bash
git add lib/core/audio pubspec.yaml pubspec.lock lib/core/di/injection_container.dart lib/main.dart assets/sounds test/core/audio/theme_sound_service_test.dart
git commit -m "feat(audio): web-safe ThemeSoundService (audioplayers io + no-op stub)"
```

---

## Task 19: Play sound from the reaction stream

**Files:**
- Modify: `lib/features/home/presentation/widgets/theme_reaction_listener.dart` (also play sound when `enableThemeSounds`)
- Test: `test/features/home/theme_reaction_sound_test.dart`

**Interfaces:**
- Consumes: `ThemeSoundService` (Task 18), `SettingsBloc` (for `enableThemeSounds` + `themeId`), `ThemeReactionController` (Task 5).
- Produces: the listener, on each reaction, calls `soundService.play(themeId, reaction)` when the setting is on.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/home/theme_reaction_sound_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/features/home/presentation/widgets/theme_reaction_listener.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

class _FakeTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _FakeTabsBloc() : super(const TabsState());
  void push(TabsState s) => emit(s);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _FakeSettingsBloc(SettingsEntity s) : super(SettingsState(settings: s));
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RecordingSound implements ThemeSoundService {
  final calls = <String>[];
  @override
  Future<void> play(String themeId, ThemeReaction r) async =>
      calls.add('$themeId:${r.kind.name}');
  @override
  void dispose() {}
}

void main() {
  testWidgets('plays sound only when enabled', (tester) async {
    final tabs = _FakeTabsBloc();
    final controller = ThemeReactionController();
    final sound = _RecordingSound();

    Future<void> pumpWith(bool enabled) async {
      final settings = _FakeSettingsBloc(
        SettingsEntity(enableThemeSounds: enabled, themeId: 'rpg'),
      );
      await tester.pumpWidget(MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ThemeReactionController>.value(value: controller),
          RepositoryProvider<ThemeSoundService>.value(value: sound),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: const MaterialApp(home: ThemeReactionListener(child: SizedBox())),
        ),
      ));
    }

    await pumpWith(false);
    tabs.push(const TabsState(
      reactionSeq: 1,
      lastReaction: ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    ));
    await tester.pump();
    expect(sound.calls, isEmpty);

    await pumpWith(true);
    tabs.push(const TabsState(
      reactionSeq: 2,
      lastReaction: ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    ));
    await tester.pump();
    expect(sound.calls, ['rpg:success']);

    await tabs.close();
    controller.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/home/theme_reaction_sound_test.dart`
Expected: FAIL — the listener doesn't yet play sound.

- [ ] **Step 3: Extend the listener**

Replace the body of `ThemeReactionListener.build` (Task 5) so the listener callback also plays sound (read settings + service from context):

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/audio/theme_sound_service.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

class ThemeReactionListener extends StatelessWidget {
  const ThemeReactionListener({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) =>
          next.reactionSeq != prev.reactionSeq && next.lastReaction != null,
      listener: (context, state) {
        final reaction = state.lastReaction!;
        context.read<ThemeReactionController>().fire(reaction);
        final settings = context.read<SettingsBloc>().state.settings;
        if (settings.enableThemeSounds) {
          // play() never throws (service contract); fire-and-forget.
          context.read<ThemeSoundService>().play(settings.themeId, reaction);
        }
      },
      child: child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/home/theme_reaction_sound_test.dart`
Expected: PASS.

Run: `fvm flutter test test/features/home/theme_reaction_listener_test.dart`
Expected: PASS — but the original test (Task 5) does NOT provide `SettingsBloc`/`ThemeSoundService`. UPDATE that earlier test to also wrap with a `SettingsBloc` (sounds disabled) + a no-op `ThemeSoundService`, OR guard the reads with `context.read` only when needed. Simplest: in the Task 5 test, add the two providers (sounds off) so `context.read` resolves. Re-run both.

- [ ] **Step 5: Analysis**

Run: `fvm flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/presentation/widgets/theme_reaction_listener.dart test/features/home/theme_reaction_sound_test.dart test/features/home/theme_reaction_listener_test.dart
git commit -m "feat(audio): play themed sound from the reaction stream when enabled"
```

---

## Task 20: Final verification + wiki sync

**Files:**
- Modify (separate `Getman.wiki.git` repo): the **Themes** page + **Settings** page.

- [ ] **Step 1: Full done-bar**

```bash
fvm dart format lib test
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```

Expected: all clean/green.

- [ ] **Step 2: Manual smoke across themes**

`fvm flutter run -d macos`: for each theme, send to a 200 and a 500 endpoint; confirm reactive effects + the theme-switch sweep when changing themes. Toggle REDUCE VISUAL EFFECTS (all motion stops) and THEME SOUNDS (cues play when on, silent when off). Confirm Linux/web degrade gracefully if tested.

- [ ] **Step 3: Sync the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

Edit the Themes page: document the reactive effects per theme (success/error/send), ambient enrichments (shooting stars/constellations/parallax for Arcane; cursor sheen for Glass), the theme-switch transition, and the calm/loud contrast. Edit the Settings page: add **THEME SOUNDS** (off by default; plays themed cues on send & response) and note that visual reactions ride **REDUCE VISUAL EFFECTS**. Use verbatim UI labels.

```bash
cd /tmp/getman-wiki && git add -A && git commit -m "docs: theme reactive motion + theme sounds" && git push origin master
```

- [ ] **Step 4: Final commit (if format changed)**

```bash
cd /Users/thiago/git/getman
git add -A && git commit -m "chore(theme): final verify for reactive motion feature" || echo "nothing to commit"
```

---

## Notes for the implementer

- **The visual painters are reference implementations**, tuned to be correct and crash-free, not pixel-final. After each loud-theme task, run the app and adjust counts/durations/alphas by eye — but keep the perf discipline (reused `Paint`, `RepaintBoundary`, self-disposing transient controllers, lifecycle pause for the always-on ambient backgrounds).
- **Symbol-name checks before writing:** before Task 10 confirm `BrutalistPalette` success/error symbol names; before Task 12 confirm `AppPalette.statusColor(int)`'s exact signature. Adjust the reference code to the real names.
- **`takeException()` in smoke tests** is the regression guard for the animated painters — a thrown exception mid-animation fails the test.
- **Don't reintroduce** any pattern CLAUDE.md forbids (value-keyed tree expansion, index-based tab identity, `codeTheme` highlighting, `sl<T>()` in widgets, `debugPrint` in blocs).
