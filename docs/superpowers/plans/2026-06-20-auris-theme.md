# AURIS Theme + Per-Theme Component-Slot System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a seventh Getman theme, **AURIS**, built on the `auris` package's sci-fi-HUD widgets, on top of a new per-theme component-slot system that lets any theme supply its own widget implementations for key UI atoms.

**Architecture:** A new 8th `ThemeExtension`, `AppComponents`, holds widget-returning closures (one per slot). A shared `defaultAppComponents()` reproduces today's rendering, so the six existing themes are visually unchanged (each attaches it in one line). Concrete widgets delegate to `context.appComponents.<slot>(…)`. The AURIS theme composes `AurisTheme.dark()/.light()` as its base `ThemeData` (preserving `AurisScheme` + bundled fonts) and attaches Getman's 8 extensions, with `aurisComponents()` returning the real `Auris*` widgets and a loud HUD `AppMotion`.

**Tech Stack:** Flutter (fvm-pinned 3.41.6) / Dart 3.11, `flutter_bloc`, `auris ^0.2.0`, existing theme-extension system (`lib/core/theme/`).

**Spec:** `docs/superpowers/specs/2026-06-20-auris-theme-design.md`

## Global Constraints

- Always invoke Flutter/Dart as `fvm flutter …` / `fvm dart …` — never bare `flutter`.
- All imports are `package:getman/...` (no relative imports; `directives_ordering`).
- Never `sl<T>()`/`GetIt` from a widget; no `Colors.black/white/red` literals outside `lib/core/theme/` (custom_lint enforced).
- New theme id constant `kAurisThemeId = 'auris'`; display name **`AURIS`** (verbatim); `defaultThemeId` stays `kClassicThemeId`.
- Theme builder signature: `ThemeData aurisTheme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false})`.
- `reduceEffects` MUST degrade motion to identity + static ambient + `glowScale: 0`; any repeating flash routes through `safeFlashCount` (WCAG 3 Hz), independent of `reduceEffects`.
- auris widgets force-unwrap `Theme.of(context).extension<AurisScheme>()!` — they may ONLY be instantiated under the AURIS theme. `defaultAppComponents()` must never construct an `Auris*` widget.
- `auris` is pre-1.0: keep ALL auris-specific code inside `lib/core/theme/themes/auris/` so its API churn never reaches the slot interfaces.
- Done-bar before any task is "complete": `fvm flutter analyze` (0), `fvm dart run custom_lint` (0), `fvm dart run bloc_tools:bloc lint lib` (0), `fvm dart format` clean, `fvm flutter test` green. The `.githooks/pre-commit` hook runs the first four on commit.
- Commit message trailers (every commit):
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TFvqsX8ZG3qFgNFRqyjGpk
  ```

---

## File Structure

**Create:**
- `lib/core/theme/extensions/app_components.dart` — `AppComponents` extension + neutral data types (`AppLogLine`, `AppLogLineKind`, `AppSelectSpec`, `AppSelectItem`, `AppBannerState`).
- `lib/core/theme/extensions/app_components_defaults.dart` — `defaultAppComponents()` + private default widgets reproducing today's rendering.
- `lib/core/ui/widgets/app_dropdown.dart` — `AppDropdown<T>` generic consumer widget over the non-generic `select` slot.
- `lib/core/theme/themes/auris/auris_palette.dart`
- `lib/core/theme/themes/auris/auris_components.dart` — `aurisComponents()` (the `Auris*` slot impls).
- `lib/core/theme/themes/auris/auris_decorations.dart` — scaffold ambient (animated + static) + auris press wrapper.
- `lib/core/theme/themes/auris/auris_motion.dart` — `aurisMotion({required bool reduceEffects})`.
- `lib/core/theme/themes/auris/auris_theme.dart` — the builder.
- Tests under `test/core/theme/...` and `test/features/...` (per task).

**Modify:**
- `lib/core/theme/extensions/app_theme_access.dart` — add `appComponents` accessor.
- The six existing theme builders (`brutalist/editorial/rpg/classic/dracula/glass`*_theme.dart) — attach `defaultAppComponents()`.
- Consumer widgets (method badge, response metadata, 4 panels, realtime panel, response header/cookie views, settings switches, key/value secret lock, url bar method dropdown, panel selector, response shimmer).
- `lib/core/theme/theme_ids.dart`, `lib/core/theme/theme_registry.dart`, `pubspec.yaml`.

---

## Phase A — Component-slot infrastructure (auris-agnostic, no behavior change)

### Task A1: `AppComponents` extension + neutral types

**Files:**
- Create: `lib/core/theme/extensions/app_components.dart`
- Test: `test/core/theme/extensions/app_components_test.dart`

**Interfaces:**
- Produces: `class AppComponents extends ThemeExtension<AppComponents>` with these closure fields (all take `BuildContext context` first):
  - `SurfaceBuilder surface` — `Widget Function(BuildContext, {required Widget child, String? title, String? code, bool accent})`
  - `MethodBadgeBuilder methodBadge` — `Widget Function(BuildContext, {required String method, bool small})`
  - `StatusBadgeBuilder statusBadge` — `Widget Function(BuildContext, {required int statusCode})`
  - `MetricBuilder metric` — `Widget Function(BuildContext, {required String label, required String value, String? unit, String? delta})`
  - `ToggleBuilder toggle` — `Widget Function(BuildContext, {required bool value, required ValueChanged<bool> onChanged, String? label})`
  - `LogViewBuilder logView` — `Widget Function(BuildContext, {required List<AppLogLine> lines, String? title, ScrollController? controller})`
  - `DataRowBuilder dataRow` — `Widget Function(BuildContext, {required String label, required String value, bool highlight})`
  - `SelectBuilder select` — `Widget Function(BuildContext, AppSelectSpec spec)`
  - `PendingIndicatorBuilder pendingIndicator` — `Widget Function(BuildContext, {String? label})`
  - `StatusBannerBuilder statusBanner` — `Widget Function(BuildContext, {required AppBannerState state, required String message})`
- Produces neutral types: `AppLogLine{String text; AppLogLineKind kind}`, `enum AppLogLineKind{outgoing, incoming, ok, warning, error}`, `AppSelectItem{String label; Widget? leading}`, `AppSelectSpec{String? placeholder; List<AppSelectItem> items; int selectedIndex; ValueChanged<int> onSelected}`, `enum AppBannerState{info, success, warning, error}`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';

void main() {
  test('AppComponents.lerp returns this (closures do not interpolate)', () {
    final c = AppComponents(
      surface: (context, {required child, title, code, accent = false}) => child,
      methodBadge: (context, {required method, small = false}) => const SizedBox(),
      statusBadge: (context, {required statusCode}) => const SizedBox(),
      metric: (context, {required label, required value, unit, delta}) => const SizedBox(),
      toggle: (context, {required value, required onChanged, label}) => const SizedBox(),
      logView: (context, {required lines, title, controller}) => const SizedBox(),
      dataRow: (context, {required label, required value, highlight = false}) => const SizedBox(),
      select: (context, spec) => const SizedBox(),
      pendingIndicator: (context, {label}) => const SizedBox(),
      statusBanner: (context, {required state, required message}) => const SizedBox(),
    );
    expect(identical(c.lerp(null, 0.5), c), isTrue);
    expect(c.copyWith().surface, equals(c.surface));
  });

  test('neutral types construct', () {
    const line = AppLogLine(text: 'hi', kind: AppLogLineKind.ok);
    expect(line.kind, AppLogLineKind.ok);
    final spec = AppSelectSpec(
      items: const [AppSelectItem(label: 'A')],
      selectedIndex: 0,
      onSelected: (_) {},
    );
    expect(spec.items.single.label, 'A');
    expect(AppBannerState.values.length, 4);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/extensions/app_components_test.dart`
Expected: FAIL — `app_components.dart` / `AppComponents` not found.

- [ ] **Step 3: Write the extension**

Create `lib/core/theme/extensions/app_components.dart`. Define the neutral types first, then the typedefs, then the class. Mirror `app_decoration.dart` exactly: all closure fields `required` in the constructor, per-field `copyWith`, `lerp(other, t) => this`.

```dart
import 'package:flutter/material.dart';

enum AppLogLineKind { outgoing, incoming, ok, warning, error }

@immutable
class AppLogLine {
  const AppLogLine({required this.text, required this.kind});
  final String text;
  final AppLogLineKind kind;
}

@immutable
class AppSelectItem {
  const AppSelectItem({required this.label, this.leading});
  final String label;
  final Widget? leading;
}

@immutable
class AppSelectSpec {
  const AppSelectSpec({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.placeholder,
  });
  final List<AppSelectItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? placeholder;
}

enum AppBannerState { info, success, warning, error }

typedef SurfaceBuilder = Widget Function(
  BuildContext context, {
  required Widget child,
  String? title,
  String? code,
  bool accent,
});
typedef MethodBadgeBuilder = Widget Function(BuildContext context, {required String method, bool small});
typedef StatusBadgeBuilder = Widget Function(BuildContext context, {required int statusCode});
typedef MetricBuilder = Widget Function(BuildContext context, {required String label, required String value, String? unit, String? delta});
typedef ToggleBuilder = Widget Function(BuildContext context, {required bool value, required ValueChanged<bool> onChanged, String? label});
typedef LogViewBuilder = Widget Function(BuildContext context, {required List<AppLogLine> lines, String? title, ScrollController? controller});
typedef DataRowBuilder = Widget Function(BuildContext context, {required String label, required String value, bool highlight});
typedef SelectBuilder = Widget Function(BuildContext context, AppSelectSpec spec);
typedef PendingIndicatorBuilder = Widget Function(BuildContext context, {String? label});
typedef StatusBannerBuilder = Widget Function(BuildContext context, {required AppBannerState state, required String message});

class AppComponents extends ThemeExtension<AppComponents> {
  const AppComponents({
    required this.surface,
    required this.methodBadge,
    required this.statusBadge,
    required this.metric,
    required this.toggle,
    required this.logView,
    required this.dataRow,
    required this.select,
    required this.pendingIndicator,
    required this.statusBanner,
  });

  final SurfaceBuilder surface;
  final MethodBadgeBuilder methodBadge;
  final StatusBadgeBuilder statusBadge;
  final MetricBuilder metric;
  final ToggleBuilder toggle;
  final LogViewBuilder logView;
  final DataRowBuilder dataRow;
  final SelectBuilder select;
  final PendingIndicatorBuilder pendingIndicator;
  final StatusBannerBuilder statusBanner;

  @override
  AppComponents copyWith({
    SurfaceBuilder? surface,
    MethodBadgeBuilder? methodBadge,
    StatusBadgeBuilder? statusBadge,
    MetricBuilder? metric,
    ToggleBuilder? toggle,
    LogViewBuilder? logView,
    DataRowBuilder? dataRow,
    SelectBuilder? select,
    PendingIndicatorBuilder? pendingIndicator,
    StatusBannerBuilder? statusBanner,
  }) {
    return AppComponents(
      surface: surface ?? this.surface,
      methodBadge: methodBadge ?? this.methodBadge,
      statusBadge: statusBadge ?? this.statusBadge,
      metric: metric ?? this.metric,
      toggle: toggle ?? this.toggle,
      logView: logView ?? this.logView,
      dataRow: dataRow ?? this.dataRow,
      select: select ?? this.select,
      pendingIndicator: pendingIndicator ?? this.pendingIndicator,
      statusBanner: statusBanner ?? this.statusBanner,
    );
  }

  @override
  AppComponents lerp(ThemeExtension<AppComponents>? other, double t) => this;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/extensions/app_components_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the accessor**

Modify `lib/core/theme/extensions/app_theme_access.dart`: add the import for `app_components.dart` (alphabetical order) and inside the extension:

```dart
  AppComponents get appComponents => Theme.of(this).extension<AppComponents>()!;
```

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/extensions/app_components.dart \
        lib/core/theme/extensions/app_theme_access.dart \
        test/core/theme/extensions/app_components_test.dart
git commit -m "feat(theme): add AppComponents extension + neutral types"
```

---

### Task A2: `defaultAppComponents()` — reproduce today's rendering

**Files:**
- Create: `lib/core/theme/extensions/app_components_defaults.dart`
- Test: `test/core/theme/extensions/app_components_defaults_test.dart`

**Interfaces:**
- Consumes: `AppComponents` and neutral types from A1; `context.appLayout/appPalette/appShape/appTypography/appDecoration` accessors.
- Produces: top-level `AppComponents defaultAppComponents()` whose closures render the CURRENT look of each surface.

**Implementation guidance (read before coding):** Each default closure must render exactly what the app shows today, so existing themes don't change. Build small private widgets in this file:
- `surface` → `Container(decoration: context.appDecoration.panelBox(context, color: ..., borderWidth: ..., offset: ..., borderRadius: ...), child: child)` (offset 0 default; the `title`/`code`/`accent` args are ignored by the default — it has no titled-panel concept).
- `methodBadge` → the current `MethodBadge` body (Container + per-method color + `methodOn` text). Read `lib/core/ui/widgets/method_badge.dart` and reproduce its build into `_DefaultMethodBadge`.
- `statusBadge` → a chip coloured by `context.appPalette.statusAccent(statusCode)` with the code text (matches `ResponseMetadataItem`'s status look; read `lib/features/tabs/presentation/widgets/response/response_metadata_item.dart`).
- `metric` → label + value(+unit)(+delta) column matching `ResponseMetadataItem`'s TIME/SIZE rendering.
- `toggle` → `Row(label?, Switch(value, onChanged))` using Material `Switch`.
- `logView` → a `ListView` of monospace rows matching realtime `_FrameRow` (`lib/features/realtime/presentation/widgets/realtime_panel.dart`): direction glyph + `IN`/`OUT` label coloured by kind + `SelectableText` in `codeFontFamily`.
- `dataRow` → `Row(label, value)` matching the current header/cookie row.
- `select` → a `PopupMenuButton`/`DropdownButton` over `spec.items` reflecting `spec.selectedIndex`, calling `spec.onSelected(index)`; matches the current dropdown look.
- `pendingIndicator` → the current `Shimmer` skeleton block (read `response_section.dart`).
- `statusBanner` → a `Container` coloured by `state` mapping to `palette.statusSuccess/statusError/...` with the message (matches realtime connection banner).

These are mechanical reproductions of existing widget bodies — no new logic. Keep each private widget under ~40 lines; pull values from `context.app*`, never hardcode.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  testWidgets('every default slot renders without throwing', (tester) async {
    final components = defaultAppComponents();
    final theme = resolveThemeData(null, Brightness.light, isCompact: false)
        .copyWith(extensions: [
      ...resolveThemeData(null, Brightness.light, isCompact: false).extensions.values,
      components,
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(builder: (context) {
        final c = context.appComponents; // via accessor
        return Scaffold(
          body: ListView(children: [
            c.surface(context, child: const Text('panel')),
            c.methodBadge(context, method: 'GET'),
            c.statusBadge(context, statusCode: 200),
            c.metric(context, label: 'TIME', value: '142', unit: 'ms'),
            c.toggle(context, value: true, onChanged: (_) {}, label: 'X'),
            c.logView(context, lines: const [AppLogLine(text: 'hi', kind: AppLogLineKind.ok)]),
            c.dataRow(context, label: 'Content-Type', value: 'application/json'),
            c.select(context, AppSelectSpec(items: const [AppSelectItem(label: 'GET')], selectedIndex: 0, onSelected: (_) {})),
            c.pendingIndicator(context),
            c.statusBanner(context, state: AppBannerState.success, message: 'CONNECTED'),
          ]),
        );
      }),
    ));
    expect(tester.takeException(), isNull);
  });
}
```
(Add `import 'package:getman/core/theme/extensions/app_theme_access.dart';` for `context.appComponents`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/extensions/app_components_defaults_test.dart`
Expected: FAIL — `defaultAppComponents` not found.

- [ ] **Step 3: Implement `defaultAppComponents()`** per the guidance above (private widgets + the top-level factory wiring each closure to its private widget).

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/extensions/app_components_defaults_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/extensions/app_components_defaults.dart \
        test/core/theme/extensions/app_components_defaults_test.dart
git commit -m "feat(theme): defaultAppComponents() reproducing current rendering"
```

---

### Task A3: Attach `defaultAppComponents()` to all six existing themes

**Files:**
- Modify: `lib/core/theme/themes/{classic,brutalist,editorial,rpg,dracula,glass}/<name>_theme.dart` (add to the `extensions: [...]` list)
- Test: `test/core/theme/theme_has_components_test.dart`

**Interfaces:**
- Consumes: `defaultAppComponents()` (A2), `appThemes` registry.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  test('every registered theme attaches AppComponents (both brightnesses)', () {
    for (final entry in appThemes.entries) {
      for (final b in Brightness.values) {
        final data = entry.value.builder(b);
        expect(data.extension<AppComponents>(), isNotNull,
            reason: '${entry.key} ($b) is missing AppComponents');
      }
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/theme_has_components_test.dart`
Expected: FAIL — `AppComponents` null for classic (the first theme iterated).

- [ ] **Step 3: Add `defaultAppComponents()` to each builder**

In each `<name>_theme.dart`, add the import `import 'package:getman/core/theme/extensions/app_components_defaults.dart';` and append `defaultAppComponents(),` to the `extensions: [...]` list in the final `base.copyWith(extensions: [...])` (or `return ThemeData(... extensions: [...])`). Example (classic):

```dart
  return base.copyWith(
    extensions: [
      layout, palette, shape, typography, decoration,
      calmMotion(reduceEffects: reduceEffects),
      const AppCopy(emptyResponse: 'No response yet.'),
      defaultAppComponents(),
    ],
  );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/theme_has_components_test.dart`
Expected: PASS.

- [ ] **Step 5: Full gate + commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm flutter test`
Expected: 0 issues, green.

```bash
git add lib/core/theme/themes/*/*_theme.dart test/core/theme/theme_has_components_test.dart
git commit -m "feat(theme): attach defaultAppComponents() to all existing themes"
```

---

### Task A4: `AppDropdown<T>` (generic consumer over the `select` slot)

**Files:**
- Create: `lib/core/ui/widgets/app_dropdown.dart`
- Test: `test/core/ui/widgets/app_dropdown_test.dart`

**Interfaces:**
- Consumes: `AppSelectSpec`, `AppSelectItem`, `context.appComponents.select`.
- Produces: `class AppDropdown<T> extends StatelessWidget` with `{required List<T> options, required T value, required ValueChanged<T> onChanged, required String Function(T) labelOf, Widget Function(T)? leadingOf, String? placeholder}`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/app_dropdown.dart';

void main() {
  testWidgets('AppDropdown maps index back to T on select', (tester) async {
    T? picked;
    final base = resolveThemeData(null, Brightness.light, isCompact: false);
    final theme = base.copyWith(
      extensions: [...base.extensions.values, defaultAppComponents()],
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: AppDropdown<String>(
          options: const ['GET', 'POST', 'PUT'],
          value: 'GET',
          labelOf: (m) => m,
          onChanged: (m) => picked = m,
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
```
(`T? picked;` — change to `String? picked;`.)

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/app_dropdown_test.dart`
Expected: FAIL — `AppDropdown` not found.

- [ ] **Step 3: Implement `AppDropdown<T>`**

```dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.labelOf,
    super.key,
    this.leadingOf,
    this.placeholder,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;
  final Widget Function(T)? leadingOf;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = options.indexOf(value);
    return context.appComponents.select(
      context,
      AppSelectSpec(
        placeholder: placeholder,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        items: [
          for (final o in options)
            AppSelectItem(label: labelOf(o), leading: leadingOf?.call(o)),
        ],
        onSelected: (i) => onChanged(options[i]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/app_dropdown_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/widgets/app_dropdown.dart test/core/ui/widgets/app_dropdown_test.dart
git commit -m "feat(ui): AppDropdown<T> over the select component slot"
```

---

## Phase B — Route consumers through the slots (still default rendering)

> Each task below: (1) add a "current widget type still present" widget test, (2) refactor the widget's `build` to delegate to `context.appComponents.<slot>(…)`, (3) verify the test + the existing feature tests still pass, (4) commit. Because the active theme supplies `defaultAppComponents()`, rendering is unchanged.

### Task B1: `MethodBadge` → `methodBadge` slot

**Files:**
- Modify: `lib/core/ui/widgets/method_badge.dart`
- Test: `test/core/ui/widgets/method_badge_slot_test.dart`

- [ ] **Step 1: Write test** — pump `MaterialApp` with a default-components theme, render `MethodBadge(method: 'GET')`, expect `find.text('GET')` and `tester.takeException()` is null.
- [ ] **Step 2: Run → fails** (no test file yet) / passes baseline. Run: `fvm flutter test test/core/ui/widgets/method_badge_slot_test.dart`.
- [ ] **Step 3: Refactor** — replace `MethodBadge.build` body with:
  ```dart
  return context.appComponents.methodBadge(context, method: method, small: small);
  ```
  (add `import 'package:getman/core/theme/extensions/app_theme_access.dart';`). Ensure the `_DefaultMethodBadge` in A2 takes `small`. The previous build body now lives in `_DefaultMethodBadge` (moved in A2).
- [ ] **Step 4: Run** the new test + `fvm flutter test test/core/ui/widgets/` → PASS.
- [ ] **Step 5: Commit** `refactor(ui): MethodBadge delegates to methodBadge slot`.

### Task B2: Response status + metric → `statusBadge` / `metric` slots

**Files:** Modify `lib/features/tabs/presentation/widgets/response/response_metadata_item.dart`; Test `test/features/tabs/.../response_metadata_slot_test.dart`.
- [ ] Step 1: Test renders `ResponseMetadataItem` for STATUS/TIME/SIZE, expects no exception + value text present.
- [ ] Step 2: Run.
- [ ] Step 3: Route the status variant to `context.appComponents.statusBadge(context, statusCode: code)` and the TIME/SIZE variants to `context.appComponents.metric(...)`. Preserve the existing fade-in animation wrapper around the slot output.
- [ ] Step 4: Run feature tests `fvm flutter test test/features/tabs/` → PASS.
- [ ] Step 5: Commit `refactor(tabs): response metadata via statusBadge/metric slots`.

### Task B3: Four panels → `surface` slot

**Files:** Modify `response_section.dart`, `request_config_section.dart`, `unified_request_panel.dart`, `realtime_panel.dart` (the panel container only); Test `test/features/tabs/.../panel_surface_slot_test.dart`.
- [ ] Step 1: Test pumps each panel host (or a minimal harness) and asserts no exception.
- [ ] Step 2: Run.
- [ ] Step 3: Replace each `Container(decoration: context.appDecoration.panelBox(context, offset: 0))` (kept inside the existing `frost(...)` wrapper) with `context.appComponents.surface(context, child: <existing child>)`. Keep the `frost()` wrapper outside the surface call.
- [ ] Step 4: Run `fvm flutter test test/features/` → PASS.
- [ ] Step 5: Commit `refactor: main panels via surface slot`.

### Task B4: Realtime frame log → `logView`; connection banner → `statusBanner`

**Files:** Modify `lib/features/realtime/presentation/widgets/realtime_panel.dart`; Test `test/features/realtime/.../realtime_slots_test.dart`.
- [ ] Step 1: Test drives a `RealtimeBloc` (reuse existing realtime test harness/fakes) to a connected state with one IN and one OUT frame; expects the frame text present + no exception.
- [ ] Step 2: Run.
- [ ] Step 3: Map frames to `List<AppLogLine>` (`OUT→outgoing`, `IN→incoming`, error frame→error, close→warning, open→ok) and render via `context.appComponents.logView(context, lines: lines, controller: _scrollController)`. Map the CONNECTED/DISCONNECTED/ERROR banner to `context.appComponents.statusBanner(context, state: ..., message: ...)`.
- [ ] Step 4: Run `fvm flutter test test/features/realtime/` → PASS.
- [ ] Step 5: Commit `refactor(realtime): frame log via logView + statusBanner slots`.

### Task B5: Response headers + cookies → `dataRow`

**Files:** Modify `lib/features/tabs/presentation/widgets/response/response_headers_view.dart` and `response_cookies_view.dart` (confirm exact filenames via `ls lib/features/tabs/presentation/widgets/response/`); Test `test/features/tabs/.../response_datarow_slot_test.dart`.
- [ ] Step 1: Test renders a headers view with one header, expects key+value text present, no exception.
- [ ] Step 2: Run.
- [ ] Step 3: Render each key/value row via `context.appComponents.dataRow(context, label: key, value: value)`.
- [ ] Step 4: Run feature tests → PASS.
- [ ] Step 5: Commit `refactor(tabs): response headers/cookies via dataRow slot`.

### Task B6: Settings + secret-lock toggles → `toggle`

**Files:** Modify `lib/features/settings/presentation/widgets/settings_dialog.dart` (`_switch()` helper) and `lib/core/ui/widgets/key_value_list_editor.dart` (the secret lock toggle); Test `test/features/settings/.../settings_toggle_slot_test.dart`.
- [ ] Step 1: Test renders the settings dialog (or the `_switch` host), toggles a switch, expects callback fired + no exception.
- [ ] Step 2: Run.
- [ ] Step 3: Route the `SwitchListTile`/`Switch` through `context.appComponents.toggle(context, value:, onChanged:, label:)`. (The secret-lock is an icon toggle, not a boolean track — leave it on `wrapInteractive` if it does not map cleanly to a `toggle`; note the decision in code. Prefer routing only the true on/off switches.)
- [ ] Step 4: Run `fvm flutter test test/features/settings/` → PASS.
- [ ] Step 5: Commit `refactor(settings): boolean switches via toggle slot`.

### Task B7: Method dropdown + panel selector → `AppDropdown`; pending shimmer → `pendingIndicator`

**Files:** Modify `lib/features/tabs/presentation/widgets/url_bar.dart` (method dropdown), `lib/features/tabs/presentation/widgets/panel_selector.dart`, `response_section.dart` (shimmer); Test `test/features/tabs/.../dropdown_pending_slot_test.dart`.
- [ ] Step 1: Test renders the URL bar method dropdown (default theme) and asserts the current method label present + no exception; renders a sending tab and asserts the pending placeholder appears.
- [ ] Step 2: Run.
- [ ] Step 3: Replace the bespoke method dropdown with `AppDropdown<String>(options: HttpMethods.all, value: method, labelOf: (m) => m, leadingOf: (m) => MethodBadge(method: m, small: true), onChanged: ...)`; replace `PanelSelector`'s list trigger similarly where it fits (if the panel selector's UX is too bespoke for `AppDropdown`, leave it and note it — do NOT force it). Replace the `isSending` shimmer block with `context.appComponents.pendingIndicator(context)`.
- [ ] Step 4: Run `fvm flutter test test/features/tabs/` → PASS.
- [ ] Step 5: Full gate (`analyze` + `custom_lint` + `bloc lint` + `test`) + commit `refactor(tabs): method dropdown + pending via slots`.

> **Phase B checkpoint:** run the entire suite `fvm flutter test`. All existing tests must stay green — this proves the slot routing is behavior-preserving for the six existing themes.

---

## Phase C — auris dependency + AURIS theme (plain, using default components)

### Task C1: Add `auris` + confirm its real API

**Files:** Modify `pubspec.yaml`; create `docs/superpowers/notes/auris-api.md` (scratch reference, git-ignored or committed as notes).

- [ ] **Step 1:** Add `auris: ^0.2.0` under `dependencies:` in `pubspec.yaml`. Run `fvm flutter pub get`. Expected: resolves (Flutter 3.41.6 ≥ auris's 3.35 floor).
- [ ] **Step 2:** Locate the installed package source: `fvm flutter pub deps` then read the package dir (`~/.pub-cache/hosted/pub.dev/auris-<version>/lib/`). Open `auris.dart`, `auris_widgets.dart`, and the `AurisScheme`/`AurisTheme` sources.
- [ ] **Step 3:** Write `docs/superpowers/notes/auris-api.md` capturing the EXACT, verified signatures used later: `AurisTheme.dark/light` params; `AurisScheme` token field names (the colors AURIS palette will source); `AurisPanel`, `AurisContainer`, `AurisBadge` (+ `AurisBadgeVariant` values), `AurisStatCard`, `AurisSwitch`, `AurisTerminal` (+ `AurisTerminalLine` + its line-type enum), `AurisDataRow`, `AurisSelect`/`AurisSelectOption`, `AurisProgressBar(.animated)`, `AurisNotification` (+ variant enum), `AurisScanBracket`, `AurisHexOrnament` constructor params. **Later auris tasks MUST use the names verified here, not this plan's sketches, if they differ.**
- [ ] **Step 4:** Smoke-check: a throwaway `fvm flutter test` widget that pumps `MaterialApp(theme: AurisTheme.dark(), home: AurisBadge('OK', variant: <verified default>))` renders without throwing. Delete the throwaway after confirming.
- [ ] **Step 5:** Commit `chore: add auris ^0.2.0 dependency + verified API notes`.

### Task C2: `auris_palette.dart` + `auris_theme.dart` (registered, plain components)

**Files:** Create `lib/core/theme/themes/auris/auris_palette.dart`, `lib/core/theme/themes/auris/auris_theme.dart`; Modify `lib/core/theme/theme_ids.dart`, `lib/core/theme/theme_registry.dart`; Test `test/core/theme/themes/auris/auris_theme_test.dart`.

**Interfaces:**
- Consumes: `AurisTheme`, `AurisScheme` (verified names from C1), `defaultAppComponents()`.
- Produces: `ThemeData aurisTheme(Brightness, {bool isCompact, bool reduceEffects})`; `kAurisThemeId`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_layout.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/extensions/app_palette.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  test('AURIS is registered with display name AURIS', () {
    expect(appThemes[kAurisThemeId]?.displayName, 'AURIS');
    expect(defaultThemeId, isNot(kAurisThemeId));
  });

  test('aurisTheme builds for all flag combos and attaches required extensions', () {
    for (final b in Brightness.values) {
      for (final compact in [false, true]) {
        for (final reduce in [false, true]) {
          final data = appThemes[kAurisThemeId]!.builder(b, isCompact: compact, reduceEffects: reduce);
          expect(data.extension<AppLayout>(), isNotNull);
          expect(data.extension<AppPalette>(), isNotNull);
          expect(data.extension<AppMotion>(), isNotNull);
          expect(data.extension<AppComponents>(), isNotNull);
        }
      }
    }
  });
}
```

- [ ] **Step 2: Run → fails** (`kAurisThemeId` undefined). Run: `fvm flutter test test/core/theme/themes/auris/auris_theme_test.dart`.
- [ ] **Step 3a:** Add `const String kAurisThemeId = 'auris';` to `theme_ids.dart`.
- [ ] **Step 3b:** Write `auris_palette.dart` — a function `AppPalette aurisPalette(AurisScheme scheme)` mapping scheme tokens → method colors (amber/gold/slate/success/danger family), status colors (2xx success, 3xx gold, 4xx amber, 5xx danger), `codeBackground` (auris panel surface), `variableResolved/Unresolved`, diff colors. Use ONLY scheme tokens / theme-local constants (allowed inside `lib/core/theme/`).
- [ ] **Step 3c:** Write `auris_theme.dart`:

```dart
import 'package:auris/auris.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';
import 'package:getman/core/theme/extensions/app_copy.dart';
import 'package:getman/core/theme/extensions/app_decoration.dart';
import 'package:getman/core/theme/extensions/app_layout.dart';
import 'package:getman/core/theme/extensions/app_shape.dart';
import 'package:getman/core/theme/extensions/app_typography.dart';
import 'package:getman/core/theme/themes/auris/auris_palette.dart';

ThemeData aurisTheme(
  Brightness brightness, {
  bool isCompact = false,
  bool reduceEffects = false,
}) {
  final base = brightness == Brightness.dark
      ? AurisTheme.dark(glowScale: reduceEffects ? 0.0 : 1.0)
      : AurisTheme.light(glowScale: reduceEffects ? 0.0 : 1.0);
  final scheme = base.extension<AurisScheme>()!; // confirmed present in C1

  final layoutBase = isCompact ? AppLayout.compact : AppLayout.normal;
  final layout = layoutBase; // tune paddings if needed
  const shape = AppShape(panelRadius: 2, buttonRadius: 2, inputRadius: 2, dialogRadius: 4, sheetRadius: 6);
  final palette = aurisPalette(scheme);
  final typography = AppTypography(
    base: base.textTheme,
    codeFontFamily: /* auris mono family from C1 notes */,
    displayWeight: FontWeight.w700,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
  );
  final decoration = AppDecoration(
    panelBox: /* a simple BoxDecoration builder reading scheme surface/border */,
    tabShape: /* simple active/hover BoxDecoration */,
    wrapInteractive: ({required child, onTap, scaleDown}) => child, // replaced in Phase E
    scaffoldBackground: (context, {required child}) => child,        // replaced in Phase E
  );

  return base.copyWith(
    extensions: <ThemeExtension>[
      ...base.extensions.values,     // PRESERVE AurisScheme + any auris extensions
      layout, palette, shape, typography, decoration,
      const AppMotion(),             // replaced in Phase E by aurisMotion(...)
      const AppCopy(emptyResponse: '// NO SIGNAL'),
      defaultAppComponents(),        // replaced in Phase D by aurisComponents()
    ],
  );
}
```
(Fill the `/* … */` from C1 notes + the existing `panelBox`/`tabShape` patterns in `classic_decorations.dart`. `AppMotion` import: `package:getman/core/theme/extensions/app_motion.dart`.)

- [ ] **Step 3d:** Register in `theme_registry.dart`: import `auris_theme.dart`, add `kAurisThemeId: ThemeDescriptor(id: kAurisThemeId, displayName: 'AURIS', builder: aurisTheme)` to `appThemes`.
- [ ] **Step 4: Run → passes.** Run: `fvm flutter test test/core/theme/themes/auris/auris_theme_test.dart`.
- [ ] **Step 5:** Full gate + commit `feat(theme): register AURIS theme (palette + base, default components)`.

> After C2, AURIS is selectable and functional with the *default* component look. Phases D/E layer the auris identity on top.

---

## Phase D — auris component implementations

### Task D1: `auris_components.dart` — `aurisComponents()`

**Files:** Create `lib/core/theme/themes/auris/auris_components.dart`; Modify `auris_theme.dart` (swap `defaultAppComponents()` → `aurisComponents()`); Test `test/core/theme/themes/auris/auris_components_test.dart`.

**Interfaces:**
- Consumes: `AppComponents` + neutral types (A1); auris widgets (C1 verified API); `AurisScheme` (present under AURIS theme).
- Produces: `AppComponents aurisComponents()`.

**Implementation:** Each closure returns the mapped `Auris*` widget, using the verified C1 signatures:
- `surface` → `title != null ? AurisPanel(title: title!, code: code, accent: accent, child: child) : AurisContainer(child: child)`.
- `methodBadge` → `AurisBadge(method, variant: <map method→variant>)`.
- `statusBadge` → `AurisBadge('$statusCode', variant: <2xx success / 3xx gold / 4xx amber / 5xx danger>)`.
- `metric` → `AurisStatCard(label: label, value: value, unit: unit, delta: delta)`.
- `toggle` → `AurisSwitch(value: value, onChanged: onChanged, label: label ?? '')`.
- `logView` → `AurisTerminal(title: title ?? 'LOG', lines: [for (l in lines) AurisTerminalLine(l.text, type: <map kind→line type>)])`.
- `dataRow` → `AurisDataRow(label: label, value: value, highlight: highlight)`.
- `select` → `AurisSelect<int>(value: spec.selectedIndex, placeholder: spec.placeholder, options: [for (i, item) AurisSelectOption(value: i, label: item.label)], onChanged: spec.onSelected)`.
- `pendingIndicator` → `AurisProgressBar.animated(value: null-or-looping, label: label ?? 'AWAITING SIGNAL')` (indeterminate; if `.animated` requires a value, drive a looping value via a tiny stateful wrapper).
- `statusBanner` → `AurisNotification(message: message, variant: <map AppBannerState→AurisNotificationVariant>)`.

- [ ] **Step 1: Write the failing test** — pump `MaterialApp(theme: aurisTheme(Brightness.dark))` and render each slot via `context.appComponents`; assert `tester.takeException()` is null AND that an auris widget type is found (e.g. `find.byType(AurisBadge)`).
- [ ] **Step 2: Run → fails** (`aurisComponents` not found). Run: `fvm flutter test test/core/theme/themes/auris/auris_components_test.dart`.
- [ ] **Step 3: Implement `aurisComponents()`** per the mapping above (reconcile any name diffs against C1 notes). For the indeterminate `pendingIndicator`, write a small private `StatefulWidget` with one looping `AnimationController` if needed.
- [ ] **Step 4:** Swap `defaultAppComponents()` → `aurisComponents()` in `auris_theme.dart`. Run the test → PASS.
- [ ] **Step 5: Guard test** — extend `test/core/theme/theme_has_components_test.dart` (or add a new test) asserting that rendering each NON-auris theme's key surfaces constructs NO auris widget (`find.byType(AurisBadge)` etc. `findsNothing` under classic). Run → PASS.
- [ ] **Step 6:** Full gate + commit `feat(theme): AURIS component slots (Auris* widgets)`.

---

## Phase E — auris motion + ambient

### Task E1: `auris_motion.dart` (loud HUD reactions)

**Files:** Create `lib/core/theme/themes/auris/auris_motion.dart`; Modify `auris_theme.dart` (swap `const AppMotion()` → `aurisMotion(reduceEffects: reduceEffects)`); Test `test/core/theme/themes/auris/auris_motion_test.dart`.

**Interfaces:**
- Consumes: `AppMotion`, `ThemeReactionController`, `ReactionStage`, `flavorFor`/`StatusReactionFlavor`, `latencyWeight`, `inFlightTension`, `safeFlashCount` (all under `lib/core/theme/motion/`).
- Produces: `AppMotion aurisMotion({required bool reduceEffects})`.

**Implementation:** Follow `glass_motion.dart` (child-hoist) + `THEME_AUTHORING.md` §3–§5b. `reduceEffects ⇒ const AppMotion()`. Full:
- `reactionOverlay` → `_AurisReactionOverlay` wrapping `ReactionStage`; `onReaction` plays: success = teal scanline sweep (intensity `latencyWeight(durationMs)`); clientError = amber bracket flash; serverError/networkError = red alarm + small shake + glitch; transport failures keyed off `reaction.transportFailure` (`TransportFailureKind`); cancelled = reverse fizzle. Hoist `child` out of per-frame rebuilds.
- `sendAffordance` → `_AurisSendAffordance` charging reticle/glow driven by `isSending` + `inFlightTension(elapsed)`; restart guard edge-detects on `old.isSending`.
- Any repeating flash clamped via `safeFlashCount`; shake gated by `reduceEffects`.

- [ ] **Step 1: Write the failing test**

```dart
// reduced ⇒ identity
test('aurisMotion reduced is identity', () {
  final m = aurisMotion(reduceEffects: true);
  expect(m, equals(const AppMotion()));
});
// full ⇒ overlay renders child + survives success and error reactions
testWidgets('aurisMotion overlay survives reactions', (tester) async {
  final controller = ThemeReactionController();
  final m = aurisMotion(reduceEffects: false);
  await tester.pumpWidget(MaterialApp(
    theme: appThemes[kAurisThemeId]!.builder(Brightness.dark),
    home: Builder(builder: (context) =>
        m.reactionOverlay(context, controller: controller, child: const Text('CHILD'))),
  ));
  expect(find.text('CHILD'), findsOneWidget);
  controller.emit(const ThemeReaction.success(statusCode: 200, durationMs: 120));
  await tester.pump(const Duration(milliseconds: 16));
  controller.emit(const ThemeReaction.serverError(statusCode: 500, durationMs: 4000));
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
});
```
(Confirm `ThemeReaction` constructor names + `ThemeReactionController.emit` against `lib/core/theme/motion/`; adapt if the API differs — e.g. existing motion tests show the exact calls.)

- [ ] **Step 2: Run → fails.** Run: `fvm flutter test test/core/theme/themes/auris/auris_motion_test.dart`.
- [ ] **Step 3: Implement `aurisMotion`** + the two private widgets per the guidance, copying the structure of `glass_motion.dart`.
- [ ] **Step 4:** Swap into `auris_theme.dart`. Run the motion test → PASS.
- [ ] **Step 5: Commit** `feat(theme): AURIS loud HUD motion (reactions + send affordance)`.

### Task E2: `auris_decorations.dart` — ambient scaffold + press

**Files:** Create `lib/core/theme/themes/auris/auris_decorations.dart`; Modify `auris_theme.dart` (`decoration.scaffoldBackground` → animated/static auris ambient; `wrapInteractive` → auris press); Test `test/core/theme/themes/auris/auris_ambient_test.dart`.

- [ ] **Step 1: Write the test** — pump the animated scaffold background, `pump` a few frames, `pumpAndSettle`, dispose (pump empty), assert no exception; pump the static variant (reduceEffects path) and assert it builds with no `AnimationController` (smoke: no exception, settles immediately).
- [ ] **Step 2: Run → fails.**
- [ ] **Step 3: Implement** `aurisScaffoldBackground` (animated: scanlines + drifting `AurisHexOrnament`, one `AnimationController`, `RepaintBoundary`, lifecycle-paused, frame-quantized; any repeating flash via `safeFlashCount`) and `aurisStaticScaffoldBackground` (no controller). Implement an auris press wrapper for `wrapInteractive` (glow/press; identity-ish under `reduceEffects`). Wire both into `auris_theme.dart`, selecting static under `reduceEffects`.
- [ ] **Step 4: Run → passes.**
- [ ] **Step 5:** Full gate + commit `feat(theme): AURIS ambient background + press`.

### Task E3: (optional) AURIS sound asset dir

**Files:** Modify `pubspec.yaml`.
- [ ] Register `assets/sounds/auris/` (the sound service no-ops if files absent). Create the dir with a `.gitkeep`. Commit `chore: register AURIS sound asset dir (placeholder)`. (Skip if assets policy disallows empty dirs — note it.)

---

## Phase F — Finalization

### Task F1: Full regression + manual run

- [ ] Run the complete gate: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format --output=none --set-exit-if-changed lib test tools && fvm flutter test`. All 0 / green.
- [ ] `fvm flutter build web` — confirm auris builds on web (fonts/CanvasKit). If a slot misbehaves on web, fall that slot back to default for web only and note it in code.
- [ ] `fvm flutter run -d macos` — switch to AURIS (Settings → APPEARANCE and via Cmd/Ctrl+K theme jump), exercise: send (reticle), 200 (sweep), 500 (alarm), realtime log, a dropdown, dark/light, reduceEffects on/off. Confirm no jank/throw.
- [ ] Commit nothing if clean; otherwise fix-forward with focused commits.

### Task F2: Backlog + wiki + memory

**Files:** Modify `docs/BACKLOG.md`; the `Getman.wiki.git` Themes page.
- [ ] Add a `docs/BACKLOG.md` item under **🎨 Themes, Visuals & Motion**: "Give the other six themes bespoke `AppComponents` implementations (brutalist/rpg/glass/etc.) now that the slot system exists." Commit `docs: backlog item for per-theme component implementations`.
- [ ] Clone/pull `https://github.com/thiagomiranda3/Getman.wiki.git`, update the Themes page: add **AURIS** (look: amber-on-near-black sci-fi HUD, chamfered auris widgets, mono fonts; behavior: loud HUD reactions — send reticle, success sweep, error alarm; supports light+dark; honors Reduce Visual Effects). Update `_Sidebar.md` if needed. Commit + push (`master`).
- [ ] (Maintainer step) Update CLAUDE.md §2 theme list + §4.8 if the component-slot system warrants a doc line; and add a memory file noting the AURIS theme + `AppComponents` slot system shipped.

---

## Self-Review

**Spec coverage:**
- §3 `AppComponents` + types + accessor → A1. ✅
- §3.2 generic dropdown → A4. ✅
- §3.3 shared defaults → A2; attached to 6 themes → A3. ✅
- §3.4 consumer refactor → B1–B7. ✅
- §4.1 builder composition (preserve `AurisScheme`) → C2 (`...base.extensions.values`). ✅
- §4.2 palette/type/shape from scheme → C2 (`aurisPalette`). ✅
- §4.3 loud HUD motion + flash safety + reduceEffects → E1, E2. ✅
- §4.4 registry (id/displayName/not-default/dark+light) → C2 + test. ✅
- §5 dependency + sounds → C1, E3. ✅
- §6 safety (unwrap guard test, pre-1.0 isolation, web) → D1 Step 5, C1, F1. ✅
- §7 tests → each task's test + F1. ✅
- §8 out of scope → F2 backlog. ✅
- §9 wiki → F2. ✅

**Placeholder scan:** auris-widget code blocks intentionally reference C1-verified names (the package is pre-1.0; C1 is the gate that turns sketches into exact signatures — this is called out explicitly, not a hidden TODO). The `/* … */` in C2 Step 3c are filled from C1 notes + existing decoration patterns; flagged inline. All Getman-side code is complete.

**Type consistency:** slot names (`surface/methodBadge/statusBadge/metric/toggle/logView/dataRow/select/pendingIndicator/statusBanner`) are identical across A1, A2, A3 test, B1–B7, D1. `AppSelectSpec`/`AppSelectItem`/`AppLogLine`/`AppBannerState` used consistently in A1, A2, A4, D1. `kAurisThemeId`/`aurisTheme`/`aurisComponents`/`aurisMotion` consistent across C2, D1, E1.

**Risk:** the only place this plan cannot be 100% verbatim is the external pre-1.0 `auris` API; Task C1 resolves that before any auris code is written, and all auris usage is quarantined to `lib/core/theme/themes/auris/`.
