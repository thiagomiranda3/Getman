# Test Coverage Improvement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add coverage tooling, raise unit/widget coverage from ~76% toward ~90% by filling the biggest uncovered code paths, and fix + extend the macOS integration suite against the recent theme/motion UI changes.

**Architecture:** A committed `tool/coverage.sh` drives `flutter test --coverage` + `lcov`/`genhtml`. Unit/widget gaps are filled by mirroring existing test harnesses (in-memory Hive for data sources, mocktail-fed real blocs for widgets, mock-repository delegation for use cases). Integration work runs the existing macOS aggregator, triages every failure (real lib regression → TDD fix; finder drift → fix the flow), then adds new loud-theme motion flows.

**Tech Stack:** Flutter (`fvm`), `flutter_bloc`, `hive_ce`, `mocktail`, `patrol_finders` (macOS integration), `lcov`/`genhtml` (Homebrew, installed).

## Global Constraints

- Always invoke Flutter as `fvm flutter ...` / `fvm dart ...`, never plain `flutter`.
- Imports are `package:getman/...` everywhere (no relative imports).
- Done-bar before claiming any task complete: `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0 issues), `fvm dart run bloc_tools:bloc lint lib` (0 issues), `fvm dart format` clean, `fvm flutter test` 100% green. These are independent passes.
- Never weaken or delete an assertion to make a test pass. A failing integration test is triaged (lib fix vs finder fix), never masked.
- Coverage exclusions (for honesty, not to hide gaps): generated `*.g.dart`, `*/hive_registrar.g.dart`, abstract repo interfaces `*/domain/repositories/*.dart`, native-only `*/update_gate_io.dart` + `*/dio_adapter_config_io.dart`, and `lib/main.dart`.
- Coverage is a target (~90%), not a hard gate. Don't write vacuous tests (pump-and-assert-nothing) to inflate the number.
- Theme widgets must degrade under `reduceEffects`; never hardcode colors/sizes/radii (read from `context.app*`).

---

## Task 1: Coverage tooling (`tool/coverage.sh`)

**Files:**
- Create: `tool/coverage.sh`
- Modify: `.gitignore` (add `coverage/`)
- Modify: `CLAUDE.md` (§5 Build & Test Commands — add the coverage line)
- Modify: `integration_test/README.md` (one-line cross-reference) — optional, only if a natural spot exists

**Interfaces:**
- Produces: `coverage/lcov.info` (raw), `coverage/lcov.filtered.info` (post-exclusion), `coverage/html/index.html` (browsable report), and a terminal per-package summary. Later tasks re-run this script to confirm gaps closed.

- [ ] **Step 1: Write the script**

Create `tool/coverage.sh` with exactly:

```bash
#!/usr/bin/env bash
# Generates a unit/widget test coverage report for Getman.
#
# Usage:
#   bash tool/coverage.sh           # run tests, build filtered report + summary
#   bash tool/coverage.sh --open    # also open the HTML report in a browser
#
# Excludes generated + non-instrumentable files so the percentage is honest:
#   *.g.dart, hive_registrar.g.dart, abstract repo interfaces, native-only
#   platform files (update_gate_io / dio_adapter_config_io), and main.dart.
set -uo pipefail
cd "$(dirname "$0")/.."

RAW=coverage/lcov.info
FILTERED=coverage/lcov.filtered.info

echo "==> Running tests with coverage..."
fvm flutter test --coverage || { echo "tests failed — aborting report"; exit 1; }

echo "==> Filtering generated / non-instrumentable files..."
lcov --remove "$RAW" \
  '*.g.dart' \
  '*/hive_registrar.g.dart' \
  '*/domain/repositories/*.dart' \
  '*/update_gate_io.dart' \
  '*/dio_adapter_config_io.dart' \
  'lib/main.dart' \
  --ignore-errors unused,inconsistent,empty,corrupt \
  -o "$FILTERED"

echo "==> Generating HTML report..."
genhtml "$FILTERED" -o coverage/html --quiet \
  --ignore-errors inconsistent,corrupt,category 2>/dev/null \
  || genhtml "$FILTERED" -o coverage/html --quiet

echo ""
echo "==> Overall + per-package line coverage:"
awk '
/^SF:/ { f=substr($0,4); sub(/^lib\//,"",f); n=split(f,p,"/"); pkg=(n>=2)?p[1]"/"p[2]:p[1] }
/^LF:/ { lf=substr($0,4) }
/^LH:/ { lh=substr($0,4); LF[pkg]+=lf; LH[pkg]+=lh; TLF+=lf; TLH+=lh }
END {
  for (k in LF) printf "%6.1f%%  %5d/%-5d  %s\n", (LF[k]?100*LH[k]/LF[k]:100), LH[k], LF[k], k
  printf "\n==== OVERALL: %.2f%%  (%d/%d) ====\n", (TLF?100*TLH/TLF:0), TLH, TLF
}' "$FILTERED" | sort -n

echo ""
echo "Report: coverage/html/index.html"
if [[ "${1:-}" == "--open" ]]; then open coverage/html/index.html; fi
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x tool/coverage.sh`

- [ ] **Step 3: Add coverage/ to .gitignore**

Add a line `coverage/` to `.gitignore` (check it isn't already present first with `grep -n coverage .gitignore`).

- [ ] **Step 4: Run the script and verify it produces a report**

Run: `bash tool/coverage.sh`
Expected: tests pass, prints a per-package table ending in `==== OVERALL: ~76% ====`, and `coverage/html/index.html` exists.
**Known gotcha (lcov 2.x from Homebrew is strict):** if `lcov --remove` or `genhtml` aborts with `ERROR: ... mismatch / inconsistent / unused`, the `--ignore-errors` flags above handle the common ones. If a *new* error category appears, add it to the `--ignore-errors` list (comma-separated) rather than removing the flag. Confirm `coverage/html/index.html` opens and shows per-file coverage.

- [ ] **Step 5: Document in CLAUDE.md §5**

In `CLAUDE.md`, in the §5 Build & Test Commands fenced block, add a line:
```
bash tool/coverage.sh                                         # unit/widget coverage report (coverage/html/index.html)
```

- [ ] **Step 6: Commit**

```bash
git add tool/coverage.sh .gitignore CLAUDE.md
git commit -m "test(coverage): add tool/coverage.sh (flutter test --coverage + lcov/genhtml report)"
```

---

## Task 2: Tier-1 logic tests (use cases + data sources at 0%)

**Files:**
- Create: `test/features/chaining/domain/usecases/request_rules_usecases_test.dart`
- Create: `test/features/settings/domain/usecases/settings_usecases_test.dart`
- Create: `test/features/chaining/data/datasources/request_rules_local_data_source_test.dart`
- Create: `test/features/settings/data/datasources/settings_local_data_source_test.dart`

**Interfaces:**
- Consumes (production code under test):
  - `GetRequestRulesUseCase(repo).call(String configId) -> Future<RequestRulesEntity>`, `SaveRequestRulesUseCase(repo).call(RequestRulesEntity) -> Future<void>` (repo: `RequestRulesRepository`).
  - `GetSettingsUseCase(repo).call() -> Future<SettingsEntity>`, `SaveSettingsUseCase(repo).call(SettingsEntity) -> Future<void>` (repo: `SettingsRepository`).
  - `RequestRulesLocalDataSourceImpl` with `getRules(String)`, `saveRules(RequestRulesModel)`, `deleteRules(String)` over `Hive.box<RequestRulesModel>(HiveBoxes.requestRules)`.
  - `SettingsLocalDataSourceImpl` with `getSettings()`, `saveSettings(SettingsModel)` over `Hive.box<SettingsModel>(HiveBoxes.settings)`; `getSettings` returns a default `SettingsModel()` when the key `'current'` is absent.
- Pattern to mirror: `test/features/history/data/datasources/history_local_data_source_test.dart` (in-memory Hive temp dir + adapter registration + `Hive.deleteFromDisk()` teardown).

- [ ] **Step 1: Write the use-case tests (both files)**

`test/features/chaining/domain/usecases/request_rules_usecases_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/repositories/request_rules_repository.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements RequestRulesRepository {}

class _FakeRules extends Fake implements RequestRulesEntity {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeRules()));

  late _MockRepo repo;
  setUp(() => repo = _MockRepo());

  test('GetRequestRulesUseCase delegates to repository.getRules', () async {
    final rules = _FakeRules();
    when(() => repo.getRules('cfg-1')).thenAnswer((_) async => rules);

    final result = await GetRequestRulesUseCase(repo).call('cfg-1');

    expect(result, same(rules));
    verify(() => repo.getRules('cfg-1')).called(1);
  });

  test('SaveRequestRulesUseCase delegates to repository.saveRules', () async {
    final rules = _FakeRules();
    when(() => repo.saveRules(any())).thenAnswer((_) async {});

    await SaveRequestRulesUseCase(repo).call(rules);

    verify(() => repo.saveRules(rules)).called(1);
  });
}
```

`test/features/settings/domain/usecases/settings_usecases_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/repositories/settings_repository.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements SettingsRepository {}

class _FakeSettings extends Fake implements SettingsEntity {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeSettings()));

  late _MockRepo repo;
  setUp(() => repo = _MockRepo());

  test('GetSettingsUseCase delegates to repository.getSettings', () async {
    final settings = _FakeSettings();
    when(() => repo.getSettings()).thenAnswer((_) async => settings);

    final result = await GetSettingsUseCase(repo).call();

    expect(result, same(settings));
    verify(() => repo.getSettings()).called(1);
  });

  test('SaveSettingsUseCase delegates to repository.saveSettings', () async {
    final settings = _FakeSettings();
    when(() => repo.saveSettings(any())).thenAnswer((_) async {});

    await SaveSettingsUseCase(repo).call(settings);

    verify(() => repo.saveSettings(settings)).called(1);
  });
}
```

- [ ] **Step 2: Write the settings data-source test**

`test/features/settings/data/datasources/settings_local_data_source_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/settings/data/datasources/settings_local_data_source.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late SettingsLocalDataSourceImpl ds;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_settings_ds_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SettingsModelAdapter());
    }
    await Hive.openBox<SettingsModel>(HiveBoxes.settings);
    ds = SettingsLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('getSettings returns a default SettingsModel when box is empty', () async {
    final s = await ds.getSettings();
    expect(s, isA<SettingsModel>());
  });

  test('saveSettings then getSettings round-trips the value', () async {
    final model = SettingsModel()..themeId = 'rpg';
    await ds.saveSettings(model);

    final loaded = await ds.getSettings();
    expect(loaded.themeId, 'rpg');
  });

  test('getSettings wraps a Hive failure in PersistenceException', () async {
    // Closing the box makes Hive.box(...) throw inside the try/catch.
    await Hive.box<SettingsModel>(HiveBoxes.settings).close();
    expect(ds.getSettings, throwsA(isA<PersistenceException>()));
  });
}
```

Note: if `SettingsModel` does not expose a mutable `themeId` field, set any other recognizable mutable `@HiveField` (read `lib/features/settings/data/models/settings_model.dart` first) and assert on it instead.

- [ ] **Step 3: Write the request-rules data-source test**

`test/features/chaining/data/datasources/request_rules_local_data_source_test.dart` — mirror the settings one, but:
- Register the adapters this box needs: `RequestRulesModelAdapter` (typeId 9) and its embedded `ExtractionRuleModelAdapter` (typeId 7) + `AssertionModelAdapter` (typeId 8). Read `lib/features/chaining/data/models/request_rules_model.dart` to confirm the exact adapter class names and the `RequestRulesModel` constructor (it is keyed by `configId`).
- Open `Hive.openBox<RequestRulesModel>(HiveBoxes.requestRules)`.
- Tests: (a) `getRules` returns `null` for an unknown id; (b) `saveRules` then `getRules` round-trips by `configId`; (c) `deleteRules` removes it (`getRules` → null after); (d) `getRules` after closing the box throws `PersistenceException`.

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/chaining/data/datasources/request_rules_local_data_source.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late RequestRulesLocalDataSourceImpl ds;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_rules_ds_test');
    Hive.init(tempDir.path);
    // Register typeIds 7, 8, 9 (confirm exact adapter names from the model file).
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(ExtractionRuleModelAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(AssertionModelAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(RequestRulesModelAdapter());
    }
    await Hive.openBox<RequestRulesModel>(HiveBoxes.requestRules);
    ds = RequestRulesLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // Build a minimal RequestRulesModel — adjust to the real constructor.
  RequestRulesModel makeRules(String configId) =>
      RequestRulesModel(configId: configId, assertions: const [], extractions: const []);

  test('getRules returns null for an unknown configId', () {
    expect(ds.getRules('missing'), isNull);
  });

  test('saveRules then getRules round-trips by configId', () async {
    await ds.saveRules(makeRules('cfg-1'));
    expect(ds.getRules('cfg-1')?.configId, 'cfg-1');
  });

  test('deleteRules removes the stored rules', () async {
    await ds.saveRules(makeRules('cfg-2'));
    await ds.deleteRules('cfg-2');
    expect(ds.getRules('cfg-2'), isNull);
  });

  test('getRules wraps a Hive failure in PersistenceException', () async {
    await Hive.box<RequestRulesModel>(HiveBoxes.requestRules).close();
    expect(() => ds.getRules('cfg-1'), throwsA(isA<PersistenceException>()));
  });
}
```

Adjust `makeRules` to the real `RequestRulesModel` constructor (the embedded model imports may live in `request_rules_model.dart`; the adapter class names for typeIds 7/8 may be exported from `extraction_rule_model.dart` / `assertion_model.dart` — import whatever files declare the `*Adapter` classes).

- [ ] **Step 4: Run the four new tests**

Run:
```bash
fvm flutter test \
  test/features/chaining/domain/usecases/request_rules_usecases_test.dart \
  test/features/settings/domain/usecases/settings_usecases_test.dart \
  test/features/settings/data/datasources/settings_local_data_source_test.dart \
  test/features/chaining/data/datasources/request_rules_local_data_source_test.dart
```
Expected: all pass. Fix constructor/adapter-name mismatches surfaced by the compiler.

- [ ] **Step 5: Static checks + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format test
git add test/features/chaining/domain/usecases test/features/settings/domain/usecases \
  test/features/settings/data/datasources test/features/chaining/data/datasources
git commit -m "test(logic): cover request-rules + settings use cases and local data sources"
```

---

## Task 3: Tier-2 batch A — tabs widgets

**Files (Create one test per widget, mirroring the cited exemplar):**
- `test/features/tabs/presentation/widgets/url_bar_test.dart` (source: `lib/features/tabs/presentation/widgets/url_bar.dart`, 260 lines)
- `test/features/tabs/presentation/widgets/code_export_dialog_test.dart` (source: `code_export_dialog.dart`, 54)
- `test/features/tabs/presentation/widgets/request_kind_method_selector_test.dart` (source: `request_kind_method_selector.dart`, 52)
- `test/features/tabs/presentation/widgets/url_overflow_menu_test.dart` (source: `url_overflow_menu.dart`, 44)
- `test/features/tabs/presentation/widgets/realtime_button_test.dart` (source: `realtime_button.dart`, 35)
- `test/features/tabs/presentation/widgets/response/response_history_timeline_test.dart` (source: `response/response_history_timeline.dart`, 79)
- `test/features/tabs/presentation/screens/request_view_test.dart` (source: `screens/request_view.dart`, 175)

**Interfaces:**
- Pattern to mirror: `test/features/tabs/presentation/widgets/auth_tab_view_test.dart` — `MockTabsRepository extends Mock implements TabsRepository`, `MockSendRequestUseCase`, `_FakeConfig`/`_FakePanel` fakes, a `_loadedBloc(...)` helper that stubs `getPanels()`/`getActivePanelId()` and pumps `LoadTabs`, and a `_pump(...)` that wraps the widget in `MaterialApp(theme: brutalistTheme(Brightness.light), home: Scaffold(body: BlocProvider.value(value: bloc, child: <Widget>)))`.
- `EnvironmentsBloc`/`SettingsBloc` are needed by `url_bar` (it resolves env vars for SEND) and `request_view`. Provide them via `MultiBlocProvider` with real blocs over mock repositories (mirror how `command_palette_test.dart` wires multiple blocs), or seed minimal states. Read each widget's `context.read<...>()` / `context.watch<...>()` calls first to know which providers it needs.

- [ ] **Step 1: Read each source widget**

For every file above, read the source to learn its constructor params, the bloc(s) it reads, the `ValueKey`s/labels it exposes (for finders), and its branches. List the branches each test must cover (e.g. `url_bar`: cURL-paste detection path vs normal URL edit; SEND dispatches `SendRequest` with resolved `envVars`; overflow menu opens; variable-highlight wiring updates on env change).

- [ ] **Step 2: Write the widget tests (one per file)**

Each test must, at minimum:
- Pump the widget with its required providers + a real theme.
- Assert it renders without throwing and without overflow (`expect(tester.takeException(), isNull)`).
- Drive at least one real interaction and assert the consequence:
  - `url_bar`: enter `curl https://x.com -H 'A: b'` → expect a single `UpdateTab` with parsed method/url/headers (spy the bloc via `blocTest` or assert resulting state); tap SEND → expect `SendRequest(tabId, envVars)` dispatched (assert `state.tabs[i].isSending` or use a `MockTabsRepository` whose `sendRequest` is verified).
  - `code_export_dialog`: pump with a tab config → expect one entry per `CodeGenTarget.values`; selecting a target renders generated code; edited URL is reflected (mirror `code_export_edits` integration intent at unit level).
  - `request_kind_method_selector`: switching method dispatches the method change; switching kind (HTTP/WS/SSE) updates state.
  - `url_overflow_menu`: opening shows the expected actions; tapping one invokes its callback / dispatches its event.
  - `realtime_button`: shows connect/disconnect per state; tap dispatches the realtime action (guard against the known stale-URL bug — assert it reads the current URL).
  - `response_history_timeline`: hidden under 2 entries; with ≥2 entries renders rows and tapping one dispatches `ViewResponseHistoryEntry(tabId, entryId)`.
  - `request_view`: renders split-pane; split ratio clamps within `[0.1, 0.9]`; beautify/save Actions reachable.

- [ ] **Step 3: Run the batch + static checks**

Run: `fvm flutter test test/features/tabs/presentation/widgets test/features/tabs/presentation/screens`
Then: `fvm flutter analyze && fvm dart run custom_lint && fvm dart format test`
Expected: all green, 0 issues.

- [ ] **Step 4: Commit**

```bash
git add test/features/tabs/presentation
git commit -m "test(tabs): widget coverage for url bar, request view, code export, selectors, realtime button, history timeline"
```

---

## Task 4: Tier-2 batch B — environments widgets

**Files:**
- `test/features/environments/presentation/widgets/environments_dialog_test.dart` (source `environments_dialog.dart`, 156)
- `test/features/environments/presentation/widgets/environment_selector_test.dart` (source `environment_selector.dart`, 89)
- `test/features/environments/presentation/widgets/environment_editor_test.dart` (source `environment_editor.dart`, 48)
- `test/features/environments/presentation/widgets/environment_list_tile_test.dart` (source `environment_list_tile.dart`, 42)

**Interfaces:**
- Pattern to mirror: `auth_tab_view_test.dart` (mocktail + real bloc) and any existing `test/features/environments/presentation/widgets/*_test.dart`. These widgets read `EnvironmentsBloc` and `SettingsBloc` (active env id lives on `SettingsEntity.activeEnvironmentId`).
- Key behaviors per CLAUDE.md §4.10: deleting the active environment dispatches `UpdateActiveEnvironmentId(null)` on `SettingsBloc` (coordinated at the widget layer in `EnvironmentsDialog._deleteEnvironment`); `AddEnvironment` carries a full `EnvironmentEntity`; secret keys toggle a lock + reveal.

- [ ] **Step 1: Read each source + existing env widget tests**

Confirm provider wiring and the exact events (`AddEnvironment`, `UpdateEnvironment`, `DeleteEnvironment`, `UpdateActiveEnvironmentId`).

- [ ] **Step 2: Write the tests**

Cover at least:
- `environments_dialog`: list renders environments; ADD opens the name prompt and dispatches `AddEnvironment` with an entity; deleting the **active** env confirms via `ConfirmDialog` then dispatches `UpdateActiveEnvironmentId(null)`; deleting a non-active env does not touch active id.
- `environment_selector`: lists envs + the synthetic "No Environment"; the active row is marked; selecting a row dispatches `UpdateActiveEnvironmentId(id)`.
- `environment_editor`: editing a variable round-trips through `KeyValueListEditor`; marking a key secret adds it to `secretKeys` and obscures the value; renaming/removing a key prunes stale secret flags.
- `environment_list_tile`: renders name; tap/edit/delete affordances invoke their callbacks.
- Always assert `tester.takeException()` is null (no overflow) at each breakpoint pumped.

- [ ] **Step 3: Run + static checks**

Run: `fvm flutter test test/features/environments/presentation/widgets`
Then: `fvm flutter analyze && fvm dart run custom_lint && fvm dart format test`

- [ ] **Step 4: Commit**

```bash
git add test/features/environments/presentation/widgets
git commit -m "test(environments): widget coverage for dialog, selector, editor, list tile"
```

---

## Task 5: Tier-2 batch C — collections + home widgets

**Files:**
- `test/features/collections/presentation/widgets/node_action_sheet_test.dart` (source `node_action_sheet.dart`, 182)
- `test/features/collections/presentation/widgets/workspace_sync_listener_test.dart` (source `workspace_sync_listener.dart`, 10)
- `test/features/history/presentation/widgets/history_list_test.dart` (source `history_list.dart`, 96)
- `test/features/home/presentation/widgets/side_menu_test.dart` (source `side_menu.dart`, 54)
- `test/features/home/presentation/widgets/empty_tabs_placeholder_test.dart` (source `empty_tabs_placeholder.dart`, 25)
- `test/features/home/presentation/widgets/add_tab_button_test.dart` (source `add_tab_button.dart`, 17)

**Interfaces:**
- Pattern to mirror: existing `test/features/collections/presentation/widgets/collections_list_test.dart` and `test/features/home/presentation/widgets/tab_chip_test.dart`.
- `node_action_sheet` is the phone action sheet: it exposes entries (open, rename, new folder, edit description, duplicate, delete, save-as-example, etc.) each wired to a `CollectionsBloc` event or callback. `history_list` reads `HistoryBloc`; tapping an entry opens it as a tab (`AddTab`), search filters, empty shows a placeholder.

- [ ] **Step 1: Read each source + the two exemplar tests**

- [ ] **Step 2: Write the tests**

Cover at least:
- `node_action_sheet`: each visible action invokes the right callback / dispatches the right event (`RenameNode`, `UpdateNodeDescription`, `DeleteNode` behind a `ConfirmDialog`, duplicate, save-as-example enabled only when appropriate). Assert no overflow.
- `workspace_sync_listener`: it's a `BlocListener` coordinator — pump it under a `CollectionsBloc` and assert it forwards to `WorkspaceSyncService` (mock it via `RepositoryProvider`) on the relevant state change, and is a no-op otherwise.
- `history_list`: renders entries newest-first; tap → `AddTab`; search filters; empty → placeholder text.
- `side_menu`: renders the branded nav; selecting a section invokes the callback.
- `empty_tabs_placeholder`: renders the "NO OPEN TABS" copy (read the exact label from `AppCopy` / the widget).
- `add_tab_button`: tap dispatches `AddTab`.

- [ ] **Step 3: Run + static checks**

Run: `fvm flutter test test/features/collections/presentation/widgets test/features/history/presentation/widgets test/features/home/presentation/widgets`
Then: `fvm flutter analyze && fvm dart run custom_lint && fvm dart format test`

- [ ] **Step 4: Commit**

```bash
git add test/features/collections/presentation/widgets test/features/history/presentation/widgets test/features/home/presentation/widgets
git commit -m "test(collections,history,home): widget coverage for node action sheet, history list, side menu, placeholders"
```

---

## Task 6: Tier-2 batch D — core UI atoms

**Files:**
- `test/core/ui/widgets/splitter_test.dart` (source `lib/core/ui/widgets/splitter.dart`, 26)
- `test/core/ui/widgets/hover_highlight_test.dart` (source `lib/core/ui/widgets/hover_highlight.dart`, 11)

**Interfaces:**
- Pattern to mirror: `test/core/ui/widgets/branded_tab_bar_test.dart` and `test/core/ui/widgets/confirm_dialog_test.dart` (pure widget pumps, no bloc).

- [ ] **Step 1: Read both sources**

Learn `Splitter`'s callbacks (`onChanged`/`onEnd` drag deltas, axis, child slots) and `HoverHighlight`'s hover-state rendering.

- [ ] **Step 2: Write the tests**

- `splitter`: pump with two children + an `onChanged`/`onEnd` spy; simulate a drag gesture (`tester.drag` / `TestPointer`) over the handle and assert the callback fires with a delta; assert it lays out both children without overflow in horizontal + vertical configs.
- `hover_highlight`: pump; drive a `TestPointer` hover (or `tester.startGesture` mouse-kind) over it and assert the highlighted decoration appears, then clears on exit.

- [ ] **Step 3: Run + static checks + commit**

```bash
fvm flutter test test/core/ui/widgets/splitter_test.dart test/core/ui/widgets/hover_highlight_test.dart
fvm flutter analyze && fvm dart run custom_lint && fvm dart format test
git add test/core/ui/widgets/splitter_test.dart test/core/ui/widgets/hover_highlight_test.dart
git commit -m "test(ui): cover Splitter drag + HoverHighlight hover states"
```

---

## Task 7: Tier-3 — main_screen shortcut Actions + theme decorations + branch gaps

**Files:**
- Modify/extend: `test/main_shortcuts_test.dart`
- Create: `test/features/home/presentation/screens/main_screen_actions_test.dart` (if the shortcut Actions are easier to exercise via a pumped `MainScreen` than via the shortcut map)
- Create: `test/core/theme/themes/editorial/editorial_decorations_test.dart` (source `editorial_decorations.dart`, 49)
- Create: `test/core/theme/themes/classic/classic_press_test.dart` (source `classic_press.dart`, 19)

**Interfaces:**
- `appShortcuts` in `main.dart` is `@visibleForTesting` (a computed activator→intent map). Pattern to mirror: existing `test/main_shortcuts_test.dart`.
- The shortcut `Action`s (`CloseTabIntent`, `SendRequestIntent`, `NextTabIntent`/`PrevTabIntent`/`JumpToTabIntent`, panel intents, `FocusUrlIntent`, `CommandPaletteIntent`, `SwitchEnvironmentIntent`) live on `MainScreen`. Decoration tests mirror `test/core/theme/app_decoration_test.dart` (build the decoration via a pumped `Builder` with the theme attached and assert it returns a `BoxDecoration`/painter without throwing, in light + dark + `reduceEffects`).

- [ ] **Step 1: Read `main.dart` shortcut wiring + the existing shortcuts test + the two decoration sources**

- [ ] **Step 2: Extend shortcut coverage**

In `test/main_shortcuts_test.dart`, assert the computed `appShortcuts` map contains the digit→`JumpToTabIntent(1..9)` bindings (the generated loop), the panel intents, and the new dialog-opener intents — i.e. every binding documented in CLAUDE.md §6 maps to the right intent type. If the `Action` callbacks themselves are uncovered, pump `MainScreen` with mock blocs and invoke an `Intent` via `Actions.invoke(context, intent)` (or `tester.sendKeyEvent` for the activator) and assert the bloc event fired.

- [ ] **Step 3: Cover the two theme decoration files**

For `editorial_decorations` + `classic_press`: pump a `Builder` under `MaterialApp(theme: <thatTheme>(brightness))`, read the decoration/press wrapper via `context.appDecoration` (or call the file's exported builders directly), and assert it produces a non-null result in light, dark, and `reduceEffects: true` without throwing. Drive the press/tap animation if one exists (`wrapInteractive`) and pump to settle.

- [ ] **Step 4: Run + static checks + commit**

```bash
fvm flutter test test/main_shortcuts_test.dart test/features/home/presentation/screens test/core/theme/themes/editorial test/core/theme/themes/classic
fvm flutter analyze && fvm dart run custom_lint && fvm dart format test
git add test/main_shortcuts_test.dart test/features/home/presentation/screens test/core/theme/themes/editorial/editorial_decorations_test.dart test/core/theme/themes/classic/classic_press_test.dart
git commit -m "test(core): cover main-screen shortcut actions + editorial/classic theme decorations"
```

- [ ] **Step 5: Re-run coverage and record the new number**

Run: `bash tool/coverage.sh`
Expected: overall is meaningfully up from 76% (target ~90%). If any Tier-1/Tier-2 file is still near 0%, open `coverage/html/index.html`, find the uncovered lines, and add the missing case before moving on.

---

## Task 8: Integration suite — run the full macOS aggregator and triage (MAIN SESSION)

> This and Tasks 9–10 run in the **main session**, not a subagent — the macOS app run is serial and GUI-driven.

**Files:** none yet (capture-only).

- [ ] **Step 1: Run the whole suite once (one build)**

Run: `bash integration_test/run_macos.sh 2>&1 | tee /tmp/e2e_baseline.log`
This builds + launches the macOS app once and runs all 38 flows sequentially.

- [ ] **Step 2: Capture every failure**

From `/tmp/e2e_baseline.log`, list each failing case with its error. Group by likely cause:
- **Render overflow / `RenderFlex overflowed`** under in-flight frames, content transitions, or ambient backgrounds (the recent theme/motion work — the prime suspects).
- **Finder not found / timeout** (a label/key/structure moved).
- **Real behavioral regression** (assertion on wrong value).

- [ ] **Step 3: Write the triage list into the plan's scratch section**

Append a `## Triage (filled at run time)` section to this plan listing each failure → hypothesis → fix location (lib vs flow). No code yet.

---

## Task 9: Integration suite — fix every failure (MAIN SESSION)

**Files:** per failure — either `lib/...` (real regression) or `integration_test/flows/*.dart` / `integration_test/support/*.dart` (finder drift).

- [ ] **Step 1: For each triaged failure, reproduce in isolation**

Run the single flow: `bash integration_test/run_macos.sh <flow_name>` (e.g. `theme_stress`). Optionally `E2E_SLOW_MS=600 bash integration_test/run_macos.sh <flow>` to watch it.

- [ ] **Step 2: Fix per classification (use systematic-debugging)**

- **Real lib regression:** write/confirm a *unit or widget* test that fails for the same reason first (TDD), then fix in `lib/`. Overflow fixes follow the existing under-theme overflow-guard pattern (see `*_components_test.dart` and the in-flight overflow guards from commit e946b15). Re-run the failing flow to confirm green.
- **Finder drift:** update the flow or `support/actions.dart` to the new label/key. Never relax an assertion to hide a real defect — if the value genuinely changed for a good reason, assert the new correct value; if it changed wrongly, that's a lib regression.

- [ ] **Step 3: Re-run the whole suite to confirm no regressions introduced**

Run: `bash integration_test/run_macos.sh 2>&1 | tee /tmp/e2e_after_fixes.log`
Expected: all previously-failing cases pass; nothing new broke.

- [ ] **Step 4: Commit (one commit per coherent fix)**

```bash
git add <files>
git commit -m "fix(<area>): <what> (integration suite green)"
# or: test(e2e): repair <flow> finder after <ui change>
```

---

## Task 10: Integration suite — add new flows for untested UI (MAIN SESSION)

**Files:**
- Create: `integration_test/flows/theme_motion_send_test.dart`
- Modify: `integration_test/all_flows_test.dart` (import + call its `main()`)
- Modify: `integration_test/BACKLOG.md` (move the now-covered items into "Covered")

**Interfaces:**
- Pattern to mirror: `integration_test/flows/theme_stress_test.dart` (iterate themes via the settings UI) + `request_send_test.dart` (send against the mock server) + `support/app_harness.dart` / `support/actions.dart` (the launch + scripted-action helpers).

- [ ] **Step 1: Read `theme_stress_test.dart`, `request_send_test.dart`, and `support/*.dart`**

Learn the theme-switch action, the mock-server send path, and the action helpers.

- [ ] **Step 2: Write `theme_motion_send_test.dart`**

For each loud theme (`brutalist`, `rpg`, `glass`, `auris`, `dracula`):
- Switch to the theme via Settings → APPEARANCE.
- Send a request against the mock server.
- While in-flight and after the response, assert `tester.takeException()` is null (no overflow from the in-flight frame / content-swap transition / send-affordance) and the response renders (status badge / body present).

Add one `reduceEffects` case: enable reduce-effects (the global visual-effects toggle) on a loud theme, send, and assert the same — static degradation, no crash, response renders.

- [ ] **Step 3: Wire it into the aggregator**

In `integration_test/all_flows_test.dart`, add `import 'flows/theme_motion_send_test.dart' as theme_motion_send;` and call `theme_motion_send.main();` in the "Feature flows" block (near `theme_stress.main();`).

- [ ] **Step 4: Run the new flow alone, then the whole suite**

Run: `bash integration_test/run_macos.sh theme_motion_send`
Then: `bash integration_test/run_macos.sh` (full suite, confirm still green).

- [ ] **Step 5: Update the BACKLOG + commit**

Move the now-automated motion items into the "Covered (deep)" section of `integration_test/BACKLOG.md`.

```bash
git add integration_test/flows/theme_motion_send_test.dart integration_test/all_flows_test.dart integration_test/BACKLOG.md
git commit -m "test(e2e): loud-theme motion-during-send + reduce-effects flows"
```

---

## Task 11: Final verification, coverage report, docs sync

**Files:** possibly `CLAUDE.md` / wiki if any user-facing behavior changed during fixes.

- [ ] **Step 1: Full static stack + unit tests**

Run, and confirm 0 issues / 100% green:
```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools
fvm flutter test
```

- [ ] **Step 2: Regenerate the coverage report and capture the final number**

Run: `bash tool/coverage.sh`
Record the final overall % (target ~90%) and confirm no targeted file is still ~0%.

- [ ] **Step 3: Full macOS integration suite green**

Run: `bash integration_test/run_macos.sh 2>&1 | tee /tmp/e2e_final.log` → all flows pass.

- [ ] **Step 4: Sync docs if behavior changed**

If any Task-9 fix changed a user-facing label/behavior, update the GitHub wiki per the CLAUDE.md §7 "Keep the wiki in sync" mandate. Pure test additions + the coverage script need no wiki edit (CLAUDE.md §5 already covers the script).

- [ ] **Step 5: Final summary**

Report: baseline vs final coverage %, count of new unit/widget tests, integration failures found + how each was fixed (lib vs finder), and new integration flows added.

---

## Self-Review (completed by plan author)

- **Spec coverage:** Part A → Task 1. Part B Tier-1 → Task 2; Tier-2 → Tasks 3–6; Tier-3 → Task 7. Part C run/fix/extend → Tasks 8/9/10. Success criteria (static stack + coverage report + integration green + docs) → Task 11. All spec sections map to a task.
- **Out-of-scope items** (native file dialogs, mTLS/proxy, re_editor internals) are intentionally absent — correct per spec.
- **Type consistency:** use-case/data-source signatures in Task 2 match the read sources; event names (`SendRequest`, `UpdateTab`, `AddEnvironment`, `UpdateActiveEnvironmentId`, `AddTab`, `ViewResponseHistoryEntry`, `LoadTabs`) match CLAUDE.md. Widget tasks instruct reading source before asserting exact constructor params (since those weren't all read at plan time) — this is deliberate for a coverage back-fill, not a placeholder.
- **Known gotcha documented:** lcov 2.x strictness (Task 1 Step 4).
```
