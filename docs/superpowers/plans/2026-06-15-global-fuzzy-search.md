# Global Fuzzy Search (Command Palette Expansion) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Broaden the existing Cmd/Ctrl+K command palette so it (1) also surfaces **request history** entries as searchable results that open as an **unlinked** tab, and (2) matches **saved requests** by their **HTTP method + URL** in addition to name + collection path. This is an enhancement of the existing palette surface — no new screen, route, shortcut, bloc, event, or persistence path.

**Architecture:** All changes are confined to the command_palette feature plus its `show()` wiring (and the matching widget test). `CommandPalette.show` gains a `historyBloc: context.read<HistoryBloc>()` read (already provided at the root `MultiBlocProvider` in `main.dart`, reachable at the `CommandPaletteIntent` action site). `_buildCommands()` appends one `_Command` per `historyBloc.state.history` entry (newest-first, after request/env/theme sources). The `_Command` value type gains an optional `matchExtra` field (default `''`); a new `_matchString(c)` projection feeds `label + subtitle + matchExtra` to `FuzzyMatcher.filter`, so saved requests can carry `'<method> <url>'` and history entries carry `'<method>'` (their URL is already the label) — all while the **displayed** label/subtitle stay unchanged. The hint text becomes `Jump to a request, history entry, environment, or theme…`.

**Tech Stack:** Flutter (`fvm flutter`), `flutter_bloc`, `equatable`, `flutter_test`, `mocktail`. No new dependencies. No domain/data layer changes, no new entity, no theme-extension changes (every value already comes from `context.app*`).

---

## File Structure

**Modify:**
- `lib/features/command_palette/presentation/widgets/command_palette.dart` — add `HistoryBloc` to `show()` + a `historyBloc` field; append a History source in `_buildCommands()`; add `matchExtra` to `_Command`; add `_matchString` projection and use it in both `FuzzyMatcher.filter` calls; set `matchExtra` on saved-request commands; update the hint text.
- `test/features/command_palette/presentation/widgets/command_palette_test.dart` — add `MockHistoryBloc`, wire it into the `pump` helper + the existing `CommandPalette(...)` constructor call, and add the new behavior tests (history appears + opens unlinked, request matches by URL, request matches by method, empty history no-op).

**Wiki (Task 5):** `Getman.wiki.git` (separate repo) — the Command Palette page (and `_Sidebar.md` if it summarizes searchable sources).

> **Scope lock (spec Locked Decision 1 + 3):** Do **not** add a new bloc/event/dialog/route/shortcut. Do **not** scan request **body** or **header** values/keys into the match string in v1 — only method + URL. Keep all edits inside the two files above.

---

### Task 1: Widen the saved-request match string (matchExtra + projection)

This is the pure-widget, no-`HistoryBloc`-yet step. It adds the `matchExtra` field, the `_matchString` projection, and wires saved requests to match by method + URL. The History source comes in Task 2 so each task is independently green.

**Files:**
- Modify: `lib/features/command_palette/presentation/widgets/command_palette.dart`
- Test: `test/features/command_palette/presentation/widgets/command_palette_test.dart`

- [ ] **Step 1: Write the failing tests (request matches by URL + by method)**

Add these two `testWidgets` to `test/features/command_palette/presentation/widgets/command_palette_test.dart`, after the existing `'tapping an environment switches it'` test (inside the same `main()`):

```dart
  testWidgets('request matches by URL fragment, not just name', (tester) async {
    // Seed a leaf whose NAME ('Widgets List') does not contain the URL token
    // 'orders' — only the URL does. Proves the widened match string.
    when(() => collections.state).thenReturn(
      CollectionsState(
        collections: const [
          CollectionNodeEntity(
            id: 'r2',
            name: 'Widgets List',
            isFolder: false,
            config: HttpRequestConfigEntity(
              id: 'c2',
              method: 'GET',
              url: 'https://api.dev/orders',
            ),
          ),
        ],
      ),
    );
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'orders');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    // The displayed label is still the node name — the URL only widened the
    // hidden match text.
    expect(find.text('Widgets List'), findsOneWidget);
  });

  testWidgets('request matches by HTTP method', (tester) async {
    when(() => collections.state).thenReturn(
      CollectionsState(
        collections: const [
          CollectionNodeEntity(
            id: 'r3',
            name: 'Remove User',
            isFolder: false,
            config: HttpRequestConfigEntity(
              id: 'c3',
              method: 'DELETE',
              url: 'https://api.dev/users/1',
            ),
          ),
        ],
      ),
    );
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Remove User'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/features/command_palette/presentation/widgets/command_palette_test.dart`
Expected: the two new tests FAIL — `find.text('Widgets List')` / `find.text('Remove User')` find nothing because the current match string is only `'${c.label} ${c.subtitle}'`, so a query of `orders`/`delete` filters them out. (The existing tests still pass.)

- [ ] **Step 3: Add `matchExtra` to `_Command`**

In `lib/features/command_palette/presentation/widgets/command_palette.dart`, update the `_Command` value type (near the bottom of the file) to carry an optional hidden match string. Replace the class with:

```dart
class _Command {
  const _Command({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.run,
    this.matchExtra = '',
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback run;

  /// Extra text folded into the fuzzy-match string but NOT displayed — lets a
  /// saved request match by method + URL (and a history entry by method)
  /// without changing the visible label/subtitle. Default `''` keeps
  /// environment/theme commands matching on label + subtitle only.
  final String matchExtra;
}
```

- [ ] **Step 4: Add the `_matchString` projection and use it in both filter calls**

In `_CommandPaletteState`, add the projection method (place it next to `_resultsFor`):

```dart
  static String _matchString(_Command c) => c.matchExtra.isEmpty
      ? '${c.label} ${c.subtitle}'
      : '${c.label} ${c.subtitle} ${c.matchExtra}';
```

Then change `_resultsFor` to use it:

```dart
  List<_Command> _resultsFor(String query) =>
      FuzzyMatcher.filter(query, _all, _matchString);
```

(`_runSelected` already calls `_resultsFor(_query.text)`, so the Enter path picks this up automatically.)

- [ ] **Step 5: Set `matchExtra` on saved-request commands**

In `_collectRequests`, add `matchExtra` to the request `_Command` (the displayed `label`/`subtitle` are unchanged):

```dart
        out.add(
          _Command(
            label: node.name,
            subtitle: path.isEmpty ? 'Request' : path,
            icon: Icons.http,
            matchExtra: '${config.method} ${config.url}',
            run: () => widget.tabsBloc.add(
              AddTab(
                config: config,
                collectionNodeId: node.id,
                collectionName: node.name,
              ),
            ),
          ),
        );
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `fvm flutter test test/features/command_palette/presentation/widgets/command_palette_test.dart`
Expected: PASS (all existing tests + the two new ones). Environment/theme commands left `matchExtra` at `''`, so the `'typing filters the list'` and `'tapping an environment switches it'` regressions stay green.

- [ ] **Step 7: Commit**

```bash
git add lib/features/command_palette/presentation/widgets/command_palette.dart test/features/command_palette/presentation/widgets/command_palette_test.dart
git commit -m "feat(palette): match saved requests by method + URL

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Wire `HistoryBloc` into the palette + append a History source

**Files:**
- Modify: `lib/features/command_palette/presentation/widgets/command_palette.dart`
- Test: `test/features/command_palette/presentation/widgets/command_palette_test.dart`

- [ ] **Step 1: Add the `MockHistoryBloc` + wire it into the test harness**

In `test/features/command_palette/presentation/widgets/command_palette_test.dart`, add the imports (keep `directives_ordering` — these sort alphabetically among the existing `package:getman/...` imports):

```dart
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
```

Add the mock class next to the other mocks:

```dart
class MockHistoryBloc extends Mock implements HistoryBloc {}
```

Declare + construct it in `setUp` alongside the others:

```dart
  late MockHistoryBloc history;
```

```dart
    history = MockHistoryBloc();
```

Stub its state (empty by default — individual tests override it). Add after the existing `when(() => environments.state)...` stub:

```dart
    when(() => history.state).thenReturn(const HistoryState());
```

Pass it into the `CommandPalette(...)` constructor inside the `pump` helper:

```dart
          body: CommandPalette(
            tabsBloc: tabs,
            collectionsBloc: collections,
            environmentsBloc: environments,
            settingsBloc: settings,
            historyBloc: history,
          ),
```

> At this point the test file references `historyBloc:` which the widget does not yet accept — the suite will not compile. That is the intended failing state for Step 3.

- [ ] **Step 2: Add the failing History behavior tests**

Add these `testWidgets` to `main()` (after the request-match tests from Task 1):

```dart
  testWidgets('history entry appears with a History subtitle and opens unlinked',
      (tester) async {
    when(() => history.state).thenReturn(
      const HistoryState(
        history: [
          HttpRequestConfigEntity(
            id: 'h1',
            method: 'POST',
            url: 'https://api.example.com/orders',
          ),
        ],
      ),
    );
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'orders');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // The URL is the row label; 'History' is the source-tag subtitle.
    expect(find.text('https://api.example.com/orders'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    await tester.tap(find.text('https://api.example.com/orders'));
    await tester.pumpAndSettle();

    final captured = verify(() => tabs.add(captureAny(that: isA<AddTab>())))
        .captured
        .single as AddTab;
    expect(captured.config?.url, 'https://api.example.com/orders');
    expect(captured.config?.method, 'POST');
    // Unlinked tab — Locked Decision 4.
    expect(captured.collectionNodeId, isNull);
    expect(captured.collectionName, isNull);
  });

  testWidgets('empty history adds no History row', (tester) async {
    // history.state already stubbed empty in setUp.
    await pump(tester);
    expect(find.text('History'), findsNothing);
    // Existing sources still render.
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
  });
```

- [ ] **Step 3: Run the tests to verify they fail (compile error first)**

Run: `fvm flutter test test/features/command_palette/presentation/widgets/command_palette_test.dart`
Expected: FAIL — the suite does not compile because `CommandPalette` has no `historyBloc` parameter (and once it does, the History row/assertions would still fail until `_buildCommands` appends the source).

- [ ] **Step 4: Add the `historyBloc` field + read in `CommandPalette`**

In `lib/features/command_palette/presentation/widgets/command_palette.dart`, add the import (alphabetical among the `package:getman/...` directives — it sorts before `settings`):

```dart
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
```

Add the constructor param + field to `CommandPalette`:

```dart
  const CommandPalette({
    required this.tabsBloc,
    required this.collectionsBloc,
    required this.environmentsBloc,
    required this.settingsBloc,
    required this.historyBloc,
    super.key,
  });
  final TabsBloc tabsBloc;
  final CollectionsBloc collectionsBloc;
  final EnvironmentsBloc environmentsBloc;
  final SettingsBloc settingsBloc;
  final HistoryBloc historyBloc;
```

Read it in `show()`:

```dart
  static Future<void> show(BuildContext context) {
    return showResponsiveDialog(
      context,
      builder: (_) => CommandPalette(
        tabsBloc: context.read<TabsBloc>(),
        collectionsBloc: context.read<CollectionsBloc>(),
        environmentsBloc: context.read<EnvironmentsBloc>(),
        settingsBloc: context.read<SettingsBloc>(),
        historyBloc: context.read<HistoryBloc>(),
      ),
    );
  }
```

> `HistoryBloc` is already in scope at the call site: `main.dart` provides it in the root `MultiBlocProvider`, and `CommandPalette.show(context)` is invoked from the `CommandPaletteIntent` `CallbackAction` under that provider tree. No DI/provider change needed.

- [ ] **Step 5: Append the History source in `_buildCommands`**

In `_buildCommands()`, after the theme loop and before `return cmds;`, append one command per history entry (newest-first — `state.history` is already reversed by the repository):

```dart
    // History source: newest-first (the repository already reverses insertion
    // order). Opens an UNLINKED tab from the stored, templated config —
    // matching history_list.dart verbatim (no collectionNodeId/Name) so a
    // re-send never compares against / overwrites a collection node, and the
    // {{var}} placeholders stay unresolved for re-sending under another env.
    for (final config in widget.historyBloc.state.history) {
      cmds.add(
        _Command(
          label: config.url.isEmpty ? '(NO URL)' : config.url,
          subtitle: 'History',
          icon: Icons.history,
          matchExtra: config.method,
          run: () => widget.tabsBloc.add(AddTab(config: config.copyWith())),
        ),
      );
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `fvm flutter test test/features/command_palette/presentation/widgets/command_palette_test.dart`
Expected: PASS (all tests, including the new History ones). The `'empty history adds no History row'` test confirms the loop is a no-op on empty state; the `'lists requests, environments and themes'` regression confirms existing sources are untouched.

- [ ] **Step 7: Commit**

```bash
git add lib/features/command_palette/presentation/widgets/command_palette.dart test/features/command_palette/presentation/widgets/command_palette_test.dart
git commit -m "feat(palette): search request history; opens as an unlinked tab

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Update the search hint text + history matchExtra note

**Files:**
- Modify: `lib/features/command_palette/presentation/widgets/command_palette.dart`

- [ ] **Step 1: Update the hint text (user-facing label change)**

In `_buildScaffold`, change the `TextField`'s `hintText` literal:

```dart
              decoration: const InputDecoration(
                hintText: 'Jump to a request, history entry, environment, or theme…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
```

> This is plain copy in the widget (not a themed token), so a string literal is correct here. Use the verbatim text above — the Wiki task (Task 5) references it.

- [ ] **Step 2: Verify the hint change does not break tests**

Run: `fvm flutter test test/features/command_palette/presentation/widgets/command_palette_test.dart`
Expected: PASS — no test asserts on the old hint text; the field is found `byType(TextField)`.

- [ ] **Step 3: Commit**

```bash
git add lib/features/command_palette/presentation/widgets/command_palette.dart
git commit -m "feat(palette): update search hint to mention history entries

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Full done-bar verification

**Files:** none (verification only).

- [ ] **Step 1: Format**

Run: `fvm dart format lib test tools`
Expected: reports 0 changed (the edited files are already formatted). If anything changes, the formatting is committed in Step 6.

- [ ] **Step 2: Static analysis (very_good_analysis)**

Run: `fvm flutter analyze`
Expected: `No issues found!`. Watch for `directives_ordering` on the new `history_bloc`/`history_state` imports — they must sort alphabetically among the `package:getman/...` directives.

- [ ] **Step 3: Architecture rules (custom_lint)**

Run: `fvm dart run custom_lint`
Expected: `No issues found!`. The palette reads `HistoryBloc` via the constructor field (passed by `show()` from `context.read`), not `GetIt`/`sl` from a widget, so `avoid_get_it_in_widgets` stays clean. No new `Colors.*` literals, so `avoid_hardcoded_brand_colors` stays clean.

- [ ] **Step 4: bloc_lint**

Run: `fvm dart run bloc_tools:bloc lint lib`
Expected: `No issues found` (no bloc/event changes — the palette only reads `state` and dispatches existing `AddTab`/`UpdateActiveEnvironmentId`/`UpdateThemeId`).

- [ ] **Step 5: Full test suite**

Run: `fvm flutter test`
Expected: 100% green — confirms no other consumer of `CommandPalette` broke (the only `CommandPalette(...)` construction outside `show()` is the widget test, which Task 2 updated; `show()` reads from context so `main.dart` needs no change).

- [ ] **Step 6: Commit any formatting (only if Step 1 changed files)**

```bash
git add -A && git commit -m "chore: format

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" || echo "nothing to format"
```

---

### Task 5: Update the wiki

**Files:**
- Wiki: `Getman.wiki.git` (separate repo) — the Command Palette page (+ `_Sidebar.md` if it lists searchable sources).

- [ ] **Step 1: Clone the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

- [ ] **Step 2: Edit the Command Palette page**

Find the page documenting Cmd/Ctrl+K (the command palette). Update it to document the two new behaviors, keeping UI copy verbatim:

- The palette now also searches **request history** — selecting a history result opens it as a **new (unlinked) tab**, carrying its captured response, so re-sending never overwrites a saved request.
- Saved requests now match by **HTTP method + URL** in addition to their name + collection path (so you can find "the POST to /orders" without remembering its saved name).
- The search hint reads exactly: `Jump to a request, history entry, environment, or theme…`.

If `_Sidebar.md` (or the page itself) enumerates the searchable sources (request / environment / theme), add **history** to that list.

- [ ] **Step 3: Commit + push the wiki**

```bash
cd /tmp/getman-wiki && git add -A && git commit -m "docs: command palette now searches history + matches requests by method/URL" && git push origin master
```

---

## Self-Review (completed during planning)

- **Spec coverage:** History source appended after request/env/theme, newest-first (Task 2, spec §Architecture 2 + Locked Decisions 5/7) ✓; history opens UNLINKED via `AddTab(config: config.copyWith())` with null `collectionNodeId`/`collectionName` (Task 2 Step 5 + test, Locked Decision 4) ✓; widened saved-request match = `label + subtitle + method + url` via `matchExtra` + `_matchString` (Task 1, Locked Decision 2) ✓; history `matchExtra = method` (URL is the label) (Task 2, Locked Decision 5) ✓; env/theme `matchExtra` stays `''` (unchanged match) ✓; `HistoryBloc` wired into `show()` from `context.read`, no DI/provider change (Task 2 §Architecture 1) ✓; hint text verbatim `Jump to a request, history entry, environment, or theme…` (Task 3) ✓; empty-history no-op (Task 2 test, spec §Error handling) ✓; wiki (Task 5, spec §Wiki) ✓.
- **Out-of-scope respected:** no body/header content scan (Locked Decision 3); no new bloc/event/route/shortcut/dialog (Locked Decision 1); no second dedupe pass (Locked Decision 6) — confined to the two named files.
- **Type consistency:** `_Command{label,subtitle,icon,run,matchExtra=''}`, `_matchString(_Command)→String`, `CommandPalette(tabsBloc,collectionsBloc,environmentsBloc,settingsBloc,historyBloc)`, `HistoryBloc.state.history : List<HttpRequestConfigEntity>` (newest-first), `HttpRequestConfigEntity{method,url,copyWith()}`, `AddTab(config:,collectionNodeId:,collectionName:,response:)`, `HistoryState({history,isLoading})` — all match the real code read during planning.
- **Test harness:** existing test mocks four blocs; Task 2 adds `MockHistoryBloc extends Mock implements HistoryBloc` + stub `history.state` + the new `historyBloc:` constructor arg in `pump` — the existing five tests keep their assertions and pass.
- **Sequencing:** Task 1 (pure widget + match-string widening, independently green) → Task 2 (HistoryBloc wiring + source) → Task 3 (copy) → Task 4 (full gate) → Task 5 (wiki LAST). Each task ends green and committed.
- **Open verification:** none — all signatures (`copyWith`, `method`, `url`, `AddTab`, `HistoryState`, `FuzzyMatcher.filter`) were read from the real files; `HistoryBloc` provider availability at the `show()` call site is per CLAUDE.md §4.1 step 5 + the spec.
