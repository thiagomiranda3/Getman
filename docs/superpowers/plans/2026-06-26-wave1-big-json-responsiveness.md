# Wave 1 — Big-JSON Responsiveness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the UI thread responsive when rendering big JSON responses by removing synchronous decode/encode/scan work from the hot paths and memoizing per-build recomputation.

**Architecture:** Six surgical perf fixes (audit IDs P-H1, P-H2, P-H3, P-H8, P-H14, P-H16) plus a `test/perf/` micro-benchmark suite. Each fix is behavior-preserving except where it adds an explicit safety cap (P-H3) or makes TREE decode lazy/async (P-H1). No feature behavior changes.

**Tech Stack:** Flutter, `flutter_bloc`, `re_editor`/`re_highlight`, `compute()` (web-safe off-isolate), `flutter_test`.

## Global Constraints

- Flutter is invoked as `fvm flutter ...` (never bare `flutter`).
- **Verification bar after every task** (all must be clean/green before commit): `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test tools`, `fvm flutter test`. The `.githooks/pre-commit` hook runs analyze/custom_lint/bloc_lint/format automatically on commit.
- Off-isolate work uses `compute()` (web-safe), **never** `Isolate.run`.
- Imports are `package:getman/...` (no relative imports); `directives_ordering` enforced.
- Never hardcode colors/sizes/weights/radii — read from `context.appLayout/appPalette/appShape/appTypography/appDecoration`. (`Colors.white`/`Colors.black` only behind the existing `// ignore: avoid_hardcoded_brand_colors` contrast exception.)
- Preserve load-bearing invariants: `_pendingSyncId` async-cancellation in `response_body_view`, `_expanded` ownership in `json_tree_view`, the `ValueKey('body_toggle_*')`/`ValueKey('tree_menu_*')` E2E anchors, and narrow `buildWhen`/`listenWhen` selectors.
- **Every commit message ends with this trailer block** (append verbatim to each commit in this plan):

  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01GocarHQk6SRtETJacrTgin
  ```

- Branch: `chore/refactor-perf-overhaul` (already created off `dev`).

---

### Task 1: P-H14 — memoize response size, stop re-encoding the body for the size label

**Files:**
- Modify: `lib/core/utils/byte_format.dart`
- Test: `test/core/utils/byte_format_test.dart`

**Interfaces:**
- Produces: `int responseSizeBytes(HttpResponseEntity response)` (unchanged signature; now memoized per response instance).

- [ ] **Step 1: Write the failing test**

Add to `test/core/utils/byte_format_test.dart` (inside the existing top-level `main()`):

```dart
  group('responseSizeBytes memoization', () {
    test('multibyte body: stable across repeated calls, equals utf8 length', () {
      // No bodyBytes, no content-length -> utf8 fallback path.
      final resp = HttpResponseEntity(
        statusCode: 200,
        body: 'café ☕ ${'x' * 1000}', // multibyte, so chars != bytes
        headers: const {},
      );
      final expected = utf8.encode(resp.body).length;
      expect(responseSizeBytes(resp), expected);
      // Second call must return the identical value (memoized, not recomputed).
      expect(responseSizeBytes(resp), expected);
    });
  });
```

Ensure the test file imports `dart:convert` and `package:getman/core/network/http_response.dart` (add if missing).

- [ ] **Step 2: Run the test to verify it passes against current behavior, then confirm it still guards after the change**

Run: `fvm flutter test test/core/utils/byte_format_test.dart`
Expected: PASS (current code already returns the utf8 length; this test pins the value so the memoization refactor cannot change it).

- [ ] **Step 3: Apply the memoization**

Replace the body of `lib/core/utils/byte_format.dart` with:

```dart
import 'dart:convert';

import 'package:getman/core/network/http_response.dart';

/// Memoizes the computed size per response instance so a textual body without a
/// `Content-Length` header is UTF-8 measured at most once. Entities are
/// immutable value objects (`copyWithBody` yields a new instance, which
/// correctly misses the cache), so a stale size is impossible. Avoids
/// re-encoding a multi-MB body on every metadata-row rebuild.
final Expando<int> _sizeCache = Expando<int>('responseSizeBytes');

/// Best-effort response size in bytes: prefers [HttpResponseEntity.bodyBytes]
/// if present, else a numeric `Content-Length` header, else the (memoized)
/// UTF-8 byte length of the body.
int responseSizeBytes(HttpResponseEntity response) {
  final bytes = response.bodyBytes;
  if (bytes != null) return bytes.length;
  for (final e in response.headers.entries) {
    if (e.key.toLowerCase() == 'content-length') {
      final n = int.tryParse(e.value.trim());
      if (n != null) return n;
    }
  }
  return _sizeCache[response] ??= utf8.encode(response.body).length;
}

/// Humanizes a byte count as `B` / `KB` / `MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
```

- [ ] **Step 4: Run the verification bar**

Run: `fvm flutter test test/core/utils/byte_format_test.dart && fvm flutter analyze && fvm dart format lib test tools`
Expected: tests PASS, analyze "No issues found!", format reports 0 changed.

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/byte_format.dart test/core/utils/byte_format_test.dart
git commit -m "perf(response): memoize responseSizeBytes to avoid re-encoding body (P-H14)"
```

---

### Task 2: P-H16 — hoist per-call RegExp construction in the variable-name suggester

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/response/response_body_view.dart` (the `_TextualResponseBodyState._suggestVariableName` method, ~lines 209-227)

**Note:** `_suggestVariableName` is a private static method, so there is no external test seam. This is a pure mechanical hoist (identical regex patterns, moved from per-call construction to `static final` fields) with **no observable behavior change**; verification is the existing suite staying green + analyzer clean. (Wave 8 extracts this to a public pure helper with its own tests.)

- [ ] **Step 1: Add the hoisted regex fields**

In `_TextualResponseBodyState` (just below the existing field declarations, before `initState`), add:

```dart
  // Hoisted out of [_suggestVariableName] so the patterns compile once, not on
  // every "Extract to {{var}}" click.
  static final RegExp _dotTailRe = RegExp(r'\.([A-Za-z_$][\w$]*)$');
  static final RegExp _bracketTailRe = RegExp(r'\[(.+)\]$');
  static final RegExp _quoteStripRe = RegExp('''['"]''');
  static final RegExp _nonIdentRe = RegExp('[^A-Za-z0-9_]');
  static final RegExp _digitsRe = RegExp(r'^[0-9]+$');
```

- [ ] **Step 2: Rewrite `_suggestVariableName` to use the fields**

Replace the existing `_suggestVariableName` method body with:

```dart
  /// Derives a starting variable name from a JSONPath's last named segment;
  /// falls back to `value` for array-index or unnamed tails.
  static String _suggestVariableName(String jsonPath) {
    var raw = '';
    final dot = _dotTailRe.firstMatch(jsonPath);
    if (dot != null) {
      raw = dot.group(1)!;
    } else {
      final bracket = _bracketTailRe.firstMatch(jsonPath);
      if (bracket != null) {
        raw = bracket.group(1)!.replaceAll(_quoteStripRe, '');
      }
    }
    final cleaned = raw.replaceAll(_nonIdentRe, '_');
    if (cleaned.isEmpty || _digitsRe.hasMatch(cleaned)) {
      return 'value';
    }
    return cleaned;
  }
```

- [ ] **Step 3: Run the verification bar**

Run: `fvm flutter analyze && fvm dart format lib test tools && fvm flutter test`
Expected: analyze "No issues found!", format 0 changed, all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/tabs/presentation/widgets/response/response_body_view.dart
git commit -m "perf(response): hoist suggest-variable regexes to static final (P-H16)"
```

---

### Task 3: P-H2 — single-pass variable override + skip lines with no `{{`

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/variable_json_span_builder.dart`
- Test: `test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart`

**Interfaces:**
- Produces: `TextSpan variableAwareJsonSpan({...})` — unchanged signature and output; the inner `overrideAt` O(n×m) per-character scan is replaced by an O(line + matches) single sweep, and a `text.contains('{{')` fast-out is added.

**Background:** `EnvironmentResolver.findVariables` yields matches from `RegExp.allMatches`, i.e. ascending by `start` and non-overlapping — so a single monotonic pointer over the matches is correct. The flattened `runs` are contiguous (`[0, cursor)` in order), so a single pointer also works across run boundaries.

- [ ] **Step 1: Write the failing test (fast-out behavior)**

Add to `test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart` inside `main()`. (Match the existing test harness in that file for building a `CodeLine`/`BuildContext`; reuse its existing helper if present.)

```dart
  testWidgets('line without {{ returns the base highlight unchanged', (
    tester,
  ) async {
    late TextSpan base;
    late TextSpan got;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            const line = CodeLine('"plainKey": "no variables here"');
            base = jsonHighlightSpanBuilder(
              context: context,
              index: 0,
              codeLine: line,
              textSpan: const TextSpan(text: line.text),
              style: const TextStyle(),
            );
            got = variableAwareJsonSpan(
              context: context,
              index: 0,
              codeLine: line,
              textSpan: const TextSpan(text: line.text),
              style: const TextStyle(),
              variables: const {'plainKey': 'x'},
              resolvedColor: const Color(0xFF00FF00),
              unresolvedColor: const Color(0xFFFF0000),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // No `{{` in the line -> identical to the base JSON highlight (no recolor).
    expect(got.toPlainText(), base.toPlainText());
    expect(got, equals(base));
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart -p vm --plain-name 'line without'`
Expected: FAIL — current code calls `findVariables(...).toList()` and returns `base` only after that work; the `expect(got, equals(base))` may pass by value today, so if it already passes, treat Step 1 as a regression guard and continue (the optimization must keep it passing).

- [ ] **Step 3: Apply the optimization**

Replace the body of `variableAwareJsonSpan` (everything after the `final base = jsonHighlightSpanBuilder(...)` call) in `lib/features/tabs/presentation/widgets/variable_json_span_builder.dart` with:

```dart
  final text = codeLine.text;
  // Fast-out: no `{{` on the line means no variable token is possible, so the
  // (regex) scan + run flattening is pure waste. Most JSON lines hit this.
  if (!text.contains('{{')) return base;

  final matches = EnvironmentResolver.findVariables(text).toList();
  if (matches.isEmpty) return base;

  // Precompute each match's color once (ascending, non-overlapping ranges).
  final ranges = <({int start, int end, Color color})>[];
  for (final m in matches) {
    final resolved =
        variables.containsKey(m.name) || EnvironmentResolver.isDynamic(m.name);
    ranges.add((
      start: m.start,
      end: m.end,
      color: resolved ? resolvedColor : unresolvedColor,
    ));
  }

  // 1. Flatten `base` into contiguous runs: (start, end, style).
  final runs = <({int start, int end, TextStyle style})>[];
  var cursor = 0;
  void visit(InlineSpan span, TextStyle inherited) {
    if (span is TextSpan) {
      final s = span.style == null ? inherited : inherited.merge(span.style);
      final t = span.text;
      if (t != null && t.isNotEmpty) {
        runs.add((start: cursor, end: cursor + t.length, style: s));
        cursor += t.length;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, s);
      }
    }
  }

  visit(base, style);
  if (cursor == 0) {
    // base had no leaf text (shouldn't happen) — fall back to whole-line style.
    runs.add((start: 0, end: text.length, style: style));
  }

  // 2. Single sweep: runs and ranges are both ascending, so one monotonic
  // pointer `mi` over the ranges suffices. O(line + matches), no per-char scan.
  final children = <InlineSpan>[];
  var mi = 0;
  for (final run in runs) {
    var i = run.start;
    while (i < run.end) {
      while (mi < ranges.length && ranges[mi].end <= i) {
        mi++;
      }
      final inRange =
          mi < ranges.length && i >= ranges[mi].start && i < ranges[mi].end;
      final color = inRange ? ranges[mi].color : null;
      final int j;
      if (inRange) {
        j = ranges[mi].end < run.end ? ranges[mi].end : run.end;
      } else {
        final nextStart = mi < ranges.length ? ranges[mi].start : run.end;
        j = nextStart < run.end ? nextStart : run.end;
      }
      final segStyle = color == null
          ? run.style
          : run.style.copyWith(color: color, fontWeight: FontWeight.w800);
      children.add(TextSpan(text: text.substring(i, j), style: segStyle));
      i = j;
    }
  }
  return TextSpan(style: style, children: children);
}
```

- [ ] **Step 4: Run the full span-builder test file**

Run: `fvm flutter test test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart`
Expected: PASS — all existing variable-coloring tests (resolved/unresolved/multiple-vars) plus the new fast-out test are green (output is byte-identical to the old algorithm).

- [ ] **Step 5: Run the verification bar and commit**

Run: `fvm flutter analyze && fvm dart format lib test tools`

```bash
git add lib/features/tabs/presentation/widgets/variable_json_span_builder.dart test/features/tabs/presentation/widgets/variable_json_span_builder_test.dart
git commit -m "perf(editor): single-pass variable recolor + skip lines with no {{ (P-H2)"
```

---

### Task 4: P-H8 — extract a pure JSON-tree flattener and memoize it per build

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/response/json_tree_view.dart`
- Test: `test/features/tabs/presentation/widgets/response/json_tree_view_test.dart`

**Interfaces:**
- Produces: top-level pure `List<JsonTreeNode> flattenVisibleJsonTree({required Object? data, required Set<String> expanded})` and public class `JsonTreeNode { String path; String label; Object? value; int depth; bool get isContainer; String get preview; }` (rename of the former private `_Node`).
- Consumed by: `_JsonTreeViewState` (memoized) and Task 7's benchmark.

- [ ] **Step 1: Write the failing test for the pure flattener**

Add to `test/features/tabs/presentation/widgets/response/json_tree_view_test.dart` inside `main()`:

```dart
  group('flattenVisibleJsonTree (pure)', () {
    test('collapsed root shows only first-level rows', () {
      final data = {
        'a': 1,
        'b': {'c': 2},
      };
      final nodes = flattenVisibleJsonTree(data: data, expanded: <String>{});
      expect(nodes.map((n) => n.path).toList(), [r'$.a', r'$.b']);
    });

    test('expanded paths reveal their children in order', () {
      final data = {
        'a': 1,
        'b': {'c': 2},
      };
      final nodes = flattenVisibleJsonTree(
        data: data,
        expanded: {r'$.b'},
      );
      expect(nodes.map((n) => n.path).toList(), [r'$.a', r'$.b', r'$.b.c']);
    });

    test('top-level list indexes by position', () {
      final nodes = flattenVisibleJsonTree(
        data: [10, 20],
        expanded: <String>{},
      );
      expect(nodes.map((n) => n.path).toList(), [r'$[0]', r'$[1]']);
      expect(nodes.map((n) => n.label).toList(), ['[0]', '[1]']);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/json_tree_view_test.dart -p vm --plain-name 'flattenVisibleJsonTree'`
Expected: FAIL — `flattenVisibleJsonTree` / `JsonTreeNode` are not defined.

- [ ] **Step 3: Rename `_Node` → `JsonTreeNode` and extract the pure flattener**

In `lib/features/tabs/presentation/widgets/response/json_tree_view.dart`:

(a) Rename the private `_Node` class to a public `JsonTreeNode` (rename the class declaration and its constructor; update the three references inside `_TreeRow`/`_TreeRowState` — `final _Node node;` → `final JsonTreeNode node;`).

(b) Add this top-level pure function (place it just above the `class JsonTreeView`):

```dart
/// Flattens [data] into the visible row list given the set of [expanded] paths.
/// Pure (no widget/state deps) so it is unit-testable and benchmarkable, and so
/// the view can memoize its result across rebuilds that don't change
/// data/expansion. Paths use [JsonPathBuilder] grammar.
List<JsonTreeNode> flattenVisibleJsonTree({
  required Object? data,
  required Set<String> expanded,
}) {
  final out = <JsonTreeNode>[];

  void flatten(Object? value, String path, String label, int depth) {
    out.add(JsonTreeNode(path: path, label: label, value: value, depth: depth));
    if (!expanded.contains(path)) return;
    if (value is Map) {
      for (final e in value.entries) {
        flatten(
          e.value,
          JsonPathBuilder.appendKey(path, e.key.toString()),
          e.key.toString(),
          depth + 1,
        );
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        flatten(
          value[i],
          JsonPathBuilder.appendIndex(path, i),
          '[$i]',
          depth + 1,
        );
      }
    }
  }

  if (data is Map) {
    for (final e in data.entries) {
      flatten(
        e.value,
        JsonPathBuilder.appendKey(JsonPathBuilder.root, e.key.toString()),
        e.key.toString(),
        0,
      );
    }
  } else if (data is List) {
    for (var i = 0; i < data.length; i++) {
      flatten(
        data[i],
        JsonPathBuilder.appendIndex(JsonPathBuilder.root, i),
        '[$i]',
        0,
      );
    }
  } else {
    out.add(JsonTreeNode(path: JsonPathBuilder.root, label: r'$', value: data, depth: 0));
  }
  return out;
}
```

(c) Delete the now-redundant private methods `_visible`, `_flatten`, `_addMap`, `_addList` from `_JsonTreeViewState`.

- [ ] **Step 4: Memoize the flattener in the state**

In `_JsonTreeViewState`:

(a) Add a cache field next to `_expanded`:

```dart
  final Set<String> _expanded = {};

  // Cached flattened rows; invalidated only when data or expansion changes —
  // not on theme/hover-driven rebuilds.
  List<JsonTreeNode>? _flat;
```

(b) In `didUpdateWidget`, invalidate the cache when data changes (inside the existing `if (!identical(...))` block, before/after `_seedExpansion()`):

```dart
  @override
  void didUpdateWidget(JsonTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _expanded.clear();
      _flat = null;
      _seedExpansion();
    }
  }
```

(c) In `_toggle`, invalidate inside the `setState`:

```dart
  void _toggle(String path) {
    setState(() {
      if (!_expanded.remove(path)) _expanded.add(path);
      _flat = null;
    });
  }
```

(d) In `build`, replace `final nodes = _visible();` with:

```dart
    final nodes = _flat ??= flattenVisibleJsonTree(
      data: widget.data,
      expanded: _expanded,
    );
```

- [ ] **Step 5: Run the tree test file**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/json_tree_view_test.dart`
Expected: PASS — the new pure-flattener tests plus all existing widget tests (expand/collapse, copy, extract) are green.

- [ ] **Step 6: Run the verification bar and commit**

Run: `fvm flutter analyze && fvm dart format lib test tools`

```bash
git add lib/features/tabs/presentation/widgets/response/json_tree_view.dart test/features/tabs/presentation/widgets/response/json_tree_view_test.dart
git commit -m "perf(tree): extract pure flattenVisibleJsonTree + memoize per build (P-H8)"
```

---

### Task 5: P-H1 — make TREE-view JSON decode lazy and off-isolate

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/response/response_body_view.dart`
- Modify: `lib/core/domain/persistence_limits.dart`
- Test: `test/features/tabs/presentation/widgets/response/response_body_view_lazy_tree_test.dart` (new)

**Interfaces:**
- Consumes: `JsonPath.tryDecode(String) -> Object?` (static; valid `compute` callback), `flattenVisibleJsonTree`/`JsonTreeNode` (Task 4).
- Produces: no new public API. Internally: `_decoded` is populated lazily only when TREE is first selected; decode runs via `compute()` for bodies over `kTreeInlineDecodeLimit`.

**Behavior change (intended):** TREE is now enabled optimistically when the body *looks* like JSON (`{`/`[` prefix). The actual decode happens on first TREE select; if it fails, the view shows a snackbar and falls back to PRETTY (TREE disabled). This removes the eager synchronous `jsonDecode` that ran on every response arrival.

- [ ] **Step 1: Add the inline-decode threshold constant**

Append to `lib/core/domain/persistence_limits.dart`:

```dart
/// JSON bodies at or below this size decode inline (sub-millisecond); larger
/// bodies decode in a background isolate via `compute()` so selecting TREE on a
/// big response never stalls the UI thread.
const int kTreeInlineDecodeLimit = 64 * 1024; // 64 KiB
```

- [ ] **Step 2: Write the failing widget tests**

Create `test/features/tabs/presentation/widgets/response/response_body_view_lazy_tree_test.dart`. Mirror the harness used by the sibling `response_body_view_compare_test.dart` (same providers / `TabsBloc` setup); the essential assertions:

```dart
// Pseudostructure — adapt provider/bloc wiring to match
// response_body_view_compare_test.dart in the same directory.

  testWidgets('TREE is enabled for a JSON-object body and decodes on tap', (
    tester,
  ) async {
    // Pump ResponseBodyView for a tab whose response.body is '{"a":1,"b":2}'.
    await pumpResponseBodyView(tester, body: '{"a":1,"b":2}');

    // TREE segment is present and enabled (no Tooltip wrapper).
    expect(find.byKey(const ValueKey('body_toggle_TREE')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('body_toggle_TREE')));
    await tester.pumpAndSettle();

    // A tree row for key "a" is rendered (decode happened lazily on tap).
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('non-JSON body leaves TREE disabled', (tester) async {
    await pumpResponseBodyView(tester, body: 'plain text, not json');
    // The TREE segment is wrapped in a Tooltip when disabled.
    final treeFinder = find.byKey(const ValueKey('body_toggle_TREE'));
    expect(treeFinder, findsOneWidget);
    expect(
      find.ancestor(of: treeFinder, matching: find.byType(Tooltip)),
      findsOneWidget,
    );
  });
```

- [ ] **Step 3: Run to verify the new tests fail (or compile-fail) before the change**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/response_body_view_lazy_tree_test.dart`
Expected: FAIL — until the helper `pumpResponseBodyView` and the lazy path exist. (Write the helper to match the compare test's setup; it should fail meaningfully, not on a missing import.)

- [ ] **Step 4: Add lazy-decode state and helpers**

In `_TextualResponseBodyState` (`response_body_view.dart`):

(a) Add a field next to `_treeAvailable`:

```dart
  bool _treeAvailable = false;

  // True while a background (or inline) decode for the tree is in flight.
  bool _treeDecoding = false;
```

(b) Add a cheap JSON-shape probe and the lazy decoder (place near `_clearTreeState`):

```dart
  /// Cheap shape probe — a JSON object/array body starts with `{`/`[`. Used to
  /// enable TREE optimistically without paying a full decode on arrival.
  static bool _looksLikeJson(String? body) {
    if (body == null) return false;
    final t = body.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// Decodes the current body for the tree, lazily and off the UI isolate for
  /// large bodies. On a parse miss (or a JSON scalar), disables TREE and falls
  /// back to PRETTY. Guarded by [_pendingSyncId] so a newer body wins.
  Future<void> _decodeForTree() async {
    final body = context
        .read<TabsBloc>()
        .state
        .tabs
        .byId(widget.tabId)
        ?.response
        ?.body;
    if (body == null || body == kResponseBodyTooLargePlaceholder) {
      setState(() {
        _treeAvailable = false;
        if (_mode == _BodyMode.tree) _mode = _BodyMode.pretty;
      });
      return;
    }
    final syncId = _pendingSyncId;
    setState(() => _treeDecoding = true);
    final decoded = body.length > kTreeInlineDecodeLimit
        ? await compute(JsonPath.tryDecode, body)
        : JsonPath.tryDecode(body);
    if (!mounted || syncId != _pendingSyncId) return;
    final treeOk = decoded is Map || decoded is List;
    setState(() {
      _treeDecoding = false;
      if (treeOk) {
        _decoded = decoded;
      } else {
        _treeAvailable = false;
        if (_mode == _BodyMode.tree) _mode = _BodyMode.pretty;
      }
    });
    if (!treeOk) showAppSnackBar(context, 'Not a JSON object/array');
  }
```

(c) Update `_clearTreeState` to also clear the decoding flag:

```dart
  /// Resets tree state (large mode has no tree). Call inside a setState.
  void _clearTreeState() {
    _decoded = null;
    _treeAvailable = false;
    _treeDecoding = false;
    if (_mode == _BodyMode.tree) _mode = _BodyMode.pretty;
  }
```

- [ ] **Step 5: Replace the eager decode in `_syncBody` (normal path)**

In `_syncBody`, replace the block from `widget.responseController.text = text;` through the end of the method (the `final decoded = ...` eager decode and its `setState`) with:

```dart
    widget.responseController.text = text;
    // Tree decode is now LAZY (see _decodeForTree): enable TREE optimistically
    // from a cheap shape probe; the real (possibly off-isolate) decode happens
    // only when the user selects TREE. This removes the synchronous jsonDecode
    // that previously ran on every response arrival.
    final treeMaybe = _looksLikeJson(rawBody) && !isPlaceholder;
    setState(() {
      _largeBody = null;
      _showFullPreview = false;
      _highlightingOptedIn = false;
      _decoded = null;
      _treeDecoding = false;
      _treeAvailable = treeMaybe;
      if (_mode == _BodyMode.tree && !treeMaybe) _mode = _BodyMode.pretty;
    });
    // If the user is already viewing TREE and the body changed, re-decode now.
    if (_mode == _BodyMode.tree && treeMaybe) {
      unawaited(_decodeForTree());
    }
  }
```

- [ ] **Step 6: Trigger decode when switching to TREE**

Replace `_setMode` with:

```dart
  void _setMode(_BodyMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (mode == _BodyMode.tree) {
      // Lazy: decode only now, and only if not already decoded/in-flight.
      if (_decoded == null && !_treeDecoding) unawaited(_decodeForTree());
    } else {
      // Switching the editor's pretty/raw rendering needs a re-sync.
      final body = context
          .read<TabsBloc>()
          .state
          .tabs
          .byId(widget.tabId)
          ?.response
          ?.body;
      unawaited(_syncBody(body));
    }
  }
```

- [ ] **Step 7: Show a spinner while TREE decodes**

In `_buildSmallMode`, replace the `Expanded(child: _mode == _BodyMode.tree ? JsonTreeView(...) : _buildEditorMode())` with:

```dart
        Expanded(
          child: _mode == _BodyMode.tree
              ? (_decoded != null
                    ? JsonTreeView(data: _decoded, onExtract: _extractToVariable)
                    : const Center(child: CircularProgressIndicator()))
              : _buildEditorMode(),
        ),
```

- [ ] **Step 8: Run the new + existing response tests**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/`
Expected: PASS. If any pre-existing test taps TREE and expected the tree synchronously, add a `await tester.pumpAndSettle();` after the tap (the decode is now async). Fix such tests in this commit.

- [ ] **Step 9: Run the full suite + verification bar**

Run: `fvm flutter test && fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test tools`
Expected: all green / no issues. (Watch for any `integration_test` TREE flow needing a settle — fix if present.)

- [ ] **Step 10: Commit**

```bash
git add lib/features/tabs/presentation/widgets/response/response_body_view.dart lib/core/domain/persistence_limits.dart test/features/tabs/presentation/widgets/response/response_body_view_lazy_tree_test.dart
git commit -m "perf(response): lazy + off-isolate TREE decode (P-H1)"
```

---

### Task 6: P-H3 — hard size cap on the opt-in highlighted/prettified path

**Files:**
- Modify: `lib/core/domain/persistence_limits.dart`
- Modify: `lib/features/tabs/presentation/widgets/response/response_body_view.dart`
- Test: `test/core/domain/persistence_limits_test.dart` (new)

**Interfaces:**
- Produces: `const int kMaxHighlightChars` and `bool canHighlightBody(int chars)` in `persistence_limits.dart`.

- [ ] **Step 1: Write the failing boundary test**

Create `test/core/domain/persistence_limits_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/persistence_limits.dart';

void main() {
  group('canHighlightBody', () {
    test('allows up to and including the cap', () {
      expect(canHighlightBody(0), isTrue);
      expect(canHighlightBody(kMaxHighlightChars), isTrue);
    });

    test('rejects beyond the cap', () {
      expect(canHighlightBody(kMaxHighlightChars + 1), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/domain/persistence_limits_test.dart`
Expected: FAIL — `kMaxHighlightChars` / `canHighlightBody` undefined.

- [ ] **Step 3: Add the cap + predicate**

Append to `lib/core/domain/persistence_limits.dart`:

```dart
/// Hard ceiling for highlighted/prettified rendering. Even when the user opts
/// into highlighting a large body (`alwaysPrettifyLargeResponses` or the
/// "PRETTIFY & SHOW" action), bodies over this size stay plain text — loading a
/// multi-MB string into re_editor rebuilds its line model synchronously on the
/// UI thread and freezes the app.
const int kMaxHighlightChars = 3 * 1024 * 1024; // 3 MiB

/// Whether a body of [chars] length may be loaded into the highlighted editor.
bool canHighlightBody(int chars) => chars <= kMaxHighlightChars;
```

- [ ] **Step 4: Apply the cap in the auto-prettify branch**

In `response_body_view.dart` `_syncBody`, extend the `autoPrettify` condition (currently `...alwaysPrettifyLargeResponses && rawBody != kResponseBodyTooLargePlaceholder`) to also require the cap:

```dart
      final autoPrettify =
          context
              .read<SettingsBloc>()
              .state
              .settings
              .alwaysPrettifyLargeResponses &&
          rawBody != kResponseBodyTooLargePlaceholder &&
          canHighlightBody(rawBody.length);
```

(Over-cap bodies now fall through to the existing plain-text large path automatically.)

- [ ] **Step 5: Apply the cap in `_prettifyAndOptIn`**

Replace `_prettifyAndOptIn` with:

```dart
  Future<void> _prettifyAndOptIn() async {
    final body = _largeBody;
    if (body == null) return;
    if (!canHighlightBody(body.length)) {
      showAppSnackBar(
        context,
        'Body too large to highlight (over 3 MB) — showing plain text',
      );
      return;
    }
    final syncId = ++_pendingSyncId;
    final prettified = await JsonUtils.prettify(body);
    if (!mounted || syncId != _pendingSyncId) return;
    widget.responseController.text = prettified;
    setState(() => _highlightingOptedIn = true);
  }
```

- [ ] **Step 6: Write a widget test for the cap (plain-text fallback)**

Add to the lazy-tree test file from Task 5 (same harness):

```dart
  testWidgets('over-cap body stays plain text under alwaysPrettify', (
    tester,
  ) async {
    final huge = 'x' * (kMaxHighlightChars + 1024); // > 3 MiB, not JSON
    await pumpResponseBodyView(
      tester,
      body: huge,
      alwaysPrettifyLargeResponses: true,
    );
    await tester.pumpAndSettle();
    // Plain-text large path: a SelectableText, no CodeEditor.
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(CodeEditor), findsNothing);
  });
```

(Extend `pumpResponseBodyView` with an `alwaysPrettifyLargeResponses` flag wired through the `SettingsBloc` seed. Import `kMaxHighlightChars` and `re_editor`'s `CodeEditor`.)

- [ ] **Step 7: Run tests + verification bar**

Run: `fvm flutter test test/core/domain/persistence_limits_test.dart test/features/tabs/presentation/widgets/response/ && fvm flutter analyze && fvm dart format lib test tools`
Expected: PASS / no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/core/domain/persistence_limits.dart lib/features/tabs/presentation/widgets/response/response_body_view.dart test/core/domain/persistence_limits_test.dart test/features/tabs/presentation/widgets/response/response_body_view_lazy_tree_test.dart
git commit -m "perf(response): cap highlighted render at 3 MiB, plain text beyond (P-H3)"
```

---

### Task 7: `test/perf/` micro-benchmark suite

**Files:**
- Create: `test/perf/wave1_bench_test.dart`

**Interfaces:**
- Consumes: `JsonPath.tryDecode`, `JsonUtils.prettify`, `EnvironmentResolver.findVariables`, `responseSizeBytes`, `flattenVisibleJsonTree`.

**Purpose:** Lock in the architectural properties (cached/off-thread/single-pass) and print before/after-style timings. These assert correctness + that the operation completes within a generous ceiling; they do **not** hard-assert tight latency (CI-stable).

- [ ] **Step 1: Write the benchmark suite**

Create `test/perf/wave1_bench_test.dart`:

```dart
@Tags(['perf'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/presentation/widgets/response/json_tree_view.dart';

String _bigJson(int entries) {
  final m = {for (var i = 0; i < entries; i++) 'key_$i': 'value_$i'};
  return jsonEncode(m);
}

void main() {
  test('bench: JsonPath.tryDecode of ~1MB JSON completes and round-trips', () {
    final body = _bigJson(20000);
    final sw = Stopwatch()..start();
    final decoded = JsonPath.tryDecode(body);
    sw.stop();
    // ignore: avoid_print
    print('tryDecode(${body.length} chars): ${sw.elapsedMilliseconds}ms');
    expect(decoded, isA<Map<String, dynamic>>());
  });

  test('bench: JsonUtils.prettify shortcuts non-JSON instantly', () async {
    const html = '<html><body>not json</body></html>';
    final sw = Stopwatch()..start();
    final out = await JsonUtils.prettify(html);
    sw.stop();
    // ignore: avoid_print
    print('prettify(non-json): ${sw.elapsedMicroseconds}us');
    expect(out, html); // short-circuit returns the body verbatim, no isolate
  });

  test('bench: findVariables over a 2000-char line', () {
    final line = '${'a' * 1000}{{token}} mid {{\$guid}} ${'b' * 1000}';
    final sw = Stopwatch()..start();
    final matches = EnvironmentResolver.findVariables(line).toList();
    sw.stop();
    // ignore: avoid_print
    print('findVariables(2000 chars): ${sw.elapsedMicroseconds}us');
    expect(matches.length, 2);
  });

  test('bench: responseSizeBytes is memoized per instance', () {
    final resp = HttpResponseEntity(
      statusCode: 200,
      body: 'x' * (256 * 1024),
      headers: const {},
    );
    final first = Stopwatch()..start();
    final a = responseSizeBytes(resp);
    first.stop();
    final second = Stopwatch()..start();
    final b = responseSizeBytes(resp);
    second.stop();
    // ignore: avoid_print
    print(
      'responseSizeBytes first=${first.elapsedMicroseconds}us '
      'cached=${second.elapsedMicroseconds}us',
    );
    expect(a, b);
    expect(a, 256 * 1024);
  });

  test('bench: flattenVisibleJsonTree over a wide object (collapsed)', () {
    final data = {for (var i = 0; i < 5000; i++) 'k$i': i};
    final sw = Stopwatch()..start();
    final nodes = flattenVisibleJsonTree(data: data, expanded: <String>{});
    sw.stop();
    // ignore: avoid_print
    print('flatten(5000 keys, collapsed): ${sw.elapsedMilliseconds}ms');
    expect(nodes.length, 5000);
  });
}
```

(Adjust the `HttpResponseEntity` constructor arguments to match its actual required parameters — check `lib/core/network/http_response.dart`.)

- [ ] **Step 2: Run the benchmark suite**

Run: `fvm flutter test test/perf/wave1_bench_test.dart`
Expected: PASS, with timing lines printed.

- [ ] **Step 3: Run the full verification bar**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`
Expected: no issues, all green.

- [ ] **Step 4: Commit**

```bash
git add test/perf/wave1_bench_test.dart
git commit -m "test(perf): wave 1 big-JSON micro-benchmarks"
```

---

## Self-Review

**Spec coverage (Wave 1 = P-H1, P-H2, P-H3, P-H8, P-H14, P-H16 + benchmarks):**
- P-H1 → Task 5 (lazy + off-isolate TREE decode). ✓
- P-H2 → Task 3 (single-pass + skip-no-`{{`). ✓
- P-H3 → Task 6 (3 MiB highlight cap). ✓
- P-H8 → Task 4 (pure flattener + memoize). ✓
- P-H14 → Task 1 (Expando memoization). ✓
- P-H16 → Task 2 (hoist regexes). ✓
- Micro-benchmarks → Task 7. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. The two spots requiring local adaptation (the `pumpResponseBodyView` helper in Tasks 5/6 and the `HttpResponseEntity` constructor args in Task 7) explicitly say to mirror the sibling `response_body_view_compare_test.dart` and the real constructor — these are harness-fit details, not logic placeholders.

**Type consistency:** `flattenVisibleJsonTree` / `JsonTreeNode` defined in Task 4 are consumed identically in Task 7. `canHighlightBody`/`kMaxHighlightChars` defined in Task 6 consumed in Tasks 5/6/7 contexts. `kTreeInlineDecodeLimit` defined in Task 5. `_decodeForTree`/`_looksLikeJson`/`_treeDecoding` introduced and used consistently within Task 5. `compute(JsonPath.tryDecode, body)` — `JsonPath.tryDecode` is a static `Object? Function(String)`, valid as a `compute` callback (re-exported `compute` via `package:flutter/material.dart`).

**Ordering note:** Task 4 (flattener) precedes Task 5 (lazy decode that feeds `JsonTreeView`) and Task 7 (benchmarks the flattener). Task 6 reuses Task 5's new test file. No forward dependencies broken.
