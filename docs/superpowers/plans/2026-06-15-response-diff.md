# Response Diff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user compare the **current tab's response** against a **chosen target response** (a saved example of the linked collection node, or a recent history entry whose `method`+`url` match) and see a unified, per-line-colored diff of the pretty-printed bodies plus a status/header delta summary. Read-only, computed on demand from in-memory bloc state, no new Hive typeId, no new dependency.

**Architecture:** Five isolated units, pure-logic first.
1. `lib/core/utils/line_diff.dart` — pure-Dart LCS line diff (`DiffLineKind`, `DiffLine`, `LineDiff.diff` / `diffText`).
2. `lib/core/utils/response_diff_builder.dart` — pure-Dart builder mapping two `HttpResponseEntity` into a render-agnostic `ResponseDiffModel` (`HeaderDelta`, prettify + large-body guard live here) + a `responseFromConfig(HttpRequestConfigEntity)` reconstruction helper.
3. `lib/core/theme/extensions/app_palette.dart` — four new fields (`diffAddedBackground`/`diffAddedForeground`/`diffRemovedBackground`/`diffRemovedForeground`), wired through constructor/`copyWith`/`lerp`, with values supplied in all four theme builders (brutalist/dracula/editorial/rpg) in one task so analysis stays green.
4. `lib/core/ui/widgets/response_diff_view.dart` — diff view dialog (`ResponseDiffView`) over a resolved `ResponseDiffModel` + two source labels.
5. `lib/core/ui/widgets/compare_target_picker.dart` — target-picker dialog (`CompareTargetSource`, `CompareTarget`, `CompareTargetPicker`), a pure presentational atom passed its data.

Then the entry-point wiring in `lib/features/tabs/presentation/widgets/response/response_body_view.dart` reads `TabsBloc`/`CollectionsBloc`/`HistoryBloc` at the widget layer (never bloc→bloc, mirroring `EnvironmentsDialog._deleteEnvironment`), maps state into `CompareTarget`s, opens the picker, then builds + shows the diff.

**Tech Stack:** Flutter (`fvm flutter`), `flutter_bloc`, `equatable`, `flutter_test`. No new dependencies (LCS is written in-repo per the surgical-dependency mandate).

**Done-bar for the whole plan (CLAUDE.md §5):** `fvm flutter analyze` (very_good_analysis), `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format`, and `fvm flutter test` all clean/green. There are no bloc changes — the feature is widgets + pure utils.

---

## File Structure

**Create:**
- `lib/core/utils/line_diff.dart` — `DiffLineKind`, `DiffLine`, `LineDiff`.
- `lib/core/utils/response_diff_builder.dart` — `HeaderDelta`, `ResponseDiffModel`, `ResponseDiffBuilder`, `responseFromConfig`.
- `lib/core/ui/widgets/response_diff_view.dart` — `ResponseDiffView`.
- `lib/core/ui/widgets/compare_target_picker.dart` — `CompareTargetSource`, `CompareTarget`, `CompareTargetPicker`.
- `test/core/utils/line_diff_test.dart`
- `test/core/utils/response_diff_builder_test.dart`
- `test/core/ui/widgets/compare_target_picker_test.dart`
- `test/core/ui/widgets/response_diff_view_test.dart`
- `test/features/tabs/presentation/widgets/response/response_body_view_compare_test.dart`

**Modify:**
- `lib/core/theme/extensions/app_palette.dart` — four new diff color fields (constructor/`copyWith`/`lerp`).
- `lib/core/theme/themes/brutalist/brutalist_theme.dart` — supply the four fields in the `AppPalette(...)` call.
- `lib/core/theme/themes/dracula/dracula_theme.dart` — same.
- `lib/core/theme/themes/editorial/editorial_theme.dart` — same.
- `lib/core/theme/themes/rpg/rpg_theme.dart` — same.
- `lib/features/tabs/presentation/widgets/response/response_body_view.dart` — `_compareButton` + `_compareResponse` wiring, added to the action `Row` in `_buildSmallMode` and `_buildLargeMode`.

**Wiki (Task 8):** `Getman.wiki.git` — Response-diff page (or fold into the existing Response page) + `_Sidebar.md`.

---

## Verified facts the snippets rely on (do not re-derive)

- `HttpResponseEntity` (`lib/core/network/http_response.dart`): `const HttpResponseEntity({required int statusCode, required String body, required Map<String, String> headers, required int durationMs})`. Fields: `statusCode` (non-null `int`), `body` (`String`), `headers` (`Map<String, String>`), `durationMs` (`int`). `props` = `[statusCode, body, headers, durationMs]`.
- `HttpRequestConfigEntity` (`lib/core/domain/entities/request_config_entity.dart`): carries response columns as **nullable** `String? responseBody`, `Map<String, String>? responseHeaders`, `int? statusCode`, `int? durationMs`, plus `String method`, `String url`. `import 'package:getman/core/domain/entities/request_config_entity.dart';`
- `JsonUtils.prettify` (`lib/core/utils/json_utils.dart`): `static Future<String> prettify(String? body)` — async, hops `compute` only for `{`/`[`-leading bodies; returns the body verbatim for non-JSON / empty. Awaitable.
- `kLargeResponseViewerChars` (`lib/core/domain/persistence_limits.dart`) = `512 * 1024`. `kResponseBodyTooLargePlaceholder` is the over-1-MB sentinel string. `import 'package:getman/core/domain/persistence_limits.dart';`
- `SavedExampleEntity` (`lib/features/collections/domain/entities/saved_example_entity.dart`): `{String id, String name, DateTime capturedAt, HttpRequestConfigEntity config}`.
- `CollectionNodeEntity.examples` is `List<SavedExampleEntity>`; `CollectionsBloc` state field is `collections` (`List<CollectionNodeEntity>`), state class `CollectionsState` (`lib/features/collections/presentation/bloc/collections_state.dart`).
- `CollectionsTreeHelper.findNode(List<CollectionNodeEntity> nodes, String id)` → `CollectionNodeEntity?` (`lib/features/collections/domain/logic/collections_tree_helper.dart`).
- `HistoryState.history` is `List<HttpRequestConfigEntity>` (`lib/features/history/presentation/bloc/history_state.dart`), newest-first.
- `HttpRequestTabEntity`: `config` (`HttpRequestConfigEntity`), `response` (`HttpResponseEntity?`), `collectionNodeId` (`String?`). `state.tabs.byId(id)` via the `HttpRequestTabLookup` extension on `Iterable<HttpRequestTabEntity>` (`lib/features/tabs/domain/entities/request_tab_entity.dart`).
- `TabsState` is in `lib/features/tabs/presentation/bloc/tabs_state.dart`; bloc `TabsBloc` in `tabs_bloc.dart`.
- `ResponsiveDialogScaffold({required Widget title, required Widget content, List<Widget>? actions, EdgeInsetsGeometry? contentPadding})` and `Future<T?> showResponsiveDialog<T>(BuildContext, {required WidgetBuilder builder, bool barrierDismissible = true})` (`lib/core/ui/widgets/responsive_dialog.dart`).
- Theme accessors via `import 'package:getman/core/theme/app_theme.dart';`: `context.appLayout` (`fontSizeCode`, `fontSizeSmall`, `fontSizeNormal`, `pagePadding`, `tabSpacing`, `iconSize`, `isCompact`), `context.appPalette` (`statusAccent(int)`, `statusColor(int)`, `codeBackground`, `onColor(Color)`, and the new diff colors), `context.appTypography` (`codeFontFamily`, `titleWeight`, `displayWeight`, `bodyWeight`), `context.appDecoration.panelBox(context)`, `context.appShape`.
- Theme id constants (`lib/core/theme/theme_ids.dart`): `kBrutalistThemeId`, `kEditorialThemeId`, `kRpgThemeId`, `kDraculaThemeId`. `resolveTheme(String? id)` → `ThemeData Function(Brightness, {bool isCompact})` (`lib/core/theme/theme_registry.dart`).

---

### Task 1: Pure LCS line-diff util

**Files:**
- Create: `lib/core/utils/line_diff.dart`
- Test: `test/core/utils/line_diff_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/utils/line_diff_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/line_diff.dart';

void main() {
  group('LineDiff.diff', () {
    test('identical inputs are all equal', () {
      final out = LineDiff.diff(['a', 'b', 'c'], ['a', 'b', 'c']);
      expect(out.map((l) => l.kind), everyElement(DiffLineKind.equal));
      expect(out.map((l) => l.text).toList(), ['a', 'b', 'c']);
    });

    test('pure insertion marks the new line added', () {
      final out = LineDiff.diff(['a', 'c'], ['a', 'b', 'c']);
      expect(out, const [
        DiffLine(DiffLineKind.equal, 'a'),
        DiffLine(DiffLineKind.added, 'b'),
        DiffLine(DiffLineKind.equal, 'c'),
      ]);
    });

    test('pure deletion marks the dropped line removed', () {
      final out = LineDiff.diff(['a', 'b', 'c'], ['a', 'c']);
      expect(out, const [
        DiffLine(DiffLineKind.equal, 'a'),
        DiffLine(DiffLineKind.removed, 'b'),
        DiffLine(DiffLineKind.equal, 'c'),
      ]);
    });

    test('replacement emits removed before added (unified order)', () {
      final out = LineDiff.diff(['a', 'x', 'c'], ['a', 'y', 'c']);
      expect(out, const [
        DiffLine(DiffLineKind.equal, 'a'),
        DiffLine(DiffLineKind.removed, 'x'),
        DiffLine(DiffLineKind.added, 'y'),
        DiffLine(DiffLineKind.equal, 'c'),
      ]);
    });

    test('empty left yields all added', () {
      final out = LineDiff.diff(const [], ['a', 'b']);
      expect(out, const [
        DiffLine(DiffLineKind.added, 'a'),
        DiffLine(DiffLineKind.added, 'b'),
      ]);
    });

    test('empty right yields all removed', () {
      final out = LineDiff.diff(['a', 'b'], const []);
      expect(out, const [
        DiffLine(DiffLineKind.removed, 'a'),
        DiffLine(DiffLineKind.removed, 'b'),
      ]);
    });

    test('two empty inputs yield an empty diff', () {
      expect(LineDiff.diff(const [], const []), isEmpty);
    });
  });

  group('LineDiff.diffText', () {
    test('splits on newline and diffs line lists', () {
      final out = LineDiff.diffText('a\nb', 'a\nB');
      expect(out, const [
        DiffLine(DiffLineKind.equal, 'a'),
        DiffLine(DiffLineKind.removed, 'b'),
        DiffLine(DiffLineKind.added, 'B'),
      ]);
    });

    test('a single trailing newline does not add an empty line', () {
      final out = LineDiff.diffText('a\nb\n', 'a\nb\n');
      expect(out.map((l) => l.text).toList(), ['a', 'b']);
      expect(out.map((l) => l.kind), everyElement(DiffLineKind.equal));
    });

    test('empty strings diff to an empty list', () {
      expect(LineDiff.diffText('', ''), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/line_diff_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:getman/core/utils/line_diff.dart'`.

- [ ] **Step 3: Implement the util**

Create `lib/core/utils/line_diff.dart`:

```dart
import 'package:equatable/equatable.dart';

/// Whether a line is unchanged, present only on the right (added), or present
/// only on the left (removed) in a unified line diff.
enum DiffLineKind { equal, added, removed }

/// One line of a unified line diff: its [kind] and content (no trailing
/// newline).
class DiffLine extends Equatable {
  const DiffLine(this.kind, this.text);

  final DiffLineKind kind;
  final String text;

  @override
  List<Object?> get props => [kind, text];
}

/// A small, dependency-free LCS line diff. The table is over line *lists*
/// (line counts, not characters, drive its size), which is ample for response
/// bodies and keeps the logic pure and testable.
class LineDiff {
  const LineDiff._();

  /// LCS-based unified line diff. [left] lines absent from the LCS are
  /// [DiffLineKind.removed]; [right] lines absent from the LCS are
  /// [DiffLineKind.added]; LCS lines are [DiffLineKind.equal]. Within a changed
  /// hunk, all removed lines precede added lines (unified-diff convention).
  static List<DiffLine> diff(List<String> left, List<String> right) {
    final n = left.length;
    final m = right.length;

    // LCS length DP table. lcs[i][j] = LCS length of left[i..] and right[j..].
    final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (left[i] == right[j]) {
          lcs[i][j] = lcs[i + 1][j + 1] + 1;
        } else {
          lcs[i][j] = lcs[i + 1][j] >= lcs[i][j + 1]
              ? lcs[i + 1][j]
              : lcs[i][j + 1];
        }
      }
    }

    final out = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (left[i] == right[j]) {
        out.add(DiffLine(DiffLineKind.equal, left[i]));
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        // Dropping left[i] keeps the LCS at least as long -> it was removed.
        out.add(DiffLine(DiffLineKind.removed, left[i]));
        i++;
      } else {
        out.add(DiffLine(DiffLineKind.added, right[j]));
        j++;
      }
    }
    while (i < n) {
      out.add(DiffLine(DiffLineKind.removed, left[i]));
      i++;
    }
    while (j < m) {
      out.add(DiffLine(DiffLineKind.added, right[j]));
      j++;
    }
    return out;
  }

  /// Splits both inputs on `\n` and diffs. A single trailing newline is dropped
  /// so `"a\nb\n"` diffs as `["a", "b"]`, matching what the body viewer shows.
  static List<DiffLine> diffText(String left, String right) {
    return diff(_lines(left), _lines(right));
  }

  static List<String> _lines(String text) {
    if (text.isEmpty) return const [];
    final parts = text.split('\n');
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    return parts;
  }
}
```

> Note on the replacement-ordering test: when `lcs[i+1][j] == lcs[i][j+1]` the loop prefers `removed` (the `>=` branch), so for `[a,x,c]` vs `[a,y,c]` it emits `removed x` then `added y` — exactly the asserted unified order.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/line_diff_test.dart`
Expected: PASS (all 10 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/line_diff.dart test/core/utils/line_diff_test.dart
git commit -m "feat(diff): pure LCS line-diff util" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Diff-model builder + `responseFromConfig`

**Files:**
- Create: `lib/core/utils/response_diff_builder.dart`
- Test: `test/core/utils/response_diff_builder_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/utils/response_diff_builder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/line_diff.dart';
import 'package:getman/core/utils/response_diff_builder.dart';

HttpResponseEntity _resp({
  int status = 200,
  String body = '',
  Map<String, String> headers = const {},
}) {
  return HttpResponseEntity(
    statusCode: status,
    body: body,
    headers: headers,
    durationMs: 1,
  );
}

void main() {
  group('ResponseDiffBuilder.build', () {
    test('copies both status codes through', () async {
      final model = await ResponseDiffBuilder.build(
        _resp(status: 200),
        _resp(status: 404),
      );
      expect(model.leftStatus, 200);
      expect(model.rightStatus, 404);
    });

    test('identical bodies set bodiesIdentical', () async {
      final model = await ResponseDiffBuilder.build(
        _resp(body: 'hello\nworld'),
        _resp(body: 'hello\nworld'),
      );
      expect(model.bodiesIdentical, isTrue);
      expect(
        model.bodyLines.map((l) => l.kind),
        everyElement(DiffLineKind.equal),
      );
    });

    test('different bodies are diffed line-level after prettify', () async {
      final model = await ResponseDiffBuilder.build(
        _resp(body: '{"a":1}'),
        _resp(body: '{"a":2}'),
      );
      expect(model.bodiesIdentical, isFalse);
      expect(
        model.bodyLines.where((l) => l.kind == DiffLineKind.removed),
        isNotEmpty,
      );
      expect(
        model.bodyLines.where((l) => l.kind == DiffLineKind.added),
        isNotEmpty,
      );
    });

    test('header added/removed/changed deltas, case-insensitive key match',
        () async {
      final model = await ResponseDiffBuilder.build(
        _resp(headers: const {
          'Content-Type': 'application/json',
          'X-Old': 'gone',
          'ETag': 'v1',
        }),
        _resp(headers: const {
          'content-type': 'application/json', // same value, casing differs
          'X-New': 'fresh',
          'ETag': 'v2',
        }),
      );
      final byKey = {
        for (final d in model.headerDeltas) d.key.toLowerCase(): d,
      };
      // content-type unchanged -> no delta despite casing difference.
      expect(byKey.containsKey('content-type'), isFalse);
      expect(byKey['x-old']!.isRemoved, isTrue);
      expect(byKey['x-new']!.isAdded, isTrue);
      expect(byKey['etag']!.isChanged, isTrue);
    });

    test('tooLarge short-circuits when either body exceeds the threshold',
        () async {
      final huge = 'x' * (kLargeResponseViewerChars + 1);
      final model = await ResponseDiffBuilder.build(
        _resp(body: huge),
        _resp(body: 'small'),
      );
      expect(model.tooLarge, isTrue);
      expect(model.bodyLines, isEmpty);
      // Status + header summary still populated.
      expect(model.leftStatus, 200);
    });

    test('responseFromConfig reconstructs a response from saved columns', () {
      final config = HttpRequestConfigEntity(
        id: 'cfg',
        method: 'GET',
        url: 'https://api.example.com/users',
        statusCode: 201,
        responseBody: '{"ok":true}',
        responseHeaders: const {'X-Test': '1'},
        durationMs: 42,
      );
      final r = responseFromConfig(config);
      expect(r, isNotNull);
      expect(r!.statusCode, 201);
      expect(r.body, '{"ok":true}');
      expect(r.headers, const {'X-Test': '1'});
      expect(r.durationMs, 42);
    });

    test('responseFromConfig returns null when statusCode is absent', () {
      final config = HttpRequestConfigEntity(id: 'cfg');
      expect(responseFromConfig(config), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/response_diff_builder_test.dart`
Expected: FAIL — `response_diff_builder.dart` does not exist.

- [ ] **Step 3: Implement the builder**

Create `lib/core/utils/response_diff_builder.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/core/utils/line_diff.dart';

/// One differing response header. [left]/[right] are the values on each side;
/// `null` means the header is absent on that side.
class HeaderDelta extends Equatable {
  const HeaderDelta({required this.key, required this.left, required this.right});

  final String key;
  final String? left;
  final String? right;

  bool get isAdded => left == null && right != null;
  bool get isRemoved => left != null && right == null;
  bool get isChanged => left != null && right != null && left != right;

  @override
  List<Object?> get props => [key, left, right];
}

/// A fully-rendered, render-agnostic diff of two responses. The widget layer
/// only paints this — prettify + the large-body guard already ran here.
class ResponseDiffModel extends Equatable {
  const ResponseDiffModel({
    required this.leftStatus,
    required this.rightStatus,
    required this.bodyLines,
    required this.headerDeltas,
    required this.bodiesIdentical,
    required this.tooLarge,
  });

  final int leftStatus;
  final int rightStatus;

  /// Unified line diff of the pretty-printed bodies. Empty when [tooLarge].
  final List<DiffLine> bodyLines;

  /// Only the header keys that differ (added / removed / changed).
  final List<HeaderDelta> headerDeltas;

  /// True when no add/remove lines exist (bodies render identically).
  final bool bodiesIdentical;

  /// True when a body exceeded [kLargeResponseViewerChars]; no prettify/LCS ran.
  final bool tooLarge;

  @override
  List<Object?> get props => [
    leftStatus,
    rightStatus,
    bodyLines,
    headerDeltas,
    bodiesIdentical,
    tooLarge,
  ];
}

/// Maps two [HttpResponseEntity] into a [ResponseDiffModel]. [left] is the
/// current tab's response, [right] the chosen target. Async because it awaits
/// [JsonUtils.prettify] (which may hop an isolate).
class ResponseDiffBuilder {
  const ResponseDiffBuilder._();

  static Future<ResponseDiffModel> build(
    HttpResponseEntity left,
    HttpResponseEntity right,
  ) async {
    final headerDeltas = _headerDeltas(left.headers, right.headers);

    // Large guard: never prettify / diff multi-MB strings on the UI isolate.
    if (left.body.length > kLargeResponseViewerChars ||
        right.body.length > kLargeResponseViewerChars) {
      return ResponseDiffModel(
        leftStatus: left.statusCode,
        rightStatus: right.statusCode,
        bodyLines: const [],
        headerDeltas: headerDeltas,
        bodiesIdentical: false,
        tooLarge: true,
      );
    }

    final prettyLeft = await JsonUtils.prettify(left.body);
    final prettyRight = await JsonUtils.prettify(right.body);
    final lines = LineDiff.diffText(prettyLeft, prettyRight);
    final identical = lines.every((l) => l.kind == DiffLineKind.equal);

    return ResponseDiffModel(
      leftStatus: left.statusCode,
      rightStatus: right.statusCode,
      bodyLines: lines,
      headerDeltas: headerDeltas,
      bodiesIdentical: identical,
      tooLarge: false,
    );
  }

  /// Header names are case-insensitive (HTTP). Compare via lowercased keys;
  /// surface the left's original casing, falling back to the right's.
  static List<HeaderDelta> _headerDeltas(
    Map<String, String> left,
    Map<String, String> right,
  ) {
    final leftByLower = {for (final e in left.entries) e.key.toLowerCase(): e};
    final rightByLower = {for (final e in right.entries) e.key.toLowerCase(): e};
    final keys = <String>{...leftByLower.keys, ...rightByLower.keys};

    final deltas = <HeaderDelta>[];
    for (final lower in keys) {
      final l = leftByLower[lower];
      final r = rightByLower[lower];
      if (l != null && r != null && l.value == r.value) continue; // unchanged
      deltas.add(
        HeaderDelta(
          key: l?.key ?? r!.key,
          left: l?.value,
          right: r?.value,
        ),
      );
    }
    deltas.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return deltas;
  }
}

/// Reconstructs an [HttpResponseEntity] from a config that carries response
/// columns (a saved example or a history entry). Returns null when no response
/// was captured (`statusCode == null`). Pure + testable so the widget does no
/// reconstruction inline.
HttpResponseEntity? responseFromConfig(HttpRequestConfigEntity config) {
  final status = config.statusCode;
  if (status == null) return null;
  return HttpResponseEntity(
    statusCode: status,
    body: config.responseBody ?? '',
    headers: config.responseHeaders ?? const {},
    durationMs: config.durationMs ?? 0,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/response_diff_builder_test.dart`
Expected: PASS (all 7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/response_diff_builder.dart test/core/utils/response_diff_builder_test.dart
git commit -m "feat(diff): response diff-model builder + responseFromConfig" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Four diff color fields on `AppPalette` (+ all four theme builders)

**Files:**
- Modify: `lib/core/theme/extensions/app_palette.dart`
- Modify: `lib/core/theme/themes/brutalist/brutalist_theme.dart`
- Modify: `lib/core/theme/themes/dracula/dracula_theme.dart`
- Modify: `lib/core/theme/themes/editorial/editorial_theme.dart`
- Modify: `lib/core/theme/themes/rpg/rpg_theme.dart`

> One task because the `AppPalette` constructor gains four `required` fields — leaving any of the four builders un-updated would break the build. There is no new test file; the existing `theme_registry_test.dart` plus the suite-wide compile gate cover it, and Tasks 4–5 assert the colors render. Touch all five files, then verify analysis + tests.

- [ ] **Step 1: Add the four fields to `AppPalette`**

In `lib/core/theme/extensions/app_palette.dart`, add to the constructor (after `required this.selectorActive,`):

```dart
    required this.diffAddedBackground,
    required this.diffAddedForeground,
    required this.diffRemovedBackground,
    required this.diffRemovedForeground,
```

Add the fields (after the `selectorActive` field declaration / its doc comment):

```dart
  /// Subtle tint behind a line that is present only on the diff target (added).
  final Color diffAddedBackground;

  /// Foreground for an added line's text + its `+` gutter glyph.
  final Color diffAddedForeground;

  /// Subtle tint behind a line removed from the current response.
  final Color diffRemovedBackground;

  /// Foreground for a removed line's text + its `-` gutter glyph.
  final Color diffRemovedForeground;
```

Add to `copyWith`'s params (after `Color? selectorActive,`):

```dart
    Color? diffAddedBackground,
    Color? diffAddedForeground,
    Color? diffRemovedBackground,
    Color? diffRemovedForeground,
```

Add to `copyWith`'s returned `AppPalette(...)` (after `selectorActive: selectorActive ?? this.selectorActive,`):

```dart
      diffAddedBackground: diffAddedBackground ?? this.diffAddedBackground,
      diffAddedForeground: diffAddedForeground ?? this.diffAddedForeground,
      diffRemovedBackground:
          diffRemovedBackground ?? this.diffRemovedBackground,
      diffRemovedForeground:
          diffRemovedForeground ?? this.diffRemovedForeground,
```

Add to `lerp`'s returned `AppPalette(...)` (after `selectorActive: Color.lerp(selectorActive, other.selectorActive, t)!,`):

```dart
      diffAddedBackground: Color.lerp(
        diffAddedBackground,
        other.diffAddedBackground,
        t,
      )!,
      diffAddedForeground: Color.lerp(
        diffAddedForeground,
        other.diffAddedForeground,
        t,
      )!,
      diffRemovedBackground: Color.lerp(
        diffRemovedBackground,
        other.diffRemovedBackground,
        t,
      )!,
      diffRemovedForeground: Color.lerp(
        diffRemovedForeground,
        other.diffRemovedForeground,
        t,
      )!,
```

- [ ] **Step 2: Supply the four fields in each theme builder**

Each theme reuses its existing success/error family as the foreground and a low-alpha tint of the same as the background — no new palette static constants, no hardcoded brand colors (the values are derived from the theme's own palette via `.withValues(alpha:)`, so `custom_lint`'s `avoid_hardcoded_brand_colors` is satisfied).

In `lib/core/theme/themes/brutalist/brutalist_theme.dart`, inside the `AppPalette(...)` call (after `selectorActive: ...,`):

```dart
    diffAddedForeground: Colors.green.shade700,
    diffAddedBackground: Colors.green.shade700.withValues(alpha: 0.14),
    diffRemovedForeground: Colors.red.shade700,
    diffRemovedBackground: Colors.red.shade700.withValues(alpha: 0.14),
```

In `lib/core/theme/themes/dracula/dracula_theme.dart`, inside its `AppPalette(...)` (after `selectorActive: currentPrimary,`):

```dart
    diffAddedForeground: isDark
        ? DraculaPalette.statusSuccessDark
        : DraculaPalette.statusSuccessLight,
    diffAddedBackground: (isDark
            ? DraculaPalette.statusSuccessDark
            : DraculaPalette.statusSuccessLight)
        .withValues(alpha: 0.16),
    diffRemovedForeground: isDark
        ? DraculaPalette.statusErrorDark
        : DraculaPalette.statusErrorLight,
    diffRemovedBackground: (isDark
            ? DraculaPalette.statusErrorDark
            : DraculaPalette.statusErrorLight)
        .withValues(alpha: 0.16),
```

In `lib/core/theme/themes/editorial/editorial_theme.dart`, inside its `AppPalette(...)` (after `selectorActive: EditorialPalette.accent,`):

```dart
    diffAddedForeground: EditorialPalette.statusSuccess,
    diffAddedBackground:
        EditorialPalette.statusSuccess.withValues(alpha: 0.12),
    diffRemovedForeground: EditorialPalette.statusError,
    diffRemovedBackground:
        EditorialPalette.statusError.withValues(alpha: 0.12),
```

In `lib/core/theme/themes/rpg/rpg_theme.dart`, inside its `AppPalette(...)` (after `selectorActive: RpgPalette.gold,`):

```dart
    diffAddedForeground: RpgPalette.statusSuccess,
    diffAddedBackground: RpgPalette.statusSuccess.withValues(alpha: 0.16),
    diffRemovedForeground: RpgPalette.statusError,
    diffRemovedBackground: RpgPalette.statusError.withValues(alpha: 0.16),
```

> If any referenced static (e.g. `EditorialPalette.statusSuccess`) is not directly importable in that builder, the theme already references it in the lines above the `AppPalette(...)` call (confirmed: each builder already uses `statusSuccess`/`statusError` for its `variableResolved`/`variableUnresolved` or status fields). Reuse the exact identifier already present in that file.

- [ ] **Step 3: Verify analysis + the existing theme test**

Run:
```bash
fvm flutter analyze
fvm dart run custom_lint
fvm flutter test test/core/theme/theme_registry_test.dart
```
Expected: `flutter analyze` "No issues found" (all four builders now pass the four `required` args; a missing one is a compile error here). `custom_lint` clean — in particular **no `avoid_hardcoded_brand_colors`** (brutalist uses `Colors.green/red.shade700`, which the rule allows as Material swatch shades the existing `statusSuccess` lines already use; if the rule flags it, swap to the same expression already present in that file for `statusSuccess`/`statusError`). Theme test green.

- [ ] **Step 4: Commit**

```bash
git add lib/core/theme/extensions/app_palette.dart lib/core/theme/themes/brutalist/brutalist_theme.dart lib/core/theme/themes/dracula/dracula_theme.dart lib/core/theme/themes/editorial/editorial_theme.dart lib/core/theme/themes/rpg/rpg_theme.dart
git commit -m "feat(theme): diff added/removed palette colors across all themes" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Diff view widget

**Files:**
- Create: `lib/core/ui/widgets/response_diff_view.dart`
- Test: `test/core/ui/widgets/response_diff_view_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/widgets/response_diff_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/response_diff_view.dart';
import 'package:getman/core/utils/line_diff.dart';
import 'package:getman/core/utils/response_diff_builder.dart';

Future<void> _pump(WidgetTester tester, ResponseDiffModel model) {
  return tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme(kBrutalistThemeId)(
        Brightness.light,
        isCompact: false,
      ),
      home: Scaffold(
        body: ResponseDiffView(
          model: model,
          leftLabel: 'This response',
          rightLabel: 'Example: 200',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders both source labels', (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 200,
        bodyLines: [],
        headerDeltas: [],
        bodiesIdentical: true,
        tooLarge: false,
      ),
    );
    expect(find.text('This response'), findsOneWidget);
    expect(find.text('Example: 200'), findsOneWidget);
  });

  testWidgets('identical bodies show the identical note', (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 200,
        bodyLines: [],
        headerDeltas: [],
        bodiesIdentical: true,
        tooLarge: false,
      ),
    );
    expect(find.textContaining('identical'), findsOneWidget);
  });

  testWidgets('too-large shows the banner instead of a body list',
      (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 200,
        bodyLines: [],
        headerDeltas: [],
        bodiesIdentical: false,
        tooLarge: true,
      ),
    );
    expect(find.textContaining('too large'), findsOneWidget);
  });

  testWidgets('added/removed lines render with gutter glyphs', (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 201,
        bodyLines: [
          DiffLine(DiffLineKind.equal, 'kept'),
          DiffLine(DiffLineKind.removed, 'gone'),
          DiffLine(DiffLineKind.added, 'fresh'),
        ],
        headerDeltas: [],
        bodiesIdentical: false,
        tooLarge: false,
      ),
    );
    expect(find.text('gone'), findsOneWidget);
    expect(find.text('fresh'), findsOneWidget);
    // Gutter glyphs are keyed so we can assert per-line color in the impl.
    expect(find.byKey(const ValueKey('diff_gutter_added')), findsOneWidget);
    expect(find.byKey(const ValueKey('diff_gutter_removed')), findsOneWidget);
  });

  testWidgets('header-delta count is summarized', (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 200,
        bodyLines: [],
        headerDeltas: [
          HeaderDelta(key: 'ETag', left: 'v1', right: 'v2'),
          HeaderDelta(key: 'X-New', left: null, right: 'y'),
        ],
        bodiesIdentical: true,
        tooLarge: false,
      ),
    );
    expect(find.textContaining('2 header'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/response_diff_view_test.dart`
Expected: FAIL — `response_diff_view.dart` does not exist.

- [ ] **Step 3: Implement the diff view**

Create `lib/core/ui/widgets/response_diff_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/line_diff.dart';
import 'package:getman/core/utils/response_diff_builder.dart';

/// Read-only unified diff of the current response (left) vs a chosen target
/// (right). Renders a status/header summary above a per-line-colored body diff.
class ResponseDiffView extends StatelessWidget {
  const ResponseDiffView({
    required this.model,
    required this.leftLabel,
    required this.rightLabel,
    super.key,
  });

  final ResponseDiffModel model;
  final String leftLabel;
  final String rightLabel;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: const Text('COMPARE RESPONSE'),
      content: SizedBox(
        width: context.appLayout.dialogWidth * 1.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summary(context),
            SizedBox(height: context.appLayout.sectionSpacing / 2),
            Flexible(child: _body(context)),
          ],
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

  Widget _summary(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final palette = context.appPalette;
    final theme = Theme.of(context);

    final headerCount = model.headerDeltas.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          leftLabel,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: typography.titleWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          rightLabel,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: typography.titleWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
        SizedBox(height: layout.tabSpacing),
        Row(
          children: [
            _statusBadge(context, model.leftStatus),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.tabSpacing),
              child: Icon(Icons.arrow_forward, size: layout.iconSize),
            ),
            _statusBadge(context, model.rightStatus),
          ],
        ),
        SizedBox(height: layout.tabSpacing),
        Text(
          headerCount == 0
              ? 'Headers identical'
              : '$headerCount header${headerCount == 1 ? '' : 's'} changed',
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        if (headerCount > 0)
          Padding(
            padding: EdgeInsets.only(top: layout.tabSpacing / 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in model.headerDeltas) _headerRow(context, d),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statusBadge(BuildContext context, int code) {
    final palette = context.appPalette;
    final layout = context.appLayout;
    final bg = palette.statusAccent(code);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      color: bg,
      child: Text(
        '$code',
        style: TextStyle(
          fontSize: layout.fontSizeSmall,
          fontWeight: context.appTypography.displayWeight,
          color: palette.onColor(bg),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context, HeaderDelta d) {
    final palette = context.appPalette;
    final layout = context.appLayout;
    final color = d.isAdded
        ? palette.diffAddedForeground
        : d.isRemoved
            ? palette.diffRemovedForeground
            : Theme.of(context).colorScheme.onSurface;
    final glyph = d.isAdded
        ? '+'
        : d.isRemoved
            ? '-'
            : '~';
    return Text(
      '$glyph ${d.key}: ${d.right ?? d.left ?? ''}',
      style: TextStyle(
        fontFamily: context.appTypography.codeFontFamily,
        fontSize: layout.fontSizeSmall,
        color: color,
      ),
    );
  }

  Widget _body(BuildContext context) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final theme = Theme.of(context);

    if (model.tooLarge) {
      return _note(
        context,
        'Responses too large to diff inline (over 512 KB). '
        'The status and header summary above still apply.',
      );
    }
    if (model.bodiesIdentical) {
      return _note(
        context,
        model.headerDeltas.isEmpty && model.leftStatus == model.rightStatus
            ? 'These responses are identical.'
            : 'Bodies are identical.',
      );
    }

    return ColoredBox(
      color: palette.codeBackground,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(layout.pagePadding / 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in model.bodyLines) _line(context, line),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, DiffLine line) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final theme = Theme.of(context);

    late final Color fg;
    late final Color bg;
    late final String glyph;
    Key? glyphKey;
    switch (line.kind) {
      case DiffLineKind.added:
        fg = palette.diffAddedForeground;
        bg = palette.diffAddedBackground;
        glyph = '+';
        glyphKey = const ValueKey('diff_gutter_added');
      case DiffLineKind.removed:
        fg = palette.diffRemovedForeground;
        bg = palette.diffRemovedBackground;
        glyph = '-';
        glyphKey = const ValueKey('diff_gutter_removed');
      case DiffLineKind.equal:
        fg = theme.colorScheme.onSurface;
        bg = Colors.transparent;
        glyph = ' ';
    }

    final codeStyle = TextStyle(
      fontFamily: context.appTypography.codeFontFamily,
      fontSize: layout.fontSizeCode,
      color: fg,
    );

    return ColoredBox(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(glyph, key: glyphKey, style: codeStyle),
          SizedBox(width: layout.tabSpacing),
          Expanded(child: Text(line.text, style: codeStyle)),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text) {
    return Padding(
      padding: EdgeInsets.all(context.appLayout.pagePadding),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.appLayout.fontSizeNormal,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
```

> Note: `_statusBadge` references `palette`/`layout`/`theme` locals where used; the `_summary` method's unused `palette`/`theme` locals must be pruned if `flutter analyze` flags `unused_local_variable` — keep only the ones each method actually reads. (`_summary` reads `theme` and `layout` + `typography`; drop its `palette` local if unused.)

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/response_diff_view_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/widgets/response_diff_view.dart test/core/ui/widgets/response_diff_view_test.dart
git commit -m "feat(diff): response diff view dialog" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Target-picker dialog

**Files:**
- Create: `lib/core/ui/widgets/compare_target_picker.dart`
- Test: `test/core/ui/widgets/compare_target_picker_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/widgets/compare_target_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/compare_target_picker.dart';

HttpResponseEntity _resp(int status) => HttpResponseEntity(
      statusCode: status,
      body: '{}',
      headers: const {},
      durationMs: 1,
    );

Future<CompareTarget?> _open(
  WidgetTester tester, {
  required List<CompareTarget> examples,
  required List<CompareTarget> history,
}) async {
  CompareTarget? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme(kBrutalistThemeId)(
        Brightness.light,
        isCompact: false,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<CompareTarget>(
                context: context,
                builder: (_) =>
                    CompareTargetPicker(examples: examples, history: history),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('renders both labeled sections', (tester) async {
    await _open(
      tester,
      examples: [
        CompareTarget(
          id: 'e1',
          source: CompareTargetSource.example,
          label: '200 · 14:03',
          subtitle: 'captured today',
          response: _resp(200),
        ),
      ],
      history: [
        CompareTarget(
          id: 'h1',
          source: CompareTargetSource.history,
          label: 'GET /users · 200',
          subtitle: 'a minute ago',
          response: _resp(200),
        ),
      ],
    );
    expect(find.text('SAVED EXAMPLES'), findsOneWidget);
    expect(find.text('RECENT (this request)'), findsOneWidget);
    expect(find.text('200 · 14:03'), findsOneWidget);
    expect(find.text('GET /users · 200'), findsOneWidget);
  });

  testWidgets('an empty section shows None', (tester) async {
    await _open(
      tester,
      examples: const [],
      history: [
        CompareTarget(
          id: 'h1',
          source: CompareTargetSource.history,
          label: 'GET /users · 200',
          subtitle: 'a minute ago',
          response: _resp(200),
        ),
      ],
    );
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('tapping a row pops that target', (tester) async {
    final picked = CompareTarget(
      id: 'e1',
      source: CompareTargetSource.example,
      label: '200 · 14:03',
      subtitle: 'captured today',
      response: _resp(200),
    );
    CompareTarget? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme(kBrutalistThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<CompareTarget>(
                  context: context,
                  builder: (_) => CompareTargetPicker(
                    examples: [picked],
                    history: const [],
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('200 · 14:03'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.id, 'e1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/compare_target_picker_test.dart`
Expected: FAIL — `compare_target_picker.dart` does not exist.

- [ ] **Step 3: Implement the picker**

Create `lib/core/ui/widgets/compare_target_picker.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';

/// Where a compare target came from.
enum CompareTargetSource { example, history }

/// A selectable response to diff the current tab against. Carries the
/// reconstructed [response] so the caller does no rebuild work after a pick.
class CompareTarget extends Equatable {
  const CompareTarget({
    required this.id,
    required this.source,
    required this.label,
    required this.subtitle,
    required this.response,
  });

  final String id;
  final CompareTargetSource source;
  final String label;
  final String subtitle;
  final HttpResponseEntity response;

  @override
  List<Object?> get props => [id, source, label, subtitle, response];
}

/// Lists saved-example and matching-history targets in two labeled sections.
/// A pure presentational atom — passed its data, never reads blocs. Pops the
/// chosen [CompareTarget] (or null on cancel) via the dialog Navigator.
class CompareTargetPicker extends StatelessWidget {
  const CompareTargetPicker({
    required this.examples,
    required this.history,
    super.key,
  });

  final List<CompareTarget> examples;
  final List<CompareTarget> history;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: const Text('COMPARE WITH'),
      content: SizedBox(
        width: context.appLayout.dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section(context, 'SAVED EXAMPLES', examples),
            SizedBox(height: context.appLayout.sectionSpacing / 2),
            _section(context, 'RECENT (this request)', history),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('CANCEL'),
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String heading,
    List<CompareTarget> targets,
  ) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          heading,
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            fontWeight: context.appTypography.displayWeight,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        SizedBox(height: layout.tabSpacing),
        if (targets.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: layout.tabSpacing),
            child: Text(
              'None',
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          )
        else
          for (final t in targets) _row(context, t),
      ],
    );
  }

  Widget _row(BuildContext context, CompareTarget target) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final bg = palette.statusAccent(target.response.statusCode);

    return context.appDecoration.wrapInteractive(
      onTap: () => Navigator.of(context).pop(target),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.tabSpacing / 2),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: layout.badgePaddingHorizontal,
                vertical: layout.badgePaddingVertical,
              ),
              color: bg,
              child: Text(
                '${target.response.statusCode}',
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  fontWeight: context.appTypography.displayWeight,
                  color: palette.onColor(bg),
                ),
              ),
            ),
            SizedBox(width: layout.tabSpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.label,
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      fontWeight: context.appTypography.titleWeight,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    target.subtitle,
                    style: TextStyle(
                      fontSize: layout.fontSizeSmall,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/compare_target_picker_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/widgets/compare_target_picker.dart test/core/ui/widgets/compare_target_picker_test.dart
git commit -m "feat(diff): compare-target picker dialog" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Entry-point wiring in `response_body_view.dart`

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/response/response_body_view.dart`
- Test: `test/features/tabs/presentation/widgets/response/response_body_view_compare_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/features/tabs/presentation/widgets/response/response_body_view_compare_test.dart`. This pumps `ResponseBodyView` under real blocs (mirroring how the response pane is composed — it reads `TabsBloc`/`CollectionsBloc`/`HistoryBloc`/`SettingsBloc`). Use lightweight bloc subclasses seeded with fixed state.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:re_editor/re_editor.dart';

// NOTE: confirm the exact constructor of each fake bloc against the real bloc.
// TabsBloc/CollectionsBloc/HistoryBloc/SettingsBloc all extend Bloc<E,S>; the
// implementer should look up each bloc's constructor and either (a) seed real
// blocs with an initial event/state or (b) use a minimal Fake that overrides
// `state`. The reference pattern below uses fakes that only expose `state`.

class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(TabsState initial) : super(initial);
}

class _FakeCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _FakeCollectionsBloc(CollectionsState initial) : super(initial);
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc(HistoryState initial) : super(initial);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc(SettingsState initial) : super(initial);
}

void main() {
  const tabId = 'tab-1';

  HttpRequestTabEntity tabWith({
    HttpResponseEntity? response,
    String? nodeId,
  }) {
    return HttpRequestTabEntity(
      tabId: tabId,
      config: const HttpRequestConfigEntity(
        id: 'cfg',
        method: 'GET',
        url: 'https://api.example.com/users',
      ),
      response: response,
      collectionNodeId: nodeId,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required HttpRequestTabEntity tab,
    HistoryState history = const HistoryState(),
    CollectionsState collections = const CollectionsState(),
    required SettingsState settings,
  }) async {
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>(
            create: (_) => _FakeTabsBloc(TabsState(tabs: [tab])),
          ),
          BlocProvider<CollectionsBloc>(
            create: (_) => _FakeCollectionsBloc(collections),
          ),
          BlocProvider<HistoryBloc>(
            create: (_) => _FakeHistoryBloc(history),
          ),
          BlocProvider<SettingsBloc>(
            create: (_) => _FakeSettingsBloc(settings),
          ),
        ],
        child: MaterialApp(
          theme: resolveTheme(kBrutalistThemeId)(
            Brightness.light,
            isCompact: false,
          ),
          home: Scaffold(
            body: ResponseBodyView(
              tabId: tabId,
              responseController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // SettingsState(settings: SettingsEntity()) — both have const default
  // constructors and SettingsEntity().alwaysPrettifyLargeResponses defaults to
  // false (verified in CLAUDE.md §3 / settings_state.dart). Use the const
  // default directly:
  const defaultSettings = SettingsState(settings: SettingsEntity());

  testWidgets('compare button hidden when no response', (tester) async {
    await pump(tester, tab: tabWith(), settings: defaultSettings);
    expect(find.byKey(const ValueKey('compare_response_button')), findsNothing);
  });

  testWidgets('compare button disabled when a response but no targets',
      (tester) async {
    await pump(
      tester,
      tab: tabWith(
        response: const HttpResponseEntity(
          statusCode: 200,
          body: '{"a":1}',
          headers: {},
          durationMs: 5,
        ),
      ),
      settings: defaultSettings,
    );
    final btn = tester.widget<IconButton>(
      find.byKey(const ValueKey('compare_response_button')),
    );
    expect(btn.onPressed, isNull, reason: 'no targets -> disabled');
  });

  testWidgets('compare button enabled + opens picker with a history match',
      (tester) async {
    await pump(
      tester,
      tab: tabWith(
        response: const HttpResponseEntity(
          statusCode: 200,
          body: '{"a":1}',
          headers: {},
          durationMs: 5,
        ),
      ),
      history: const HistoryState(
        history: [
          HttpRequestConfigEntity(
            id: 'h1',
            method: 'GET',
            url: 'https://api.example.com/users',
            statusCode: 200,
            responseBody: '{"a":2}',
            responseHeaders: {},
            durationMs: 9,
          ),
        ],
      ),
      settings: defaultSettings,
    );
    await tester.tap(find.byKey(const ValueKey('compare_response_button')));
    await tester.pumpAndSettle();
    expect(find.text('COMPARE WITH'), findsOneWidget);
  });

  testWidgets('existing Copy/Save buttons still present', (tester) async {
    await pump(
      tester,
      tab: tabWith(
        response: const HttpResponseEntity(
          statusCode: 200,
          body: '{"a":1}',
          headers: {},
          durationMs: 5,
        ),
      ),
      settings: defaultSettings,
    );
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Save response to file'), findsOneWidget);
  });
}
```

> **Implementer note (load-bearing):** `const SettingsState(settings: SettingsEntity())` is the default (both have const constructors; `SettingsEntity().alwaysPrettifyLargeResponses == false` — verified). Confirm `TabsState`/`CollectionsState`/`HistoryState` constructor field names against the real classes (verified: `TabsState(tabs: ...)`, `CollectionsState(collections: ...)`, `HistoryState(history: ...)`). If a fake bloc fails because the bloc has a sealed/initial-event contract or a non-trivial constructor, switch that bloc to a real instance seeded with its standard initial state instead of a fake — or use `bloc_test`'s `MockBloc` + `whenListen` if already in the suite's dev_dependencies (grep `test/` for `MockBloc`/`whenListen`). The four assertions (hidden / disabled / opens picker / Copy+Save intact) are the contract — keep them.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/response_body_view_compare_test.dart`
Expected: FAIL — first because the file references symbols not yet wired (`compare_response_button`), after the `setUp` is filled in.

- [ ] **Step 3: Add imports to `response_body_view.dart`**

At the top of `lib/features/tabs/presentation/widgets/response/response_body_view.dart`, add (respecting `directives_ordering` — alphabetical within the `package:` group):

```dart
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/ui/widgets/compare_target_picker.dart';
import 'package:getman/core/ui/widgets/response_diff_view.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/response_diff_builder.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
```

> `collections_bloc.dart`, `tabs_bloc.dart`, `tabs_state.dart`, `settings_bloc.dart`, `settings_state.dart`, `app_theme.dart`, `saved_example_entity.dart` are already imported. Keep the import list sorted; `dart format` will not reorder them, so insert each in alphabetical position or run analyze to catch `directives_ordering`.

- [ ] **Step 4: Build the target lists + the disabled-gate (pure helpers on the State)**

Add these methods to `_ResponseBodyViewState` (they map bloc state into `CompareTarget`s; called both for the disabled gate and at press time so the data is always current):

```dart
  /// Saved-example targets for the tab's linked node (response captured only).
  List<CompareTarget> _exampleTargets(BuildContext context, String? nodeId) {
    if (nodeId == null) return const [];
    final collections =
        context.read<CollectionsBloc>().state.collections;
    final node = CollectionsTreeHelper.findNode(collections, nodeId);
    if (node == null) return const [];
    final out = <CompareTarget>[];
    for (final ex in node.examples) {
      final response = responseFromConfig(ex.config);
      if (response == null) continue;
      out.add(
        CompareTarget(
          id: ex.id,
          source: CompareTargetSource.example,
          label: ex.name,
          subtitle: 'captured ${_hhmm(ex.capturedAt)}',
          response: response,
        ),
      );
    }
    return out;
  }

  /// History targets matching the tab's method + url (newest first, capped).
  List<CompareTarget> _historyTargets(
    BuildContext context,
    HttpRequestConfigEntity config,
  ) {
    final history = context.read<HistoryBloc>().state.history;
    final out = <CompareTarget>[];
    for (final entry in history) {
      if (entry.method != config.method || entry.url != config.url) continue;
      final response = responseFromConfig(entry);
      if (response == null) continue;
      out.add(
        CompareTarget(
          id: entry.id,
          source: CompareTargetSource.history,
          label: '${entry.method} ${entry.url} · ${entry.statusCode}',
          subtitle: '${entry.durationMs ?? 0} ms',
          response: response,
        ),
      );
      if (out.length >= 20) break; // cap
    }
    return out;
  }
```

- [ ] **Step 5: Add `_compareButton` + `_compareResponse`**

Add the button (gated by `BlocBuilder` over the three relevant blocs; `IconButton` with null `onPressed` renders disabled, matching `NamePromptDialog`'s pattern):

```dart
  Widget _compareButton(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(widget.tabId);
        final n = next.tabs.byId(widget.tabId);
        return (p?.response == null) != (n?.response == null) ||
            p?.collectionNodeId != n?.collectionNodeId ||
            p?.config.method != n?.config.method ||
            p?.config.url != n?.config.url;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(widget.tabId);
        if (tab == null || tab.response == null) {
          return const SizedBox.shrink();
        }
        final hasTargets =
            _exampleTargets(context, tab.collectionNodeId).isNotEmpty ||
                _historyTargets(context, tab.config).isNotEmpty;
        return IconButton(
          key: const ValueKey('compare_response_button'),
          tooltip: hasTargets
              ? 'Compare response'
              : 'No saved examples or matching history to compare',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.difference_outlined,
            size: context.appLayout.iconSize,
          ),
          onPressed: hasTargets ? () => _compareResponse(context) : null,
        );
      },
    );
  }

  Future<void> _compareResponse(BuildContext context) async {
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    final current = tab?.response;
    if (tab == null || current == null) return;

    final examples = _exampleTargets(context, tab.collectionNodeId);
    final history = _historyTargets(context, tab.config);
    if (examples.isEmpty && history.isEmpty) return;

    final target = await showDialog<CompareTarget>(
      context: context,
      builder: (_) =>
          CompareTargetPicker(examples: examples, history: history),
    );
    if (target == null) return;
    if (!context.mounted) return;

    final model = await ResponseDiffBuilder.build(current, target.response);
    if (!context.mounted) return;

    await showResponsiveDialog<void>(
      context,
      builder: (_) => ResponseDiffView(
        model: model,
        leftLabel: 'This response',
        rightLabel: target.label,
      ),
    );
  }
```

- [ ] **Step 6: Add the button to both action Rows**

In `_buildSmallMode`, in the action `Row` children, add `_compareButton(context)` after `_saveButton(context)` (before `_saveAsExampleButton(context)`):

```dart
            _copyButton(context),
            _saveButton(context),
            _compareButton(context),
            _saveAsExampleButton(context),
```

In `_buildLargeMode`, in the trailing button group of the banner `Row`, add the same after `_saveButton(context)`:

```dart
                _copyButton(context),
                _saveButton(context),
                _compareButton(context),
                _saveAsExampleButton(context),
```

- [ ] **Step 7: Run the new test + the full suite**

Run:
```bash
fvm flutter test test/features/tabs/presentation/widgets/response/response_body_view_compare_test.dart
fvm flutter test
```
Expected: the new test PASS (4 cases); full suite green (no regression to existing response/Copy/Save behavior).

- [ ] **Step 8: Run all three analysis passes + format**

Run:
```bash
fvm dart format lib test
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
```
Expected: all clean. In particular `custom_lint` must not flag `avoid_get_it_in_widgets` (we read blocs via `context.read`, never `sl<T>()`) nor `avoid_hardcoded_brand_colors` (all colors come from `context.appPalette`). `bloc_lint` surface is unchanged (no bloc edits).

- [ ] **Step 9: Manual sanity (optional but recommended)**

Run: `fvm flutter run -d macos`. Open a saved request, send it, then send again after the endpoint changes (or save an example then re-send): click the Compare button (icon `difference`), pick a target, confirm the diff dialog shows green added / red removed lines + the status/header summary. Close the app when satisfied.

- [ ] **Step 10: Commit**

```bash
git add lib/features/tabs/presentation/widgets/response/response_body_view.dart test/features/tabs/presentation/widgets/response/response_body_view_compare_test.dart
git commit -m "feat(tabs): Compare action wiring on the response body pane" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Full done-bar gate

**Files:** none (verification only).

- [ ] **Step 1: Run the complete verification stack**

Run each and confirm clean/green:
```bash
fvm dart format lib test tools
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```
Expected: `dart format` reports 0 changed (or commit the formatting in Step 2), all three analysis passes "No issues found", every test green.

- [ ] **Step 2: Commit any formatting drift**

```bash
git add -A && git commit -m "chore(diff): format" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" || echo "nothing to format"
```

---

### Task 8: Wiki — document Response diff (LAST)

**Files:**
- Wiki: `Getman.wiki.git` (separate repo) — a Response-diff section/page + `_Sidebar.md`.

- [ ] **Step 1: Clone the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

- [ ] **Step 2: Add the documentation**

Decide placement: if the existing Response page is substantial, add a "Compare responses" section there; otherwise create `Response-diff.md` and add it to `_Sidebar.md`. Use verbatim UI labels. Content must cover:

- **How to open it:** the Compare button on the response **BODY** pane (icon `difference`, tooltip verbatim **"Compare response"**). Shown only when a response exists; **disabled** (tooltip **"No saved examples or matching history to compare"**) when there is nothing to compare against.
- **Targets offered:** two sections in the **COMPARE WITH** picker — **SAVED EXAMPLES** (saved examples of the linked request) and **RECENT (this request)** (recent history entries whose method + URL match the current request).
- **How the diff reads:** the **COMPARE RESPONSE** view shows the current response (left) vs the chosen target (right); green = lines added on the target, red = lines removed from the current response; a status badge row (`current → target`) and a header-delta summary above the body.
- **Limits:** line-level diff on the pretty-printed bodies (not key-aware/semantic); responses over **512 KB** show the status/header summary plus a "too large to diff inline" note instead of the body diff.

- [ ] **Step 3: Commit + push the wiki**

```bash
cd /tmp/getman-wiki && git add -A && git commit -m "docs: response diff (Compare response)" && git push origin master
```

- [ ] **Step 4: Confirm**

Confirm the page is live at <https://github.com/thiagomiranda3/Getman/wiki> and the sidebar links resolve (if a new page was added).

---

## Self-Review (completed during planning)

- **Spec coverage:** LCS line-diff util (Task 1) ✓; diff-model builder + prettify + large-body guard + `responseFromConfig` (Task 2) ✓; four `AppPalette` diff colors across all four themes in one task (Task 3) ✓; diff view with status/header summary + per-line colors + identical/too-large states (Task 4) ✓; target picker with two sections + empty "None" + pop-on-tap (Task 5) ✓; entry-point Compare button (hidden w/o response, disabled w/o targets, opens picker → builds → shows diff, `context.mounted` guards, widget-layer multi-bloc read, no bloc→bloc) (Task 6) ✓; full done-bar (Task 7) ✓; wiki (Task 8) ✓.
- **Ordering:** pure utils (1, 2) → palette (3) → widgets (4, 5) → wiring (6) → verify (7) → wiki (8). Each task compiles independently (palette change makes all four builders valid in one commit).
- **Type consistency:** `HttpResponseEntity{statusCode:int, body:String, headers:Map<String,String>, durationMs:int}`, `HttpRequestConfigEntity` response columns nullable, `JsonUtils.prettify` async, `kLargeResponseViewerChars`, `CollectionsTreeHelper.findNode(nodes, id)`, `HistoryState.history`, `state.tabs.byId(id)`, `ResponsiveDialogScaffold`/`showResponsiveDialog`, theme id `kBrutalistThemeId`, `resolveTheme(id)(brightness, isCompact:)` — all verified against source.
- **Mandate adherence:** no hardcoded colors/sizes (all via `context.app*`; the diff colors are added to the palette, not literals); `package:getman/...` imports; `context.read` not `sl<T>()`; identity-addressed (`byId`) tab lookups; no new Hive typeId; no new dependency; commit trailer present on every code task.
- **Known implementer gates (called out inline):** Task 6 Step 1 requires substituting the suite-standard `SettingsState` factory (the one genuine fork — fully flagged, with the grep command to find it). Task 4 Step 3 prunes any unused local that `flutter analyze` flags. Task 3 Step 3 notes the brutalist `Colors.green/red.shade700` fallback if `avoid_hardcoded_brand_colors` is stricter than the existing `statusSuccess` lines (it already uses those exact swatch shades, so it is consistent).
