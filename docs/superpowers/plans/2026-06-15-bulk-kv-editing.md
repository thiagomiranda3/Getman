# Bulk Header / Param Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit the **Params** and **Headers** tabs as a free-text `key: value` block (Postman-style "Bulk edit") instead of one row at a time. A per-tab toggle flips between the existing row-by-row `KeyValueListEditor` and a single multiline text view. Switching either way is lossless (round-trip). Parsing splits each line on the **first** `:` and trims both sides; blank lines and empty-key lines are dropped. The canonical value (`List<QueryParamEntity>` for params, `Map<String,String>` for headers) and the `onChanged` → `UpdateTab` path are unchanged.

**Architecture:** A pure-Dart codec (`BulkKvCodec`, in `core/utils`) converts between the editor's row currency `List<(String, String)>` and a `key: value` text block — it is the exact type `KeyValueListEditor.decode`/`encode` already speak, so it knows nothing about `QueryParamEntity`/`Map`. A reusable atom (`BulkKvEditor`, in `core/ui/widgets`) hosts a single multiline `TextField` with the same echo-suppression discipline as `KeyValueListEditor` (re-seed the controller only when `initialText` genuinely changes). `ParamsTabView` and `HeadersTabView` (`request_editor_tabs.dart`) become `StatefulWidget`s holding an ephemeral `bool _bulk`, render a themed toggle, and switch between `KeyValueListEditor` (row mode) and `BulkKvEditor` (bulk mode) — both paths feed the **same** `decode`/`encode` closures and the one `UpdateTab` dispatch. No bloc, domain, entity, or Hive changes.

**Tech Stack:** Flutter (`fvm flutter`), `flutter_bloc`, `equatable`, `flutter_test`. No new dependencies.

---

## File Structure

**Create:**
- `lib/core/utils/bulk_kv_codec.dart` — `BulkKvCodec.serialize(List<(String,String)>)` / `BulkKvCodec.parse(String)`. Pure Dart, no Flutter, lives beside the other `core/utils` helpers.
- `lib/core/ui/widgets/bulk_kv_editor.dart` — `BulkKvEditor` (a `StatefulWidget` hosting one multiline `TextField`, themed via `context.app*`, echo-suppressed).
- `test/core/utils/bulk_kv_codec_test.dart`
- `test/core/ui/widgets/bulk_kv_editor_test.dart`
- `test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart`

**Modify:**
- `lib/features/tabs/presentation/widgets/request_editor_tabs.dart` — `ParamsTabView` + `HeadersTabView` become `StatefulWidget`s with a row⇄bulk toggle.

**Wiki (Task 5):** `Getman.wiki.git` (separate repo) — the **Requests** page (PARAMS / HEADERS / BODY tabs).

---

### Task 1: Bulk key/value codec (pure Dart)

**Files:**
- Create: `lib/core/utils/bulk_kv_codec.dart`
- Test: `test/core/utils/bulk_kv_codec_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/utils/bulk_kv_codec_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/bulk_kv_codec.dart';

void main() {
  group('BulkKvCodec.serialize', () {
    test('empty list serializes to empty string', () {
      expect(BulkKvCodec.serialize(const []), '');
    });

    test('rows become one "key: value" line each, canonical order', () {
      final text = BulkKvCodec.serialize(const [
        ('Accept', '*/*'),
        ('Authorization', 'Bearer abc'),
      ]);
      expect(text, 'Accept: */*\nAuthorization: Bearer abc');
    });

    test('value is emitted verbatim (no trimming on serialize)', () {
      expect(BulkKvCodec.serialize(const [('X', '  spaced  ')]), 'X:   spaced  ');
    });

    test('empty-key rows are skipped', () {
      expect(BulkKvCodec.serialize(const [('', 'orphan'), ('K', 'v')]), 'K: v');
    });

    test('a key with an empty value still emits "key: "', () {
      expect(BulkKvCodec.serialize(const [('Accept', '')]), 'Accept: ');
    });
  });

  group('BulkKvCodec.parse', () {
    test('empty / whitespace-only input yields no rows', () {
      expect(BulkKvCodec.parse(''), const <(String, String)>[]);
      expect(BulkKvCodec.parse('   \n\t\n  '), const <(String, String)>[]);
    });

    test('splits on the first colon and trims both sides (D2)', () {
      expect(BulkKvCodec.parse('Accept :  */*  '), const [('Accept', '*/*')]);
    });

    test('value containing a colon keeps everything after the first one (D2)', () {
      expect(
        BulkKvCodec.parse('Authorization: Bearer a:b'),
        const [('Authorization', 'Bearer a:b')],
      );
    });

    test('a line with no colon becomes (key, "") (D3)', () {
      expect(BulkKvCodec.parse('Accept'), const [('Accept', '')]);
    });

    test('blank lines between pairs are dropped (D4)', () {
      expect(
        BulkKvCodec.parse('A: 1\n\n   \nB: 2'),
        const [('A', '1'), ('B', '2')],
      );
    });

    test('a line whose key trims to empty is dropped (D5)', () {
      expect(BulkKvCodec.parse(': value'), const <(String, String)>[]);
      expect(BulkKvCodec.parse('   : x'), const <(String, String)>[]);
    });

    test('trailing newline produces no phantom pair (D4)', () {
      expect(BulkKvCodec.parse('A: 1\n'), const [('A', '1')]);
    });

    test('duplicate keys are preserved in order', () {
      expect(
        BulkKvCodec.parse('tag: a\ntag: b'),
        const [('tag', 'a'), ('tag', 'b')],
      );
    });
  });

  group('round-trip parse(serialize(rows)) == rows', () {
    test('representative canonical rows survive a round-trip', () {
      const rows = [
        ('Accept', '*/*'),
        ('Authorization', 'Bearer a:b'),
        ('Empty', ''),
        ('tag', 'a'),
        ('tag', 'b'),
      ];
      expect(BulkKvCodec.parse(BulkKvCodec.serialize(rows)), rows);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/bulk_kv_codec_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:getman/core/utils/bulk_kv_codec.dart'`.

- [ ] **Step 3: Write the codec**

Create `lib/core/utils/bulk_kv_codec.dart`:

```dart
/// Converts between the key/value editor's row currency
/// `List<(String, String)>` and a Postman-style `key: value` text block.
///
/// Pure Dart — no Flutter, no bloc — so both [ParamsTabView] and
/// [HeadersTabView] reuse it and it is unit-testable in isolation. It deals
/// only in `(key, value)` rows; the per-tab `encode`/`decode` closures convert
/// rows ↔ the canonical value (`List<QueryParamEntity>` / `Map<String,String>`)
/// exactly as the row editor already does, so bulk and row paths produce
/// identical canonical values.
class BulkKvCodec {
  const BulkKvCodec._();

  /// Rows → text block. One `key: value` line per pair, canonical order, value
  /// emitted verbatim (no trimming). Empty-key pairs are skipped — they never
  /// reach canonical state anyway (both tab `encode`s drop empty keys).
  static String serialize(List<(String, String)> rows) {
    final buffer = StringBuffer();
    var first = true;
    for (final (key, value) in rows) {
      if (key.isEmpty) continue;
      if (!first) buffer.write('\n');
      buffer
        ..write(key)
        ..write(': ')
        ..write(value);
      first = false;
    }
    return buffer.toString();
  }

  /// Text block → rows. Each line is split on the FIRST `:`.
  ///   - blank / whitespace-only line  → dropped (D4)
  ///   - no colon                      → (trimmedLine, '')          (D3)
  ///   - colon present                 → (key.trim(), value.trim()) (D2)
  ///   - empty key after trim          → dropped                    (D5)
  static List<(String, String)> parse(String text) {
    final rows = <(String, String)>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue; // D4
      final colon = line.indexOf(':');
      if (colon < 0) {
        rows.add((line, '')); // D3 — line is already trimmed and non-empty
        continue;
      }
      final key = line.substring(0, colon).trim();
      if (key.isEmpty) continue; // D5
      final value = line.substring(colon + 1).trim(); // D2
      rows.add((key, value));
    }
    return rows;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/bulk_kv_codec_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Format + commit**

```bash
fvm dart format lib/core/utils/bulk_kv_codec.dart test/core/utils/bulk_kv_codec_test.dart
git add lib/core/utils/bulk_kv_codec.dart test/core/utils/bulk_kv_codec_test.dart
git commit -m "$(cat <<'EOF'
feat(tabs): pure key:value bulk codec for params/headers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Bulk text view atom (`BulkKvEditor`)

**Files:**
- Create: `lib/core/ui/widgets/bulk_kv_editor.dart`
- Test: `test/core/ui/widgets/bulk_kv_editor_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/widgets/bulk_kv_editor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('seeds the field from initialText', (tester) async {
    await pump(
      tester,
      const BulkKvEditor(
        initialText: 'Accept: */*\nAuthorization: Bearer x',
        onChanged: _noop,
      ),
    );

    expect(
      find.widgetWithText(TextField, 'Accept: */*\nAuthorization: Bearer x'),
      findsOneWidget,
    );
  });

  testWidgets('reports the raw edited text on change', (tester) async {
    final emissions = <String>[];
    await pump(
      tester,
      BulkKvEditor(initialText: '', onChanged: emissions.add),
    );

    await tester.enterText(find.byType(TextField), 'A: 1');
    await tester.pump();

    expect(emissions.last, 'A: 1');
  });

  testWidgets('does not reset the field when the SAME text echoes back', (
    tester,
  ) async {
    // Mirror the BLoC round-trip: the owner re-passes the text the editor
    // just emitted. The controller must not be re-seeded (cursor preserved).
    var current = 'A: 1';
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            BulkKvEditor(
              initialText: current,
              onChanged: (text) => setState(() => current = text),
            ),
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'A: 12');
    await tester.pump();

    // Field shows what the user typed, not a stale re-seed.
    expect(find.widgetWithText(TextField, 'A: 12'), findsOneWidget);
  });

  testWidgets('re-seeds when initialText genuinely changes externally', (
    tester,
  ) async {
    await pump(
      tester,
      const BulkKvEditor(initialText: 'A: 1', onChanged: _noop),
    );
    expect(find.widgetWithText(TextField, 'A: 1'), findsOneWidget);

    await pump(
      tester,
      const BulkKvEditor(initialText: 'B: 2', onChanged: _noop),
    );
    expect(find.widgetWithText(TextField, 'B: 2'), findsOneWidget);
  });

  testWidgets('fieldPrefix anchors a ValueKey for E2E targeting', (
    tester,
  ) async {
    await pump(
      tester,
      const BulkKvEditor(
        initialText: '',
        onChanged: _noop,
        fieldPrefix: 'param',
      ),
    );

    expect(find.byKey(const ValueKey('param_bulk')), findsOneWidget);
  });
}

void _noop(String _) {}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/bulk_kv_editor_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:getman/core/ui/widgets/bulk_kv_editor.dart'`.

- [ ] **Step 3: Write the atom**

Create `lib/core/ui/widgets/bulk_kv_editor.dart`. All sizes/colors/radii/weights come from `context.app*` (verified field names: `appTypography.codeFontFamily` / `.bodyWeight`, `appLayout.fontSizeCode` / `.inputPadding` / `.isCompact`, `appShape.inputRadius`):

```dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// A single multiline `key: value` text view backing the bulk-edit mode of the
/// params and headers tabs. Format-agnostic: it reports the **raw text** up via
/// [onChanged]; the owning tab view parses it with `BulkKvCodec` and runs its
/// existing `encode` closure, so bulk and row modes produce identical canonical
/// values.
///
/// Echo suppression mirrors [KeyValueListEditor]: the controller is re-seeded
/// only when [initialText] genuinely changes AND differs from the controller's
/// current text, so the BLoC round-trip echo never resets the cursor mid-type.
class BulkKvEditor extends StatefulWidget {
  const BulkKvEditor({
    required this.initialText,
    required this.onChanged,
    super.key,
    this.fieldPrefix,
  });

  /// The serialized canonical value at open time (and on every external change).
  final String initialText;

  /// Reports the raw text upward on every keystroke.
  final ValueChanged<String> onChanged;

  /// When set, the field gets a stable `ValueKey('<prefix>_bulk')` so E2E tests
  /// can target it (mirrors `KeyValueListEditor.fieldPrefix`).
  final String? fieldPrefix;

  @override
  State<BulkKvEditor> createState() => _BulkKvEditorState();
}

class _BulkKvEditorState extends State<BulkKvEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void didUpdateWidget(BulkKvEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-seed on a genuine external change — and never clobber what the
    // user is currently typing (the echo of our own emission).
    if (widget.initialText != oldWidget.initialText &&
        widget.initialText != _controller.text) {
      _controller.text = widget.initialText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);

    final textStyle = TextStyle(
      fontFamily: typography.codeFontFamily,
      fontSize: layout.fontSizeCode,
      fontWeight: typography.bodyWeight,
      color: theme.colorScheme.onSurface,
    );

    return TextField(
      key: widget.fieldPrefix == null
          ? null
          : ValueKey('${widget.fieldPrefix}_bulk'),
      controller: _controller,
      onChanged: widget.onChanged,
      maxLines: null,
      expands: true,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      autocorrect: false,
      enableSuggestions: false,
      style: textStyle,
      decoration: InputDecoration(
        hintText: 'Key: Value\nKey: Value',
        hintMaxLines: 2,
        alignLabelWithHint: true,
        contentPadding: EdgeInsets.all(layout.inputPadding),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.appShape.inputRadius),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/bulk_kv_editor_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Format + analyze + commit**

```bash
fvm dart format lib/core/ui/widgets/bulk_kv_editor.dart test/core/ui/widgets/bulk_kv_editor_test.dart
fvm flutter analyze lib/core/ui/widgets/bulk_kv_editor.dart
git add lib/core/ui/widgets/bulk_kv_editor.dart test/core/ui/widgets/bulk_kv_editor_test.dart
git commit -m "$(cat <<'EOF'
feat(tabs): BulkKvEditor multiline atom for bulk key:value editing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Wire the row⇄bulk toggle into `ParamsTabView` and `HeadersTabView`

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/request_editor_tabs.dart`
- Test: `test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart`

This task converts both tab views to `StatefulWidget`s holding an ephemeral `bool _bulk` (D7) and renders a shared toggle header above the editor body. Both modes feed the **same** `decode`/`encode` closures already in the file, so the canonical value and the single `UpdateTab` dispatch are unchanged. The existing `_VariableContextBuilder` wrapping (Settings + Environments blocs) and `fieldPrefix` stay; bulk mode is plain text (no `{{var}}` highlighting — locked non-goal §3).

- [ ] **Step 1: Write the failing widget test**

The toggle lives inside the tab views, which require `TabsBloc`, `SettingsBloc`, **and** `EnvironmentsBloc` in scope (the `_VariableContextBuilder` reads the latter two even when no environment is active). Before writing the test, READ these to copy the exact harness/mocking style and constructor shapes used elsewhere:
- `test/features/tabs/presentation/widgets/body_tab_view_test.dart` — how a real `TabsBloc` is built over a `MockTabsRepository` + `MockSendRequestUseCase`, loaded via `LoadTabs`, and how a `HttpRequestTabEntity` tab/config is seeded (`_loadedBloc`, `tab(...)`, `registerFallbackValue`). Mirror this for the `TabsBloc`.
- `test/features/tabs/presentation/widgets/response_section_test.dart` — how `MultiBlocProvider` provides `TabsBloc` + `SettingsBloc` (`BlocProvider<SettingsBloc>(create: (_) => _settingsBloc(settings))`) inside a `MaterialApp(theme: brutalistTheme(...))`. **Add a third provider for `EnvironmentsBloc`** the same way (a loaded `EnvironmentsBloc`, or a mock with `whenListen` over an empty `EnvironmentsState()` — whichever mocking style the existing env tests use; an empty environment set is fine since the test does not assert on resolution).
- `test/core/ui/widgets/key_value_list_editor_test.dart` (already read — row-editor finders: `find.widgetWithText(TextField, 'KEY')`, `find.text('Accept')`).

Create `test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart`. Use the SAME bloc-provisioning approach `body_tab_view_test.dart` uses (mirror its `setUp`, fakes/mocks, and `pump` helper exactly — do not invent a different harness). The skeleton below shows the assertions; fill the `pumpParamsTab` / `pumpHeadersTab` body with that file's provider+state seeding pattern, seeding a tab whose `config.headers = {'Accept': '*/*'}` (headers) or whose URL carries `?q=1` so `config.params` decodes to one row (params):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
// + the bloc/state/event imports that body_tab_view_test.dart uses,
//   plus brutalist_theme.dart for the MaterialApp theme.

void main() {
  // Reuse body_tab_view_test.dart's harness verbatim: build the same
  // MultiBlocProvider (TabsBloc + SettingsBloc + EnvironmentsBloc, faked) with
  // a single seeded tab, wrapped in MaterialApp(theme: brutalistTheme(...)).
  //
  // Provide two helpers that pump HeadersTabView / ParamsTabView for that tab:
  //   Future<void> pumpHeadersTab(WidgetTester tester);
  //   Future<void> pumpParamsTab(WidgetTester tester);

  testWidgets('headers tab starts in row mode (no bulk editor)', (
    tester,
  ) async {
    await pumpHeadersTab(tester);
    expect(find.byType(KeyValueListEditor<Map<String, String>>), findsOneWidget);
    expect(find.byType(BulkKvEditor), findsNothing);
    expect(find.byTooltip('Bulk edit'), findsOneWidget);
  });

  testWidgets('toggling headers to bulk shows the serialized block', (
    tester,
  ) async {
    await pumpHeadersTab(tester);
    await tester.tap(find.byTooltip('Bulk edit'));
    await tester.pumpAndSettle();

    expect(find.byType(BulkKvEditor), findsOneWidget);
    expect(find.byType(KeyValueListEditor<Map<String, String>>), findsNothing);
    // Seeded {'Accept': '*/*'} serialized into the text block.
    expect(find.widgetWithText(TextField, 'Accept: */*'), findsOneWidget);
    // The toggle now offers the reverse action.
    expect(find.byTooltip('Edit as rows'), findsOneWidget);
  });

  testWidgets('editing in bulk mode then back to rows reflects the parse', (
    tester,
  ) async {
    await pumpHeadersTab(tester);
    await tester.tap(find.byTooltip('Bulk edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Accept: */*\nX-Token: abc',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Edit as rows'));
    await tester.pumpAndSettle();

    expect(find.byType(KeyValueListEditor<Map<String, String>>), findsOneWidget);
    expect(find.text('X-Token'), findsOneWidget);
    expect(find.text('abc'), findsOneWidget);
  });

  testWidgets('params tab also offers the bulk toggle', (tester) async {
    await pumpParamsTab(tester);
    expect(find.byTooltip('Bulk edit'), findsOneWidget);
  });
}
```

> Implementer note: `find.widgetWithText(TextField, 'Accept: */*')` matches the multiline `BulkKvEditor` field by its controller text. If `body_tab_view_test.dart` pumps a phone vs desktop layout, keep the default (desktop) so the row finders match `key_value_list_editor_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart`
Expected: FAIL — `find.byTooltip('Bulk edit')` finds nothing / `BulkKvEditor` never appears (the toggle does not exist yet).

- [ ] **Step 3: Add imports + a shared toggle header widget**

In `lib/features/tabs/presentation/widgets/request_editor_tabs.dart`, add imports (alphabetical within the `package:getman/...` block, after the existing `bulk`/`ui/widgets` lines — `directives_ordering` is enforced):

```dart
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';
import 'package:getman/core/utils/bulk_kv_codec.dart';
```

Add a private toggle-header widget near the top of the file (e.g. just below `_VariableContextBuilder`). It is theme-driven (`context.appDecoration.wrapInteractive`, `appLayout`, `appTypography`, `appPalette`) — no hardcoded sizes/colors:

```dart
/// Small header above the params/headers editor body offering the row⇄bulk
/// toggle. [bulk] is the current mode; [onToggle] flips it. The icon/label
/// describe the action the tap performs (Postman convention).
class _BulkModeToggle extends StatelessWidget {
  const _BulkModeToggle({required this.bulk, required this.onToggle});

  final bool bulk;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);
    // In bulk mode the action returns to rows; in row mode it goes to bulk.
    final label = bulk ? 'Edit as rows' : 'Bulk edit';
    final icon = bulk ? Icons.view_list_outlined : Icons.notes_outlined;

    return Align(
      alignment: Alignment.centerRight,
      child: context.appDecoration.wrapInteractive(
        onTap: onToggle,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.badgePaddingHorizontal,
            vertical: layout.badgePaddingVertical,
          ),
          child: Tooltip(
            message: label,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: layout.smallIconSize,
                  color: theme.colorScheme.secondary,
                ),
                SizedBox(width: layout.tabSpacing),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: typography.titleWeight,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Convert `ParamsTabView` to a `StatefulWidget` with the toggle**

Replace the existing `ParamsTabView` (lines ~76–122) with a stateful version. The `BlocBuilder` + `_VariableContextBuilder` + the existing `decode`/`encode`/`equals`/`onChanged` closures are unchanged; they are now produced inside the builder and shared by both modes. Bulk mode passes plain text (no `variableContext`):

```dart
/// Ordered query-param editor. Duplicate keys allowed, order preserved —
/// the URL is the single source of truth, so edits round-trip through it.
class ParamsTabView extends StatefulWidget {
  const ParamsTabView({required this.tabId, super.key});
  final String tabId;

  @override
  State<ParamsTabView> createState() => _ParamsTabViewState();
}

class _ParamsTabViewState extends State<ParamsTabView> {
  // Ephemeral view preference (D7): not persisted, resets to row on reload.
  bool _bulk = false;

  @override
  Widget build(BuildContext context) {
    final tabId = widget.tabId;
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        return prev.tabs.byId(tabId)?.config.url !=
            next.tabs.byId(tabId)?.config.url;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        List<QueryParamEntity> encode(List<(String, String)> rows) => [
          for (final (key, value) in rows)
            if (key.isNotEmpty) QueryParamEntity(key: key, value: value),
        ];
        List<(String, String)> decode(List<QueryParamEntity> params) => [
          for (final p in params) (p.key, p.value),
        ];
        void emit(List<QueryParamEntity> list) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          bloc.add(
            UpdateTab(
              current.copyWith(config: current.config.copyWith(params: list)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BulkModeToggle(
              bulk: _bulk,
              onToggle: () => setState(() => _bulk = !_bulk),
            ),
            Expanded(
              child: _bulk
                  ? BulkKvEditor(
                      fieldPrefix: 'param',
                      initialText: BulkKvCodec.serialize(
                        decode(tab.config.params),
                      ),
                      onChanged: (text) => emit(encode(BulkKvCodec.parse(text))),
                    )
                  : _VariableContextBuilder(
                      builder: (context, varContext) =>
                          KeyValueListEditor<List<QueryParamEntity>>(
                            items: tab.config.params,
                            variableContext: varContext,
                            fieldPrefix: 'param',
                            decode: decode,
                            encode: encode,
                            equals: _queryParamListEquality.equals,
                            onChanged: emit,
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

- [ ] **Step 5: Convert `HeadersTabView` the same way**

Replace the existing `HeadersTabView` (lines ~126–171) analogously — `Map<String,String>` canonical type, `fieldPrefix: 'header'`, `equals: stringMapEquality.equals`, and the existing headers `encode`/`decode`/`onChanged`:

```dart
/// Header editor keyed as `Map<String, String>` — duplicates are not a real
/// concern for headers in this UI; last-write-wins is fine.
class HeadersTabView extends StatefulWidget {
  const HeadersTabView({required this.tabId, super.key});
  final String tabId;

  @override
  State<HeadersTabView> createState() => _HeadersTabViewState();
}

class _HeadersTabViewState extends State<HeadersTabView> {
  bool _bulk = false;

  @override
  Widget build(BuildContext context) {
    final tabId = widget.tabId;
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) => !stringMapEquality.equals(
        prev.tabs.byId(tabId)?.config.headers,
        next.tabs.byId(tabId)?.config.headers,
      ),
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        Map<String, String> encode(List<(String, String)> rows) => {
          for (final (key, value) in rows)
            if (key.isNotEmpty) key: value,
        };
        List<(String, String)> decode(Map<String, String> headers) => [
          for (final e in headers.entries) (e.key, e.value),
        ];
        void emit(Map<String, String> map) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          bloc.add(
            UpdateTab(
              current.copyWith(config: current.config.copyWith(headers: map)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BulkModeToggle(
              bulk: _bulk,
              onToggle: () => setState(() => _bulk = !_bulk),
            ),
            Expanded(
              child: _bulk
                  ? BulkKvEditor(
                      fieldPrefix: 'header',
                      initialText: BulkKvCodec.serialize(
                        decode(tab.config.headers),
                      ),
                      onChanged: (text) => emit(encode(BulkKvCodec.parse(text))),
                    )
                  : _VariableContextBuilder(
                      builder: (context, varContext) =>
                          KeyValueListEditor<Map<String, String>>(
                            items: tab.config.headers,
                            variableContext: varContext,
                            fieldPrefix: 'header',
                            decode: decode,
                            encode: encode,
                            equals: stringMapEquality.equals,
                            onChanged: emit,
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

> Note: the previous bodies inlined `decode`/`encode`/`onChanged` directly in the `KeyValueListEditor` constructor. Hoisting them to local functions (`decode`/`encode`/`emit`) lets the bulk path reuse the EXACT same closures (D8/D9) — do not duplicate them with subtly different logic, or the round-trip diverges.

- [ ] **Step 6: Run the new toggle test to verify it passes**

Run: `fvm flutter test test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 7: Run the existing tab-view + key/value editor tests (regression)**

Run: `fvm flutter test test/features/tabs/presentation/widgets/ test/core/ui/widgets/key_value_list_editor_test.dart`
Expected: PASS. Row mode is the default and the row editor is unchanged, so existing behavior is preserved.

- [ ] **Step 8: Format, analyze (all three passes), commit**

```bash
fvm dart format lib/features/tabs/presentation/widgets/request_editor_tabs.dart test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
git add lib/features/tabs/presentation/widgets/request_editor_tabs.dart test/features/tabs/presentation/widgets/bulk_kv_toggle_test.dart
git commit -m "$(cat <<'EOF'
feat(tabs): row/bulk edit toggle on the params and headers tabs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Full done-bar verification

**Files:** none (verification only).

- [ ] **Step 1: Run the complete gate stack**

Run each and confirm clean (CLAUDE.md §5 — these are independent passes; a clean `analyze` does NOT imply `custom_lint`/`bloc_lint` are clean):

```bash
fvm dart format lib test tools
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm flutter test
```

Expected: `dart format` reports 0 changed (or any reformat is committed); all three analysis passes report "No issues found"; all tests green. In particular, `custom_lint` must not flag `avoid_hardcoded_brand_colors` — `BulkKvEditor` and `_BulkModeToggle` use only `theme.colorScheme.*` and `context.app*` colors (no `Colors.black/white/red`).

- [ ] **Step 2: Commit any formatting fixups (if needed)**

```bash
git add -A && git commit -m "$(cat <<'EOF'
chore(tabs): format bulk-edit sources

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)" || echo "nothing to format"
```

---

### Task 5: Update the wiki

**Files:**
- Wiki: `Getman.wiki.git` (separate repo) — the **Requests** page (PARAMS / HEADERS / BODY tabs).

Per the "Keep the wiki in sync" mandate (CLAUDE.md §7), this adds a user-visible capability (a Bulk edit toggle on Params and Headers), so the wiki must be updated as part of this work.

- [ ] **Step 1: Clone the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

- [ ] **Step 2: Edit the Requests page**

Open the page documenting the PARAMS / HEADERS / BODY tabs (likely `Requests.md` — confirm by listing `/tmp/getman-wiki`; check `_Sidebar.md` for the exact page name). Add a short **Bulk edit** subsection under the Params/Headers description. Use the verbatim UI labels `Bulk edit` / `Edit as rows`. Cover:
- A toggle on the Params and Headers tabs switches between the row-by-row editor and a free-text block.
- The bulk format is one `key: value` pair per line.
- Each line is split on the **first** `:` (so a colon inside a value, e.g. `Authorization: Bearer a:b`, is preserved); both sides are trimmed.
- A line with no colon keeps the whole line as the key with an empty value.
- Blank/whitespace-only lines are ignored, and lines whose key is empty (e.g. `: value`) are dropped.
- There is **no** disabled-row syntax (no `#`/`//` convention) — params and headers carry no enabled/disabled flag.
- Switching either direction preserves the data losslessly.
- The **Environment Variables** editor is intentionally row-only (no bulk toggle), because the secret lock/reveal affordance has no lossless flat-text representation.

No new page and no `_Sidebar.md` change are needed.

- [ ] **Step 3: Commit + push the wiki**

```bash
cd /tmp/getman-wiki && git add -A && git commit -m "docs: bulk edit for params and headers" && git push origin master
```

---

## Self-Review (completed during planning)

- **Spec coverage:** pure codec with all of D2–D6 + round-trip (Task 1) ✓; reusable `BulkKvEditor` atom with echo-suppression + `fieldPrefix` E2E anchor (Task 2) ✓; row⇄bulk toggle on `ParamsTabView` + `HeadersTabView` as ephemeral `bool _bulk` (D7), shared `decode`/`encode`/`emit` closures (D8/D9/D10), bulk mode plain text (no highlighting — locked non-goal) (Task 3) ✓; env-vars editor untouched / no toggle offered (it is a different consumer of `KeyValueListEditor` and not edited) ✓; full done-bar (Task 4) ✓; wiki (Task 5) ✓.
- **Type accuracy (verified against the real files):** `KeyValueListEditor<T>` constructor params (`items`, `onChanged`, `decode`, `encode`, `equals`, `variableContext`, `fieldPrefix`) match `key_value_list_editor.dart`; `QueryParamEntity({required key, required value})`; `_queryParamListEquality` and `stringMapEquality` already top-level in `request_editor_tabs.dart`; `UpdateTab`, `tab.copyWith(config:)`, `config.copyWith(params:|headers:)`, `state.tabs.byId(tabId)` all used as today; `_VariableContextBuilder` reused verbatim; row currency is `List<(String, String)>` (record tuples) exactly as `decode`/`encode` already speak.
- **Theme adherence (verified field names in `extensions/`):** `appLayout.fontSizeCode`/`fontSizeSmall`/`inputPadding`/`isCompact`/`smallIconSize`/`tabSpacing`/`badgePaddingHorizontal`/`badgePaddingVertical`; `appShape.inputRadius`; `appTypography.codeFontFamily`/`bodyWeight`/`titleWeight`; `appDecoration.wrapInteractive(child:, onTap:)`. No hardcoded sizes/colors/radii/weights; only `theme.colorScheme.*` for foreground colors.
- **Imports:** all `package:getman/...` (no relative imports); new `import` lines placed to keep `directives_ordering` clean.
- **No bloc/domain/Hive changes:** confirmed — bulk reuses the existing `UpdateTab` path; toggle state is ephemeral widget state.
- **Sequencing:** pure unit (Task 1) → atom widget test (Task 2) → wiring widget test (Task 3) → full gate (Task 4) → wiki LAST (Task 5).
- **Open verification for the implementer:** Task 3 Step 1 requires copying `body_tab_view_test.dart`'s exact bloc-provisioning harness (fakes/mocks for `TabsBloc`/`SettingsBloc`/`EnvironmentsBloc` + seeded tab) — READ it first rather than inventing a harness.
