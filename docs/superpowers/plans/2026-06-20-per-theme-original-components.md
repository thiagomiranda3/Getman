# Per-Theme Original Components (VM-F1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Brutalist, Arcane Quest, Liquid Glass, Editorial, and Dracula their own bespoke `AppComponents` widget sets (Classic stays on defaults), so each theme feels like an original product — built through the existing slot seam with no app-widget edits.

**Architecture:** Each customized theme gets `lib/core/theme/themes/<name>/<name>_components.dart` exporting `AppComponents <name>Components({bool reduceEffects})` = `defaultAppComponents().copyWith(...)`, overriding only the high-personality slots and inheriting the rest. The theme builder attaches it instead of `defaultAppComponents()`. Every app consumer already reads `context.appComponents.<slot>`, so no consumer changes.

**Tech Stack:** Flutter, `flutter_bloc`, theme `ThemeExtension`s. Tests: `flutter_test` + `mocktail`. Reference implementation: `lib/core/theme/themes/auris/auris_components.dart` and its test `test/core/theme/themes/auris/auris_components_test.dart`.

## Global Constraints

- **No app-widget edits.** Only `lib/core/theme/themes/<name>/` files + their tests change. Verified consumers (all already route through the slot): `lib/core/ui/widgets/method_badge.dart`, `lib/core/ui/widgets/app_dropdown.dart`, `lib/features/tabs/presentation/widgets/request_config_section.dart`, `.../response_section.dart`, `.../unified_request_panel.dart`, `.../response/response_headers_view.dart`, `.../response/response_cookies_view.dart`, `lib/features/settings/presentation/widgets/settings_dialog.dart`, `lib/features/updates/presentation/widgets/update_settings_section.dart`, `lib/features/realtime/presentation/widgets/realtime_panel.dart`.
- **`select` slot is inherited by every theme** (unwired in-app today — VM-F2). Never override it here.
- **`surface` must fill** — it is called without a title from inside an `Expanded`; the child must still fill (forward tight constraints; never shrink-wrap a fill-wanting child).
- **`logView` must size to available height** — it lives in an `Expanded`; use a `LayoutBuilder`, subtract header chrome when height is bounded.
- **`metric` must stay a compact inline chip** — it sits in the response-metadata horizontal `Wrap`; fold `unit`/`delta` into the value text.
- **`reduceEffects` degrades all animation to static.** Builders that animate take `{bool reduceEffects = false}` and render a still variant when true. The theme builder passes `<name>Components(reduceEffects: reduceEffects)`.
- **Flash safety (WCAG 2.3.1):** any repeating blink ≤ 3 Hz. Only Dracula's cursor blinks (held ≤ 1.5 Hz).
- **Lint:** files under `lib/core/theme/themes/<name>/` are exempt from `avoid_hardcoded_brand_colors` (that rule is scoped outside `lib/core/theme/`), so theme palette constants and effect literals are allowed. No `data/` imports, no `GetIt`/`sl`, no BLoC imports. `package:getman/...` absolute imports only.
- **Done-bar (run before every commit; the `.githooks/pre-commit` hook also runs the first four):** `fvm flutter analyze` (0 issues) + `fvm dart run custom_lint` (0 issues) + `fvm dart run bloc_tools:bloc lint lib` (0 issues) + `fvm dart format lib test tools` clean + `fvm flutter test` green.
- **Calm/loud contrast (THEME_AUTHORING §2):** Editorial & Dracula stay restrained (no shake/heavy motion; a static glow + a ≤1.5 Hz cursor are the only "motion"). Classic is untouched.

---

## File map

| File | Responsibility |
|---|---|
| `lib/core/theme/themes/brutalist/brutalist_components.dart` | **NEW** — `brutalistComponents({reduceEffects})` + its private widgets |
| `lib/core/theme/themes/brutalist/brutalist_theme.dart` | **MODIFY** — attach `brutalistComponents(...)` |
| `test/core/theme/themes/brutalist/brutalist_components_test.dart` | **NEW** — per-slot smoke + overflow guard + reduceEffects |
| `lib/core/theme/themes/rpg/rpg_components.dart` | **NEW** |
| `lib/core/theme/themes/rpg/rpg_theme.dart` | **MODIFY** |
| `test/core/theme/themes/rpg/rpg_components_test.dart` | **NEW** |
| `lib/core/theme/themes/glass/glass_components.dart` | **NEW** |
| `lib/core/theme/themes/glass/glass_theme.dart` | **MODIFY** |
| `test/core/theme/themes/glass/glass_components_test.dart` | **NEW** |
| `lib/core/theme/themes/editorial/editorial_components.dart` | **NEW** |
| `lib/core/theme/themes/editorial/editorial_theme.dart` | **MODIFY** |
| `test/core/theme/themes/editorial/editorial_components_test.dart` | **NEW** |
| `lib/core/theme/themes/dracula/dracula_components.dart` | **NEW** |
| `lib/core/theme/themes/dracula/dracula_theme.dart` | **MODIFY** |
| `test/core/theme/themes/dracula/dracula_components_test.dart` | **NEW** |

Classic: no changes.

The generic `test/core/theme/theme_has_components_test.dart` already asserts every theme attaches `AppComponents` — no change.

---

## Slot signatures (from `lib/core/theme/extensions/app_components.dart`)

Every `<name>_components.dart` overrides closures with these exact shapes (copy verbatim):

```dart
Widget surface(BuildContext context, {required Widget child, String? title, String? code, bool accent});
Widget methodBadge(BuildContext context, {required String method, bool small});
Widget statusBadge(BuildContext context, {required int statusCode});
Widget metric(BuildContext context, {required String label, required String value, String? unit, String? delta});
Widget toggle(BuildContext context, {required bool value, required ValueChanged<bool> onChanged, String? label});
Widget logView(BuildContext context, {required List<AppLogLine> lines, String? title, ScrollController? controller});
Widget dataRow(BuildContext context, {required String label, required String value, bool highlight});
Widget statusBanner(BuildContext context, {required AppBannerState state, required String message});
Widget pendingIndicator(BuildContext context, {String? label});
```

`AppLogLine` has `.text` (String) and `.kind` (`AppLogLineKind.{outgoing,incoming,open,close,error}`). `AppBannerState` = `{info, success, warning, error}`. Pull colors/sizes/weights from `context.appPalette` / `context.appLayout` / `context.appShape` / `context.appTypography` where a shared value exists; theme palette constants are allowed for effect-specific literals.

Useful palette/layout accessors (already used in `app_components_defaults.dart`): `context.appPalette.methodColor(method)`, `.methodOn(method)`, `.statusColor(code)`, `.statusAccent(code)`, `.onColor(color)`, `.statusSuccess/.statusError/.statusWarning`; `context.appLayout.borderThin/.borderHeavy/.fontSizeSmall/.fontSizeNormal/.fontSizeCode/.smallIconSize/.isCompact/.tabSpacing/.badgePaddingHorizontal/.badgePaddingVertical`; `context.appShape.panelRadius`; `context.appTypography.displayWeight/.titleWeight/.bodyWeight/.codeFontFamily`.

---

## Phase 1 — Brutalist (FLAGSHIP) 🟥

Concept: ink-press / risograph print shop. Hard borders, hard offset shadows, uppercase, mono accents, a stuck-on header label, ink-stamp badges, a fanfold line-printer log, a chunky snap switch.

### Task 1: Brutalist component set

**Files:**
- Create: `lib/core/theme/themes/brutalist/brutalist_components.dart`
- Modify: `lib/core/theme/themes/brutalist/brutalist_theme.dart` (swap the `defaultAppComponents()` entry)
- Test: `test/core/theme/themes/brutalist/brutalist_components_test.dart`

**Interfaces:**
- Produces: `AppComponents brutalistComponents({bool reduceEffects = false})`; public widget types tests find: `BrutalSlab`, `BrutalStamp`, `BrutalTickerChip`, `BrutalSwitch`, `BrutalFanfoldLog`, `BrutalPrintedRow`, `BrutalPressIndicator`, `BrutalStampBanner`.
- Consumes: `defaultAppComponents()` (inherited slots), `AppComponents`, `AppLogLine`, `AppBannerState` from `app_components.dart`; `context.app*` accessors from `app_theme.dart`.

- [ ] **Step 1: Write the failing smoke test (one slot) to prove the wiring**

Create `test/core/theme/themes/brutalist/brutalist_components_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_components.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget Function(BuildContext) build, {
  double width = 400,
  double height = 200,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: Builder(builder: build)),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  final dark = brutalistTheme(Brightness.dark);

  testWidgets('methodBadge → BrutalStamp', (tester) async {
    await _pump(tester, dark,
        (c) => c.appComponents.methodBadge(c, method: 'GET'));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalStamp), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it — expect a COMPILE failure**

Run: `fvm flutter test test/core/theme/themes/brutalist/brutalist_components_test.dart`
Expected: FAIL — `brutalist_components.dart` / `BrutalStamp` does not exist yet.

- [ ] **Step 3: Create `brutalist_components.dart` with all slots**

Create `lib/core/theme/themes/brutalist/brutalist_components.dart`:

```dart
// Brutalist component-slot overrides — "ink-press / risograph print shop".
// Hard borders, hard offset shadows, uppercase, mono accents. Built as
// defaultAppComponents().copyWith(...) so unlisted slots (select) inherit.
//
// Rules: no data/GetIt/BLoC imports; theme palette constants allowed
// (file is under lib/core/theme/, exempt from avoid_hardcoded_brand_colors).

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';

AppComponents brutalistComponents({bool reduceEffects = false}) {
  return defaultAppComponents().copyWith(
    surface: _surface,
    methodBadge: (context, {required method, small = false}) =>
        BrutalStamp(text: method, color: context.appPalette.methodColor(method)),
    statusBadge: (context, {required statusCode}) => BrutalStamp(
      text: '$statusCode',
      color: context.appPalette.statusColor(statusCode),
      label: 'STATUS',
    ),
    metric: (context, {required label, required value, unit, delta}) =>
        BrutalTickerChip(label: label, value: [
          if (unit != null) '$value $unit' else value,
          if (delta != null) delta,
        ].join('  ')),
    toggle: (context, {required value, required onChanged, label}) =>
        BrutalSwitch(value: value, onChanged: onChanged, label: label, animate: !reduceEffects),
    logView: (context, {required lines, title, controller}) =>
        BrutalFanfoldLog(lines: lines, controller: controller),
    dataRow: (context, {required label, required value, highlight = false}) =>
        BrutalPrintedRow(label: label, value: value, highlight: highlight),
    pendingIndicator: (context, {label}) =>
        BrutalPressIndicator(label: label ?? 'PRINTING…', animate: !reduceEffects),
    statusBanner: (context, {required state, required message}) =>
        BrutalStampBanner(state: state, message: message),
  );
}

Widget _surface(BuildContext context,
    {required Widget child, String? title, String? code, bool accent = false}) {
  return BrutalSlab(title: title, child: child);
}

// --- surface -------------------------------------------------------------
class BrutalSlab extends StatelessWidget {
  const BrutalSlab({required this.child, this.title, super.key});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final slab = DecoratedBox(
      decoration: context.appDecoration.panelBox(context, offset: 0),
      child: child,
    );
    if (title == null) return slab;
    // Stuck-on header label: an offset, hard-shadowed tag over the slab.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StuckLabel(title!),
        Expanded(child: slab),
      ],
    );
  }
}

class _StuckLabel extends StatelessWidget {
  const _StuckLabel(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.primaryColor,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
        boxShadow: [BoxShadow(color: theme.dividerColor, offset: Offset(layout.borderHeavy, layout.borderHeavy))],
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeSmall,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// --- ink stamp (method + status) ----------------------------------------
class BrutalStamp extends StatelessWidget {
  const BrutalStamp({required this.text, required this.color, this.label, super.key});
  final String text;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final on = context.appPalette.onColor(color);
    return Container(
      margin: label != null ? EdgeInsets.only(right: layout.isCompact ? 8 : 12) : EdgeInsets.zero,
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: layout.borderHeavy),
        boxShadow: [BoxShadow(color: theme.dividerColor, offset: Offset(layout.borderHeavy, layout.borderHeavy))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Text('$label: ',
                style: TextStyle(color: on, fontSize: layout.fontSizeSmall, fontWeight: context.appTypography.titleWeight)),
          Text(text.toUpperCase(),
              style: TextStyle(color: on, fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.displayWeight, letterSpacing: 1)),
        ],
      ),
    );
  }
}

// --- metric (inline ticker chip, NO shadow → fits the Wrap) -------------
class BrutalTickerChip extends StatelessWidget {
  const BrutalTickerChip({required this.label, required this.value, super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${label.toUpperCase()} ',
              style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: context.appTypography.titleWeight, color: theme.colorScheme.onSurface)),
          Text(value,
              style: TextStyle(fontFamily: context.appTypography.codeFontFamily, fontSize: layout.fontSizeNormal, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }
}

// --- chunky snap switch -------------------------------------------------
class BrutalSwitch extends StatelessWidget {
  const BrutalSwitch({required this.value, required this.onChanged, this.label, this.animate = true, super.key});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final track = GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 56,
        height: 28,
        decoration: BoxDecoration(
          color: value ? theme.primaryColor : theme.cardColor,
          border: Border.all(color: theme.dividerColor, width: layout.borderThin),
        ),
        child: AnimatedAlign(
          duration: animate ? const Duration(milliseconds: 90) : Duration.zero,
          curve: Curves.easeOutBack,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              border: Border.all(color: theme.dividerColor, width: layout.borderThin),
              boxShadow: [BoxShadow(color: theme.dividerColor, offset: const Offset(2, 2))],
            ),
          ),
        ),
      ),
    );
    if (label == null) return track;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label!, style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.bodyWeight, color: theme.colorScheme.onSurface)),
      const SizedBox(width: 8),
      track,
    ]);
  }
}

// --- fanfold line-printer log -------------------------------------------
class BrutalFanfoldLog extends StatelessWidget {
  const BrutalFanfoldLog({required this.lines, this.controller, super.key});
  final List<AppLogLine> lines;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      itemCount: lines.length,
      itemBuilder: (context, i) => _FanfoldRow(line: lines[i], even: i.isEven),
    );
  }
}

class _FanfoldRow extends StatelessWidget {
  const _FanfoldRow({required this.line, required this.even});
  final AppLogLine line;
  final bool even;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final glyph = switch (line.kind) {
      AppLogLineKind.outgoing => '▲',
      AppLogLineKind.incoming => '▼',
      AppLogLineKind.open => '⊕',
      AppLogLineKind.close => '⊗',
      AppLogLineKind.error => '✕',
    };
    return Container(
      color: even ? theme.cardColor : theme.dividerColor.withValues(alpha: 0.08),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Tractor-feed hole margin.
        Container(
          width: 18,
          decoration: BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor, width: layout.borderThin))),
          child: Center(child: Text('•', style: TextStyle(color: theme.dividerColor))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(glyph, style: TextStyle(fontFamily: context.appTypography.codeFontFamily, color: theme.colorScheme.onSurface)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText(line.text,
                style: TextStyle(fontFamily: context.appTypography.codeFontFamily, fontSize: layout.fontSizeCode, color: theme.colorScheme.onSurface)),
          ),
        ),
      ]),
    );
  }
}

// --- printed data row ----------------------------------------------------
class BrutalPrintedRow extends StatelessWidget {
  const BrutalPrintedRow({required this.label, required this.value, this.highlight = false, super.key});
  final String label;
  final String value;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor, width: layout.borderThin))),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: theme.primaryColor, border: Border.all(color: theme.dividerColor, width: layout.borderThin)),
          child: Text(label, style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: context.appTypography.titleWeight, fontSize: layout.fontSizeSmall)),
        ),
        Expanded(
          child: SelectableText(value,
              style: TextStyle(fontFamily: context.appTypography.codeFontFamily, fontSize: layout.fontSizeNormal, fontWeight: highlight ? context.appTypography.titleWeight : null, color: theme.colorScheme.onSurface)),
        ),
      ]),
    );
  }
}

// --- pending: hard block-shimmer ("press run") --------------------------
class BrutalPressIndicator extends StatefulWidget {
  const BrutalPressIndicator({required this.label, this.animate = true, super.key});
  final String label;
  final bool animate;
  @override
  State<BrutalPressIndicator> createState() => _BrutalPressIndicatorState();
}

class _BrutalPressIndicatorState extends State<BrutalPressIndicator> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    }
  }
  @override
  void dispose() { _c?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final blocks = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: TextStyle(fontFamily: context.appTypography.codeFontFamily, fontWeight: context.appTypography.displayWeight, color: theme.colorScheme.onSurface)),
      const SizedBox(height: 12),
      for (var i = 0; i < 6; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(height: 18, decoration: BoxDecoration(color: theme.cardColor, border: Border.all(color: theme.dividerColor, width: layout.borderThin))),
        ),
    ]);
    if (_c == null) return Padding(padding: const EdgeInsets.all(16), child: blocks);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _c!,
        child: blocks,
        builder: (context, child) => Opacity(opacity: 0.6 + 0.4 * (1 - (_c!.value - 0.5).abs() * 2), child: child),
      ),
    );
  }
}

// --- stamped status banner ----------------------------------------------
class BrutalStampBanner extends StatelessWidget {
  const BrutalStampBanner({required this.state, required this.message, super.key});
  final AppBannerState state;
  final String message;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final palette = context.appPalette;
    final color = switch (state) {
      AppBannerState.success => palette.statusSuccess,
      AppBannerState.error => palette.statusError,
      AppBannerState.warning => palette.statusWarning,
      AppBannerState.info => theme.colorScheme.secondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: layout.borderHeavy),
        boxShadow: [BoxShadow(color: theme.dividerColor, offset: Offset(layout.borderHeavy, layout.borderHeavy))],
      ),
      child: Text(message.toUpperCase(),
          style: TextStyle(color: palette.onColor(color), fontWeight: context.appTypography.displayWeight, fontSize: layout.fontSizeNormal, letterSpacing: 1)),
    );
  }
}
```

- [ ] **Step 4: Wire it into the theme builder**

In `lib/core/theme/themes/brutalist/brutalist_theme.dart`:
- Add import: `import 'package:getman/core/theme/themes/brutalist/brutalist_components.dart';`
- Remove the now-unused `import '.../app_components_defaults.dart';` **only if** nothing else uses it (it isn't — the only use was `defaultAppComponents()`).
- In the `extensions: [...]` list, replace `defaultAppComponents(),` with `brutalistComponents(reduceEffects: reduceEffects),`.

- [ ] **Step 5: Run the smoke test — expect PASS**

Run: `fvm flutter test test/core/theme/themes/brutalist/brutalist_components_test.dart`
Expected: PASS.

- [ ] **Step 6: Add the full slot-smoke, overflow-guard, and reduceEffects tests**

Append the following tests inside `main()` (after the existing `methodBadge` test). This is the per-theme test battery — adapt the bespoke type names per theme in later phases.

```dart
  testWidgets('statusBadge → BrutalStamp', (tester) async {
    await _pump(tester, dark, (c) => c.appComponents.statusBadge(c, statusCode: 200));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalStamp), findsWidgets);
  });

  testWidgets('surface (no title) fills + no overflow', (tester) async {
    await _pump(tester, dark, (c) => c.appComponents.surface(c, child: const Text('BODY')));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalSlab), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('surface (title) shows stuck label', (tester) async {
    await _pump(tester, dark, (c) => c.appComponents.surface(c, title: 'PANEL', child: const Text('B')));
    expect(tester.takeException(), isNull);
    expect(find.text('PANEL'), findsOneWidget);
  });

  testWidgets('metric is inline-safe in a tight Wrap', (tester) async {
    await _pump(tester, dark, width: 300, height: 60,
        (c) => Wrap(children: [
              c.appComponents.statusBadge(c, statusCode: 200),
              c.appComponents.metric(c, label: 'TIME', value: '42', unit: 'ms'),
              c.appComponents.metric(c, label: 'SIZE', value: '1.2', unit: 'KB'),
            ]));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalTickerChip), findsNWidgets(2));
  });

  testWidgets('toggle → BrutalSwitch (tap flips)', (tester) async {
    var v = false;
    await _pump(tester, dark, (c) => StatefulBuilder(
        builder: (c, setState) => c.appComponents.toggle(c, value: v, label: 'X',
            onChanged: (n) => setState(() => v = n))));
    await tester.tap(find.byType(BrutalSwitch));
    await tester.pumpAndSettle();
    expect(v, isTrue);
  });

  testWidgets('logView sizes to bounded height (no overflow)', (tester) async {
    await _pump(tester, dark, height: 80,
        (c) => c.appComponents.logView(c, title: 'LOG', lines: const [
              AppLogLine(text: 'a', kind: AppLogLineKind.outgoing),
              AppLogLine(text: 'b', kind: AppLogLineKind.incoming),
            ]));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalFanfoldLog), findsOneWidget);
  });

  testWidgets('dataRow → BrutalPrintedRow', (tester) async {
    await _pump(tester, dark, (c) => c.appComponents.dataRow(c, label: 'a', value: 'b'));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalPrintedRow), findsOneWidget);
  });

  testWidgets('statusBanner → BrutalStampBanner', (tester) async {
    await _pump(tester, dark, (c) => c.appComponents.statusBanner(c, state: AppBannerState.success, message: 'OK'));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalStampBanner), findsOneWidget);
  });

  testWidgets('pendingIndicator animates then disposes cleanly', (tester) async {
    await _pump(tester, dark, (c) => c.appComponents.pendingIndicator(c));
    expect(find.byType(BrutalPressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduceEffects: pending + switch render static (no ticker)', (tester) async {
    final reduced = brutalistTheme(Brightness.dark, reduceEffects: true);
    await _pump(tester, reduced, (c) => Column(children: [
          SizedBox(height: 120, child: c.appComponents.pendingIndicator(c)),
          c.appComponents.toggle(c, value: true, onChanged: (_) {}, label: 'X'),
        ]));
    expect(tester.takeException(), isNull);
    // Static pending indicator schedules no frames: pumpAndSettle returns at once.
    await tester.pumpAndSettle();
    expect(find.byType(BrutalPressIndicator), findsOneWidget);
  });
```

- [ ] **Step 7: Add the real-widget overflow guard (ResponseSection + RealtimePanel)**

Add this block to the test file. Copy the mock/fake scaffolding and the two render tests from `test/core/theme/themes/auris/auris_components_test.dart` **verbatim** (lines ~50–119 for mocks/fakes/`_respondedTab`/`_loadedBloc`/`_settingsBloc`, and the two `testWidgets` render tests at ~341–450), changing only: the theme to `brutalistTheme(Brightness.dark)`, and replacing the AURIS-specific final asserts (`find.byType(AurisTerminal)` / `AurisNotification`) with `expect(tester.takeException(), isNull);` plus `expect(find.byType(BrutalFanfoldLog), findsOneWidget);` and `expect(find.byType(BrutalStampBanner), findsOneWidget);` in the RealtimePanel test. These imports are needed (copy from the AURIS test): `flutter_bloc`, `mocktail`, `re_editor`, the bloc/entity/usecase imports, `ResponseSection`, `RealtimePanel`.

This guard is what caught real overflow in AURIS; do not skip it.

- [ ] **Step 8: Run the full test file — expect PASS**

Run: `fvm flutter test test/core/theme/themes/brutalist/brutalist_components_test.dart`
Expected: PASS (all tests green, no `takeException`).

- [ ] **Step 9: Run the full done-bar**

Run:
```
fvm dart format lib test tools
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```
Expected: format clean, analyze 0 issues, custom_lint 0 issues, bloc lint 0 issues, all tests green.

- [ ] **Step 10: Commit**

```bash
git add lib/core/theme/themes/brutalist/brutalist_components.dart \
        lib/core/theme/themes/brutalist/brutalist_theme.dart \
        test/core/theme/themes/brutalist/brutalist_components_test.dart
git commit -m "feat(theme): brutalist bespoke components (ink-press slot set)"
```

### 🔔 REVIEW GATE — stop here

Brutalist is the flagship. **Pause and have the user run the app on the Brutalist theme** (`fvm flutter run -d macos`, switch to BRUTALIST) and confirm the direction (slab panels + stuck labels, ink-stamp badges, fanfold log, snap switch) before building the other four. Apply any direction changes here first, then proceed.

---

## Phase 2 — Arcane Quest (rpg) 🟪

Concept: spellbook / RPG screen — runic-framed parchment panels, a faceted gem status badge, a grimoire scroll log, an enchanted lever, a summoning-ring pending state.

### Task 2: Arcane Quest component set

**Files:**
- Create: `lib/core/theme/themes/rpg/rpg_components.dart`
- Modify: `lib/core/theme/themes/rpg/rpg_theme.dart`
- Test: `test/core/theme/themes/rpg/rpg_components_test.dart`

**Interfaces:**
- Produces: `AppComponents rpgComponents({bool reduceEffects = false})`; widget types: `RunicPanel`, `RunePlateBadge`, `GemBadge`, `RunestoneChip`, `EnchantedLever`, `GrimoireLog`, `QuestLedgerRow`, `SummoningRing`, `HeraldicBanner`.

- [ ] **Step 1:** Read `lib/core/theme/themes/brutalist/brutalist_components.dart` (the just-built reference) for the file shape, the `copyWith` slot wiring, and the `reduceEffects` plumbing; read `lib/core/theme/themes/rpg/rpg_palette.dart` + `rpg_sparkle.dart` for the theme's rune/parchment colors and existing painters to reuse.

- [ ] **Step 2: Write the failing smoke test**

Create `test/core/theme/themes/rpg/rpg_components_test.dart` using the same `_pump` helper as Brutalist Step 1 (copy it), importing `rpg_theme.dart` + `rpg_components.dart`, with a first test:
```dart
  testWidgets('statusBadge → GemBadge', (tester) async {
    await _pump(tester, rpgTheme(Brightness.dark),
        (c) => c.appComponents.statusBadge(c, statusCode: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(GemBadge), findsOneWidget);
  });
```

- [ ] **Step 3: Run it — expect COMPILE failure** (`rpg_components.dart` missing).
Run: `fvm flutter test test/core/theme/themes/rpg/rpg_components_test.dart`

- [ ] **Step 4: Create `rpg_components.dart`** with `rpgComponents({reduceEffects})` overriding `surface/methodBadge/statusBadge/metric/toggle/logView/dataRow/pendingIndicator/statusBanner`, following the Brutalist file's structure. Slot specs:
  - **`RunicPanel`** (surface): parchment-tinted `Container` (use the rpg palette's parchment/surface color); a `CustomPaint` border with simple rune/flourish corner marks (a static `CustomPainter` — build the `Path` once, reuse the `Paint`). Titled → an engraved header banner row above the child; untitled → fill the child (forward constraints, wrap child in `Expanded` only inside a `Column` with a bounded parent; for the no-title path return the painted container directly so it fills).
  - **`RunePlateBadge`** (methodBadge): a small heraldic plate; method color = `context.appPalette.methodColor(method)`.
  - **`GemBadge`** (statusBadge): a faceted gem via `CustomPainter` (a hexagon/diamond polygon + a lighter facet highlight triangle). Color by class: `statusColor(statusCode)`; render the code centered. Keep ≤ ~40px tall so it sits inline.
  - **`RunestoneChip`** (metric): a small engraved stone tablet, inline-safe (no large tile); fold unit/delta into the value.
  - **`EnchantedLever`** (toggle): a lever that tilts up/down on toggle; a rune glow (a `BoxShadow`/radial) when on, **static glow** when `reduceEffects` (no animation). Tap flips.
  - **`GrimoireLog`** (logView): `ListView.builder`, each row a grimoire entry — a rune bullet (colored by kind) + mono payload, parchment row ground. `LayoutBuilder`-free is fine (a plain `ListView` fills its bounded `Expanded`), like the Brutalist fanfold log.
  - **`QuestLedgerRow`** (dataRow): rune bullet + engraved small-caps key + mono value + a thin parchment rule.
  - **`SummoningRing`** (pendingIndicator): a single looping `AnimationController` rotating a rune ring `CustomPainter` (centered, `RepaintBoundary`); disposes on unmount. When `reduceEffects`, render a **static** ring (no controller). Mirror `BrutalPressIndicator`'s `_c == null` static path.
  - **`HeraldicBanner`** (statusBanner): a ribbon-styled bar; color by `AppBannerState` like `BrutalStampBanner`.

- [ ] **Step 5: Wire** `rpgComponents(reduceEffects: reduceEffects)` into `rpg_theme.dart`'s `extensions:` list (replace `defaultAppComponents()`; drop the now-unused defaults import if unused).

- [ ] **Step 6: Run the smoke test — expect PASS.**

- [ ] **Step 7: Add the full battery** — copy the Brutalist Step 6 + Step 7 test blocks, swapping bespoke type names (`GemBadge`, `RunicPanel`, `RunestoneChip`, `EnchantedLever`, `GrimoireLog`, `QuestLedgerRow`, `HeraldicBanner`, `SummoningRing`) and the theme (`rpgTheme`). Keep the inline-Wrap metric test, the bounded-height logView test, the reduceEffects static test (assert the summoning ring renders and `pumpAndSettle` returns under reduceEffects), and the ResponseSection + RealtimePanel overflow guards.

- [ ] **Step 8: Run the test file — expect PASS.**
Run: `fvm flutter test test/core/theme/themes/rpg/rpg_components_test.dart`

- [ ] **Step 9: Run the full done-bar** (same five commands as Task 1 Step 9). Expected: all clean/green.

- [ ] **Step 10: Commit**
```bash
git add lib/core/theme/themes/rpg/rpg_components.dart lib/core/theme/themes/rpg/rpg_theme.dart test/core/theme/themes/rpg/rpg_components_test.dart
git commit -m "feat(theme): arcane quest bespoke components (spellbook slot set)"
```

---

## Phase 3 — Liquid Glass (glass) 🟦

Concept: visionOS frosted HUD — frosted glass tiles (reuse the theme's real blur), translucent lozenge badges, a liquid-glass switch, a blurred terminal log.

### Task 3: Liquid Glass component set

**Files:**
- Create: `lib/core/theme/themes/glass/glass_components.dart`
- Modify: `lib/core/theme/themes/glass/glass_theme.dart`
- Test: `test/core/theme/themes/glass/glass_components_test.dart`

**Interfaces:**
- Produces: `AppComponents glassComponents({bool reduceEffects = false})`; widget types: `FrostedTile`, `GlassLozenge`, `FrostedLozengeMetric`, `LiquidSwitch`, `BlurredTerminalLog`, `GlassDataRow`, `FrostedRipple`, `FrostedCapsuleBanner`.

- [ ] **Step 1:** Read `glass_components.dart`'s siblings: `glass_decorations.dart` (for `glassFrost` / `glassPanelBox` and how blur is applied + the `reduceEffects` identity-frost path), `glass_palette.dart` (accent/panel/border/text colors). Note: prefer reading the frost via `context.appDecoration.frost` (already identity under `reduceEffects`) so blur auto-degrades — you usually do NOT need to thread `reduceEffects` into the surface/log slots; only the liquid-switch squish and the ripple need the flag. Read the Brutalist reference file for the slot-wiring shape.

- [ ] **Step 2: Write the failing smoke test** (`glass_components_test.dart`, `_pump` helper copied), first test:
```dart
  testWidgets('surface (title) → FrostedTile', (tester) async {
    await _pump(tester, glassTheme(Brightness.dark),
        (c) => c.appComponents.surface(c, title: 'PANEL', child: const Text('B')));
    expect(tester.takeException(), isNull);
    expect(find.byType(FrostedTile), findsOneWidget);
  });
```

- [ ] **Step 3: Run it — expect COMPILE failure.**

- [ ] **Step 4: Create `glass_components.dart`.** Slot specs:
  - **`FrostedTile`** (surface): wrap child in the theme's frost (`context.appDecoration.frost?.call(context, child: ...)` if non-null, else the child) + a hairline specular border via `glassPanelBox`. Must fill: for the no-title path return the frosted box directly (forwarding constraints); titled → a floating translucent title chip above the child in a `Column` with `Expanded(child: ...)`.
  - **`GlassLozenge`** (method + status badge, shared with a color param): pill (`BorderRadius.circular(999)`), fill = color at low alpha, a specular top highlight (a `LinearGradient` white→transparent). Method color from `methodColor`; status from `statusColor`.
  - **`FrostedLozengeMetric`** (metric): a compact frosted pill, inline-safe, label + value.
  - **`LiquidSwitch`** (toggle): a frosted rounded track + a glossy circular thumb with a specular highlight; an `AnimatedAlign` thumb slide + a subtle scale "squish" when `animate` (reduceEffects=false); instant + no squish when reduced. Tap flips.
  - **`BlurredTerminalLog`** (logView): a frosted scroll surface (`ListView.builder` over rows with translucent direction pills + mono payload). Fills its bounded `Expanded`.
  - **`GlassDataRow`** (dataRow): translucent row + hairline divider; accent-tinted key.
  - **`FrostedRipple`** (pendingIndicator): a soft looping shimmer/ripple (single controller, disposes on unmount); **static frosted placeholder** when reduced (no controller).
  - **`FrostedCapsuleBanner`** (statusBanner): a rounded translucent capsule, color by state + subtle glow.
  - Builder signature: `glassComponents({bool reduceEffects = false})`; pass `reduceEffects` to `LiquidSwitch(animate: !reduceEffects)` and `FrostedRipple(animate: !reduceEffects)`.

- [ ] **Step 5: Wire** `glassComponents(reduceEffects: reduceEffects)` into `glass_theme.dart` (replace `defaultAppComponents()`).

- [ ] **Step 6: Run the smoke test — expect PASS.**

- [ ] **Step 7: Add the full battery** (copy Brutalist Step 6 + 7 blocks; swap types: `FrostedTile`, `GlassLozenge`, `FrostedLozengeMetric`, `LiquidSwitch`, `BlurredTerminalLog`, `GlassDataRow`, `FrostedCapsuleBanner`, `FrostedRipple`; theme `glassTheme`). Keep the inline-Wrap metric, bounded logView, reduceEffects-static, and the two overflow-guard render tests.

- [ ] **Step 8: Run the test file — expect PASS.**
Run: `fvm flutter test test/core/theme/themes/glass/glass_components_test.dart`

- [ ] **Step 9: Run the full done-bar.** Expected: all clean/green.

- [ ] **Step 10: Commit**
```bash
git add lib/core/theme/themes/glass/glass_components.dart lib/core/theme/themes/glass/glass_theme.dart test/core/theme/themes/glass/glass_components_test.dart
git commit -m "feat(theme): liquid glass bespoke components (frosted HUD slot set)"
```

---

## Phase 4 — Editorial 📰 (calm, restrained)

Concept: print magazine — article panels with hairline rules + serif headings, quiet typographic tags, footnote metrics, a dispatch log. **No animation/glow.**

### Task 4: Editorial component set

**Files:**
- Create: `lib/core/theme/themes/editorial/editorial_components.dart`
- Modify: `lib/core/theme/themes/editorial/editorial_theme.dart`
- Test: `test/core/theme/themes/editorial/editorial_components_test.dart`

**Interfaces:**
- Produces: `AppComponents editorialComponents()` (**no `reduceEffects` flag — Editorial introduces no animation**); widget types: `ArticlePanel`, `TypographicTag`, `FootnoteMetric`, `OutlinedSwitch`, `DispatchLog`, `ReferenceRow`, `EditorialNoteBar`. For `pendingIndicator`, render a quiet static `GalleyProof` (thin static lines) — no controller.

- [ ] **Step 1:** Read `editorial_palette.dart` (serif/typographic colors + accent) and the Brutalist reference for the slot-wiring shape. Note this builder takes **no** `reduceEffects` flag.

- [ ] **Step 2: Write the failing smoke test** (`editorial_components_test.dart`, `_pump` copied):
```dart
  testWidgets('dataRow → ReferenceRow', (tester) async {
    await _pump(tester, editorialTheme(Brightness.light),
        (c) => c.appComponents.dataRow(c, label: 'content-type', value: 'application/json'));
    expect(tester.takeException(), isNull);
    expect(find.byType(ReferenceRow), findsOneWidget);
  });
```

- [ ] **Step 3: Run it — expect COMPILE failure.**

- [ ] **Step 4: Create `editorial_components.dart`.** Slot specs (all static, restrained):
  - **`ArticlePanel`** (surface): thin hairline-rule frame (`Border.all` at `borderThin`), generous internal padding; titled → a serif section heading + an underline rule above the child (`Column` + `Expanded`). No-title → fill the child.
  - **`TypographicTag`** (method + status, shared): small-caps label in a hairline box, muted tint (use a low-alpha `methodColor`/`statusColor` fill or just a hairline box with colored text). Quiet — no shadow.
  - **`FootnoteMetric`** (metric): small-caps label + value separated by a thin vertical rule; inline-safe.
  - **`OutlinedSwitch`** (toggle): a thin-outlined minimal track + small thumb; `AnimatedAlign` slide is fine (motion-light, not a "glow"); tap flips. No flag needed.
  - **`DispatchLog`** (logView): `ListView.builder`; each row a small-caps source label (OUT/IN/OPEN/CLOSE/ERROR mapped from kind) + mono payload, hairline divider, airy leading. Fills bounded `Expanded`.
  - **`ReferenceRow`** (dataRow): small-caps key + readable value + a hairline rule between.
  - **`GalleyProof`** (pendingIndicator): a column of thin static lines (no animation) + a quiet label.
  - **`EditorialNoteBar`** (statusBanner): a quiet ruled bar with a small-caps label, muted color by state.

- [ ] **Step 5: Wire** `editorialComponents()` into `editorial_theme.dart` (replace `defaultAppComponents()`).

- [ ] **Step 6: Run the smoke test — expect PASS.**

- [ ] **Step 7: Add the full battery** (copy Brutalist Step 6 + 7; swap types: `ArticlePanel`, `TypographicTag`, `FootnoteMetric`, `OutlinedSwitch`, `DispatchLog`, `ReferenceRow`, `EditorialNoteBar`, `GalleyProof`; theme `editorialTheme`). **Drop the reduceEffects-static test's animation assertion** (Editorial has no animated slot) — instead assert `pendingIndicator` renders `GalleyProof` and `pumpAndSettle` returns immediately even at full effects. Keep inline-Wrap metric, bounded logView, and the two overflow guards.

- [ ] **Step 8: Run the test file — expect PASS.**

- [ ] **Step 9: Run the full done-bar.** Expected: all clean/green.

- [ ] **Step 10: Commit**
```bash
git add lib/core/theme/themes/editorial/editorial_components.dart lib/core/theme/themes/editorial/editorial_theme.dart test/core/theme/themes/editorial/editorial_components_test.dart
git commit -m "feat(theme): editorial bespoke components (magazine slot set)"
```

---

## Phase 5 — Dracula 🧛 (calm, restrained)

Concept: neon dev-console — console panels with a static purple edge-glow and `// title` headers, neon capsule badges, a dev-console log, a blinking-cursor pending line.

### Task 5: Dracula component set

**Files:**
- Create: `lib/core/theme/themes/dracula/dracula_components.dart`
- Modify: `lib/core/theme/themes/dracula/dracula_theme.dart`
- Test: `test/core/theme/themes/dracula/dracula_components_test.dart`

**Interfaces:**
- Produces: `AppComponents draculaComponents({bool reduceEffects = false})`; widget types: `ConsolePanel`, `NeonCapsule`, `TerminalMetric`, `ConsoleToggle`, `DevConsoleLog`, `ConsoleKvRow`, `BlinkingCursor`, `ConsoleStatusLine`.

- [ ] **Step 1:** Read `dracula_palette.dart` for the iconic accents (purple/pink/green/cyan/orange/red) + `dracula_press.dart`; read the Brutalist reference for the slot-wiring shape.

- [ ] **Step 2: Write the failing smoke test** (`dracula_components_test.dart`, `_pump` copied):
```dart
  testWidgets('logView → DevConsoleLog', (tester) async {
    await _pump(tester, draculaTheme(Brightness.dark), height: 80,
        (c) => c.appComponents.logView(c, title: 'LOG', lines: const [
              AppLogLine(text: 'GET /api', kind: AppLogLineKind.outgoing),
            ]));
    expect(tester.takeException(), isNull);
    expect(find.byType(DevConsoleLog), findsOneWidget);
  });
```

- [ ] **Step 3: Run it — expect COMPILE failure.**

- [ ] **Step 4: Create `dracula_components.dart`.** Slot specs (restrained; the only motion is the cursor blink):
  - **`ConsolePanel`** (surface): softly rounded dark panel; a **static** subtle purple edge-glow (a single soft `BoxShadow` in the accent — no animation); titled → a `// title` comment-style header in `codeFontFamily` above the child. No-title → fill the child.
  - **`NeonCapsule`** (method + status, shared): rounded pill (radius 999) in the relevant accent + a subtle static glow. Method colors from `methodColor`; status: green 2xx / cyan 3xx / orange 4xx / red 5xx (use `statusColor`).
  - **`TerminalMetric`** (metric): `label: value` in `codeFontFamily` with an accent-colored key; inline-safe.
  - **`ConsoleToggle`** (toggle): rounded track, accent fill + subtle glow when on; `AnimatedAlign` thumb slide; tap flips.
  - **`DevConsoleLog`** (logView): `ListView.builder`; each row a colored prefix glyph by kind (`→` outgoing / `←` incoming / `⊕` open / `⊗` close / `✗` error) in `codeFontFamily` + mono payload — REPL style. Fills bounded `Expanded`.
  - **`ConsoleKvRow`** (dataRow): `key:` in an accent color + mono value.
  - **`BlinkingCursor`** (pendingIndicator): an "awaiting response…" line with a block cursor `▋` blinking via a single `AnimationController` at **period ≥ 666ms (≤1.5 Hz)** — well under the 3 Hz WCAG cap. Under `reduceEffects`, render a **steady** (non-blinking) cursor (no controller). The blink toggles opacity 1↔0 once per period.
  - **`ConsoleStatusLine`** (statusBanner): a `[OK]`/`[ERR]`/`[!]`/`[i]`-prefixed terminal line, color by state.
  - Builder: `draculaComponents({bool reduceEffects = false})`; pass to `BlinkingCursor(animate: !reduceEffects)`.

- [ ] **Step 5: Wire** `draculaComponents(reduceEffects: reduceEffects)` into `dracula_theme.dart` (replace `defaultAppComponents()`).

- [ ] **Step 6: Run the smoke test — expect PASS.**

- [ ] **Step 7: Add the full battery** (copy Brutalist Step 6 + 7; swap types: `ConsolePanel`, `NeonCapsule`, `TerminalMetric`, `ConsoleToggle`, `DevConsoleLog`, `ConsoleKvRow`, `ConsoleStatusLine`, `BlinkingCursor`; theme `draculaTheme`). Add a flash-safety assertion: pump `BlinkingCursor` at full effects, advance `tester.pump(const Duration(seconds: 1))` a few times, and assert no exception (a coarse guarantee the controller loops cleanly). Keep the reduceEffects-static test (steady cursor; `pumpAndSettle` returns), inline-Wrap metric, bounded logView, and the two overflow guards.

- [ ] **Step 8: Run the test file — expect PASS.**

- [ ] **Step 9: Run the full done-bar.** Expected: all clean/green.

- [ ] **Step 10: Commit**
```bash
git add lib/core/theme/themes/dracula/dracula_components.dart lib/core/theme/themes/dracula/dracula_theme.dart test/core/theme/themes/dracula/dracula_components_test.dart
git commit -m "feat(theme): dracula bespoke components (neon dev-console slot set)"
```

---

## Phase 6 — Docs & wiki sync

### Task 6: Sync docs

**Files:**
- Modify: `docs/BACKLOG.md` (mark VM-F1 done / note remaining ideas)
- Modify: `CLAUDE.md` (§2 AURIS/AppComponents line — note all themes except Classic now ship bespoke components)
- Modify: the Themes wiki page in the separate `Getman.wiki.git` repo (CLAUDE.md §7)

- [ ] **Step 1:** In `docs/BACKLOG.md`, update **VM-F1**: mark Brutalist/Arcane/Glass/Editorial/Dracula done; leave a note that Classic stays on defaults by design and `select` (VM-F2) is still open.

- [ ] **Step 2:** In `CLAUDE.md` §2 (the `AppComponents` paragraph), update the sentence that says only AURIS overrides the slots → now Brutalist/Arcane/Glass/Editorial/Dracula each ship a `<name>_components.dart`; Classic inherits `defaultAppComponents()`.

- [ ] **Step 3:** Update `docs/THEME_AUTHORING.md` §10 closing note if it still implies AURIS is the only example (point to the new per-theme files as additional references).

- [ ] **Step 4:** Sync the wiki Themes page: clone `https://github.com/thiagomiranda3/Getman.wiki.git`, edit the Themes page to note each theme (except Classic) now has its own component widgets and describe the look per theme, commit + push (branch `master`). (Per CLAUDE.md §7 — do this only after the user has seen the themes.)

- [ ] **Step 5: Commit the in-repo doc changes**
```bash
git add docs/BACKLOG.md CLAUDE.md docs/THEME_AUTHORING.md
git commit -m "docs: per-theme bespoke components (VM-F1) — backlog + CLAUDE.md + theme-authoring sync"
```

---

## Self-review notes (author)

- **Spec coverage:** §4.1 Brutalist → Task 1; §4.2 Arcane → Task 2; §4.3 Glass → Task 3; §4.4 Editorial → Task 4; §4.5 Dracula → Task 5; §4.6 Classic → no task (intentional, stated in File map); §3 constraints → Global Constraints + each task's overflow/reduceEffects tests; §6 testing → each task Steps 6–8; §7 order + flagship gate → Phase 1 review gate; §8 out-of-scope (select/new slots/sound/motion) → honored (select inherited; no app edits); wiki sync → Task 6.
- **Placeholder scan:** Brutalist task carries full code. Rollout tasks carry full slot specs + signature behavior + exact test type names + the instruction to copy the (now real, committed) Brutalist file and AURIS test scaffold verbatim — concrete, not "implement later".
- **Type consistency:** builder names `brutalistComponents`/`rpgComponents`/`glassComponents`/`editorialComponents`(no flag)/`draculaComponents`; widget type names match between each task's Interfaces block, its slot specs, and its test asserts.
