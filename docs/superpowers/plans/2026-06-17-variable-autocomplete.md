# `{{variable}}` Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-field autocomplete menu for `{{variable}}` references in the URL bar and the params/headers value fields.

**Architecture:** Two pure-Dart modules (a trigger/insertion detector and a suggestion builder) sit behind a single reusable widget, `VariableAutocomplete`, that wraps a `TextField`. The widget owns an overlay menu anchored via `LayerLink` and intercepts navigation keys with a `Shortcuts`+`Actions` pair gated by an "is the menu open" callback. The URL bar and `KeyValueListEditor` each wrap their field and inject a `suggestionsFor` closure that reads live variable state.

**Tech Stack:** Flutter, `flutter_bloc` (read-only in closures), the existing `EnvironmentResolver` / `VariableResolutionHelper` variable infrastructure.

## Global Constraints

- Flutter SDK is pinned via `.fvmrc`: invoke as `fvm flutter ...` / `fvm dart ...`, never plain `flutter`.
- Imports are `package:getman/...` everywhere (no relative imports).
- No hardcoded font sizes/weights/colors/radii: pull from `context.appLayout` / `appPalette` / `appShape` / `appTypography` / `appDecoration`. Inline numeric layout constants that mirror existing widgets (e.g. `isCompact ? 8 : 12`, a viewport `maxHeight` cap) are acceptable, matching `key_value_list_editor.dart` / `url_bar.dart`.
- Never use `Colors.black` / `Colors.white` / `Colors.red` for themeable surfaces (custom_lint `avoid_hardcoded_brand_colors`).
- Domain/pure files import only pure Dart + their declared deps; no Flutter in `core/utils/`.
- Verification bar (must all be clean before "done"): `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test`, `fvm flutter test`.
- No `@HiveType`/`@HiveField` changes in this feature → no `build_runner`.

---

### Task 1: Trigger/insertion detector (pure)

**Files:**
- Create: `lib/core/utils/variable_autocomplete_query.dart`
- Test: `test/core/utils/variable_autocomplete_query_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class ActiveVariableQuery { final int replaceStart; final int replaceEnd; final String query; final bool hasClosingBraces; }` and `ActiveVariableQuery? detectActiveVariableQuery(String text, int caretOffset)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/variable_autocomplete_query_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/variable_autocomplete_query.dart';

void main() {
  group('detectActiveVariableQuery', () {
    test('empty query right after "{{"', () {
      final q = detectActiveVariableQuery('https://{{', 10);
      expect(q, isNotNull);
      expect(q!.query, '');
      expect(q.replaceStart, 10);
      expect(q.replaceEnd, 10);
      expect(q.hasClosingBraces, isFalse);
    });

    test('partial name', () {
      final q = detectActiveVariableQuery('{{ba', 4);
      expect(q!.query, 'ba');
      expect(q.replaceStart, 2);
      expect(q.replaceEnd, 4);
    });

    test('caret inside an already-closed token reports hasClosingBraces', () {
      final q = detectActiveVariableQuery('{{ba}}', 4); // caret before "}}"
      expect(q!.query, 'ba');
      expect(q.hasClosingBraces, isTrue);
    });

    test('caret after a closed token => no active query', () {
      expect(detectActiveVariableQuery('{{ab}}', 6), isNull);
    });

    test('a space (non-identifier char) ends the token', () {
      expect(detectActiveVariableQuery('{{ab cd', 7), isNull);
    });

    test('dynamic var with leading \$', () {
      final q = detectActiveVariableQuery(r'{{$gu', 5);
      expect(q!.query, r'$gu');
    });

    test('uses the nearest "{{" and ignores an earlier closed token', () {
      final q = detectActiveVariableQuery('{{a}}/{{b', 9);
      expect(q!.query, 'b');
      expect(q.replaceStart, 8);
    });

    test('single "{" is not a trigger', () {
      expect(detectActiveVariableQuery('{a', 2), isNull);
    });

    test('caret before any "{{" => null', () {
      expect(detectActiveVariableQuery('abc', 2), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/variable_autocomplete_query_test.dart`
Expected: FAIL — `variable_autocomplete_query.dart` / `detectActiveVariableQuery` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/utils/variable_autocomplete_query.dart

/// The `{{variable}}` token currently being typed at the caret, used to drive
/// the variable autocomplete menu and to compute the insertion. Pure Dart.
class ActiveVariableQuery {
  const ActiveVariableQuery({
    required this.replaceStart,
    required this.replaceEnd,
    required this.query,
    required this.hasClosingBraces,
  });

  /// Index where the variable name starts (just after the opening `{{`).
  final int replaceStart;

  /// The caret offset (end of the typed query).
  final int replaceEnd;

  /// Text between `{{` and the caret. May be empty (just opened).
  final String query;

  /// Whether a `}}` immediately follows the caret (don't double the braces).
  final bool hasClosingBraces;
}

final RegExp _identifierChar = RegExp(r'[A-Za-z0-9_\-.$]');

/// Detects the open `{{` token at [caretOffset], or null if the caret is not
/// inside an in-progress `{{name` (e.g. no opening braces, a closed token, or
/// a non-identifier char between `{{` and the caret). Callers must only invoke
/// this with a collapsed selection.
ActiveVariableQuery? detectActiveVariableQuery(String text, int caretOffset) {
  if (caretOffset < 2 || caretOffset > text.length) return null;
  final open = text.lastIndexOf('{{', caretOffset - 2);
  if (open < 0) return null;
  final nameStart = open + 2;
  if (nameStart > caretOffset) return null;
  final query = text.substring(nameStart, caretOffset);
  for (var i = 0; i < query.length; i++) {
    if (!_identifierChar.hasMatch(query[i])) return null;
  }
  final hasClosingBraces = caretOffset + 2 <= text.length &&
      text.substring(caretOffset, caretOffset + 2) == '}}';
  return ActiveVariableQuery(
    replaceStart: nameStart,
    replaceEnd: caretOffset,
    query: query,
    hasClosingBraces: hasClosingBraces,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/variable_autocomplete_query_test.dart`
Expected: PASS (all cases).

- [ ] **Step 5: Format, analyze, commit**

```bash
fvm dart format lib/core/utils/variable_autocomplete_query.dart test/core/utils/variable_autocomplete_query_test.dart
fvm flutter analyze lib/core/utils/variable_autocomplete_query.dart
git add lib/core/utils/variable_autocomplete_query.dart test/core/utils/variable_autocomplete_query_test.dart
git commit -m "feat(variables): pure detector for the active {{var}} token

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Suggestion builder (pure)

**Files:**
- Create: `lib/core/utils/variable_suggestions.dart`
- Test: `test/core/utils/variable_suggestions_test.dart`

**Interfaces:**
- Consumes: `ResolvedVariable`, `VariableValueKind` from `package:getman/core/utils/variable_resolution_helper.dart`.
- Produces: `class VariableSuggestion { final String name; final ResolvedVariable classification; }`, `const List<String> kSuggestableDynamicNames`, and `List<VariableSuggestion> buildVariableSuggestions({required String query, required Iterable<String> userVariableNames, required ResolvedVariable Function(String name) classify, bool includeDynamics = true})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/variable_suggestions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';

ResolvedVariable _classify(String name) {
  if (name == 'apiKey') {
    return const ResolvedVariable(
      name: 'apiKey',
      kind: VariableValueKind.secret,
      value: 'shh',
      environmentName: 'Dev',
    );
  }
  return ResolvedVariable(
    name: name,
    kind: VariableValueKind.resolved,
    value: 'v-$name',
    environmentName: 'Dev',
  );
}

List<String> _names(List<VariableSuggestion> s) => [for (final x in s) x.name];

void main() {
  group('buildVariableSuggestions', () {
    test('empty query returns user vars (alpha) then dynamics', () {
      final out = buildVariableSuggestions(
        query: '',
        userVariableNames: const ['token', 'baseUrl'],
        classify: _classify,
      );
      expect(_names(out).take(2), ['baseUrl', 'token']);
      expect(_names(out), contains(r'$guid'));
    });

    test('case-insensitive filter', () {
      final out = buildVariableSuggestions(
        query: 'BASE',
        userVariableNames: const ['baseUrl', 'token'],
        classify: _classify,
        includeDynamics: false,
      );
      expect(_names(out), ['baseUrl']);
    });

    test('prefix matches rank above substring matches', () {
      final out = buildVariableSuggestions(
        query: 'id',
        userVariableNames: const ['userId', 'id'],
        classify: _classify,
        includeDynamics: false,
      );
      expect(_names(out), ['id', 'userId']);
    });

    test('includeDynamics false omits built-ins', () {
      final out = buildVariableSuggestions(
        query: '',
        userVariableNames: const ['x'],
        classify: _classify,
        includeDynamics: false,
      );
      expect(_names(out), ['x']);
    });

    test('does not suggest the \$randomUuid alias', () {
      expect(kSuggestableDynamicNames, isNot(contains(r'$randomUuid')));
      expect(kSuggestableDynamicNames, contains(r'$randomUUID'));
    });

    test('carries the classification through (secret preserved)', () {
      final out = buildVariableSuggestions(
        query: 'api',
        userVariableNames: const ['apiKey'],
        classify: _classify,
        includeDynamics: false,
      );
      expect(out.single.classification.kind, VariableValueKind.secret);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/variable_suggestions_test.dart`
Expected: FAIL — `variable_suggestions.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/utils/variable_suggestions.dart
import 'package:getman/core/utils/variable_resolution_helper.dart';

/// One row in the variable autocomplete menu: the [name] to insert plus its
/// [classification] (kind/value/source) for the preview. Pure Dart.
class VariableSuggestion {
  const VariableSuggestion({required this.name, required this.classification});
  final String name;
  final ResolvedVariable classification;
}

/// Dynamic built-ins offered as suggestions. Mirrors
/// [EnvironmentResolver.dynamicNames] but drops the `$randomUuid` lowercase
/// alias of `$randomUUID` so the menu shows no near-duplicate row.
const List<String> kSuggestableDynamicNames = [
  r'$guid',
  r'$randomUUID',
  r'$timestamp',
  r'$isoTimestamp',
  r'$randomInt',
];

/// Builds the filtered, ordered suggestion list for [query]. Candidate names
/// are [userVariableNames] (env ∪ collection) plus the curated dynamics (unless
/// [includeDynamics] is false). Ordering: prefix matches before substring
/// matches; within a rank, user variables before dynamics, then alphabetical.
/// Each surviving name is run through [classify] for its preview.
List<VariableSuggestion> buildVariableSuggestions({
  required String query,
  required Iterable<String> userVariableNames,
  required ResolvedVariable Function(String name) classify,
  bool includeDynamics = true,
}) {
  final lower = query.toLowerCase();
  final seen = <String>{};
  final users = <String>[];
  for (final n in userVariableNames) {
    if (seen.add(n)) users.add(n);
  }
  final dynamics = includeDynamics
      ? [for (final n in kSuggestableDynamicNames) if (!seen.contains(n)) n]
      : const <String>[];
  final dynamicSet = dynamics.toSet();

  bool matches(String n) => lower.isEmpty || n.toLowerCase().contains(lower);
  int rank(String n) => n.toLowerCase().startsWith(lower) ? 0 : 1;

  final candidates = [...users, ...dynamics].where(matches).toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final d = (dynamicSet.contains(a) ? 1 : 0)
          .compareTo(dynamicSet.contains(b) ? 1 : 0);
      if (d != 0) return d;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  return [
    for (final n in candidates)
      VariableSuggestion(name: n, classification: classify(n)),
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/variable_suggestions_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
fvm dart format lib/core/utils/variable_suggestions.dart test/core/utils/variable_suggestions_test.dart
fvm flutter analyze lib/core/utils/variable_suggestions.dart
git add lib/core/utils/variable_suggestions.dart test/core/utils/variable_suggestions_test.dart
git commit -m "feat(variables): pure suggestion builder for {{var}} autocomplete

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `VariableAutocomplete` widget

**Files:**
- Create: `lib/core/ui/widgets/variable_autocomplete.dart`
- Test: `test/core/ui/widgets/variable_autocomplete_test.dart`

**Interfaces:**
- Consumes: `detectActiveVariableQuery`/`ActiveVariableQuery` (Task 1); `VariableSuggestion`/`buildVariableSuggestions` (Task 2); `ResolvedVariable`/`VariableValueKind`; theme accessors.
- Produces: `typedef VariableSuggestionsProvider = List<VariableSuggestion> Function(String query);` and `class VariableAutocomplete extends StatefulWidget` with named params `{required TextEditingController controller, required FocusNode focusNode, required VariableSuggestionsProvider suggestionsFor, required Widget child}`.

- [ ] **Step 1: Write the implementation**

```dart
// lib/core/ui/widgets/variable_autocomplete.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/variable_autocomplete_query.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';

typedef VariableSuggestionsProvider =
    List<VariableSuggestion> Function(String query);

class _NextSuggestionIntent extends Intent {
  const _NextSuggestionIntent();
}

class _PrevSuggestionIntent extends Intent {
  const _PrevSuggestionIntent();
}

class _AcceptSuggestionIntent extends Intent {
  const _AcceptSuggestionIntent();
}

class _DismissSuggestionIntent extends Intent {
  const _DismissSuggestionIntent();
}

class _OpenSuggestionIntent extends Intent {
  const _OpenSuggestionIntent();
}

/// An [Action] whose enablement is read live from [isEnabledCallback] at
/// key-event time. When disabled, the key event is not consumed and falls
/// through to the default text-editing shortcuts.
class _GatedAction extends Action<Intent> {
  _GatedAction({required this.isEnabledCallback, required this.onInvoke});
  final bool Function() isEnabledCallback;
  final VoidCallback onInvoke;

  @override
  bool isEnabled(Intent intent) => isEnabledCallback();

  @override
  Object? invoke(Intent intent) {
    onInvoke();
    return null;
  }
}

/// Wraps a [TextField] ([child]) with a `{{variable}}` autocomplete menu.
/// Typing `{{` (or Cmd/Ctrl+Space) opens a keyboard-navigable overlay built
/// from [suggestionsFor]; accepting inserts `name}}`.
class VariableAutocomplete extends StatefulWidget {
  const VariableAutocomplete({
    required this.controller,
    required this.focusNode,
    required this.suggestionsFor,
    required this.child,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VariableSuggestionsProvider suggestionsFor;
  final Widget child;

  @override
  State<VariableAutocomplete> createState() => _VariableAutocompleteState();
}

class _VariableAutocompleteState extends State<VariableAutocomplete> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  List<VariableSuggestion> _suggestions = const [];
  int _selected = 0;
  ActiveVariableQuery? _activeQuery;
  bool _dismissed = false; // Esc latch; cleared on the next text change.
  String _lastText = '';

  bool get _isOpen => _entry != null;

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onControllerChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) _close();
  }

  void _onControllerChanged() {
    final text = widget.controller.text;
    if (text != _lastText) {
      _dismissed = false;
      _lastText = text;
    }
    _refresh();
  }

  void _refresh() {
    if (_dismissed || !widget.focusNode.hasFocus) return _close();
    final sel = widget.controller.selection;
    if (!sel.isCollapsed || sel.baseOffset < 0) return _close();
    final query = detectActiveVariableQuery(
      widget.controller.text,
      sel.baseOffset,
    );
    if (query == null) return _close();
    final suggestions = widget.suggestionsFor(query.query);
    if (suggestions.isEmpty) return _close();
    _activeQuery = query;
    _suggestions = suggestions;
    _selected = _selected.clamp(0, suggestions.length - 1);
    _open();
    _entry!.markNeedsBuild();
  }

  void _open() {
    if (_entry != null) return;
    _entry = OverlayEntry(builder: _buildMenu);
    Overlay.of(context).insert(_entry!);
  }

  void _close() => _removeOverlay();

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
    _activeQuery = null;
    _suggestions = const [];
    _selected = 0;
  }

  void _moveSelection(int delta) {
    if (!_isOpen || _suggestions.isEmpty) return;
    _selected = (_selected + delta) % _suggestions.length;
    if (_selected < 0) _selected += _suggestions.length;
    _entry!.markNeedsBuild();
  }

  void _acceptAt(int index) {
    final query = _activeQuery;
    if (query == null || index < 0 || index >= _suggestions.length) return;
    final name = _suggestions[index].name;
    final text = widget.controller.text;
    final before = text.substring(0, query.replaceStart);
    final after = text.substring(query.replaceEnd);
    final insert = query.hasClosingBraces ? name : '$name}}';
    final caret =
        before.length + insert.length + (query.hasClosingBraces ? 2 : 0);
    _close();
    widget.controller.value = TextEditingValue(
      text: '$before$insert$after',
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  void _dismiss() {
    if (!_isOpen) return;
    _dismissed = true;
    _close();
  }

  void _openViaShortcut() {
    _dismissed = false;
    if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
    final sel = widget.controller.selection;
    final hasActive = sel.isCollapsed &&
        sel.baseOffset >= 0 &&
        detectActiveVariableQuery(widget.controller.text, sel.baseOffset) !=
            null;
    if (hasActive) {
      _refresh();
      return;
    }
    final text = widget.controller.text;
    final caret = (sel.isCollapsed && sel.baseOffset >= 0)
        ? sel.baseOffset
        : text.length;
    // Insert an empty token; the controller listener then opens the menu.
    widget.controller.value = TextEditingValue(
      text: '${text.substring(0, caret)}{{}}${text.substring(caret)}',
      selection: TextSelection.collapsed(offset: caret + 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): _NextSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): _PrevSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.enter): _AcceptSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.tab): _AcceptSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _DismissSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.space, control: true):
              _OpenSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.space, meta: true):
              _OpenSuggestionIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _NextSuggestionIntent: _GatedAction(
              isEnabledCallback: () => _isOpen,
              onInvoke: () => _moveSelection(1),
            ),
            _PrevSuggestionIntent: _GatedAction(
              isEnabledCallback: () => _isOpen,
              onInvoke: () => _moveSelection(-1),
            ),
            _AcceptSuggestionIntent: _GatedAction(
              isEnabledCallback: () => _isOpen,
              onInvoke: () => _acceptAt(_selected),
            ),
            _DismissSuggestionIntent: _GatedAction(
              isEnabledCallback: () => _isOpen,
              onInvoke: _dismiss,
            ),
            _OpenSuggestionIntent: _GatedAction(
              isEnabledCallback: () => true,
              onInvoke: _openViaShortcut,
            ),
          },
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final width = _link.leaderSize?.width ?? 280.0;
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 4),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              // ~6 rows; viewport cap, mirrors inline constraints elsewhere.
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: context.appDecoration.panelBox(context),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, i) =>
                    _row(context, _suggestions[i], i, i == _selected),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    VariableSuggestion s,
    int index,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final palette = context.appPalette;
    final layout = context.appLayout;
    final c = s.classification;
    final isSecret = c.kind == VariableValueKind.secret;
    final isDynamic = c.kind == VariableValueKind.dynamicValue;
    final preview = isSecret ? '••••' : (c.value ?? '');
    final source = isDynamic ? 'dynamic' : (c.environmentName ?? '');
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return InkWell(
      onTap: () => _acceptAt(index),
      child: Container(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        padding: EdgeInsets.symmetric(
          horizontal: layout.isCompact ? 8 : 12,
          vertical: layout.isCompact ? 6 : 8,
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                s.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                  color: isDynamic
                      ? palette.variableResolved
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (source.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                source,
                style: TextStyle(fontSize: layout.fontSizeNormal, color: muted),
              ),
            ],
            if (preview.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  preview,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: layout.fontSizeNormal,
                    color: muted,
                    fontStyle: isDynamic ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write the failing widget test**

```dart
// test/core/ui/widgets/variable_autocomplete_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/variable_autocomplete.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';

ResolvedVariable _classify(String name) => ResolvedVariable(
  name: name,
  kind: VariableValueKind.resolved,
  value: 'v-$name',
  environmentName: 'Dev',
);

List<VariableSuggestion> _suggest(String q) => buildVariableSuggestions(
  query: q,
  userVariableNames: const ['baseUrl', 'token', 'userId'],
  classify: _classify,
  includeDynamics: false,
);

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: VariableAutocomplete(
            controller: controller,
            focusNode: focusNode,
            suggestionsFor: _suggest,
            child: TextField(controller: controller, focusNode: focusNode),
          ),
        ),
      ),
    );
  }

  testWidgets('typing "{{" opens the menu with all suggestions', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
    expect(find.text('token'), findsOneWidget);
    expect(find.text('userId'), findsOneWidget);
  });

  testWidgets('typing filters the menu', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{to');
    await tester.pumpAndSettle();
    expect(find.text('token'), findsOneWidget);
    expect(find.text('baseUrl'), findsNothing);
  });

  testWidgets('Enter inserts the selected suggestion with closing braces', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, '{{baseUrl}}');
    expect(controller.selection.baseOffset, '{{baseUrl}}'.length);
  });

  testWidgets('ArrowDown then Enter inserts the second suggestion', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, '{{token}}');
  });

  testWidgets('Escape closes the menu and does not reopen on the same text', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsNothing);
  });

  testWidgets('tapping a row inserts it', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    await tester.tap(find.text('userId'));
    await tester.pumpAndSettle();
    expect(controller.text, '{{userId}}');
  });

  testWidgets('Ctrl+Space opens the menu on an empty field', (tester) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the widget test**

Run: `fvm flutter test test/core/ui/widgets/variable_autocomplete_test.dart`
Expected: PASS. If the `enter`/`tab` events do not reach the actions, confirm `enterText` focused the field (it does) and that `pumpAndSettle` ran after each key.

- [ ] **Step 4: Format, analyze (incl. custom_lint), commit**

```bash
fvm dart format lib/core/ui/widgets/variable_autocomplete.dart test/core/ui/widgets/variable_autocomplete_test.dart
fvm flutter analyze lib/core/ui/widgets/variable_autocomplete.dart
fvm dart run custom_lint
git add lib/core/ui/widgets/variable_autocomplete.dart test/core/ui/widgets/variable_autocomplete_test.dart
git commit -m "feat(variables): reusable {{var}} autocomplete field widget

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Wire autocomplete into params/headers value fields

**Files:**
- Modify: `lib/core/ui/widgets/key_value_list_editor.dart`
- Test: `test/core/ui/widgets/key_value_list_editor_test.dart` (extend)

**Interfaces:**
- Consumes: `VariableAutocomplete`/`VariableSuggestionsProvider` (Task 3); `buildVariableSuggestions` (Task 2); `VariableResolutionHelper.classify`.
- Produces: behavior only — value fields backed by a `VariableHighlightController` gain the autocomplete menu; the public `KeyValueListEditor` API is unchanged.

Notes on the current code:
- `_KeyValueRow` (StatefulWidget, `_KeyValueRowState` around `lib/core/ui/widgets/key_value_list_editor.dart:263`) builds the value `TextField` near line 300 with **no `FocusNode`**.
- The parent `_KeyValueListEditorState.build` (around line 176-194) already wires `onVariableEnter`/colors/variables onto each `VariableHighlightController`. The `variableContext` (`VariableHoverContext` with `.variables`/`.secretKeys`/`.environmentName`) is in scope there.

- [ ] **Step 1: Add the failing test**

Append inside `main()` in `test/core/ui/widgets/key_value_list_editor_test.dart`. Add these imports at the top of the file:

```dart
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
```

Add a harness variant + test:

```dart
  testWidgets('value field shows {{var}} autocomplete when a '
      'variableContext is provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: KeyValueListEditor<Map<String, String>>(
            items: const <String, String>{},
            decode: (map) => [for (final e in map.entries) (e.key, e.value)],
            encode: (rows) => {
              for (final (key, value) in rows)
                if (key.isNotEmpty) key: value,
            },
            equals: const MapEquality<String, String>().equals,
            variableContext: const VariableHoverContext(
              variables: {'baseUrl': 'https://x', 'token': 't'},
              environmentName: 'Dev',
            ),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    // First (empty) row's value field.
    await tester.enterText(find.widgetWithText(TextField, 'VALUE').first, '{{');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
    expect(find.text('token'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/key_value_list_editor_test.dart -p vm --plain-name "autocomplete"`
Expected: FAIL — no `baseUrl`/`token` overlay appears (autocomplete not wired yet).

- [ ] **Step 3: Add a value FocusNode to `_KeyValueRowState`**

In `lib/core/ui/widgets/key_value_list_editor.dart`, in `_KeyValueRowState` (near line 263), add the focus node and dispose it:

```dart
class _KeyValueRowState extends State<_KeyValueRow> {
  bool _isHovered = false;
  bool _revealed = false;
  final FocusNode _valueFocusNode = FocusNode();

  @override
  void dispose() {
    _valueFocusNode.dispose();
    super.dispose();
  }
```

- [ ] **Step 4: Pass a suggestions provider down to `_KeyValueRow`**

Add a field + constructor param to `_KeyValueRow` (the Stateless, around line 232-261):

```dart
  const _KeyValueRow({
    required this.keyController,
    required this.valController,
    required this.layout,
    required this.onKeyChanged,
    required this.onValChanged,
    required this.onDelete,
    super.key,
    this.rowIndex = 0,
    this.fieldPrefix,
    this.showSecretToggle = false,
    this.isSecret = false,
    this.onToggleSecret,
    this.valueSuggestionsFor,
  });
  // ... existing fields ...
  final VariableSuggestionsProvider? valueSuggestionsFor;
```

Add the import at the top of the file:

```dart
import 'package:getman/core/ui/widgets/variable_autocomplete.dart';
import 'package:getman/core/utils/variable_suggestions.dart';
```

- [ ] **Step 5: Build the provider in the parent and pass it in**

In `_KeyValueListEditorState.build`'s `itemBuilder` (around line 196-226), where `_KeyValueRow(...)` is constructed, compute a provider when a `variableContext` is present and the value controller highlights:

```dart
        final varContext = widget.variableContext;
        final valController = _valControllers[index];
        VariableSuggestionsProvider? valueSuggestionsFor;
        if (varContext != null &&
            valController is VariableHighlightController) {
          // (existing onVariableEnter/colors/updateVariables cascade stays.)
          valueSuggestionsFor = (query) => buildVariableSuggestions(
            query: query,
            userVariableNames: varContext.variables.keys,
            classify: (name) => VariableResolutionHelper.classify(
              name: name,
              variables: varContext.variables,
              secretKeys: varContext.secretKeys,
              environmentName: varContext.environmentName,
            ),
          );
        }

        return _KeyValueRow(
          key: ValueKey(_keyControllers[index]),
          // ... existing args ...
          valueSuggestionsFor: valueSuggestionsFor,
        );
```

- [ ] **Step 6: Wrap the value field in `_KeyValueRowState.build`**

In `_KeyValueRowState.build` (around line 300), replace the bare `valueField` `TextField` with the field given a `focusNode`, then conditionally wrap it. Change the `TextField` to add `focusNode: _valueFocusNode,` and wrap after construction:

```dart
    final valueField = TextField(
      key: widget.fieldPrefix == null
          ? null
          : ValueKey('${widget.fieldPrefix}_val_${widget.rowIndex}'),
      style: textStyle,
      focusNode: _valueFocusNode,
      obscureText: widget.isSecret && !_revealed,
      decoration: InputDecoration(
        // ... unchanged ...
      ),
      controller: widget.valController,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onValChanged,
    );
    final valueFieldWithAutocomplete = widget.valueSuggestionsFor == null
        ? valueField
        : VariableAutocomplete(
            controller: widget.valController,
            focusNode: _valueFocusNode,
            suggestionsFor: widget.valueSuggestionsFor!,
            child: valueField,
          );
```

Then use `valueFieldWithAutocomplete` everywhere the layout currently uses `valueField` (the phone `Column` `valueField` at ~line 391 and the desktop `Row`'s `Expanded(child: valueField)` at ~line 398).

- [ ] **Step 7: Run the test to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/key_value_list_editor_test.dart`
Expected: PASS (new test green, all existing tests still green).

- [ ] **Step 8: Format, analyze (incl. custom_lint), commit**

```bash
fvm dart format lib/core/ui/widgets/key_value_list_editor.dart test/core/ui/widgets/key_value_list_editor_test.dart
fvm flutter analyze lib/core/ui/widgets/key_value_list_editor.dart
fvm dart run custom_lint
git add lib/core/ui/widgets/key_value_list_editor.dart test/core/ui/widgets/key_value_list_editor_test.dart
git commit -m "feat(variables): {{var}} autocomplete in params/headers value fields

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Wire autocomplete into the URL bar

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/url_bar.dart`

**Interfaces:**
- Consumes: `VariableAutocomplete` (Task 3), `buildVariableSuggestions` (Task 2), `VariableResolutionHelper.classifyLayered`, plus the env/collection plumbing already imported by `url_bar.dart`.
- Produces: behavior only — the URL field gains the autocomplete menu.

Notes: `url_bar.dart` already gathers the layered context inside `_showVariablePopover` (`lib/features/tabs/presentation/widgets/url_bar.dart:108-132`). This task factors that gather into a reusable helper used by both the popover and the new suggestions provider (DRY), then wraps the URL `TextField` (the `Expanded` at `:228-252`).

- [ ] **Step 1: Add imports**

At the top of `lib/features/tabs/presentation/widgets/url_bar.dart`, add:

```dart
import 'package:getman/core/ui/widgets/variable_autocomplete.dart';
import 'package:getman/core/utils/variable_suggestions.dart';
```

- [ ] **Step 2: Extract a layered-context helper and a suggestions provider**

Add these methods to `_UrlBarState` (next to `_showVariablePopover`):

```dart
  ({
    Map<String, String> envVars,
    Set<String> envSecrets,
    String? envName,
    Map<String, String> collectionVars,
    Set<String> collectionSecrets,
  })
  _layeredContext() {
    final envState = context.read<EnvironmentsBloc>().state;
    final settings = context.read<SettingsBloc>().state.settings;
    final env = ActiveEnvironmentHelper.activeEnvironment(
      envState.environments,
      settings.activeEnvironmentId,
    );
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    final collected = tab?.collectionNodeId == null
        ? (variables: const <String, String>{}, secretKeys: const <String>{})
        : CollectionsTreeHelper.collectVariables(
            context.read<CollectionsBloc>().state.collections,
            tab!.collectionNodeId!,
          );
    return (
      envVars: env?.variables ?? const {},
      envSecrets: env?.secretKeys ?? const {},
      envName: env?.name,
      collectionVars: collected.variables,
      collectionSecrets: collected.secretKeys,
    );
  }

  List<VariableSuggestion> _urlSuggestions(String query) {
    final ctx = _layeredContext();
    return buildVariableSuggestions(
      query: query,
      userVariableNames: <String>{
        ...ctx.envVars.keys,
        ...ctx.collectionVars.keys,
      },
      classify: (name) => VariableResolutionHelper.classifyLayered(
        name: name,
        collectionVariables: ctx.collectionVars,
        collectionSecrets: ctx.collectionSecrets,
        environmentVariables: ctx.envVars,
        environmentSecrets: ctx.envSecrets,
        environmentName: ctx.envName,
      ),
    );
  }
```

- [ ] **Step 3: Refactor `_showVariablePopover` to reuse the helper (DRY)**

Replace the body of `_showVariablePopover` (`:108-132`) so it builds `data` from `_layeredContext()` instead of re-reading the blocs:

```dart
  void _showVariablePopover(String name, Offset globalPosition) {
    if (!mounted) return;
    final ctx = _layeredContext();
    final data = VariableResolutionHelper.classifyLayered(
      name: name,
      collectionVariables: ctx.collectionVars,
      collectionSecrets: ctx.collectionSecrets,
      environmentVariables: ctx.envVars,
      environmentSecrets: ctx.envSecrets,
      environmentName: ctx.envName,
    );
    _hoverController.showFor(context, data, globalPosition);
  }
```

- [ ] **Step 4: Wrap the URL TextField**

At `:228-252`, wrap the `TextField` (currently the direct child of `Expanded`) with `VariableAutocomplete`:

```dart
                          Expanded(
                            child: VariableAutocomplete(
                              controller: _urlController,
                              focusNode: _urlFocusNode,
                              suggestionsFor: _urlSuggestions,
                              child: TextField(
                                key: const ValueKey('url_field'),
                                controller: _urlController,
                                focusNode: _urlFocusNode,
                                // ... rest unchanged ...
                              ),
                            ),
                          ),
```

- [ ] **Step 5: Analyze + run the full suite**

Run:
```bash
fvm dart format lib/features/tabs/presentation/widgets/url_bar.dart
fvm flutter analyze lib/features/tabs/presentation/widgets/url_bar.dart
fvm flutter test
```
Expected: analyze clean; full suite green (no URL-bar widget-test harness exists; behavior is covered by Task 3's widget tests and Task 4's editor test — see Step 6 for the manual smoke).

- [ ] **Step 6: Manual smoke (no automated URL-bar harness)**

Run: `fvm flutter run -d macos`
Verify: in a request tab with an active environment that has e.g. `baseUrl`, focus the URL field, type `{{` → the menu appears with `baseUrl` (+ dynamics); arrow-navigate; Enter inserts `{{baseUrl}}`; Cmd/Ctrl+Space opens it on demand. (On macOS, Cmd+Space may be captured by Spotlight — use Ctrl+Space.)

- [ ] **Step 7: Commit**

```bash
git add lib/features/tabs/presentation/widgets/url_bar.dart
git commit -m "feat(variables): {{var}} autocomplete in the URL bar

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Full verification + wiki sync

**Files:**
- Docs: the `Getman.wiki.git` repo (variables/environments page).

- [ ] **Step 1: Run the full verification bar**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test
fvm flutter test
```
Expected: all clean / 100% green. Fix anything that is not before proceeding.

- [ ] **Step 2: Draft the wiki update**

Per the CLAUDE.md "Keep the wiki in sync" mandate, this adds user-facing behavior. Clone `https://github.com/thiagomiranda3/Getman.wiki.git`, edit the Variables / Environments page to document: typing `{{` (or Cmd/Ctrl+Space) in the URL / params / headers value fields opens an autocomplete menu of environment + collection + dynamic variables; ↑/↓ navigate, Enter/Tab/click insert, Esc dismisses.

- [ ] **Step 3: Confirm before pushing the wiki**

Pushing to the public wiki is an outward-facing action — show the user the drafted page diff and get an explicit go-ahead before `git push` on the wiki repo.

- [ ] **Step 4: Finalize the feature branch**

Use superpowers:finishing-a-development-branch to decide merge/PR/cleanup for `feat/variable-autocomplete`.

---

## Self-Review

**Spec coverage:**
- URL bar autocomplete → Task 5. ✅
- Params/headers value fields → Task 4. ✅
- Trigger `{{` + live filter → Task 1 (detect) + Task 3 (widget listener). ✅
- Cmd/Ctrl+Space → Task 3 (`_OpenSuggestionIntent` / `_openViaShortcut`). ✅
- Enter/Tab/click accept, Esc dismiss, focus-loss close → Task 3. ✅
- List = env + collection + dynamics with preview, secrets masked → Task 2 (`buildVariableSuggestions` + `kSuggestableDynamicNames`) + Task 3 (`_row` masking). ✅
- Insert `name}}` / skip braces if present / caret after `}}` → Task 1 (`hasClosingBraces`) + Task 3 (`_acceptAt`). ✅
- Out-of-scope (body editor, AUTH fields, env-var editor) → untouched (env editor passes no `variableContext`). ✅
- Keyboard-interception via gated `Shortcuts`+`Actions` → Task 3 (`_GatedAction`). ✅
- Theming via `context.app*` → Task 3 `_buildMenu`/`_row`. ✅
- Wiki sync → Task 6. ✅

**Placeholder scan:** No TBD/TODO; every code step shows full code; commands have expected output. ✅

**Type consistency:** `ActiveVariableQuery` fields (`replaceStart`/`replaceEnd`/`query`/`hasClosingBraces`) are used identically in Tasks 1 and 3. `VariableSuggestion` (`name`/`classification`) and `VariableSuggestionsProvider` signatures match across Tasks 2, 3, 4, 5. `buildVariableSuggestions` named params (`query`/`userVariableNames`/`classify`/`includeDynamics`) match every call site. `VariableResolutionHelper.classify` (single-layer, Task 4) and `classifyLayered` (Task 5) match their real signatures in `lib/core/utils/variable_resolution_helper.dart`. ✅
