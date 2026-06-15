# Env Variable Hover Tooltip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hovering an environment-variable token (`{{var}}`) in the URL bar or in params/headers value fields shows a small popover revealing the value that will actually be substituted at send time, based on the active environment (secrets masked with a reveal toggle).

**Architecture:** A pure-Dart classifier (`VariableResolutionHelper`, in `core/utils` beside `EnvironmentResolver`) maps a variable name + the active environment into a `ResolvedVariable` (`resolved` / `secret` / `dynamic` / `unresolved`). A reusable popover (`VariableHoverPopover`) + an `OverlayEntry` controller (`VariableHoverController`) render it. `VariableHighlightController` already builds the colored token spans; it gains an optional hover sink (`onVariableEnter`/`onVariableExit`) that the owning widget uses to drive the popover. The URL bar wires it directly; the params/headers value fields adopt `VariableHighlightController` (gaining the highlighting they lack today) via a new optional `variableContext` on `KeyValueListEditor`.

**Tech Stack:** Flutter (`fvm flutter`), `flutter_bloc`, `equatable`, `flutter_test`. No new dependencies.

---

## File Structure

**Create:**
- `lib/core/utils/variable_resolution_helper.dart` — `VariableValueKind`, `ResolvedVariable`, `VariableResolutionHelper.classify(...)`. Pure Dart, lives beside `environment_resolver.dart`.
- `lib/core/ui/widgets/variable_hover_popover.dart` — `VariableHoverContext` (value object), `VariableHoverPopover` (card), `VariableHoverController` (overlay show/hide).
- `test/core/utils/variable_resolution_helper_test.dart`
- `test/core/ui/widgets/variable_hover_popover_test.dart`
- `test/core/ui/widgets/variable_hover_detection_test.dart` (Approach A spike + behavior)

**Modify:**
- `lib/core/utils/environment_resolver.dart` — expose `resolveDynamic(name)`.
- `lib/core/ui/widgets/variable_highlight_controller.dart` — add `onVariableEnter`/`onVariableExit` sink, attach to token spans.
- `lib/features/environments/domain/logic/active_environment_helper.dart` — add `activeEnvironment(...)`.
- `lib/features/tabs/presentation/widgets/url_bar.dart` — wire sink → popover.
- `lib/core/ui/widgets/key_value_list_editor.dart` — optional `variableContext`; value fields use `VariableHighlightController` + sink.
- `lib/features/tabs/presentation/widgets/request_editor_tabs.dart` — compute & pass `VariableHoverContext` for Params/Headers.

**Wiki (Task 6):** `Getman.wiki.git` — Environments/Variables page.

---

### Task 1: Variable resolution helper (pure Dart)

**Files:**
- Modify: `lib/core/utils/environment_resolver.dart`
- Create: `lib/core/utils/variable_resolution_helper.dart`
- Test: `test/core/utils/variable_resolution_helper_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/utils/variable_resolution_helper_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

void main() {
  group('VariableResolutionHelper.classify', () {
    test('resolved variable returns value + resolved kind + env name', () {
      final r = VariableResolutionHelper.classify(
        name: 'base_url',
        variables: const {'base_url': 'https://api.example.com'},
        secretKeys: const {},
        environmentName: 'Production',
      );
      expect(r.name, 'base_url');
      expect(r.kind, VariableValueKind.resolved);
      expect(r.value, 'https://api.example.com');
      expect(r.environmentName, 'Production');
    });

    test('secret variable returns secret kind with value present', () {
      final r = VariableResolutionHelper.classify(
        name: 'token',
        variables: const {'token': 'sk-123'},
        secretKeys: const {'token'},
        environmentName: 'Production',
      );
      expect(r.kind, VariableValueKind.secret);
      expect(r.value, 'sk-123');
    });

    test('dynamic variable returns dynamicValue kind with a sample value', () {
      final r = VariableResolutionHelper.classify(
        name: r'$timestamp',
        variables: const {},
        secretKeys: const {},
        environmentName: 'Production',
      );
      expect(r.kind, VariableValueKind.dynamicValue);
      expect(int.tryParse(r.value ?? ''), isNotNull);
    });

    test('env var wins over a dynamic name of the same spelling', () {
      final r = VariableResolutionHelper.classify(
        name: r'$timestamp',
        variables: const {r'$timestamp': 'pinned'},
        secretKeys: const {},
        environmentName: 'Production',
      );
      expect(r.kind, VariableValueKind.resolved);
      expect(r.value, 'pinned');
    });

    test('unknown variable returns unresolved with null value', () {
      final r = VariableResolutionHelper.classify(
        name: 'missing',
        variables: const {},
        secretKeys: const {},
        environmentName: 'Production',
      );
      expect(r.kind, VariableValueKind.unresolved);
      expect(r.value, isNull);
      expect(r.environmentName, 'Production');
    });

    test('no active environment surfaces null environmentName', () {
      final r = VariableResolutionHelper.classify(
        name: 'missing',
        variables: const {},
        secretKeys: const {},
        environmentName: null,
      );
      expect(r.kind, VariableValueKind.unresolved);
      expect(r.environmentName, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/variable_resolution_helper_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:getman/core/utils/variable_resolution_helper.dart'`.

- [ ] **Step 3: Expose `resolveDynamic` on `EnvironmentResolver`**

In `lib/core/utils/environment_resolver.dart`, add a public accessor (place it right after the existing `isDynamic`):

```dart
  /// Public accessor for a dynamic variable's freshly-generated value, or null
  /// if [name] is not a recognized dynamic variable. Each call regenerates —
  /// matching send-time behavior — so the hover tooltip shows a representative
  /// sample, not a pinned value.
  static String? resolveDynamic(String name) => _resolveDynamic(name);
```

- [ ] **Step 4: Write the helper**

Create `lib/core/utils/variable_resolution_helper.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/core/utils/environment_resolver.dart';

/// How a `{{var}}` token resolves against the active environment.
enum VariableValueKind { resolved, secret, dynamicValue, unresolved }

/// The classification of a single variable name for the hover tooltip.
class ResolvedVariable extends Equatable {
  const ResolvedVariable({
    required this.name,
    required this.kind,
    this.value,
    this.environmentName,
  });

  final String name;
  final VariableValueKind kind;

  /// The value to display: the resolved string for [resolved]/[secret], a
  /// freshly-generated sample for [dynamicValue], or null for [unresolved].
  final String? value;

  /// Active environment display name; null when no environment is active.
  final String? environmentName;

  @override
  List<Object?> get props => [name, kind, value, environmentName];
}

/// Classifies a variable name against the active environment. Pure Dart — no
/// Flutter, no Hive. Lives beside [EnvironmentResolver] in core/utils so core
/// widgets can depend on it without reaching into a feature.
class VariableResolutionHelper {
  const VariableResolutionHelper._();

  static ResolvedVariable classify({
    required String name,
    required Map<String, String> variables,
    required Set<String> secretKeys,
    required String? environmentName,
  }) {
    // An env var always wins over a dynamic name of the same spelling, matching
    // EnvironmentResolver.resolve.
    if (variables.containsKey(name)) {
      return ResolvedVariable(
        name: name,
        kind: secretKeys.contains(name)
            ? VariableValueKind.secret
            : VariableValueKind.resolved,
        value: variables[name],
        environmentName: environmentName,
      );
    }
    if (EnvironmentResolver.isDynamic(name)) {
      return ResolvedVariable(
        name: name,
        kind: VariableValueKind.dynamicValue,
        value: EnvironmentResolver.resolveDynamic(name),
        environmentName: environmentName,
      );
    }
    return ResolvedVariable(
      name: name,
      kind: VariableValueKind.unresolved,
      environmentName: environmentName,
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/variable_resolution_helper_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/utils/environment_resolver.dart lib/core/utils/variable_resolution_helper.dart test/core/utils/variable_resolution_helper_test.dart
git commit -m "feat(env): variable resolution classifier for hover tooltip"
```

---

### Task 2: Hover popover card + overlay controller

**Files:**
- Create: `lib/core/ui/widgets/variable_hover_popover.dart`
- Test: `test/core/ui/widgets/variable_hover_popover_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/widgets/variable_hover_popover_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

Future<void> _pump(WidgetTester tester, ResolvedVariable data) {
  return tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme(ThemeIds.brutalist)(Brightness.light, isCompact: false),
      home: Scaffold(body: Center(child: VariableHoverPopover(data: data))),
    ),
  );
}

void main() {
  testWidgets('resolved variable shows name, value, and source', (tester) async {
    await _pump(
      tester,
      const ResolvedVariable(
        name: 'base_url',
        kind: VariableValueKind.resolved,
        value: 'https://api.example.com',
        environmentName: 'Production',
      ),
    );
    expect(find.text('{{base_url}}'), findsOneWidget);
    expect(find.text('https://api.example.com'), findsOneWidget);
    expect(find.textContaining('Production'), findsOneWidget);
  });

  testWidgets('secret masks value until reveal is toggled', (tester) async {
    await _pump(
      tester,
      const ResolvedVariable(
        name: 'token',
        kind: VariableValueKind.secret,
        value: 'sk-123',
        environmentName: 'Production',
      ),
    );
    expect(find.text('sk-123'), findsNothing);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(find.text('sk-123'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('dynamic variable shows generated-per-request label', (tester) async {
    await _pump(
      tester,
      const ResolvedVariable(
        name: r'$timestamp',
        kind: VariableValueKind.dynamicValue,
        value: '1700000000',
        environmentName: 'Production',
      ),
    );
    expect(find.textContaining('Generated per request'), findsOneWidget);
    expect(find.text('1700000000'), findsOneWidget);
  });

  testWidgets('unresolved with no env shows no-active-environment', (tester) async {
    await _pump(
      tester,
      const ResolvedVariable(name: 'x', kind: VariableValueKind.unresolved),
    );
    expect(find.textContaining('No active environment'), findsOneWidget);
  });

  testWidgets('unresolved with env shows not-defined-in', (tester) async {
    await _pump(
      tester,
      const ResolvedVariable(
        name: 'x',
        kind: VariableValueKind.unresolved,
        environmentName: 'Production',
      ),
    );
    expect(find.textContaining('Not defined in'), findsOneWidget);
    expect(find.textContaining('Production'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/variable_hover_popover_test.dart`
Expected: FAIL — `variable_hover_popover.dart` does not exist.

- [ ] **Step 3: Write the popover, context, and controller**

Create `lib/core/ui/widgets/variable_hover_popover.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

/// Active-environment data passed into a [KeyValueListEditor] (or any field) to
/// enable `{{var}}` highlighting + hover resolution. Null disables the feature.
class VariableHoverContext extends Equatable {
  const VariableHoverContext({
    this.variables = const {},
    this.secretKeys = const {},
    this.environmentName,
  });

  final Map<String, String> variables;

  /// Names flagged secret in the active environment — masked in the popover.
  final Set<String> secretKeys;

  /// Active environment display name; null when no environment is active.
  final String? environmentName;

  @override
  List<Object?> get props => [variables, secretKeys, environmentName];
}

/// The hover card. Not a stock [Tooltip] — secrets need an interactive reveal
/// toggle and the card must stay open while the pointer is over it.
class VariableHoverPopover extends StatefulWidget {
  const VariableHoverPopover({required this.data, super.key});

  final ResolvedVariable data;

  @override
  State<VariableHoverPopover> createState() => _VariableHoverPopoverState();
}

class _VariableHoverPopoverState extends State<VariableHoverPopover> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appPalette;
    final layout = context.appLayout;
    final typography = context.appTypography;
    final data = widget.data;

    final nameStyle = TextStyle(
      fontFamily: typography.codeFontFamily,
      fontSize: layout.fontSizeNormal,
      fontWeight: typography.titleWeight,
      color: theme.colorScheme.onSurface,
    );
    final valueStyle = TextStyle(
      fontFamily: typography.codeFontFamily,
      fontSize: layout.fontSizeNormal,
      color: palette.variableResolved,
    );
    final sourceStyle = TextStyle(
      fontSize: layout.fontSizeSmall,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
        decoration: context.appDecoration.panelBox(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('{{${data.name}}}', style: nameStyle),
            SizedBox(height: layout.tabSpacing),
            ..._body(context, valueStyle: valueStyle, sourceStyle: sourceStyle),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context, {
    required TextStyle valueStyle,
    required TextStyle sourceStyle,
  }) {
    final data = widget.data;
    switch (data.kind) {
      case VariableValueKind.resolved:
        return [
          SelectableText(data.value ?? '', style: valueStyle),
          if (data.environmentName != null) ...[
            SizedBox(height: context.appLayout.tabSpacing),
            Text('from ${data.environmentName}', style: sourceStyle),
          ],
        ];
      case VariableValueKind.secret:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: _revealed
                    ? SelectableText(data.value ?? '', style: valueStyle)
                    : Text('•••••• (secret)', style: valueStyle),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _revealed ? Icons.visibility_off : Icons.visibility,
                  size: context.appLayout.isCompact ? 18 : 20,
                ),
                tooltip: _revealed ? 'Hide value' : 'Reveal value',
                onPressed: () => setState(() => _revealed = !_revealed),
              ),
            ],
          ),
          if (data.environmentName != null)
            Text('from ${data.environmentName}', style: sourceStyle),
        ];
      case VariableValueKind.dynamicValue:
        return [
          Text('Generated per request', style: sourceStyle),
          SizedBox(height: context.appLayout.tabSpacing),
          SelectableText(data.value ?? '', style: valueStyle),
        ];
      case VariableValueKind.unresolved:
        return [
          Text(
            data.environmentName == null
                ? 'No active environment'
                : 'Not defined in ${data.environmentName}',
            style: TextStyle(
              fontSize: context.appLayout.fontSizeNormal,
              color: context.appPalette.variableUnresolved,
            ),
          ),
        ];
    }
  }
}

/// Owns a single [OverlayEntry] for the hover popover. The owning State creates
/// one, drives it from the highlight controller's hover sink, and disposes it.
/// A short hide delay lets the pointer travel from the token into the card.
class VariableHoverController {
  OverlayEntry? _entry;
  Timer? _hideTimer;

  /// Shows (or re-anchors) the popover near [globalAnchor] (the pointer).
  void showFor(
    BuildContext context,
    ResolvedVariable data,
    Offset globalAnchor,
  ) {
    _hideTimer?.cancel();
    final overlay = Overlay.of(context);
    final box = overlay.context.findRenderObject() as RenderBox?;
    final overlaySize = box?.size ?? MediaQuery.sizeOf(context);
    final local = box?.globalToLocal(globalAnchor) ?? globalAnchor;
    // Keep the 320-wide card on-screen at the right edge.
    final left = local.dx.clamp(0.0, (overlaySize.width - 324).clamp(0.0, double.infinity));
    final top = local.dy + 18;

    _entry?.remove();
    _entry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: left,
        top: top,
        child: MouseRegion(
          onEnter: (_) => cancelHide(),
          onExit: (_) => scheduleHide(),
          child: VariableHoverPopover(data: data),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void cancelHide() => _hideTimer?.cancel();

  void scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), hideNow);
  }

  void hideNow() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _entry?.remove();
    _entry = null;
  }

  void dispose() => hideNow();
}
```

> Note: if `context.appLayout.fontSizeSmall` does not exist, use `fontSizeNormal` — verify the field name in `lib/core/theme/app_theme.dart` (the `AppLayout` extension) before relying on it.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/variable_hover_popover_test.dart`
Expected: PASS (all 5 tests). If a theme field name is wrong, fix per the note above and re-run.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/widgets/variable_hover_popover.dart test/core/ui/widgets/variable_hover_popover_test.dart
git commit -m "feat(ui): variable hover popover card + overlay controller"
```

---

### Task 3: Hover detection — spike Approach A, then add the sink

**Files:**
- Modify: `lib/core/ui/widgets/variable_highlight_controller.dart`
- Test: `test/core/ui/widgets/variable_hover_detection_test.dart`

- [ ] **Step 1: Write the spike test (decides A vs B)**

Create `test/core/ui/widgets/variable_hover_detection_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';

void main() {
  testWidgets('hovering a {{var}} token reports the variable name', (tester) async {
    String? hovered;
    final controller = VariableHighlightController(
      text: '{{base_url}}/users',
      variables: const {'base_url': 'https://api.example.com'},
    )
      ..updateColors(resolved: Colors.green, unresolved: Colors.red)
      ..onVariableEnter = (name, _) => hovered = name
      ..onVariableExit = () => hovered = null;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 400, child: TextField(controller: controller)),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    // The token starts at the left of the field; aim near the first glyphs.
    final rect = tester.getRect(find.byType(TextField));
    await gesture.moveTo(Offset(rect.left + 20, rect.center.dy));
    await tester.pumpAndSettle();

    expect(
      hovered,
      'base_url',
      reason: 'If null, RenderEditable did not forward TextSpan.onEnter — '
          'switch to Approach B (see plan fallback section).',
    );
  });
}
```

- [ ] **Step 2: Add the hover sink to `VariableHighlightController`**

In `lib/core/ui/widgets/variable_highlight_controller.dart`, add a typedef and two nullable fields, and attach them to the token span. Full replacement for the class (sink fields + the token-span construction inside `buildTextSpan`):

Add near the top of the file (after imports):

```dart
/// Reports a hovered `{{var}}` token: its [name] and the global pointer
/// position (so the owner can anchor a popover). Set by the owning widget.
typedef VariableEnterCallback = void Function(String name, Offset globalPosition);
```

Add these fields to the class (next to `_resolvedColor`/`_unresolvedColor`):

```dart
  /// Optional hover sink. When set, each `{{var}}` token span reports pointer
  /// enter/exit so the owner can show/hide a resolution popover. Null = no
  /// hover behavior (unchanged rendering).
  VariableEnterCallback? onVariableEnter;
  VoidCallback? onVariableExit;
```

Replace the token `TextSpan` construction in `buildTextSpan` (the `children.add(TextSpan(style: highlightStyle, text: ...))` block) with:

```dart
      final enter = onVariableEnter;
      final exit = onVariableExit;
      children.add(
        TextSpan(
          style: highlightStyle,
          text: current.substring(match.start, match.end),
          mouseCursor: enter == null ? null : SystemMouseCursors.basic,
          onEnter: enter == null
              ? null
              : (event) => enter(match.name, event.position),
          onExit: exit == null ? null : (_) => exit(),
        ),
      );
```

(`SystemMouseCursors`, `PointerEnterEvent`, and `Offset` all come from the existing `package:flutter/material.dart` import.)

- [ ] **Step 3: Run the spike test**

Run: `fvm flutter test test/core/ui/widgets/variable_hover_detection_test.dart`
Expected: PASS.

**Decision point:**
- **PASS → Approach A is viable. Proceed to Task 4 as written.**
- **FAIL (`hovered` was null) → use Approach B.** Keep the sink fields (they are still the public contract), but the spans cannot drive them. Implement the fallback below, then proceed to Tasks 4–5 using the wrapper instead of relying on span callbacks. The popover, controller, classifier, and consumer wiring are identical; only *how the name + position are detected* changes.

  **Approach B (fallback only):** Create `lib/core/ui/widgets/variable_hover_region.dart` — a widget wrapping a single-line `TextField` that detects token hover by mirroring the field's layout:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:getman/core/utils/environment_resolver.dart';

  /// Wraps a single-line field, reporting which `{{var}}` token (if any) is
  /// under the pointer. Used only when RenderEditable does not forward
  /// TextSpan.onEnter (see plan Task 3).
  class VariableHoverRegion extends StatelessWidget {
    const VariableHoverRegion({
      required this.text,
      required this.style,
      required this.scrollController,
      required this.contentPaddingLeft,
      required this.onEnterToken,
      required this.onExitToken,
      required this.child,
      super.key,
    });

    final String text;
    final TextStyle style;
    final ScrollController scrollController; // the field's horizontal scroll
    final double contentPaddingLeft;
    final void Function(String name, Offset globalPosition) onEnterToken;
    final VoidCallback onExitToken;
    final Widget child;

    @override
    Widget build(BuildContext context) {
      return MouseRegion(
        onHover: (event) => _handle(context, event.localPosition, event.position),
        onExit: (_) => onExitToken(),
        child: child,
      );
    }

    void _handle(BuildContext context, Offset local, Offset global) {
      final matches = EnvironmentResolver.findVariables(text).toList();
      if (matches.isEmpty) {
        onExitToken();
        return;
      }
      final scroll = scrollController.hasClients ? scrollController.offset : 0.0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final textX = local.dx - contentPaddingLeft + scroll;
      for (final m in matches) {
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: m.start, extentOffset: m.end),
        );
        for (final b in boxes) {
          if (textX >= b.left && textX <= b.right) {
            onEnterToken(m.name, global);
            painter.dispose();
            return;
          }
        }
      }
      onExitToken();
      painter.dispose();
    }
  }
  ```

  Then in Tasks 4–5, wrap each `TextField` in `VariableHoverRegion` (passing a `ScrollController` also given to `TextField(scrollController:)`, the field's `style`, and its left content padding) instead of setting `onVariableEnter`/`onVariableExit`. Commit the wrapper separately:
  ```bash
  git add lib/core/ui/widgets/variable_hover_region.dart
  git commit -m "feat(ui): TextPainter-based variable hover detection (Approach B fallback)"
  ```

- [ ] **Step 4: Run the full existing suite to confirm no regression**

Run: `fvm flutter test test/core/ui/widgets/`
Expected: PASS (existing `VariableHighlightController`/URL-bar tests unaffected — the new fields default to null).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/widgets/variable_highlight_controller.dart test/core/ui/widgets/variable_hover_detection_test.dart
git commit -m "feat(ui): hover sink on VariableHighlightController + detection spike"
```

---

### Task 4: Wire the URL bar

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/url_bar.dart`

- [ ] **Step 1: Add the controller + imports**

At the top of `url_bar.dart`, add imports:

```dart
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
```

In `_UrlBarState`, add the field (beside `_urlController`):

```dart
  final VariableHoverController _hoverController = VariableHoverController();
```

- [ ] **Step 2: Set the sink in `initState`**

In `_UrlBarState.initState`, after `_urlController = VariableHighlightController();`, attach the sink:

```dart
    _urlController
      ..onVariableEnter = _showVariablePopover
      ..onVariableExit = _hoverController.scheduleHide;
```

- [ ] **Step 3: Add the resolution + show helpers and dispose**

Add these methods to `_UrlBarState` (read blocs live at hover time so the value is always current):

```dart
  void _showVariablePopover(String name, Offset globalPosition) {
    if (!mounted) return;
    final envState = context.read<EnvironmentsBloc>().state;
    final settings = context.read<SettingsBloc>().state.settings;
    final env = ActiveEnvironmentHelper.activeEnvironment(
      envState.environments,
      settings.activeEnvironmentId,
    );
    final data = VariableResolutionHelper.classify(
      name: name,
      variables: env?.variables ?? const {},
      secretKeys: env?.secretKeys ?? const {},
      environmentName: env?.name,
    );
    _hoverController.showFor(context, data, globalPosition);
  }
```

Update `dispose` to also dispose the hover controller (add before `_urlController.dispose();`):

```dart
    _hoverController.dispose();
```

> `ActiveEnvironmentHelper` is already imported. `Offset` comes from material.

- [ ] **Step 4: Add `activeEnvironment` to the helper (dependency for Step 3)**

In `lib/features/environments/domain/logic/active_environment_helper.dart`, add:

```dart
  static EnvironmentEntity? activeEnvironment(
    List<EnvironmentEntity> environments,
    String? activeId,
  ) {
    if (activeId == null) return null;
    for (final env in environments) {
      if (env.id == activeId) return env;
    }
    return null;
  }
```

- [ ] **Step 5: Verify analysis + manual sanity**

Run: `fvm flutter analyze && fvm dart run custom_lint`
Expected: No issues found (both passes).

Run: `fvm flutter run -d macos`, set an active environment with `base_url`, type `{{base_url}}/users` in a tab's URL, hover the token → popover shows the value. Hover an undefined `{{nope}}` → "Not defined in …". (Close the app when satisfied.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/tabs/presentation/widgets/url_bar.dart lib/features/environments/domain/logic/active_environment_helper.dart
git commit -m "feat(tabs): hover tooltip for variables in the URL bar"
```

---

### Task 5: Wire params/headers value fields

**Files:**
- Modify: `lib/core/ui/widgets/key_value_list_editor.dart`
- Modify: `lib/features/tabs/presentation/widgets/request_editor_tabs.dart`

- [ ] **Step 1: Add `variableContext` to `KeyValueListEditor`**

In `key_value_list_editor.dart`, add imports:

```dart
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
```

Add the constructor param + field (after `onSecretKeysChanged`):

```dart
    this.variableContext,
```
```dart
  /// When non-null, value fields highlight `{{var}}` tokens and show a hover
  /// popover resolving them against the active environment. Null (params/headers
  /// pass it; env editor and others do not) leaves value fields as plain text.
  final VariableHoverContext? variableContext;
```

- [ ] **Step 2: Build value controllers as highlight controllers when enabled**

In `_KeyValueListEditorState`, add the hover controller field:

```dart
  final VariableHoverController _hoverController = VariableHoverController();
```

Change `_initControllers` so the value controllers are `VariableHighlightController` when a context is present:

```dart
  void _initControllers(List<(String, String)> rows) {
    _keyControllers = [
      for (final (key, _) in rows) TextEditingController(text: key),
    ];
    _valControllers = [
      for (final (_, value) in rows) _newValueController(value),
    ];
    _addEmptyRow();
  }

  TextEditingController _newValueController(String value) {
    return widget.variableContext != null
        ? VariableHighlightController(text: value)
        : TextEditingController(text: value);
  }
```

Update `_addEmptyRow` to use it:

```dart
  void _addEmptyRow() {
    _keyControllers.add(TextEditingController());
    _valControllers.add(_newValueController(''));
  }
```

Add dispose of the hover controller in `dispose` (before `super.dispose()`):

```dart
    _hoverController.dispose();
```

- [ ] **Step 3: Push colors/variables/sink onto value controllers each build**

In `_KeyValueListEditorState.build`, inside `itemBuilder` (before constructing `_KeyValueRow`), configure the value controller when highlighting is enabled:

```dart
        final varContext = widget.variableContext;
        final valController = _valControllers[index];
        if (varContext != null && valController is VariableHighlightController) {
          final palette = context.appPalette;
          valController
            ..updateColors(
              resolved: palette.variableResolved,
              unresolved: palette.variableUnresolved,
            )
            ..updateVariables(varContext.variables)
            ..onVariableEnter = (name, pos) =>
                _showVariablePopover(context, name, pos)
            ..onVariableExit = _hoverController.scheduleHide;
        }
```

Add the show helper to the state class:

```dart
  void _showVariablePopover(BuildContext context, String name, Offset pos) {
    final varContext = widget.variableContext;
    if (varContext == null) return;
    final data = VariableResolutionHelper.classify(
      name: name,
      variables: varContext.variables,
      secretKeys: varContext.secretKeys,
      environmentName: varContext.environmentName,
    );
    _hoverController.showFor(context, data, pos);
  }
```

> If the spike in Task 3 selected **Approach B**, instead wrap `valueField` in `_KeyValueRow` with `VariableHoverRegion` (passing a `ScrollController` shared with the `TextField`, `textStyle`, and `fieldPadding.left`); the `_showVariablePopover` + classifier stay identical.

- [ ] **Step 4: Pass `variableContext` from Params/Headers tab views**

In `request_editor_tabs.dart`, add imports:

```dart
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
```

Add a private builder widget at the bottom of the file (above the body-editor section is fine — anywhere top-level):

```dart
/// Recomputes the active-environment [VariableHoverContext] and rebuilds when
/// the environment set or the active-environment id changes, so value-field
/// hover popovers always reflect the current environment.
class _VariableContextBuilder extends StatelessWidget {
  const _VariableContextBuilder({required this.builder});

  final Widget Function(BuildContext, VariableHoverContext) builder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
      builder: (context, settingsState) {
        return BlocBuilder<EnvironmentsBloc, EnvironmentsState>(
          buildWhen: (p, n) => p.environments != n.environments,
          builder: (context, envState) {
            final env = ActiveEnvironmentHelper.activeEnvironment(
              envState.environments,
              settingsState.settings.activeEnvironmentId,
            );
            return builder(
              context,
              VariableHoverContext(
                variables: env?.variables ?? const {},
                secretKeys: env?.secretKeys ?? const {},
                environmentName: env?.name,
              ),
            );
          },
        );
      },
    );
  }
}
```

Wrap the `KeyValueListEditor` in `ParamsTabView` (replace the `return KeyValueListEditor<...>(...)` with the builder + `variableContext`):

```dart
        return _VariableContextBuilder(
          builder: (context, varContext) =>
              KeyValueListEditor<List<QueryParamEntity>>(
            items: tab.config.params,
            variableContext: varContext,
            decode: (params) => [for (final p in params) (p.key, p.value)],
            encode: (rows) => [
              for (final (key, value) in rows)
                if (key.isNotEmpty) QueryParamEntity(key: key, value: value),
            ],
            equals: _queryParamListEquality.equals,
            onChanged: (list) {
              final bloc = context.read<TabsBloc>();
              final current = bloc.state.tabs.byId(tabId);
              if (current == null) return;
              bloc.add(
                UpdateTab(
                  current.copyWith(
                    config: current.config.copyWith(params: list),
                  ),
                ),
              );
            },
          ),
        );
```

Do the same for `HeadersTabView` (wrap its `KeyValueListEditor<Map<String, String>>(...)` in `_VariableContextBuilder` and add `variableContext: varContext,`).

- [ ] **Step 5: Verify analysis**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib`
Expected: No issues found (all three). In particular, `custom_lint` must not flag `avoid_hardcoded_brand_colors` — the popover uses palette colors only.

- [ ] **Step 6: Run existing key/value editor tests (regression)**

Run: `fvm flutter test test/`
Expected: PASS. The env editor and other `KeyValueListEditor` consumers pass no `variableContext` (default null) → value controllers stay plain `TextEditingController`, behavior unchanged.

- [ ] **Step 7: Manual sanity**

Run: `fvm flutter run -d macos`. With an active environment, add a header `Authorization: Bearer {{token}}` (mark `token` secret in the env). Hover `{{token}}` in the value field → masked popover with reveal toggle. Hover a param value `{{base_url}}` → resolved value. Close the app when satisfied.

- [ ] **Step 8: Commit**

```bash
git add lib/core/ui/widgets/key_value_list_editor.dart lib/features/tabs/presentation/widgets/request_editor_tabs.dart
git commit -m "feat(tabs): hover tooltip + highlighting for variables in params/headers values"
```

---

### Task 6: Full verification + wiki

**Files:**
- Wiki: `Getman.wiki.git` (separate repo) — Environments/Variables page.

- [ ] **Step 1: Run the full done-bar**

Run each and confirm clean:
```bash
fvm dart format lib test tools
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```
Expected: `dart format` reports 0 changed (or commit the formatting), all three analysis passes "No issues found", all tests green.

- [ ] **Step 2: Update the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```
Edit the Environments/Variables page (the one documenting `{{var}}` syntax): add a short section, e.g. *"Hover to resolve — hover the mouse over a `{{variable}}` in the URL bar or a params/headers value to see the value it resolves to under the active environment. Secrets show masked with a reveal toggle; dynamic variables (`{{$timestamp}}`, …) show a generated sample."* Keep UI labels verbatim.

```bash
cd /tmp/getman-wiki && git add -A && git commit -m "docs: hover-to-resolve variable tooltip" && git push origin master
```

- [ ] **Step 3: Final commit (if formatting changed anything)**

```bash
git add -A && git commit -m "chore: format" || echo "nothing to format"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** URL bar (Task 4) ✓; params/headers values (Task 5) ✓; resolved/secret/dynamic/unresolved popover content (Task 2) ✓; secret mask+reveal (Task 2) ✓; resolution helper extending `ActiveEnvironmentHelper` + dynamic sample (Tasks 1, 4) ✓; env-editor exclusion (null `variableContext`, Task 5 Step 6) ✓; detection A-with-B-fallback (Task 3) ✓; mobile no-op (hover-only, inherent) ✓; testing (Tasks 1, 2, 3) ✓; wiki (Task 6) ✓.
- **Placeholder scan:** none — all steps carry concrete code/commands. The one genuine fork (A vs B) is fully specified with concrete code for both and a deterministic decision gate.
- **Type consistency:** `VariableValueKind` (`resolved`/`secret`/`dynamicValue`/`unresolved`), `ResolvedVariable{name,kind,value,environmentName}`, `VariableResolutionHelper.classify(name,variables,secretKeys,environmentName)`, `VariableHoverContext{variables,secretKeys,environmentName}`, `VariableEnterCallback(name,globalPosition)`, `VariableHoverController.{showFor,scheduleHide,cancelHide,hideNow,dispose}`, `ActiveEnvironmentHelper.activeEnvironment(...)` — used consistently across Tasks 1–5.
- **Open verification:** `AppLayout.fontSizeSmall` is assumed in Task 2 (fallback noted to `fontSizeNormal`). Approach-A viability is gated by the Task 3 spike, not assumed.
