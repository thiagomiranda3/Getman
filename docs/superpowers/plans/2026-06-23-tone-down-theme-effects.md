# Tone Down Theme Effects — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Getman feel professional and calm by removing sounds, status-code reactions, the per-click background ripple, the SEND ritual / in-flight frame, tab + content transitions, and the two effect toggles; tame the button press to one subtle effect — while keeping the autonomous backgrounds, cursor parallax, idle breathing, tree drag/drop juice, and the theme-switch crossfade.

**Architecture:** Surgical removal (Approach 2 in the spec). The effects are wired through two `ThemeExtension`s — `AppMotion` (event hooks: `reactionOverlay`, `sendAffordance`, `inFlightFrame`, `contentTransition`, `tabChipTransition`, plus the kept `tree*` hooks) and `AppDecoration.wrapInteractive` (press). Each removed effect's hook is deleted from the extension, from every theme builder, and from its call site in the same task so the build stays green at each commit. With the loud effects gone, their supporting "reaction spine" (`lib/core/theme/motion/*`) and the audio subsystem become dead code and are deleted. The ambient backgrounds keep their drift ticker, cursor `pointer` parallax, and `WorkspacePulse` `touch()`-based idle breathing.

**Tech Stack:** Flutter (`fvm flutter`), `flutter_bloc`, `get_it`, `hive_ce` (+ `hive_ce_generator`), `provider`. Themes under `lib/core/theme/themes/<name>/`.

## Global Constraints

- **Always invoke Flutter as `fvm flutter ...`**, never plain `flutter`. Dart tools as `fvm dart run ...`.
- **Done-bar (all must pass before any task is "done"):** `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0 issues), `fvm dart run bloc_tools:bloc lint lib` (0 issues), `fvm dart format lib test tools` (clean), `fvm flutter test` (100% green). The three analysis passes are independent.
- **Imports are `package:getman/...` everywhere** (no relative imports).
- **Never reuse a Hive `typeId` or `HiveField` number.** After removing settings fields 22 & 27, the next free `HiveField` is **28**.
- **Never `sl<T>()`/`GetIt` from a widget** (custom_lint `avoid_get_it_in_widgets`); blocs use `dart:developer log`, never `debugPrint`/foundation imports.
- **Commit message trailer (every commit):**
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SRzveT6EFpZWvuWcfeAddS
  ```
- **`reduceEffects` parameter is KEPT** through `resolveThemeData` → theme builders / ambient widgets; only the *setting* that fed it is removed. Hardwire `false` at the single call site (Task 8) so backgrounds stay animated.

---

### Task 1: Response stays visible during re-send

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/response_section.dart:56-58`
- Test: `test/features/tabs/presentation/widgets/response_section_test.dart` (create if absent)

**Interfaces:**
- Consumes: `TabsState.tabs`, `HttpRequestTabEntity { bool isSending; HttpResponseEntity? response; }`, `context.appComponents.pendingIndicator(context)`.
- Produces: no new public symbols — a behavior change only.

- [ ] **Step 1: Write the failing test**

Add to `response_section_test.dart` (use the existing test's harness/helpers if the file exists; otherwise mirror a sibling widget test's `pumpWidget` + theme + `BlocProvider<TabsBloc>` setup). Two cases:

```dart
testWidgets('keeps the previous response visible while re-sending', (tester) async {
  // tab.isSending == true AND tab.response != null (e.g. a 200 body "PREVIOUS")
  await pumpResponseSection(tester, isSending: true, response: okResponse(body: 'PREVIOUS'));
  expect(find.textContaining('PREVIOUS'), findsWidgets); // body still shown
  // The themed pending/skeleton indicator must NOT replace it.
  expect(find.byKey(const ValueKey('response_pending_indicator')), findsNothing);
});

testWidgets('shows the pending indicator while sending with no previous response', (tester) async {
  await pumpResponseSection(tester, isSending: true, response: null);
  expect(find.byKey(const ValueKey('response_pending_indicator')), findsOneWidget);
});
```

If `pendingIndicator` has no stable key, assert on whatever it renders for the default (classic) theme instead (e.g. a `Shimmer`/`CircularProgressIndicator` finder) — inspect `defaultAppComponents().pendingIndicator` first and match its real output.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response_section_test.dart`
Expected: the first test FAILS (previous response is replaced by the pending indicator).

- [ ] **Step 3: Implement the gate**

In `response_section.dart`, replace:

```dart
        if (tab.isSending) {
          return context.appComponents.pendingIndicator(context);
        }

        final response = tab.response;
```

with:

```dart
        final response = tab.response;
        if (tab.isSending && response == null) {
          return context.appComponents.pendingIndicator(context);
        }
```

(Leave the `if (response == null) { ...empty state... }` block and the loaded `Column` below unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response_section_test.dart`
Expected: PASS (both cases).

- [ ] **Step 5: Done-bar + commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`
Expected: all clean/green.

```bash
git add lib/features/tabs/presentation/widgets/response_section.dart test/features/tabs/presentation/widgets/response_section_test.dart
git commit -m "feat(tabs): keep previous response visible during re-send"
```

---

### Task 2: Tame the button press to one subtle effect

**Files:**
- Create: `lib/core/theme/themes/shared/subtle_press.dart`
- Delete: `lib/core/theme/themes/brutalist/brutalist_bounce.dart`
- Modify: each theme's decorations builder that sets `wrapInteractive` — `lib/core/theme/themes/brutalist/brutalist_decorations.dart`, `classic/classic_*` (already `ClassicPress`), `editorial/*`, `dracula/*`, `rpg/rpg_decorations.dart`, `glass/glass_decorations.dart`, `auris/auris_decorations.dart` (search: `grep -rn "wrapInteractive:" lib/core/theme/themes`).
- Test: `test/core/theme/subtle_press_test.dart` (create)

**Interfaces:**
- Consumes: `InteractiveWrapper` typedef from `lib/core/theme/extensions/app_decoration.dart` — `Widget Function({required Widget child, VoidCallback? onTap, double? scaleDown})`.
- Produces: `SubtlePress({required Widget child, VoidCallback? onTap, double? scaleDown, bool animate = true})` — a `StatefulWidget` that on tap-down scales to `scaleDown ?? 0.99` and dims opacity to 0.85 over 120ms, then springs back / fires `onTap` on tap-up. When `animate == false` it is a plain `GestureDetector` (no animation).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/subtle_press_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/shared/subtle_press.dart';

void main() {
  testWidgets('SubtlePress scales to ~0.99 on press, not a 0.95 bounce', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SubtlePress(
            onTap: () => tapped = true,
            child: const SizedBox(width: 50, height: 50, key: ValueKey('press_child')),
          ),
        ),
      ),
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('press_child'))));
    await tester.pump(const Duration(milliseconds: 120));
    final scaleT = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scaleT, closeTo(0.99, 0.001)); // subtle, NOT 0.95
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('animate:false is a plain tap target (no AnimatedScale)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SubtlePress(animate: false, child: SizedBox(width: 10, height: 10)),
    ));
    expect(find.byType(AnimatedScale), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/subtle_press_test.dart`
Expected: FAIL — `subtle_press.dart` does not exist.

- [ ] **Step 3: Create `SubtlePress`**

Copy the body of `lib/core/theme/themes/classic/classic_press.dart` into `lib/core/theme/themes/shared/subtle_press.dart`, renaming `ClassicPress`→`SubtlePress` and `_ClassicPressState`→`_SubtlePressState`. Keep the exact behavior (scale `scaleDown ?? 0.99`, opacity 0.85, 120ms, `animate` flag, `GestureDetector` with `onTapDown/Up/Cancel`). The doc comment should read: `/// Subtle, theme-agnostic press feedback: a quick opacity dim + tiny scale on tap.`

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/subtle_press_test.dart`
Expected: PASS.

- [ ] **Step 5: Point every theme's `wrapInteractive` at `SubtlePress`**

For each theme decorations file, set `wrapInteractive` to:

```dart
wrapInteractive: ({required child, onTap, scaleDown}) => SubtlePress(
  onTap: onTap,
  scaleDown: scaleDown,
  child: child,
),
```

(Import `package:getman/core/theme/themes/shared/subtle_press.dart`.) For **Brutalist**, this replaces the `BrutalBounce(...)` wrapper. For **Classic**, replace `ClassicPress(...)` with `SubtlePress(...)` and delete `classic_press.dart` if nothing else references it (`grep -rn ClassicPress lib test`). Themes that pass `animate: !reduceEffects` should keep doing so: `SubtlePress(animate: !reduceEffects, ...)`.

- [ ] **Step 6: Delete `BrutalBounce`**

```bash
git rm lib/core/theme/themes/brutalist/brutalist_bounce.dart
```
Then `grep -rn "BrutalBounce" lib test` → remove every remaining reference (imports, any direct uses, and `brutalist_bounce_test.dart` if present: `git rm` it).

- [ ] **Step 7: Done-bar (fix what analyze/test name) + commit**

Run the full done-bar. `fvm flutter analyze` will name any unused imports / dangling `BrutalBounce`/`ClassicPress` references — fix each. Update or remove any theme decoration test that asserted the bounce.

```bash
git add -A
git commit -m "refactor(theme): tame button press to a single subtle effect; remove BrutalBounce"
```

---

### Task 3: Remove the per-click background "water ripple"

**Files:**
- Modify: `lib/core/theme/motion/ambient_signals.dart` (drop `AmbientImpulse` + the `impulses` field)
- Modify: `lib/core/theme/themes/brutalist/brutalist_ambient.dart`, `auris/auris_ambient.dart`, `glass/glass_decorations.dart`, `rpg/rpg_decorations.dart`
- Test: the four `*_ambient`/`*_decorations` tests + any `ambient_signals` test

**Interfaces:**
- Consumes: `WorkspacePulseController.touch()`, the `pointer` `ValueListenable<Offset>`, `AmbientSignals { pointer, pulse, isDark }` (after edit).
- Produces: `AmbientSignals` no longer has `impulses`; `AmbientImpulse` no longer exists.

- [ ] **Step 1: Update the failing test first**

In each ambient widget's test (search `grep -rln "debug.*ImpulseCount\|AmbientImpulse\|_addImpulse\|onPointerDown" test/`), replace any "click seeds an impulse / ripple count increments" assertion with the inverse:

```dart
testWidgets('a pointer-down does NOT seed a ripple but still touches the pulse', (tester) async {
  // pump the animated ambient with a provided WorkspacePulseController
  // tap inside the ambient surface
  // assert: no ripple/impulse rendered; pulse.idleFactor was reset (touch called)
});
```

Match the existing test's harness. If the test asserts via a `@visibleForTesting debug*ImpulseCount` counter, delete that counter usage; assert `pulse.debugHasListeners` / idle reset instead.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/` (or the specific ambient test files)
Expected: FAIL — ripples are still seeded.

- [ ] **Step 3: Strip impulses from `AmbientSignals`**

In `ambient_signals.dart`: delete the entire `AmbientImpulse` class and the `impulses` field (+ its doc + constructor param) from `AmbientSignals`. Result:

```dart
@immutable
class AmbientSignals {
  const AmbientSignals({
    required this.pointer,
    required this.pulse,
    required this.isDark,
  });
  final ValueListenable<Offset> pointer;
  final WorkspacePulseController pulse;
  final bool isDark;
}
```

- [ ] **Step 4: Strip impulses from each ambient widget**

In each of the four files:
- Delete the `_impulses` `ValueNotifier<List<AmbientImpulse>>` field, its `.dispose()`, the `_addImpulse` method's impulse-list building, the widget-owned impulse clock, and the `@visibleForTesting debug*ImpulseCount`.
- In `onPointerDown`, keep **only** `_pulse?.touch();` (drop the `_addImpulse(...)` ripple seed). If `onPointerDown` then does nothing but `touch()`, keep the `Listener` for that call.
- In the `AmbientSignals(...)` construction, remove `impulses: _impulses,`.
- In the painter: delete the `for (final imp in signals?.impulses...)` ripple-drawing loop and any impulse-only fields. Remove `impulses` from the painter's `repaint:` `Listenable.merge([...])`.
- Keep the drift `AnimationController`, the `pointer`/`MouseRegion` parallax, and the pulse merge.

- [ ] **Step 5: Run tests to verify they pass**

Run: `fvm flutter test test/core/theme/themes/`
Expected: PASS (no ripple; touch still fires; drift still animates).

- [ ] **Step 6: Done-bar + commit**

Run the full done-bar; fix any unused imports (`AmbientImpulse`) analyze names.

```bash
git add -A
git commit -m "refactor(theme): remove per-click background ripple; keep drift + parallax + idle breathing"
```

---

### Task 4: Remove `sendAffordance` + `inFlightFrame`

**Files:**
- Modify: `lib/core/theme/extensions/app_motion.dart` (drop the two typedefs, fields, identity fns, copyWith params)
- Modify: `lib/core/theme/themes/{brutalist,rpg,glass,auris}/*_motion.dart` (drop the two hooks + their private widgets/painters)
- Modify: `lib/features/tabs/presentation/widgets/url_bar.dart:346-348` (sendAffordance call site)
- Modify: `lib/features/tabs/presentation/screens/request_view.dart:254-256` (inFlightFrame call site)
- Test: the four `*_motion_test.dart`; `url_bar`/`request_view` tests

**Interfaces:**
- Consumes: `AppMotion` (post-edit, without `sendAffordance`/`inFlightFrame`).
- Produces: `AppMotion` with 6 hooks (`reactionOverlay`, `contentTransition`, `tabChipTransition`, `treeDragFeedback`, `treeDropHighlight`, `treeExpandFlourish`).

- [ ] **Step 1: Update tests first**

In each `*_motion_test.dart`, delete tests that assert the send ritual / in-flight frame render. Add (or keep) a test that the SEND button still shows its spinner when `isSending` — that belongs in `url_bar` test; verify/add:

```dart
testWidgets('SEND button shows a CircularProgressIndicator while sending', (tester) async {
  // pump UrlBar with a tab whose isSending == true
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
});
```

- [ ] **Step 2: Run to verify failure/baseline**

Run: `fvm flutter test test/core/theme/` — expect failures only in the assertions you just inverted/removed (or compile errors once Step 3 starts). Confirm the new `url_bar` spinner test passes against current code (it should — the spinner is independent of `sendAffordance`).

- [ ] **Step 3: Remove the call sites**

In `url_bar.dart`, replace:

```dart
                          if (tab.config.kind == RequestKind.http)
                            context.appMotion.sendAffordance(
                              context,
                              isSending: tab.isSending,
                              child: context.appDecoration.wrapInteractive(
                                child: ElevatedButton( ... ),
                              ),
                            ),
```
with the inner widget directly:
```dart
                          if (tab.config.kind == RequestKind.http)
                            context.appDecoration.wrapInteractive(
                              child: ElevatedButton( ... ),
                            ),
```

In `request_view.dart`, replace the `context.appMotion.inFlightFrame(context, isSending: isSending, child: <X>)` wrapper with `<X>` directly (the `BlocSelector<…, bool>` that computed `isSending` solely for the frame can be collapsed to its `child` builder; if `isSending` is no longer referenced, remove the now-unused selector).

- [ ] **Step 4: Remove the hooks from `AppMotion` and the theme builders**

In `app_motion.dart`: delete `SendAffordanceBuilder`, `InFlightFrameBuilder`, `_identitySendAffordance`, `_identityInFlightFrame`, the `sendAffordance`/`inFlightFrame` fields, constructor defaults, and copyWith params.

In each `{brutalist,rpg,glass,auris}_motion.dart`: remove the `sendAffordance:` and `inFlightFrame:` entries from the `AppMotion(...)` return, and delete the private classes they referenced (e.g. brutalist `_BrutalStampSend`, `_MarchingBarPainter`, `_BrutalistInFlightFrame`, `_BrutalistMarchingFramePainter`; the analogous `_*Send*`/`_*InFlightFrame*` classes in the other three).

- [ ] **Step 5: Run done-bar; fix compiler/analyze output**

Run: `fvm flutter analyze` — it will name unused imports (`inFlightTension`, etc. stay if `reactionOverlay` still uses them) and any leftover references. Fix each. Then `fvm flutter test`.
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(theme): remove SEND ritual and in-flight panel frame"
```

---

### Task 5: Remove `contentTransition` + `tabChipTransition`

**Files:**
- Modify: `lib/core/theme/extensions/app_motion.dart`
- Modify: `lib/core/theme/themes/{brutalist,rpg,glass,auris}/*_motion.dart`
- Modify: `lib/features/home/presentation/widgets/tab_content_stack.dart:209,242-245`
- Modify: `lib/features/home/presentation/screens/main_screen.dart` (`_ChipEntrance`)
- Test: the four `*_motion_test.dart`; `tab_content_stack`/`main_screen` tests

**Interfaces:**
- Consumes: `AppMotion` (post-edit).
- Produces: `AppMotion` with 4 hooks (`reactionOverlay` + the three `tree*`).

- [ ] **Step 1: Update tests first**

Delete `*_motion_test.dart` assertions for the content transition / chip entrance. Add a `tab_content_stack` test that switching the active tab swaps content **immediately** (no transition overlay):

```dart
testWidgets('switching tabs swaps content with no transition overlay', (tester) async {
  // pump TabContentStack, switch active tab id, pump one frame
  expect(find.byKey(const ValueKey('content_transition_overlay')), findsNothing);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/home/` — expect the new test to FAIL against current code (overlay present mid-transition).

- [ ] **Step 3: Remove the `contentTransition` call site**

In `tab_content_stack.dart`, replace:

```dart
    return context.appMotion.contentTransition(
      context,
      transitionKey: transitionKey,
      child: <X>,
    );
```
with `return <X>;` and delete the now-unused `final transitionKey = '$panelId/$activeId';` line.

- [ ] **Step 4: Simplify `_ChipEntrance` to a keyed pass-through**

In `main_screen.dart`, `_ChipEntrance` must remain (it carries the chip's `ValueKey` that `ReorderableListView` requires) but drop the animation. Replace its `State` body so `build` returns `widget.child` and remove the `AnimationController`. Simplest — convert to a `StatelessWidget`:

```dart
/// Keyed pass-through for a tab chip. The [key] MUST be the chip's ValueKey so
/// ReorderableListView preserves per-tab identity (its direct children need keys).
class _ChipEntrance extends StatelessWidget {
  const _ChipEntrance({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
```

(Leave the `_ChipEntrance(key: ValueKey(...), child: ...)` call site unchanged.)

- [ ] **Step 5: Remove the hooks from `AppMotion` and theme builders**

In `app_motion.dart`: delete `ContentTransitionBuilder`, `TabChipTransitionBuilder`, `_identityContentTransition`, `_identityTabChipTransition`, the two fields, defaults, and copyWith params.

In each `{brutalist,rpg,glass,auris}_motion.dart`: remove the `contentTransition:` and `tabChipTransition:` entries and delete their private classes/builders (e.g. brutalist `_BrutalistContentTransition`, `_BrutalistSlamPainter`, `_brutalistChipEntrance`; analogues in the others).

- [ ] **Step 6: Done-bar + commit**

Run the full done-bar; fix anything analyze names.

```bash
git add -A
git commit -m "refactor(theme): remove request-viewer and tab open/close transitions"
```

---

### Task 6: Remove status-code reactions + the whole reaction spine

**Files:**
- Modify: `lib/core/theme/extensions/app_motion.dart` (drop `reactionOverlay`)
- Modify: `lib/core/theme/themes/{brutalist,rpg,glass,auris}_motion.dart` + `lib/core/theme/themes/shared/calm_motion.dart`
- Delete: `lib/core/theme/motion/theme_reaction_controller.dart`, `reaction_stage.dart`, `status_reaction_flavor.dart`, `latency_weight.dart`, `photosensitivity.dart`, `theme_reaction.dart`
- Delete: `lib/features/home/presentation/widgets/theme_reaction_listener.dart`
- Modify: `lib/features/home/presentation/screens/main_screen.dart:353` (unwrap `ThemeReactionListener`)
- Modify: `lib/main.dart:199-201,287-290` (drop the `ThemeReactionController` provider + the `reactionOverlay` wrap)
- Modify: `lib/core/di/injection_container.dart:257` (drop `ThemeReactionController` registration)
- Modify: `lib/features/tabs/presentation/bloc/tabs_bloc.dart` (drop `_fireReaction`, `_transportFailureFor`, the 5 call sites, `_reactionSeq`) + `tabs_state.dart` (drop `lastReaction`, `reactionSeq`)
- Delete tests: `theme_reaction_listener_test.dart`, reaction-spine unit tests
- Test: `tabs_bloc`/`tabs_state` tests (drop reaction assertions)

**Interfaces:**
- Consumes: nothing new.
- Produces: `AppMotion` with only the three `tree*` hooks; `WorkspacePulseController` survives (now driven solely by ambient `touch()`); `TabsState` no longer exposes `reactionSeq`/`lastReaction`.

- [ ] **Step 1: Update/delete tests first**

- `git rm` reaction-spine unit tests: `grep -rln "status_reaction_flavor\|latency_weight\|photosensitivity\|reaction_stage\|theme_reaction_controller\|ThemeReaction\b" test/` → for files dedicated to those, remove them; for shared files, delete only the relevant cases.
- `git rm test/features/home/theme_reaction_listener_test.dart` and `test/features/home/theme_reaction_sound_test.dart`.
- In `tabs_bloc`/`tabs_state` tests, remove assertions on `reactionSeq`/`lastReaction`.

- [ ] **Step 2: Remove the bloc reaction plumbing**

In `tabs_bloc.dart`: delete `_reactionSeq`, `_fireReaction(...)`, `_transportFailureFor(...)`, and all 5 `_fireReaction(...)` call sites (sendStarted, success-terminal, cancelled, error-terminal, networkError). Remove the `ThemeReaction` import. In `tabs_state.dart`: delete `lastReaction` + `reactionSeq` fields, their constructor params, `props` entries, and copyWith handling.

- [ ] **Step 3: Unwrap the listener and providers**

- `main_screen.dart`: replace `ThemeReactionListener(child: <X>)` with `<X>`.
- `main.dart`: delete the `ChangeNotifierProvider<ThemeReactionController>.value(...)` entry, and replace the `context.appMotion.reactionOverlay(context, controller: context.read<ThemeReactionController>(), child: <Y>)` wrap with `<Y>` directly (keep the `context.appDecoration.scaffoldBackground(...)` inside).
- `injection_container.dart`: delete the `..registerLazySingleton(ThemeReactionController.new)` line (keep `WorkspacePulseController`).

- [ ] **Step 4: Remove `reactionOverlay` from `AppMotion` and the builders**

In `app_motion.dart`: delete `ReactionOverlayBuilder`, `_identityReactionOverlay`, the `reactionOverlay` field/default/copyWith param, and the now-unused `import '.../theme_reaction_controller.dart'`.

In each `{brutalist,rpg,glass,auris}_motion.dart`: remove the `reactionOverlay:` entry and delete its private classes (e.g. brutalist `_BrutalReactionOverlay`, `_StampLabel`, `_BarrierStamp`, `StampSpec`, `stampSpecFor`; analogues + sparkle/shower painters in rpg, etc.). Each builder now returns only the three `tree*` hooks (keep the `if (reduceEffects) return const AppMotion();` guard).

For `calm_motion.dart`: it sets **only** `reactionOverlay`, so `calmMotion` now returns `const AppMotion()` for both branches. Delete `_CalmReactionOverlay`, `CalmSpec`, `calmSpecFor`, and all reaction-spine imports. Result:

```dart
import 'package:getman/core/theme/extensions/app_motion.dart';

/// Calm themes ship no event-driven motion.
AppMotion calmMotion({required bool reduceEffects}) => const AppMotion();
```

- [ ] **Step 5: Delete the orphaned spine files**

```bash
git rm lib/core/theme/motion/theme_reaction_controller.dart \
       lib/core/theme/motion/reaction_stage.dart \
       lib/core/theme/motion/status_reaction_flavor.dart \
       lib/core/theme/motion/latency_weight.dart \
       lib/core/theme/motion/photosensitivity.dart \
       lib/core/theme/motion/theme_reaction.dart
```
Then `grep -rn "theme_reaction\|ReactionStage\|flavorFor\|StatusReactionFlavor\|latencyWeight\|inFlightTension\|safeFlashCount\|ThemeReactionController" lib test` → there must be **zero** remaining references. Fix any stragglers.

- [ ] **Step 6: Done-bar + commit**

Run the full done-bar (this is the largest task — analyze + bloc_lint + tests are the net).

```bash
git add -A
git commit -m "refactor(theme): remove status-code reactions and the reaction spine"
```

---

### Task 7: Remove the sound subsystem

**Files:**
- Delete: `lib/core/audio/theme_sound_service.dart`, `lib/core/audio/theme_sound_service_audioplayers.dart` (the `audio/` dir)
- Modify: `pubspec.yaml` (drop `audioplayers` dep + `assets/sounds/` declaration)
- Delete: `assets/sounds/` (if present)
- Modify: `lib/core/di/injection_container.dart:261` (drop `ThemeSoundService` registration)
- Modify: `lib/main.dart:196-198` (drop the `RepositoryProvider<ThemeSoundService>`)
- Test: `git rm` any sound-service test

**Interfaces:**
- Consumes: nothing (the only runtime caller, `ThemeReactionListener`, was removed in Task 6).
- Produces: no audio in the app.

- [ ] **Step 1: Confirm no remaining callers**

Run: `grep -rn "ThemeSoundService\|createThemeSoundService\|audioplayers\|AssetSource\|theme_sound" lib test`
Expected: only the DI registration, the `main.dart` provider, the two `audio/` files, and pubspec — no `.play(...)` callers (Task 6 removed the listener).

- [ ] **Step 2: Remove wiring**

- `injection_container.dart`: delete `..registerLazySingleton<ThemeSoundService>(createThemeSoundService)` and its import.
- `main.dart`: delete the `RepositoryProvider<ThemeSoundService>.value(value: di.sl<ThemeSoundService>())` entry and its import.

- [ ] **Step 3: Delete the files + dependency + assets**

```bash
git rm lib/core/audio/theme_sound_service.dart lib/core/audio/theme_sound_service_audioplayers.dart
```
- `pubspec.yaml`: remove the `audioplayers: ...` line under `dependencies:`, and remove the `- assets/sounds/` entry under `flutter: assets:`.
- If `assets/sounds/` exists: `git rm -r assets/sounds`.
- `git rm` any `test/**/theme_sound*_test.dart` not already removed in Task 6.

- [ ] **Step 4: Refresh packages + done-bar**

Run: `fvm flutter pub get` then the full done-bar.
Expected: `fvm flutter analyze` clean (no `audioplayers` import anywhere), tests green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(audio): remove theme sound subsystem and audioplayers dependency"
```

---

### Task 8: Remove the two settings (sounds + reduce-visual-effects)

**Files:**
- Modify: `lib/features/settings/domain/entities/settings_entity.dart` (drop `reduceVisualEffects`, `enableThemeSounds`)
- Modify: `lib/features/settings/data/models/settings_model.dart` (drop `@HiveField(22)`, `@HiveField(27)`; update `fromJson`/`toJson`/`copyWith`/`toEntity`/`fromEntity`)
- Regenerate: `lib/features/settings/data/models/settings_model.g.dart`
- Modify: `lib/features/settings/presentation/bloc/settings_event.dart` (drop `UpdateReduceVisualEffects`, `UpdateEnableThemeSounds`)
- Modify: `lib/features/settings/presentation/bloc/settings_bloc.dart` (drop both handlers)
- Modify: `lib/features/settings/presentation/widgets/settings_dialog.dart:289-302` (drop both toggle rows)
- Modify: `lib/main.dart` (resolveThemeData call site — hardwire `reduceEffects: false`)
- Test: settings bloc/model/dialog tests

**Interfaces:**
- Consumes: `resolveThemeData(themeId, brightness, {bool isCompact, bool reduceEffects})` — now called with `reduceEffects: false`.
- Produces: `SettingsEntity`/`SettingsModel` without the two fields; no `Update*` events for them.

- [ ] **Step 1: Update tests first**

In settings bloc/model/dialog tests, remove cases for `UpdateReduceVisualEffects`, `UpdateEnableThemeSounds`, and any `reduceVisualEffects`/`enableThemeSounds` round-trip assertions. Add a dialog test asserting **neither** toggle is present:

```dart
testWidgets('settings dialog has no THEME SOUNDS or REDUCE VISUAL EFFECTS toggles', (tester) async {
  // pump SettingsDialog (APPEARANCE/GENERAL tab where they lived)
  expect(find.text('THEME SOUNDS'), findsNothing);
  expect(find.text('REDUCE VISUAL EFFECTS'), findsNothing);
  expect(find.byKey(const ValueKey('theme_sounds_switch')), findsNothing);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/settings/`
Expected: the new dialog test FAILS (toggles still present).

- [ ] **Step 3: Remove from entity + model**

- `settings_entity.dart`: delete both `final bool` fields, their constructor defaults, `copyWith` params + body lines, and `props` entries.
- `settings_model.dart`: delete the `@HiveField(22) reduceVisualEffects` and `@HiveField(27) enableThemeSounds` declarations, their constructor params, and their lines in `fromJson`, `toJson`, `copyWith`, `toEntity`, `fromEntity`. **Do not renumber any other field.**

- [ ] **Step 4: Regenerate Hive adapter**

Run: `fvm dart run build_runner build --delete-conflicting-outputs`
Expected: `settings_model.g.dart` regenerated; the two fields no longer read/written. Confirm with `grep -n "reduceVisualEffects\|enableThemeSounds" lib/features/settings/data/models/settings_model.g.dart` → no matches.

- [ ] **Step 5: Remove events, handlers, toggles; hardwire reduceEffects**

- `settings_event.dart`: delete `UpdateReduceVisualEffects` and `UpdateEnableThemeSounds`.
- `settings_bloc.dart`: delete the `on<UpdateReduceVisualEffects>(...)` and `on<UpdateEnableThemeSounds>(...)` registrations/handlers.
- `settings_dialog.dart`: delete both toggle rows (the `REDUCE VISUAL EFFECTS` row and the `THEME SOUNDS` row, lines ~289-302).
- `main.dart`: in both `resolveThemeData(...)` calls (light + dark), replace `reduceEffects: settings.reduceVisualEffects` with `reduceEffects: false`. If the root `BlocBuilder<SettingsBloc>` `buildWhen` references `reduceVisualEffects`, remove that clause.

- [ ] **Step 6: Done-bar + commit**

Run the full done-bar (incl. build_runner output committed).

```bash
git add -A
git commit -m "feat(settings): remove THEME SOUNDS and REDUCE VISUAL EFFECTS toggles"
```

---

### Task 9: Documentation + wiki sync

**Files:**
- Modify: `CLAUDE.md` (§1 stack: drop `audioplayers`; §3 settings HiveField table: drop 22 & 27, set next-free **28**; §2/§4.8 motion + audio notes)
- Modify: `docs/THEME_AUTHORING.md` (remove the reactive-motion / sound / photosensitivity checklist sections that no longer apply; document the surviving hooks: `tree*` + ambient + theme-switch + subtle press)
- Modify: the `Getman.wiki.git` repo — Settings page + Themes/motion page
- Test: none (docs)

**Interfaces:** none.

- [ ] **Step 1: Update `CLAUDE.md`**

Edit the relevant sections to match the code now: remove the `audioplayers` mention and the `enableThemeSounds`/`reduceVisualEffects` HiveField rows (note "removed — do not reuse 22/27; next free 28"); update §4.8's "AppMotion 7th extension" description to list only the surviving hooks (`treeDragFeedback`/`treeDropHighlight`/`treeExpandFlourish`) + ambient + theme-switch; remove the `ThemeReaction` spine / `flavorFor` / photosensitivity references; note the press is now a single shared `SubtlePress`.

- [ ] **Step 2: Update `docs/THEME_AUTHORING.md`**

Remove §5b (photosensitivity flash cap) and the reactive-motion checklist items for `reactionOverlay`/`sendAffordance`/`inFlightFrame`/`contentTransition`/`tabChipTransition`/sound. Keep the ambient `scaffoldBackground`, theme-switch transition, tree-juice hooks, and `wrapInteractive` (now `SubtlePress`).

- [ ] **Step 3: Sync the wiki**

```bash
cd "$(mktemp -d)" && git clone https://github.com/thiagomiranda3/Getman.wiki.git && cd Getman.wiki
```
Edit the **Settings** page: remove "Theme sounds" and "Reduce visual effects" entries. Edit the **Themes** (or motion) page: state that status-code reactions, the per-click ripple, the SEND ritual, in-flight frame, and tab/content transitions were removed for a calmer feel; backgrounds (moving stars, glass blur), cursor parallax, tree drag/drop juice, and the theme-switch crossfade remain; sounds were removed entirely. Keep UI labels verbatim.

```bash
git add -A && git commit -m "Sync: tone down theme effects (sounds + reactions removed, calmer motion)" && git push origin master
```

- [ ] **Step 4: Commit the in-repo docs**

```bash
git add CLAUDE.md docs/THEME_AUTHORING.md
git commit -m "docs: sync CLAUDE.md + THEME_AUTHORING for toned-down effects"
```

---

## Self-Review

**Spec coverage:**
- Sounds removal → Tasks 7 + 8 (field/toggle) + 6 (play call via listener). ✓
- Status reactions + spine → Task 6. ✓
- Click ripple → Task 3. ✓
- SEND ritual + in-flight frame → Task 4 (+ Task 1 keeps response visible). ✓
- Tab/content transitions → Task 5. ✓
- Button press taming → Task 2. ✓
- REDUCE VISUAL EFFECTS removal + hardwired `reduceEffects:false` → Task 8. ✓
- Response-visible-during-resend → Task 1. ✓
- Kept items (backgrounds, parallax, idle breathing, tree juice, theme-switch, spinner) → preserved by construction (Tasks 3/6 keep `touch()`/drift/`WorkspacePulse`; no task touches tree-juice hooks or `ThemeSwitchTransition`). ✓
- Hive bookkeeping (no reuse of 22/27; next free 28) → Task 8 + Task 9. ✓
- Wiki + CLAUDE.md + THEME_AUTHORING → Task 9. ✓

**Placeholder scan:** Deletion steps direct the implementer to grep for references and let `analyze`/`test` name leftovers — this is concrete (the failing build is the spec for a removal), not a TODO. Behavioral steps include full code. No "TBD"/"handle edge cases"/"similar to Task N". ✓

**Type consistency:** `SubtlePress({child, onTap, scaleDown, animate})` is defined in Task 2 and consumed by the `InteractiveWrapper` typedef (`{child, onTap, scaleDown}`) — matches. `AppMotion` hook set shrinks consistently across Tasks 4→5→6 (8→6→4→3). `AmbientSignals {pointer, pulse, isDark}` (Task 3) matches its consumers. `resolveThemeData(..., reduceEffects:)` kept and called with `false` (Task 8). ✓
