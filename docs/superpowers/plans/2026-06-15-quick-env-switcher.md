# Quick Environment Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user a fast, keyboard-driven way to switch the active environment without leaving the keyboard or opening the full Cmd/Ctrl+K command palette. A new shortcut (**Cmd/Ctrl+E**) opens a minimal modal overlay: an arrow-navigable list of `No Environment` + every saved environment, with the currently-active one marked and pre-highlighted. Up/Down moves the highlight, **Enter** selects (dispatches the switch + closes), **Esc** dismisses without changing anything.

**Architecture:** A new `QuickEnvSwitcher` modal widget — a focused, environments-only sibling of `CommandPalette`. It deliberately mirrors `CommandPalette`'s skeleton (`show()` reads both blocs at open time and snapshots state into the widget; `Shortcuts` → `Actions` with private `_MoveSelectionIntent`/`_RunSelectionIntent`; `ResponsiveDialogScaffold` chrome). A new `SwitchEnvironmentIntent` + Cmd/Ctrl+E activators in `appShortcuts`, with the `Action` wired at the **root** in `main.dart` beside `CommandPaletteIntent` (both required blocs are root-provided). No new bloc, no `data/`, no use case, no new domain entity — the switcher reads `EnvironmentsBloc.state.environments` (the list) and the active id from `SettingsBloc.state.settings.activeEnvironmentId`, and dispatches the existing `UpdateActiveEnvironmentId(id)` (nullable; `null` = No Environment). Two-bloc coordination happens at the widget layer (never bloc→bloc), following `EnvironmentsDialog._deleteEnvironment`.

**Tech Stack:** Flutter (`fvm flutter`), `flutter_bloc`, `equatable`, `flutter_test`, `mocktail` (mock blocs, matching `command_palette_test.dart`). No new dependencies.

**Theming note (verified):** `AppLayout` is NOT built per-theme. All four theme builders (`brutalist`, `editorial`, `rpg`, `dracula`) reference the shared `static const AppLayout.normal` / `AppLayout.compact` in `lib/core/theme/extensions/app_layout.dart` (e.g. `final layout = isCompact ? AppLayout.compact : AppLayout.normal;`). Therefore a new `AppLayout` field is added in exactly ONE file (`app_layout.dart`: constructor param + field + `copyWith` + `lerp` + both consts) — NOT in each theme builder. The overlay width reuses the existing `dialogWidth` (400 / 320); the list cap needs a new field `quickListMaxHeight` because no existing field fits.

---

## File Structure

**Create:**
- `lib/features/environments/presentation/widgets/quick_env_switcher.dart` — `QuickEnvSwitcher` (`show()` + state + private `_EnvRow`, `_MoveSelectionIntent`, `_RunSelectionIntent`).
- `test/features/environments/presentation/widgets/quick_env_switcher_test.dart` — widget test (open / navigate / select / dispatch / tap parity / empty list).

**Modify:**
- `lib/core/theme/extensions/app_layout.dart` — add `quickListMaxHeight` field (constructor, field, `copyWith`, `lerp`, `normal`, `compact`).
- `lib/core/navigation/intents.dart` — add `SwitchEnvironmentIntent`.
- `lib/main.dart` — add the two Cmd/Ctrl+E activators to `appShortcuts`; add the root `SwitchEnvironmentIntent` action calling `QuickEnvSwitcher.show`.
- `test/main_shortcuts_test.dart` — add a Cmd+E / Ctrl+E → `SwitchEnvironmentIntent` map assertion.

**Wiki (Task 5):** `Getman.wiki.git` — keyboard-shortcuts page + Environments page.

---

### Task 1: Add `quickListMaxHeight` to `AppLayout`

The overlay's scrollable row list needs a themed max height (the palette hardcodes `360`; new code must read it from the theme). No existing `AppLayout` field caps a list height, so add one. This is a single-file change because every theme builder shares the `AppLayout.normal` / `AppLayout.compact` consts.

**Files:**
- Modify: `lib/core/theme/extensions/app_layout.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_layout_quick_list_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_layout.dart';

void main() {
  group('AppLayout.quickListMaxHeight', () {
    test('normal exposes a positive list cap', () {
      expect(AppLayout.normal.quickListMaxHeight, greaterThan(0));
    });

    test('compact is no taller than normal', () {
      expect(
        AppLayout.compact.quickListMaxHeight,
        lessThanOrEqualTo(AppLayout.normal.quickListMaxHeight),
      );
    });

    test('copyWith overrides the cap', () {
      final layout = AppLayout.normal.copyWith(quickListMaxHeight: 123);
      expect(layout.quickListMaxHeight, 123);
    });

    test('lerp moves the cap toward the target', () {
      final a = AppLayout.normal.copyWith(quickListMaxHeight: 100);
      final b = AppLayout.normal.copyWith(quickListMaxHeight: 200);
      final mid = a.lerp(b, 0.5);
      expect(mid.quickListMaxHeight, 150);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/app_layout_quick_list_test.dart`
Expected: FAIL — `The getter 'quickListMaxHeight' isn't defined for the type 'AppLayout'`.

- [ ] **Step 3: Add the field**

In `lib/core/theme/extensions/app_layout.dart`:

Add the constructor parameter (place it after `required this.foldGutterWidth,` inside the `const AppLayout({...})` constructor):

```dart
    required this.quickListMaxHeight,
```

Add the field declaration (after the `foldGutterWidth` field + its doc comment, near the bottom of the field block):

```dart
  /// Max height of the scrollable row list in compact overlays such as the
  /// quick environment switcher — caps the list so the modal stays bounded.
  final double quickListMaxHeight;
```

Add the `copyWith` parameter (after `double? foldGutterWidth,`):

```dart
    double? quickListMaxHeight,
```

Add it to the `copyWith` return (after `foldGutterWidth: foldGutterWidth ?? this.foldGutterWidth,`):

```dart
      quickListMaxHeight: quickListMaxHeight ?? this.quickListMaxHeight,
```

Add it to `lerp` (after `foldGutterWidth: l(foldGutterWidth, other.foldGutterWidth),`):

```dart
      quickListMaxHeight: l(quickListMaxHeight, other.quickListMaxHeight),
```

Add it to `static const normal` (after `foldGutterWidth: 20,`):

```dart
    quickListMaxHeight: 360,
```

Add it to `static const compact` (after `foldGutterWidth: 16,`):

```dart
    quickListMaxHeight: 280,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/app_layout_quick_list_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Confirm no theme builder regressed**

Run: `fvm flutter analyze lib/core/theme`
Expected: No issues found — the four theme builders consume `AppLayout.normal`/`.compact`, which now carry the new field with no edit required.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/extensions/app_layout.dart test/core/theme/app_layout_quick_list_test.dart
git commit -m "feat(theme): AppLayout.quickListMaxHeight for compact overlays

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The `QuickEnvSwitcher` widget (+ widget test)

Build the overlay: a `ResponsiveDialogScaffold` over an arrow-navigable list of `No Environment` + every saved environment, mirroring `CommandPalette`'s `Shortcuts`/`Actions`/`_Move`/`_Run` pattern. Read blocs at open time via `show()`; dispatch `UpdateActiveEnvironmentId` on the held `SettingsBloc`.

**Files:**
- Create: `lib/features/environments/presentation/widgets/quick_env_switcher.dart`
- Test: `test/features/environments/presentation/widgets/quick_env_switcher_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/features/environments/presentation/widgets/quick_env_switcher_test.dart`. This copies the `command_palette_test.dart` harness (mocktail-mocked `SettingsBloc`, brutalist theme, pump inside a `Scaffold`). The widget takes a snapshot `environments` list + `activeId` directly, so no `EnvironmentsBloc` is needed for the list — only a mock `SettingsBloc` to verify the dispatched event.

```dart
// Widget tests for QuickEnvSwitcher: lists No Environment + every env, marks +
// pre-highlights the active row, navigates with arrows, selects with Enter/tap,
// and dispatches UpdateActiveEnvironmentId on the held SettingsBloc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/widgets/quick_env_switcher.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:mocktail/mocktail.dart';

class MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  late MockSettingsBloc settings;

  final envs = [
    EnvironmentEntity(id: 'e1', name: 'Production'),
    EnvironmentEntity(id: 'e2', name: 'Staging'),
  ];

  setUpAll(() {
    registerFallbackValue(const UpdateActiveEnvironmentId(null));
  });

  setUp(() {
    settings = MockSettingsBloc();
    when(() => settings.add(any())).thenReturn(null);
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<EnvironmentEntity> environments,
    required String? activeId,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: QuickEnvSwitcher(
            environments: environments,
            activeId: activeId,
            settingsBloc: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists No Environment plus every environment', (tester) async {
    await pump(tester, environments: envs, activeId: 'e1');
    expect(find.text('No Environment'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
    expect(find.text('SWITCH ENVIRONMENT'), findsOneWidget);
  });

  testWidgets('active row shows the check marker', (tester) async {
    await pump(tester, environments: envs, activeId: 'e2');
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('Enter on open selects the pre-highlighted active row', (
    tester,
  ) async {
    // Active is e2 (Staging) → it opens pre-highlighted, so a bare Enter
    // re-selects e2 and pops.
    await pump(tester, environments: envs, activeId: 'e2');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            'e2',
          ),
        ),
      ),
    ).called(1);
    expect(find.byType(QuickEnvSwitcher), findsNothing);
  });

  testWidgets('ArrowUp from the active row reaches No Environment (null)', (
    tester,
  ) async {
    // Rows: [No Environment, Production(e1), Staging(e2)]. Active e1 opens at
    // index 1; one ArrowUp moves to No Environment; Enter dispatches null.
    await pump(tester, environments: envs, activeId: 'e1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            null,
          ),
        ),
      ),
    ).called(1);
    expect(find.byType(QuickEnvSwitcher), findsNothing);
  });

  testWidgets('ArrowDown then Enter selects the next environment', (
    tester,
  ) async {
    // Active e1 opens at index 1 (Production); ArrowDown → index 2 (Staging,
    // e2); Enter dispatches e2.
    await pump(tester, environments: envs, activeId: 'e1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            'e2',
          ),
        ),
      ),
    ).called(1);
  });

  testWidgets('tapping a row dispatches the same event as Enter on it', (
    tester,
  ) async {
    await pump(tester, environments: envs, activeId: null);
    await tester.tap(find.text('Staging'));
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            'e2',
          ),
        ),
      ),
    ).called(1);
    expect(find.byType(QuickEnvSwitcher), findsNothing);
  });

  testWidgets('no saved environments still renders just No Environment', (
    tester,
  ) async {
    await pump(tester, environments: const [], activeId: null);
    expect(find.text('No Environment'), findsOneWidget);
    expect(find.text('Production'), findsNothing);
    await tester.tap(find.text('No Environment'));
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            null,
          ),
        ),
      ),
    ).called(1);
  });

  testWidgets('stale active id falls back to No Environment highlight', (
    tester,
  ) async {
    // activeId points at a deleted env → no row matches → highlight falls back
    // to index 0 (No Environment). Enter dispatches null.
    await pump(tester, environments: envs, activeId: 'gone');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            null,
          ),
        ),
      ),
    ).called(1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/environments/presentation/widgets/quick_env_switcher_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:getman/features/environments/presentation/widgets/quick_env_switcher.dart'`.

- [ ] **Step 3: Write the widget**

Create `lib/features/environments/presentation/widgets/quick_env_switcher.dart`. The imports mirror `command_palette.dart`. Note `package:getman/core/theme/app_theme.dart` is the barrel that exports the `context.appLayout` / `context.appPalette` / `context.appTypography` accessors (it re-exports `extensions/app_theme_access.dart`); `package:getman/core/theme/responsive.dart` provides `context.isDialogFullscreen`.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';

/// Cmd/Ctrl+E quick switcher: an arrow-navigable list of `No Environment` plus
/// every saved environment. A smaller sibling of [CommandPalette] scoped to
/// environments only, with no text search. Reads both blocs at open time
/// (passed in by [show]) and dispatches the existing [UpdateActiveEnvironmentId]
/// event — no new bloc.
class QuickEnvSwitcher extends StatefulWidget {
  const QuickEnvSwitcher({
    required this.environments,
    required this.activeId,
    required this.settingsBloc,
    super.key,
  });

  /// Snapshot of the env list read at open time.
  final List<EnvironmentEntity> environments;

  /// Active environment id at open time; null == No Environment.
  final String? activeId;

  /// Held so the widget can dispatch the switch itself, mirroring how
  /// [CommandPalette] holds [SettingsBloc].
  final SettingsBloc settingsBloc;

  static Future<void> show(BuildContext context) {
    final envState = context.read<EnvironmentsBloc>().state;
    final settingsBloc = context.read<SettingsBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) => QuickEnvSwitcher(
        environments: envState.environments,
        activeId: settingsBloc.state.settings.activeEnvironmentId,
        settingsBloc: settingsBloc,
      ),
    );
  }

  @override
  State<QuickEnvSwitcher> createState() => _QuickEnvSwitcherState();
}

class _QuickEnvSwitcherState extends State<QuickEnvSwitcher> {
  late final List<_EnvRow> _rows = _buildRows();
  // Index of the keyboard-highlighted row; opens on the active row so a stray
  // Enter is a harmless re-select.
  late final ValueNotifier<int> _selected = ValueNotifier<int>(
    _rows.indexWhere((r) => r.isActive).clamp(0, _rows.length - 1),
  );

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  List<_EnvRow> _buildRows() {
    return [
      _EnvRow(
        label: 'No Environment',
        envId: null,
        isActive: widget.activeId == null,
      ),
      for (final env in widget.environments)
        _EnvRow(
          label: env.name,
          envId: env.id,
          isActive: env.id == widget.activeId,
        ),
    ];
  }

  void _moveSelection(int delta) {
    _selected.value = (_selected.value + delta).clamp(0, _rows.length - 1);
  }

  void _runSelected() => _invoke(_selected.value.clamp(0, _rows.length - 1));

  void _invoke(int index) {
    final row = _rows[index.clamp(0, _rows.length - 1)];
    widget.settingsBloc.add(UpdateActiveEnvironmentId(row.envId));
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    // There is no text field competing for arrow/Enter, so an autofocused
    // Focus wrapper makes the Shortcuts resolve immediately on open.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveSelectionIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveSelectionIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): _RunSelectionIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _RunSelectionIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveSelectionIntent: CallbackAction<_MoveSelectionIntent>(
            onInvoke: (i) {
              _moveSelection(i.delta);
              return null;
            },
          ),
          _RunSelectionIntent: CallbackAction<_RunSelectionIntent>(
            onInvoke: (_) {
              _runSelected();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: _buildScaffold(context)),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final layout = context.appLayout;
    return ResponsiveDialogScaffold(
      title: const Text('SWITCH ENVIRONMENT'),
      content: SizedBox(
        width: context.isDialogFullscreen ? double.maxFinite : layout.dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: layout.quickListMaxHeight),
          child: ValueListenableBuilder<int>(
            valueListenable: _selected,
            builder: (context, selected, _) {
              final highlight =
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.14);
              return ListView.builder(
                shrinkWrap: true,
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final row = _rows[i];
                  return ColoredBox(
                    key: ValueKey('quick_env_row_$i'),
                    color: i == selected ? highlight : Colors.transparent,
                    child: ListTile(
                      dense: true,
                      leading: row.isActive
                          ? Icon(
                              Icons.check,
                              size: layout.smallIconSize,
                              color: Theme.of(context).colorScheme.secondary,
                            )
                          : SizedBox(width: layout.smallIconSize),
                      title: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: context.appTypography.titleWeight,
                        ),
                      ),
                      onTap: () => _invoke(i),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}

/// One row in the switcher: the `No Environment` row ([envId] == null) or a
/// saved environment. A small union so selection is a single index with no
/// magic-string sentinels in the keyboard code.
class _EnvRow {
  const _EnvRow({
    required this.label,
    required this.envId,
    required this.isActive,
  });
  final String label;
  final String? envId;
  final bool isActive;
}

class _MoveSelectionIntent extends Intent {
  const _MoveSelectionIntent(this.delta);
  final int delta;
}

class _RunSelectionIntent extends Intent {
  const _RunSelectionIntent();
}
```

> Verify `context.appTypography.titleWeight` exists (it is used identically in `command_palette.dart` line 278) and that `Theme.of(context).colorScheme.secondary` is the active-marker color (matches `environment_selector.dart` `_menuItems`). Both are established patterns; do not introduce literals.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/environments/presentation/widgets/quick_env_switcher_test.dart`
Expected: PASS (all 8 tests).

- [ ] **Step 5: Verify analysis on the new widget**

Run: `fvm flutter analyze lib/features/environments/presentation/widgets/quick_env_switcher.dart && fvm dart run custom_lint`
Expected: No issues found (both). In particular `avoid_hardcoded_brand_colors` must not fire — the only `Colors.*` use is `Colors.transparent` (a non-brand sentinel, the same one `command_palette.dart` uses for an unselected row).

- [ ] **Step 6: Commit**

```bash
git add lib/features/environments/presentation/widgets/quick_env_switcher.dart test/features/environments/presentation/widgets/quick_env_switcher_test.dart
git commit -m "feat(environments): quick env switcher overlay widget

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `SwitchEnvironmentIntent` + Cmd/Ctrl+E in `appShortcuts`

Add the intent and bind both modifiers (meta + control), matching every existing letter shortcut. Assert the map wiring in the existing shortcuts test.

**Files:**
- Modify: `lib/core/navigation/intents.dart`
- Modify: `lib/main.dart`
- Test: `test/main_shortcuts_test.dart`

- [ ] **Step 1: Write the failing test (extend the existing shortcuts test)**

In `test/main_shortcuts_test.dart`, add an import at the top (the file currently imports `package:getman/core/navigation/intents.dart` and `package:getman/main.dart`; the new intent comes from the already-imported intents file, so no new import is needed). Add this test inside the `group('appShortcuts', () { ... })` block, after `test('existing bindings still resolve', ...)`:

```dart
    test('Cmd/Ctrl+E map to SwitchEnvironmentIntent', () {
      expect(
        appShortcuts[const SingleActivator(
          LogicalKeyboardKey.keyE,
          meta: true,
        )],
        isA<SwitchEnvironmentIntent>(),
      );
      expect(
        appShortcuts[const SingleActivator(
          LogicalKeyboardKey.keyE,
          control: true,
        )],
        isA<SwitchEnvironmentIntent>(),
      );
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/main_shortcuts_test.dart`
Expected: FAIL — `The name 'SwitchEnvironmentIntent' isn't a type` (and the lookups return null once it compiles).

- [ ] **Step 3: Add the intent**

In `lib/core/navigation/intents.dart`, add after `CommandPaletteIntent`:

```dart
/// Open the quick environment switcher overlay. Bound to Cmd/Ctrl+E.
class SwitchEnvironmentIntent extends Intent {
  const SwitchEnvironmentIntent();
}
```

- [ ] **Step 4: Add the activators to `appShortcuts`**

In `lib/main.dart`, inside the `appShortcuts` map literal, add after the two `CommandPaletteIntent` entries (the `keyK` block, before the `tab` entries):

```dart
  const SingleActivator(LogicalKeyboardKey.keyE, control: true):
      const SwitchEnvironmentIntent(),
  const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
      const SwitchEnvironmentIntent(),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `fvm flutter test test/main_shortcuts_test.dart`
Expected: PASS (the new test plus the three existing ones).

- [ ] **Step 6: Commit**

```bash
git add lib/core/navigation/intents.dart lib/main.dart test/main_shortcuts_test.dart
git commit -m "feat(navigation): SwitchEnvironmentIntent bound to Cmd/Ctrl+E

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire the root `Action` in `main.dart`

Register `SwitchEnvironmentIntent`'s `Action` at the root `Actions` map beside `CommandPaletteIntent`, invoking `QuickEnvSwitcher.show(context)`. Both required blocs (`EnvironmentsBloc`, `SettingsBloc`) are root-provided, so `context.read<...>()` inside `show()` resolves here.

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add the import**

At the top of `lib/main.dart`, add (alphabetically, near the other `features/environments/...` imports — after `environments_event.dart`):

```dart
import 'package:getman/features/environments/presentation/widgets/quick_env_switcher.dart';
```

- [ ] **Step 2: Register the root action**

In the root `Actions` map (the one containing `NewTabIntent` and `CommandPaletteIntent`, around line 192), add after the `CommandPaletteIntent` entry:

```dart
                      SwitchEnvironmentIntent:
                          CallbackAction<SwitchEnvironmentIntent>(
                            onInvoke: (intent) {
                              unawaited(QuickEnvSwitcher.show(context));
                              return null;
                            },
                          ),
```

> `SwitchEnvironmentIntent` is already imported via `intents.dart` (imported in `main.dart`); `unawaited` is from the existing `dart:async` import.

- [ ] **Step 3: Verify analysis (all three passes)**

Run:
```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
```
Expected: No issues found from all three.

- [ ] **Step 4: Manual sanity (desktop)**

Run: `fvm flutter run -d macos`. Create at least one environment via the env selector. Press **Cmd+E** → the SWITCH ENVIRONMENT overlay opens with the active row marked + highlighted. Press ArrowDown/ArrowUp to move, **Enter** to switch (the env selector label updates), **Esc** to dismiss without changing. Close the app when satisfied.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat(navigation): wire Cmd/Ctrl+E to open the quick env switcher

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Full verification + wiki

**Files:**
- Wiki: `Getman.wiki.git` (separate repo) — keyboard-shortcuts page + Environments page.

- [ ] **Step 1: Run the full done-bar**

Run each and confirm clean:
```bash
fvm dart format lib test tools
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```
Expected: `dart format` reports 0 changed (or commit the formatting in Step 4), all three analysis passes "No issues found", all tests green.

- [ ] **Step 2: Clone + edit the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

Edit the keyboard-shortcuts reference page (the one listing Cmd/Ctrl+K and the other global shortcuts): add a row/line for **Cmd/Ctrl+E — Quick environment switcher** (alongside Cmd/Ctrl+K). If a new page is created, also add it to `_Sidebar.md`.

Edit the **Environments** page: add a short blurb describing the switcher as a third way to change the active environment beside the dropdown and the command palette, e.g.:

> **Quick switch (Cmd/Ctrl+E).** Press Cmd/Ctrl+E to open the **SWITCH ENVIRONMENT** overlay — an arrow-navigable list of **No Environment** plus your saved environments, with the active one marked. Use Up/Down to move, Enter to switch, Esc to cancel. It is a pure switcher (no create/edit/delete — use the dropdown's **Manage environments…** for that).

Keep UI labels verbatim: **SWITCH ENVIRONMENT** and **No Environment**.

- [ ] **Step 3: Commit + push the wiki**

```bash
cd /tmp/getman-wiki && git add -A && git commit -m "docs: quick environment switcher (Cmd/Ctrl+E)" && git push origin master
```

- [ ] **Step 4: Final format commit (if formatting changed anything)**

```bash
git add -A && git commit -m "chore: format

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" || echo "nothing to format"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** new `QuickEnvSwitcher` widget (Task 2) ✓; `SwitchEnvironmentIntent` + Cmd/Ctrl+E activators (Task 3) ✓; root `Action` invoking `show()` (Task 4) ✓; arrow nav + Enter via `_MoveSelectionIntent`/`_RunSelectionIntent` mirroring the palette (Task 2) ✓; active row marked + pre-highlighted on open (Task 2 + test "Enter on open") ✓; `No Environment` always first with verbatim label (Task 2) ✓; no fuzzy/text filter (no search field — autofocused `Focus` wrapper) ✓; reads both blocs at open time, snapshots into the widget, dispatches `UpdateActiveEnvironmentId` (Task 2 `show()`) ✓; two-bloc coordination at the widget layer, no new bloc (Task 2) ✓; theming via `context.appLayout`/`appPalette`(secondary)/`appTypography`, `dialogWidth` reused + new `quickListMaxHeight` instead of a literal (Tasks 1–2) ✓; edge cases — empty list, stale active id, tap parity (Task 2 tests) ✓; wiki keyboard-shortcuts + Environments pages (Task 5) ✓.
- **Sequencing:** pure theme field first (Task 1, unit-tested), then the widget (Task 2, widget test), then the intent + map (Task 3, map assertion), then root wiring (Task 4), then wiki (Task 5) — each builds on the last.
- **Type consistency (verified against the codebase):** `UpdateActiveEnvironmentId(String? id)` (nullable, `props => [id]`) — `settings_event.dart`; `EnvironmentEntity{id,name,variables,secretKeys}` — `environment_entity.dart`; `EnvironmentsState.environments` (`List<EnvironmentEntity>`) — `environments_state.dart`; `SettingsBloc.state.settings.activeEnvironmentId` (read in `show()`); `ResponsiveDialogScaffold({title, content, actions})` + `showResponsiveDialog<void>(context, builder:)` — `responsive_dialog.dart`; `context.isDialogFullscreen` — `responsive.dart`; `context.appLayout.{dialogWidth, smallIconSize, quickListMaxHeight}`, `context.appTypography.titleWeight`, `colorScheme.{primary, secondary}` — matching `command_palette.dart` + `environment_selector.dart`; `brutalistTheme(Brightness.light)` test theme + mocktail `MockSettingsBloc` — copied from `command_palette_test.dart`; `appShortcuts` `@visibleForTesting` map + `SingleActivator(LogicalKeyboardKey.keyE, meta/control: true)` lookups — `main_shortcuts_test.dart`.
- **Theming reality check:** `AppLayout` is a single shared pair of consts (`normal`/`compact`) referenced by all four theme builders — so the new field is a one-file edit (Task 1), NOT "across all four theme builders" as the spec hedged. Width reuses the existing `dialogWidth`; only the list cap is new.
- **Done-bar:** Task 5 Step 1 runs all five gate commands; per-task analysis runs in Tasks 2–4.
- **Open verification:** `context.appTypography.titleWeight` and `colorScheme.secondary` are reused verbatim from existing widgets (palette + selector), so no new API is assumed; a one-line note in Task 2 Step 3 flags them for a quick confirm.
