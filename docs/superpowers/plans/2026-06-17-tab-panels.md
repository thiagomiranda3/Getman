# Tab Panels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add virtual-desktop-style **panels** that group request tabs; the user can add/rename/reorder/remove panels and shift tabs between them, with only the active panel's tabs shown, and full state (dirty tabs included) restored on restart.

**Architecture:** Approach A — a panel-aware `TabsBloc`. `PanelEntity` (id, name, ordered tabs, remembered active tab) becomes the unit the bloc manages. `TabsState` keeps `tabs`/`activeIndex` as the *active panel's* view (recomputed and stored on every emit via a `_derive` helper) so every existing tab widget is untouched. The tab Hive model (typeId 2) is unchanged; a new `PanelModel` (typeId 12) stores only panel structure (ids), with tab entities staying in the existing `tabs` box.

**Tech Stack:** Flutter (`fvm flutter`), `flutter_bloc`, `hive_ce` + `hive_ce_generator`, `get_it`, `equatable`, `uuid`, `two_dimensional_scrollables`, patrol_finders (E2E).

## Global Constraints

- Always invoke Flutter as `fvm flutter ...` (never plain `flutter`); Dart tools as `fvm dart run ...`.
- Done-bar (all must be clean before "done"): `fvm flutter analyze` (very_good_analysis), `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test tools tools/getman_lints integration_test`, `fvm flutter test`. These are independent passes.
- After any `@HiveType`/`@HiveField` change: `dart run build_runner build --delete-conflicting-outputs`.
- **Never renumber an existing typeId.** New model uses **typeId 12** (next free becomes 13).
- Imports are `package:getman/...` everywhere (no relative imports; `directives_ordering` enforced).
- BLoCs log via `dart:developer`'s `log(msg, name: 'TabsBloc')` — never `debugPrint`/`print`.
- No hardcoded sizes/colors/weights/radii/paddings in widgets — read `context.appLayout`/`appPalette`/`appShape`/`appTypography`/`appDecoration`; layout branches use `ResponsiveBuildContext` getters. No `Colors.black/white/red` outside `lib/core/theme/`.
- Never `sl<T>()`/`GetIt` from a widget (custom_lint `avoid_get_it_in_widgets`).
- Identity-addressed events carry `tabId`/`panelId`, never index (except `SetActiveIndex`/`ReorderTabs`/`ReorderPanels` where position *is* the operation).
- Commit after every task. Spec: `docs/superpowers/specs/2026-06-17-tab-panels-design.md`.

---

## File Structure

**Create:**
- `lib/features/tabs/domain/entities/panel_entity.dart` — `PanelEntity` + `PanelListLookup` extension.
- `lib/features/tabs/data/models/panel_model.dart` (+ generated `panel_model.g.dart`) — `PanelModel` typeId 12.
- `lib/features/tabs/presentation/widgets/panel_selector.dart` — the dropdown selector + overlay menu (desktop/tablet/phone).
- `lib/features/tabs/presentation/widgets/panel_close_coordinator.dart` — `closePanelWithSavePrompt(context, panelId)` widget-layer orchestration.
- `test/features/tabs/domain/entities/panel_entity_test.dart`
- `test/features/tabs/data/models/panel_model_test.dart`
- `test/features/tabs/data/datasources/tabs_local_data_source_panels_test.dart`
- `test/features/tabs/data/repositories/tabs_repository_panels_test.dart`
- `test/features/tabs/presentation/bloc/tabs_bloc_panels_test.dart`
- `test/features/tabs/presentation/widgets/panel_selector_test.dart`
- `test/features/tabs/presentation/widgets/panel_close_coordinator_test.dart`
- `integration_test/panels_test.dart` (+ helpers as needed)

**Modify:**
- `lib/features/tabs/presentation/bloc/tabs_state.dart` — add `panels` + `activePanelId`.
- `lib/features/tabs/presentation/bloc/tabs_event.dart` — add 7 panel events.
- `lib/features/tabs/presentation/bloc/tabs_bloc.dart` — panel-aware refactor + new handlers.
- `lib/features/tabs/domain/repositories/tabs_repository.dart` — add panel methods.
- `lib/features/tabs/data/repositories/tabs_repository_impl.dart` — implement them.
- `lib/features/tabs/data/datasources/tabs_local_data_source.dart` — panels box + meta.
- `lib/core/storage/hive_boxes.dart` — add `panels` constant.
- `lib/core/di/injection_container.dart` — register `PanelModelAdapter`, open `panels` box.
- `lib/core/navigation/intents.dart` — add 4 panel intents.
- `lib/main.dart` — add panel shortcuts.
- `lib/features/home/presentation/screens/main_screen.dart` — place `PanelSelector`, add panel actions, wire close coordinator.
- `lib/features/home/presentation/widgets/tab_widget.dart` — `MOVE TO PANEL ▸` submenu + drag wrapper.
- `lib/features/tabs/presentation/widgets/tab_switcher_sheet.dart` + `lib/features/home/presentation/widgets/tab_chip.dart` — compactPhone panel UI.
- `CLAUDE.md` — typeId table row 12, §4.2 note.
- (separate `Getman.wiki.git`) Panels page + `_Sidebar.md`.
- existing `test/features/tabs/presentation/bloc/tabs_bloc_test.dart` — adapt to panel-aware state (Task 4).

---

## Phase 1 — Domain & Data Foundation

### Task 1: `PanelEntity` domain entity

**Files:**
- Create: `lib/features/tabs/domain/entities/panel_entity.dart`
- Test: `test/features/tabs/domain/entities/panel_entity_test.dart`

**Interfaces:**
- Produces: `PanelEntity({required String id, required String name, required List<HttpRequestTabEntity> tabs, required String activeTabId})`, `copyWith({String? id, String? name, List<HttpRequestTabEntity>? tabs, String? activeTabId})`, and `extension PanelListLookup on Iterable<PanelEntity> { PanelEntity? byId(String id); }`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:flutter_test/flutter_test.dart';

HttpRequestTabEntity _tab(String id) =>
    HttpRequestTabEntity(tabId: id, config: HttpRequestConfigEntity(id: id));

void main() {
  group('PanelEntity', () {
    test('equality is value-based over all fields', () {
      final a = PanelEntity(id: 'p1', name: 'Panel 1', tabs: [_tab('t1')], activeTabId: 't1');
      final b = PanelEntity(id: 'p1', name: 'Panel 1', tabs: [_tab('t1')], activeTabId: 't1');
      expect(a, equals(b));
    });

    test('copyWith replaces only provided fields', () {
      final p = PanelEntity(id: 'p1', name: 'Panel 1', tabs: [_tab('t1')], activeTabId: 't1');
      final renamed = p.copyWith(name: 'Work');
      expect(renamed.name, 'Work');
      expect(renamed.id, 'p1');
      expect(renamed.tabs, p.tabs);
      expect(renamed.activeTabId, 't1');
    });

    test('PanelListLookup.byId finds the panel or null', () {
      final list = [
        PanelEntity(id: 'p1', name: 'A', tabs: [_tab('t1')], activeTabId: 't1'),
        PanelEntity(id: 'p2', name: 'B', tabs: [_tab('t2')], activeTabId: 't2'),
      ];
      expect(list.byId('p2')!.name, 'B');
      expect(list.byId('nope'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `fvm flutter test test/features/tabs/domain/entities/panel_entity_test.dart`
Expected: FAIL — `panel_entity.dart` doesn't exist / `PanelEntity` undefined.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

extension PanelListLookup on Iterable<PanelEntity> {
  /// Shorthand for `firstWhereOrNull((p) => p.id == id)`.
  PanelEntity? byId(String id) => firstWhereOrNull((p) => p.id == id);
}

/// A virtual-desktop workspace grouping request tabs. Only the active panel's
/// tabs are shown in the tab strip. Invariant (enforced in TabsBloc): [tabs]
/// is never empty and [activeTabId] always names a tab in [tabs].
class PanelEntity extends Equatable {
  const PanelEntity({
    required this.id,
    required this.name,
    required this.tabs,
    required this.activeTabId,
  });

  final String id;
  final String name;
  final List<HttpRequestTabEntity> tabs;
  final String activeTabId;

  PanelEntity copyWith({
    String? id,
    String? name,
    List<HttpRequestTabEntity>? tabs,
    String? activeTabId,
  }) {
    return PanelEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }

  @override
  List<Object?> get props => [id, name, tabs, activeTabId];
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `fvm flutter test test/features/tabs/domain/entities/panel_entity_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/tabs/domain/entities/panel_entity.dart test/features/tabs/domain/entities/panel_entity_test.dart
git commit -m "feat(panels): PanelEntity domain entity + lookup

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `PanelModel` Hive model (typeId 12) + DI registration

**Files:**
- Create: `lib/features/tabs/data/models/panel_model.dart`
- Modify: `lib/core/storage/hive_boxes.dart`, `lib/core/di/injection_container.dart`
- Test: `test/features/tabs/data/models/panel_model_test.dart`

**Interfaces:**
- Consumes: `PanelEntity` (Task 1), `HttpRequestTabEntity`.
- Produces: `PanelModel` with `@HiveField(0) id`, `(1) name`, `(2) List<String> orderedTabIds`, `(3) activeTabId`; `PanelModel.fromEntity(PanelEntity)`; `PanelEntity toEntity(Map<String, HttpRequestTabEntity> tabsById)` (builds tabs from `orderedTabIds`, skipping ids absent from the map). `HiveBoxes.panels == 'panels'`.

- [ ] **Step 1: Add the box-name constant** in `lib/core/storage/hive_boxes.dart` after `tabsMeta`:

```dart
  /// Panel structure (typeId 12). Tab entities stay in [tabs]; this box stores
  /// only `{id, name, orderedTabIds, activeTabId}`. Order + active panel live
  /// in [tabsMeta] under `panelOrder` / `activePanelId`.
  static const String panels = 'panels';
```

- [ ] **Step 2: Write the failing test**

```dart
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/tabs/data/models/panel_model.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:flutter_test/flutter_test.dart';

HttpRequestTabEntity _tab(String id) =>
    HttpRequestTabEntity(tabId: id, config: HttpRequestConfigEntity(id: id));

void main() {
  test('fromEntity stores only ids; toEntity rebuilds tabs in order', () {
    final entity = PanelEntity(
      id: 'p1', name: 'Work',
      tabs: [_tab('t1'), _tab('t2')], activeTabId: 't2',
    );
    final model = PanelModel.fromEntity(entity);
    expect(model.orderedTabIds, ['t1', 't2']);
    expect(model.activeTabId, 't2');

    final back = model.toEntity({'t1': _tab('t1'), 't2': _tab('t2')});
    expect(back.tabs.map((t) => t.tabId), ['t1', 't2']);
    expect(back.name, 'Work');
    expect(back.activeTabId, 't2');
  });

  test('toEntity skips ids missing from the map', () {
    final model = PanelModel(
      id: 'p1', name: 'A', orderedTabIds: ['t1', 'gone', 't2'], activeTabId: 't1',
    );
    final back = model.toEntity({'t1': _tab('t1'), 't2': _tab('t2')});
    expect(back.tabs.map((t) => t.tabId), ['t1', 't2']);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `fvm flutter test test/features/tabs/data/models/panel_model_test.dart`
Expected: FAIL — `panel_model.dart` missing.

- [ ] **Step 4: Write the model**

```dart
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

part 'panel_model.g.dart';

@HiveType(typeId: 12)
class PanelModel extends HiveObject {
  PanelModel({
    required this.name,
    required this.orderedTabIds,
    required this.activeTabId,
    String? id,
  }) : id = id ?? const Uuid().v4();

  factory PanelModel.fromEntity(PanelEntity entity) => PanelModel(
        id: entity.id,
        name: entity.name,
        orderedTabIds: entity.tabs.map((t) => t.tabId).toList(),
        activeTabId: entity.activeTabId,
      );

  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<String> orderedTabIds;

  @HiveField(3)
  String activeTabId;

  /// Rebuilds the entity by mapping [orderedTabIds] through [tabsById]. Ids with
  /// no live tab are skipped (the bloc auto-seeds a blank if this empties a
  /// panel — see TabsBloc invariant 2).
  PanelEntity toEntity(Map<String, HttpRequestTabEntity> tabsById) {
    final tabs = <HttpRequestTabEntity>[];
    for (final id in orderedTabIds) {
      final tab = tabsById[id];
      if (tab != null) tabs.add(tab);
    }
    return PanelEntity(
      id: id,
      name: name,
      tabs: tabs,
      activeTabId: activeTabId,
    );
  }
}
```

- [ ] **Step 5: Generate the adapter**

Run: `fvm dart run build_runner build --delete-conflicting-outputs`
Expected: creates `lib/features/tabs/data/models/panel_model.g.dart` with `PanelModelAdapter` (typeId 12). Confirm no "duplicate typeId" error.

- [ ] **Step 6: Register adapter + open box** in `lib/core/di/injection_container.dart`. Add to the adapter cascade (after `StoredResponseModelAdapter()` or anywhere in the chain):

```dart
      ..registerAdapter(PanelModelAdapter())
```

Add to the `Future.wait` box-opening list:

```dart
    Hive.openBox<PanelModel>(HiveBoxes.panels),
```

Add the import: `import 'package:getman/features/tabs/data/models/panel_model.dart';` (respect `directives_ordering`).

- [ ] **Step 7: Run tests + analyze**

Run: `fvm flutter test test/features/tabs/data/models/panel_model_test.dart && fvm flutter analyze`
Expected: PASS (2 tests); analyze "No issues found!".

- [ ] **Step 8: Commit**

```bash
git add lib/features/tabs/data/models/panel_model.dart lib/features/tabs/data/models/panel_model.g.dart lib/core/storage/hive_boxes.dart lib/core/di/injection_container.dart test/features/tabs/data/models/panel_model_test.dart
git commit -m "feat(panels): PanelModel typeId 12 + DI registration

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Repository + data source panel methods

**Files:**
- Modify: `lib/features/tabs/domain/repositories/tabs_repository.dart`, `lib/features/tabs/data/repositories/tabs_repository_impl.dart`, `lib/features/tabs/data/datasources/tabs_local_data_source.dart`
- Test: `test/features/tabs/data/datasources/tabs_local_data_source_panels_test.dart`, `test/features/tabs/data/repositories/tabs_repository_panels_test.dart`

**Interfaces:**
- Produces (on `TabsRepository`): `Future<List<PanelEntity>> getPanels()`, `Future<String?> getActivePanelId()`, `Future<void> putPanel(PanelEntity panel)`, `Future<void> deletePanels(List<String> panelIds)`, `Future<void> savePanelMeta(List<String> panelOrder, String activePanelId)`.
- Produces (on `TabsLocalDataSource`): `Future<List<PanelModel>> getPanels()` (ordered by `panelOrder` meta), `Future<String?> getActivePanelId()`, `Future<void> putPanel(PanelModel panel)`, `Future<void> deletePanels(Iterable<String> panelIds)`, `Future<void> savePanelMeta(List<String> panelOrder, String activePanelId)`; constants `panelOrderKey = 'panelOrder'`, `activePanelKey = 'activePanelId'`.
- `getPanels()` on the **repository** assembles full `PanelEntity`s from tab models + panel models, and performs the legacy-upgrade migration (panels box empty + tabs present → one `'Panel 1'`).

- [ ] **Step 1: Write the failing data-source test**

```dart
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/models/panel_model.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// NOTE: follow the existing tabs_local_data_source_test.dart setup for Hive temp-dir init.

void main() {
  late TabsLocalDataSourceImpl ds;
  setUp(() async {
    // Mirror the Hive init from the existing tabs data-source test (temp dir).
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(PanelModelAdapter());
    await Hive.openBox<PanelModel>(HiveBoxes.panels);
    await Hive.openBox(HiveBoxes.tabsMeta);
    ds = TabsLocalDataSourceImpl();
  });
  tearDown(() async => Hive.deleteFromDisk());

  test('putPanel + getPanels returns panels ordered by panelOrder meta', () async {
    await ds.putPanel(PanelModel(id: 'p2', name: 'B', orderedTabIds: ['t2'], activeTabId: 't2'));
    await ds.putPanel(PanelModel(id: 'p1', name: 'A', orderedTabIds: ['t1'], activeTabId: 't1'));
    await ds.savePanelMeta(['p1', 'p2'], 'p1');

    final panels = await ds.getPanels();
    expect(panels.map((p) => p.id), ['p1', 'p2']);
    expect(await ds.getActivePanelId(), 'p1');
  });

  test('deletePanels removes panel models', () async {
    await ds.putPanel(PanelModel(id: 'p1', name: 'A', orderedTabIds: ['t1'], activeTabId: 't1'));
    await ds.deletePanels(['p1']);
    expect(await ds.getPanels(), isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `fvm flutter test test/features/tabs/data/datasources/tabs_local_data_source_panels_test.dart`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Implement data-source methods.** Add to the abstract `TabsLocalDataSource`:

```dart
  Future<List<PanelModel>> getPanels();
  Future<String?> getActivePanelId();
  Future<void> putPanel(PanelModel panel);
  Future<void> deletePanels(Iterable<String> panelIds);
  Future<void> savePanelMeta(List<String> panelOrder, String activePanelId);
```

Add to `TabsLocalDataSourceImpl` (alongside `orderKey`):

```dart
  static const String panelOrderKey = 'panelOrder';
  static const String activePanelKey = 'activePanelId';

  Box<PanelModel> _panelsBox() => Hive.box<PanelModel>(HiveBoxes.panels);

  @override
  Future<List<PanelModel>> getPanels() async {
    try {
      final box = _panelsBox();
      final stored = _metaBox().get(panelOrderKey);
      final order = stored is List ? stored.cast<String>() : const <String>[];
      final byId = {for (final p in box.values) p.id: p};
      final result = <PanelModel>[];
      for (final id in order) {
        final p = byId.remove(id);
        if (p != null) result.add(p);
      }
      result.addAll(byId.values);
      return result;
    } catch (e) {
      throw PersistenceException('Failed to read panels', cause: e);
    }
  }

  @override
  Future<String?> getActivePanelId() async {
    final v = _metaBox().get(activePanelKey);
    return v is String ? v : null;
  }

  @override
  Future<void> putPanel(PanelModel panel) async {
    try {
      await _panelsBox().put(panel.id, panel);
    } catch (e) {
      throw PersistenceException('Failed to save panel', cause: e);
    }
  }

  @override
  Future<void> deletePanels(Iterable<String> panelIds) async {
    try {
      await _panelsBox().deleteAll(panelIds);
    } catch (e) {
      throw PersistenceException('Failed to delete panels', cause: e);
    }
  }

  @override
  Future<void> savePanelMeta(List<String> panelOrder, String activePanelId) async {
    try {
      await _metaBox().put(panelOrderKey, panelOrder);
      await _metaBox().put(activePanelKey, activePanelId);
    } catch (e) {
      throw PersistenceException('Failed to save panel meta', cause: e);
    }
  }
```

- [ ] **Step 4: Run the data-source test to verify it passes**

Run: `fvm flutter test test/features/tabs/data/datasources/tabs_local_data_source_panels_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Write the failing repository test** (`tabs_repository_panels_test.dart`) using mock data source (mirror the mocking style of the existing `tabs_repository_impl` test — `mocktail`):

```dart
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/tabs/data/models/panel_model.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/repositories/tabs_repository_impl.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDs extends Mock implements TabsLocalDataSource {}
class _MockNet extends Mock implements NetworkService {}

void main() {
  late _MockDs ds;
  late TabsRepositoryImpl repo;
  setUp(() {
    ds = _MockDs();
    repo = TabsRepositoryImpl(localDataSource: ds, networkService: _MockNet());
  });

  test('getPanels migrates existing tabs into one "Panel 1" when panels box empty', () async {
    when(() => ds.getTabs()).thenAnswer((_) async => [
          HttpRequestTabModel(config: HttpRequestConfig.fromEntity(HttpRequestConfigEntity(id: 't1')), tabId: 't1'),
          HttpRequestTabModel(config: HttpRequestConfig.fromEntity(HttpRequestConfigEntity(id: 't2')), tabId: 't2'),
        ]);
    when(() => ds.getPanels()).thenAnswer((_) async => <PanelModel>[]);

    final panels = await repo.getPanels();
    expect(panels.length, 1);
    expect(panels.single.name, 'Panel 1');
    expect(panels.single.tabs.map((t) => t.tabId), ['t1', 't2']);
    expect(panels.single.activeTabId, 't1');
  });

  test('getPanels returns empty when nothing persisted (true first run)', () async {
    when(() => ds.getTabs()).thenAnswer((_) async => []);
    when(() => ds.getPanels()).thenAnswer((_) async => []);
    expect(await repo.getPanels(), isEmpty);
  });

  test('getPanels reconstructs persisted panels from tab models', () async {
    when(() => ds.getTabs()).thenAnswer((_) async => [
          HttpRequestTabModel(config: HttpRequestConfig.fromEntity(HttpRequestConfigEntity(id: 't1')), tabId: 't1'),
        ]);
    when(() => ds.getPanels()).thenAnswer((_) async => [
          PanelModel(id: 'p1', name: 'Work', orderedTabIds: ['t1'], activeTabId: 't1'),
        ]);
    final panels = await repo.getPanels();
    expect(panels.single.name, 'Work');
    expect(panels.single.tabs.single.tabId, 't1');
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `fvm flutter test test/features/tabs/data/repositories/tabs_repository_panels_test.dart`
Expected: FAIL — repository panel methods undefined.

- [ ] **Step 7: Implement repository methods.** Add to abstract `TabsRepository`:

```dart
  Future<List<PanelEntity>> getPanels();
  Future<String?> getActivePanelId();
  Future<void> putPanel(PanelEntity panel);
  Future<void> deletePanels(List<String> panelIds);
  Future<void> savePanelMeta(List<String> panelOrder, String activePanelId);
```

(Add imports: `panel_entity.dart`.) Add to `TabsRepositoryImpl` (uses `guardPersistence` like the existing methods; add `import 'package:uuid/uuid.dart';` + the panel model/entity imports):

```dart
  @override
  Future<List<PanelEntity>> getPanels() => guardPersistence(() async {
        final tabModels = await localDataSource.getTabs();
        final tabsById = {for (final m in tabModels) m.tabId: m.toEntity()};
        final panelModels = await localDataSource.getPanels();
        if (panelModels.isEmpty) {
          if (tabsById.isEmpty) return <PanelEntity>[];
          // Legacy upgrade: wrap all existing tabs (in their saved order) into
          // one "Panel 1". The bloc persists this on first load.
          final ordered = tabModels.map((m) => m.tabId).toList();
          return [
            PanelEntity(
              id: const Uuid().v4(),
              name: 'Panel 1',
              tabs: ordered.map((id) => tabsById[id]!).toList(),
              activeTabId: ordered.first,
            ),
          ];
        }
        return panelModels.map((pm) => pm.toEntity(tabsById)).toList();
      });

  @override
  Future<String?> getActivePanelId() =>
      guardPersistence(localDataSource.getActivePanelId);

  @override
  Future<void> putPanel(PanelEntity panel) => guardPersistence(
        () => localDataSource.putPanel(PanelModel.fromEntity(panel)),
      );

  @override
  Future<void> deletePanels(List<String> panelIds) =>
      guardPersistence(() => localDataSource.deletePanels(panelIds));

  @override
  Future<void> savePanelMeta(List<String> panelOrder, String activePanelId) =>
      guardPersistence(
        () => localDataSource.savePanelMeta(panelOrder, activePanelId),
      );
```

- [ ] **Step 8: Run both data tests + analyze**

Run: `fvm flutter test test/features/tabs/data/ && fvm flutter analyze`
Expected: PASS; analyze clean. (If `guardPersistence`'s exact name differs, match the existing impl — it wraps and rethrows as `PersistenceFailure`.)

- [ ] **Step 9: Commit**

```bash
git add lib/features/tabs/domain/repositories/tabs_repository.dart lib/features/tabs/data/repositories/tabs_repository_impl.dart lib/features/tabs/data/datasources/tabs_local_data_source.dart test/features/tabs/data/
git commit -m "feat(panels): repository + data-source panel persistence with legacy migration

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — Panel-Aware Bloc

### Task 4: Panel-aware `TabsState` + `TabsBloc` refactor (existing behavior preserved, scoped to one panel)

This is the core task. It makes `panels`/`activePanelId` the source of truth while keeping `state.tabs`/`state.activeIndex` working, rewrites every existing handler to operate on the active panel (resolving cross-panel for in-flight sends), adds the ≥1-tab auto-seed invariant, and adds panel-aware `LoadTabs` migration. New panel *events* come in Tasks 5–6.

**Files:**
- Modify: `lib/features/tabs/presentation/bloc/tabs_state.dart`, `lib/features/tabs/presentation/bloc/tabs_bloc.dart`, existing `test/features/tabs/presentation/bloc/tabs_bloc_test.dart`
- Test: `test/features/tabs/presentation/bloc/tabs_bloc_panels_test.dart` (load/migration cases)

**Interfaces:**
- Produces on `TabsState`: fields `List<PanelEntity> panels`, `String activePanelId` (plus kept `tabs`, `activeIndex`, `isLoading`); getter `PanelEntity? get activePanel`.
- Produces on `TabsBloc` (private, used by Tasks 5–6): `TabsState _derive(List<PanelEntity> panels, String activePanelId, {bool? isLoading})`, `PanelEntity get _activePanel`, `HttpRequestTabEntity? _findTab(String tabId)`, `List<PanelEntity> _replacePanel(List<PanelEntity>, PanelEntity)`, `List<PanelEntity> _replaceTabAcrossPanels(HttpRequestTabEntity)`, `PanelEntity _ensureNonEmpty(PanelEntity)`, `String _nextPanelName()`, `Future<void> _persistPanel(PanelEntity)`, `Future<void> _persistPanelMeta()`.

- [ ] **Step 1: Rewrite `tabs_state.dart`**

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

class TabsState extends Equatable {
  const TabsState({
    this.panels = const [],
    this.activePanelId = '',
    this.tabs = const [],
    this.activeIndex = 0,
    this.isLoading = false,
  });

  /// All panels, in display order. Invariant: non-empty once loaded.
  final List<PanelEntity> panels;

  /// Id of the active panel (its tabs are surfaced as [tabs]/[activeIndex]).
  final String activePanelId;

  /// The ACTIVE panel's tabs — recomputed on every emit so existing widgets
  /// (and their buildWhen selectors) keep reading `state.tabs` unchanged.
  final List<HttpRequestTabEntity> tabs;

  /// Index of the active panel's active tab within [tabs].
  final int activeIndex;

  final bool isLoading;

  PanelEntity? get activePanel => panels.byId(activePanelId);

  @override
  List<Object?> get props => [panels, activePanelId, tabs, activeIndex, isLoading];

  TabsState copyWith({
    List<PanelEntity>? panels,
    String? activePanelId,
    List<HttpRequestTabEntity>? tabs,
    int? activeIndex,
    bool? isLoading,
  }) {
    return TabsState(
      panels: panels ?? this.panels,
      activePanelId: activePanelId ?? this.activePanelId,
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
```

- [ ] **Step 2: Add helpers + rewrite handlers in `tabs_bloc.dart`.** Add imports (`panel_entity.dart`). Add these helpers to the class:

```dart
  PanelEntity get _activePanel =>
      state.panels.byId(state.activePanelId) ?? state.panels.first;

  Iterable<HttpRequestTabEntity> get _allTabs =>
      state.panels.expand((p) => p.tabs);

  HttpRequestTabEntity? _findTab(String tabId) => _allTabs.byId(tabId);

  /// Recompute the derived active-panel view (tabs/activeIndex) from panels.
  TabsState _derive(
    List<PanelEntity> panels,
    String activePanelId, {
    bool? isLoading,
  }) {
    final active = panels.byId(activePanelId) ??
        (panels.isNotEmpty ? panels.first : null);
    final tabs = active?.tabs ?? const <HttpRequestTabEntity>[];
    final idx = active == null
        ? 0
        : tabs.indexWhere((t) => t.tabId == active.activeTabId);
    return TabsState(
      panels: panels,
      activePanelId: active?.id ?? '',
      tabs: tabs,
      activeIndex: idx < 0 ? 0 : idx,
      isLoading: isLoading ?? state.isLoading,
    );
  }

  List<PanelEntity> _replacePanel(
    List<PanelEntity> panels,
    PanelEntity replacement,
  ) {
    final i = panels.indexWhere((p) => p.id == replacement.id);
    if (i == -1) return panels;
    final copy = [...panels];
    copy[i] = replacement;
    return copy;
  }

  /// Replace a tab wherever it lives (in-flight sends, update, time-travel —
  /// the owning panel may not be the active one).
  List<PanelEntity> _replaceTabAcrossPanels(HttpRequestTabEntity replacement) {
    return state.panels.map((p) {
      final i = p.tabs.indexWhere((t) => t.tabId == replacement.tabId);
      if (i == -1) return p;
      final tabs = [...p.tabs];
      tabs[i] = replacement;
      return p.copyWith(tabs: tabs);
    }).toList();
  }

  /// Invariant 2: a panel is never empty. Seeds + persists a blank NEW REQUEST
  /// tab if [p] has none, returning the non-empty panel.
  PanelEntity _ensureNonEmpty(PanelEntity p) {
    if (p.tabs.isNotEmpty) return p;
    final id = _uuid.v4();
    final blank = HttpRequestTabEntity(
      tabId: id,
      config: HttpRequestConfigEntity(id: id),
    );
    unawaited(_guardWrite(() => _repository.putTab(blank)));
    return p.copyWith(tabs: [blank], activeTabId: id);
  }

  String _nextPanelName() {
    final used = state.panels.map((p) => p.name).toSet();
    var n = 1;
    while (used.contains('Panel $n')) {
      n++;
    }
    return 'Panel $n';
  }

  Future<void> _persistPanel(PanelEntity panel) =>
      _guardWrite(() => _repository.putPanel(panel));

  Future<void> _persistPanelMeta() => _guardWrite(
        () => _repository.savePanelMeta(
          state.panels.map((p) => p.id).toList(),
          state.activePanelId,
        ),
      );
```

- [ ] **Step 3: Rewrite `_onLoadTabs`** (panel-aware load + migration + first-run seed):

```dart
  Future<void> _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      var panels = await _repository.getPanels();
      final storedActive = await _repository.getActivePanelId();

      if (panels.isEmpty) {
        // True first run: seed "Panel 1" with a working sample request.
        final tabId = _uuid.v4();
        final panelId = _uuid.v4();
        final seed = PanelEntity(
          id: panelId,
          name: 'Panel 1',
          tabs: [
            HttpRequestTabEntity(
              tabId: tabId,
              config: HttpRequestConfigEntity(
                id: tabId,
                url: 'https://httpbin.org/get',
              ),
            ),
          ],
          activeTabId: tabId,
        );
        emit(_derive([seed], panelId, isLoading: false));
        await _guardWrite(() => _repository.putTab(seed.tabs.first));
        await _persistPanel(seed);
        await _persistPanelMeta();
        return;
      }

      // Sanitize transient flags + enforce the >=1-tab invariant per panel.
      panels = panels
          .map(
            (p) => _ensureNonEmpty(
              p.copyWith(
                tabs: p.tabs
                    .map((t) => t.isSending ? t.copyWith(isSending: false) : t)
                    .toList(),
              ),
            ),
          )
          .toList();

      final activeId = (storedActive != null && panels.byId(storedActive) != null)
          ? storedActive
          : panels.first.id;
      emit(_derive(panels, activeId, isLoading: false));

      // If meta was absent, we just migrated from the legacy layout — persist
      // the assembled panels so the next launch reads from the panels box.
      if (storedActive == null) {
        for (final p in panels) {
          await _persistPanel(p);
        }
        await _persistPanelMeta();
      }
    } on PersistenceFailure catch (f) {
      log('LoadTabs failed: ${f.message}', name: 'TabsBloc');
      emit(state.copyWith(isLoading: false));
    }
  }
```

- [ ] **Step 4: Rewrite the existing tab-event handlers** to operate on the active panel (cross-panel for sends/update/time-travel). Replace the bodies of `_onAddTab`, `_onRemoveTab`, `_onSetActiveIndex` (now `Future<void>` + registered with `on<SetActiveIndex>` unchanged), `_onReorderTabs`, `_onUpdateTab`, `_onCloseOtherTabs`, `_onCloseTabsToTheRight`, `_onCloseTabsToTheLeft`, `_onDuplicateTab`, `_onSendRequest`, `_applyToTab`, `_markResponseDirty`, `_onViewResponseHistoryEntry`, and `_flushDirtyTabs` with the versions below. Delete `_replaceTabById` and `_persistOrder` (superseded by `_replaceTabAcrossPanels` / `_persistPanel`). Update `close()`.

```dart
  Future<void> _onAddTab(AddTab event, Emitter<TabsState> emit) async {
    // Global dedup: if a tab for this node is already open in any panel, switch
    // to it instead of opening a duplicate.
    if (event.collectionNodeId != null) {
      for (final p in state.panels) {
        final existing = p.tabs.firstWhereOrNull(
          (t) => t.collectionNodeId == event.collectionNodeId,
        );
        if (existing != null) {
          final updated = p.copyWith(activeTabId: existing.tabId);
          emit(_derive(_replacePanel(state.panels, updated), p.id));
          await _persistPanel(updated);
          await _persistPanelMeta();
          return;
        }
      }
    }

    final newTab = HttpRequestTabEntity(
      tabId: _uuid.v4(),
      config: event.config ?? HttpRequestConfigEntity(id: _uuid.v4()),
      collectionNodeId: event.collectionNodeId,
      collectionName: event.collectionName,
      response: event.response,
    );
    final active = _activePanel;
    final updated = active.copyWith(
      tabs: [...active.tabs, newTab],
      activeTabId: newTab.tabId,
    );
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _guardWrite(() => _repository.putTab(newTab));
    await _persistPanel(updated);
  }

  Future<void> _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final owner = state.panels.firstWhereOrNull(
      (p) => p.tabs.any((t) => t.tabId == event.tabId),
    );
    if (owner == null) return;
    _requests.cancelAndFinish(event.tabId);

    final removedIdx = owner.tabs.indexWhere((t) => t.tabId == event.tabId);
    final remaining = [...owner.tabs]..removeAt(removedIdx);
    var updated = owner.copyWith(tabs: remaining);
    if (owner.activeTabId == event.tabId && remaining.isNotEmpty) {
      final newActive = remaining[removedIdx.clamp(0, remaining.length - 1)];
      updated = updated.copyWith(activeTabId: newActive.tabId);
    }
    updated = _ensureNonEmpty(updated);

    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    _dirtyTabIds.remove(event.tabId);
    await _guardWrite(() => _repository.deleteTabs([event.tabId]));
    await _persistPanel(updated);
  }

  Future<void> _onSetActiveIndex(
    SetActiveIndex event,
    Emitter<TabsState> emit,
  ) async {
    final active = _activePanel;
    if (event.index < 0 || event.index >= active.tabs.length) return;
    final updated = active.copyWith(activeTabId: active.tabs[event.index].tabId);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _persistPanel(updated);
  }

  Future<void> _onReorderTabs(
    ReorderTabs event,
    Emitter<TabsState> emit,
  ) async {
    final active = _activePanel;
    final tabs = [...active.tabs];
    var newIndex = event.newIndex;
    if (event.oldIndex < newIndex) newIndex -= 1;
    final item = tabs.removeAt(event.oldIndex);
    tabs.insert(newIndex, item);
    final updated = active.copyWith(tabs: tabs);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _persistPanel(updated);
  }

  void _onUpdateTab(UpdateTab event, Emitter<TabsState> emit) {
    if (_findTab(event.tab.tabId) == null) return;
    emit(_derive(_replaceTabAcrossPanels(event.tab), state.activePanelId));
    _dirtyTabIds.add(event.tab.tabId);
    _scheduleSave();
  }

  Future<void> _onCloseOtherTabs(
    CloseOtherTabs event,
    Emitter<TabsState> emit,
  ) async {
    final active = _activePanel;
    if (active.tabs.length <= 1) return;
    final keep = active.tabs.byId(event.tabId);
    if (keep == null) return;
    final removedIds = active.tabs
        .where((t) => t.tabId != event.tabId)
        .map((t) => t.tabId)
        .toList(growable: false);
    final updated = active.copyWith(tabs: [keep], activeTabId: keep.tabId);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistPanel(updated);
  }

  Future<void> _onCloseTabsToTheRight(
    CloseTabsToTheRight event,
    Emitter<TabsState> emit,
  ) async {
    final active = _activePanel;
    final index = active.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1 || index >= active.tabs.length - 1) return;
    final kept = active.tabs.sublist(0, index + 1);
    final removedIds =
        active.tabs.sublist(index + 1).map((t) => t.tabId).toList(growable: false);
    final activeKept = kept.any((t) => t.tabId == active.activeTabId);
    final updated = active.copyWith(
      tabs: kept,
      activeTabId: activeKept ? active.activeTabId : kept.last.tabId,
    );
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistPanel(updated);
  }

  Future<void> _onCloseTabsToTheLeft(
    CloseTabsToTheLeft event,
    Emitter<TabsState> emit,
  ) async {
    final active = _activePanel;
    final index = active.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index <= 0) return;
    final kept = active.tabs.sublist(index);
    final removedIds =
        active.tabs.sublist(0, index).map((t) => t.tabId).toList(growable: false);
    final activeKept = kept.any((t) => t.tabId == active.activeTabId);
    final updated = active.copyWith(
      tabs: kept,
      activeTabId: activeKept ? active.activeTabId : kept.first.tabId,
    );
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    _dirtyTabIds.removeAll(removedIds);
    await _guardWrite(() => _repository.deleteTabs(removedIds));
    await _persistPanel(updated);
  }

  Future<void> _onDuplicateTab(
    DuplicateTab event,
    Emitter<TabsState> emit,
  ) async {
    final active = _activePanel;
    final index = active.tabs.indexWhere((t) => t.tabId == event.tabId);
    if (index == -1) return;
    final dup = HttpRequestTabEntity(
      tabId: _uuid.v4(),
      config: active.tabs[index].config.copyWith(),
    );
    final tabs = [...active.tabs]..insert(index + 1, dup);
    final updated = active.copyWith(tabs: tabs, activeTabId: dup.tabId);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _guardWrite(() => _repository.putTab(dup));
    await _persistPanel(updated);
  }
```

For `_onSendRequest`: change only the lookup + emit lines — replace `state.tabs.byId(event.tabId)` with `_findTab(event.tabId)`, and the initial `isSending:true` emit with `emit(_derive(_replaceTabAcrossPanels(tab.copyWith(isSending: true, extractionResults: const [], assertionResults: const [])), state.activePanelId));`. The `_applyToTab`/`_recordResponse`/`_applyRules`/`_markResponseDirty` calls stay (their bodies are updated below). Then:

```dart
  void _applyToTab(
    Emitter<TabsState> emit,
    String tabId,
    HttpRequestTabEntity Function(HttpRequestTabEntity live) transform,
  ) {
    final live = _findTab(tabId);
    if (live == null) return;
    emit(_derive(_replaceTabAcrossPanels(transform(live)), state.activePanelId));
  }

  void _markResponseDirty(String tabId) {
    if (_findTab(tabId) == null) return;
    _dirtyTabIds.add(tabId);
    _scheduleSave();
  }

  void _onViewResponseHistoryEntry(
    ViewResponseHistoryEntry event,
    Emitter<TabsState> emit,
  ) {
    final tab = _findTab(event.tabId);
    if (tab == null) return;
    final entry =
        tab.responseHistory.firstWhereOrNull((e) => e.id == event.entryId);
    if (entry == null) return;
    emit(_derive(
      _replaceTabAcrossPanels(tab.copyWith(response: entry.response)),
      state.activePanelId,
    ));
    _markResponseDirty(event.tabId);
  }

  Future<void> _flushDirtyTabs() async {
    if (_dirtyTabIds.isEmpty) return;
    final pending = _dirtyTabIds.toList(growable: false);
    for (final id in pending) {
      _dirtyTabIds.remove(id);
      final tab = _findTab(id);
      if (tab == null) continue;
      try {
        await traceAsync('tabs.putTab', () => _repository.putTab(tab));
      } on PersistenceFailure catch (f) {
        _dirtyTabIds.add(id);
        log('Tab save failed: ${f.message}', name: 'TabsBloc');
      }
    }
  }

  @override
  Future<void> close() async {
    _debounceTimer?.cancel();
    _requests.cancelAll();
    await _flushDirtyTabs();
    for (final p in state.panels) {
      await _persistPanel(p);
    }
    await _persistPanelMeta();
    return super.close();
  }
```

Also update `_applyRules` — it already uses `_applyToTab`, which is now cross-panel; no change needed.

- [ ] **Step 5: Update the existing `tabs_bloc_test.dart`.** The bloc now starts every fixture through `LoadTabs` (which creates a panel) or seeds a panel. For assertions:
  - Replace any full-`TabsState` equality expectations with assertions on `bloc.state.tabs` / `bloc.state.activeIndex` (these still reflect the active panel).
  - For tests that pre-seed tabs by emitting a state, seed via a panel: build `PanelEntity(id: 'p1', name: 'Panel 1', tabs: [...], activeTabId: ...)` and emit `_derive`-equivalent state, or drive through `LoadTabs` with a mock repo returning panels. Use the mock `TabsRepository` with `getPanels()`/`getActivePanelId()` stubbed.
  - Add stubs: `when(() => repository.putPanel(any())).thenAnswer((_) async {});`, `when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});`, `when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');`, `when(() => repository.getPanels()).thenAnswer((_) async => [<seed panel>]);`.

- [ ] **Step 6: Write new load/migration bloc tests** in `tabs_bloc_panels_test.dart`:

```dart
// Using bloc_test + mocktail, mirroring the existing tabs_bloc_test setup.
blocTest<TabsBloc, TabsState>(
  'LoadTabs seeds "Panel 1" with sample request on true first run',
  build: () {
    when(() => repository.getPanels()).thenAnswer((_) async => []);
    when(() => repository.getActivePanelId()).thenAnswer((_) async => null);
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});
    return buildBloc();
  },
  act: (b) => b.add(const LoadTabs()),
  verify: (b) {
    expect(b.state.panels.single.name, 'Panel 1');
    expect(b.state.tabs.single.config.url, 'https://httpbin.org/get');
    expect(b.state.activePanelId, b.state.panels.single.id);
  },
);

blocTest<TabsBloc, TabsState>(
  'LoadTabs persists migrated panels when meta was absent',
  build: () {
    final migrated = PanelEntity(id: 'p1', name: 'Panel 1', tabs: [tab('t1')], activeTabId: 't1');
    when(() => repository.getPanels()).thenAnswer((_) async => [migrated]);
    when(() => repository.getActivePanelId()).thenAnswer((_) async => null);
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});
    return buildBloc();
  },
  act: (b) => b.add(const LoadTabs()),
  verify: (_) {
    verify(() => repository.putPanel(any())).called(greaterThanOrEqualTo(1));
    verify(() => repository.savePanelMeta(any(), any())).called(1);
  },
);
```

- [ ] **Step 7: Run the full tabs test suite + analyze + bloc_lint**

Run: `fvm flutter test test/features/tabs/ && fvm flutter analyze && fvm dart run bloc_tools:bloc lint lib`
Expected: all green; both linters clean.

- [ ] **Step 8: Commit**

```bash
git add lib/features/tabs/presentation/bloc/ test/features/tabs/presentation/bloc/
git commit -m "refactor(panels): panel-aware TabsBloc/TabsState (existing behavior scoped to active panel) + load migration

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Panel lifecycle events (Add / Remove / Rename / SetActive / Reorder)

**Files:**
- Modify: `lib/features/tabs/presentation/bloc/tabs_event.dart`, `lib/features/tabs/presentation/bloc/tabs_bloc.dart`
- Test: append to `test/features/tabs/presentation/bloc/tabs_bloc_panels_test.dart`

**Interfaces:**
- Produces (events): `AddPanel({String? name})`, `RemovePanel(String panelId)`, `RenamePanel(String panelId, String name)`, `SetActivePanel(String panelId)`, `ReorderPanels(int oldIndex, int newIndex)`.

- [ ] **Step 1: Write failing bloc tests** (append):

```dart
blocTest<TabsBloc, TabsState>(
  'AddPanel creates a "Panel N" with one blank tab and activates it',
  build: buildLoadedBloc, // helper that LoadTabs into a single "Panel 1"
  act: (b) => b.add(const AddPanel()),
  verify: (b) {
    expect(b.state.panels.length, 2);
    expect(b.state.panels.last.name, 'Panel 2');
    expect(b.state.panels.last.tabs.length, 1);
    expect(b.state.activePanelId, b.state.panels.last.id);
  },
);

blocTest<TabsBloc, TabsState>(
  'RemovePanel is rejected when only one panel remains',
  build: buildLoadedBloc,
  act: (b) => b.add(RemovePanel(b.state.panels.single.id)),
  verify: (b) => expect(b.state.panels.length, 1),
);

blocTest<TabsBloc, TabsState>(
  'RemovePanel of the active panel switches to a neighbor',
  build: buildLoadedBloc,
  act: (b) {
    b.add(const AddPanel()); // now 2 panels, panel 2 active
    final p2 = b.state.panels.last.id;
    b.add(RemovePanel(p2));
  },
  verify: (b) {
    expect(b.state.panels.length, 1);
    expect(b.state.activePanelId, b.state.panels.single.id);
  },
);

blocTest<TabsBloc, TabsState>(
  'RenamePanel with empty name resets to default "Panel N"',
  build: buildLoadedBloc,
  act: (b) => b.add(RenamePanel(b.state.panels.single.id, '   ')),
  verify: (b) => expect(b.state.panels.single.name, 'Panel 1'),
);

blocTest<TabsBloc, TabsState>(
  'SetActivePanel restores that panel\'s remembered active tab',
  build: buildLoadedBloc,
  act: (b) {
    final p1 = b.state.panels.single.id;
    b.add(const AddPanel());          // creates + activates Panel 2
    b.add(SetActivePanel(p1));        // back to Panel 1
  },
  verify: (b) => expect(b.state.activePanelId, b.state.panels.first.id),
);
```

- [ ] **Step 2: Run to verify they fail**

Run: `fvm flutter test test/features/tabs/presentation/bloc/tabs_bloc_panels_test.dart`
Expected: FAIL — events undefined.

- [ ] **Step 3: Add the events** to `tabs_event.dart`:

```dart
class AddPanel extends TabsEvent {
  const AddPanel({this.name});
  final String? name;
  @override
  List<Object?> get props => [name];
}

class RemovePanel extends TabsEvent {
  const RemovePanel(this.panelId);
  final String panelId;
  @override
  List<Object?> get props => [panelId];
}

class RenamePanel extends TabsEvent {
  const RenamePanel(this.panelId, this.name);
  final String panelId;
  final String name;
  @override
  List<Object?> get props => [panelId, name];
}

class SetActivePanel extends TabsEvent {
  const SetActivePanel(this.panelId);
  final String panelId;
  @override
  List<Object?> get props => [panelId];
}

class ReorderPanels extends TabsEvent {
  const ReorderPanels(this.oldIndex, this.newIndex);
  final int oldIndex;
  final int newIndex;
  @override
  List<Object?> get props => [oldIndex, newIndex];
}
```

- [ ] **Step 4: Register + implement handlers** in `tabs_bloc.dart`. Add to the constructor:

```dart
    on<AddPanel>(_onAddPanel);
    on<RemovePanel>(_onRemovePanel);
    on<RenamePanel>(_onRenamePanel);
    on<SetActivePanel>(_onSetActivePanel);
    on<ReorderPanels>(_onReorderPanels);
```

Handlers:

```dart
  Future<void> _onAddPanel(AddPanel event, Emitter<TabsState> emit) async {
    final panelId = _uuid.v4();
    final tabId = _uuid.v4();
    final blank = HttpRequestTabEntity(
      tabId: tabId,
      config: HttpRequestConfigEntity(id: tabId),
    );
    final panel = PanelEntity(
      id: panelId,
      name: event.name ?? _nextPanelName(),
      tabs: [blank],
      activeTabId: tabId,
    );
    emit(_derive([...state.panels, panel], panelId));
    await _guardWrite(() => _repository.putTab(blank));
    await _persistPanel(panel);
    await _persistPanelMeta();
  }

  Future<void> _onRemovePanel(
    RemovePanel event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.length <= 1) return;
    final idx = state.panels.indexWhere((p) => p.id == event.panelId);
    if (idx == -1) return;
    final removed = state.panels[idx];
    for (final t in removed.tabs) {
      _requests.cancelAndFinish(t.tabId);
      _dirtyTabIds.remove(t.tabId);
    }
    final newPanels = [...state.panels]..removeAt(idx);
    var activeId = state.activePanelId;
    if (activeId == event.panelId) {
      activeId = newPanels[(idx - 1).clamp(0, newPanels.length - 1)].id;
    }
    emit(_derive(newPanels, activeId));
    await _guardWrite(
      () => _repository.deleteTabs(removed.tabs.map((t) => t.tabId).toList()),
    );
    await _guardWrite(() => _repository.deletePanels([event.panelId]));
    await _persistPanelMeta();
  }

  Future<void> _onRenamePanel(
    RenamePanel event,
    Emitter<TabsState> emit,
  ) async {
    final panel = state.panels.byId(event.panelId);
    if (panel == null) return;
    final trimmed = event.name.trim();
    final name = trimmed.isEmpty ? _nextPanelName() : trimmed;
    final updated = panel.copyWith(name: name);
    emit(_derive(_replacePanel(state.panels, updated), state.activePanelId));
    await _persistPanel(updated);
  }

  Future<void> _onSetActivePanel(
    SetActivePanel event,
    Emitter<TabsState> emit,
  ) async {
    if (state.panels.byId(event.panelId) == null) return;
    if (event.panelId == state.activePanelId) return;
    emit(_derive(state.panels, event.panelId));
    await _persistPanelMeta();
  }

  Future<void> _onReorderPanels(
    ReorderPanels event,
    Emitter<TabsState> emit,
  ) async {
    final panels = [...state.panels];
    var newIndex = event.newIndex;
    if (event.oldIndex < newIndex) newIndex -= 1;
    final item = panels.removeAt(event.oldIndex);
    panels.insert(newIndex, item);
    emit(_derive(panels, state.activePanelId));
    await _persistPanelMeta();
  }
```

- [ ] **Step 5: Run tests + analyze + bloc_lint**

Run: `fvm flutter test test/features/tabs/presentation/bloc/ && fvm flutter analyze && fvm dart run bloc_tools:bloc lint lib`
Expected: green/clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/tabs/presentation/bloc/ test/features/tabs/presentation/bloc/
git commit -m "feat(panels): panel lifecycle events (add/remove/rename/switch/reorder)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Move-tab-between-panels events

**Files:**
- Modify: `lib/features/tabs/presentation/bloc/tabs_event.dart`, `lib/features/tabs/presentation/bloc/tabs_bloc.dart`
- Test: append to `test/features/tabs/presentation/bloc/tabs_bloc_panels_test.dart`

**Interfaces:**
- Produces (events): `MoveTabToPanel(String tabId, String targetPanelId)`, `MoveTabToNewPanel(String tabId, {String? name})`.

- [ ] **Step 1: Write failing bloc tests** (append):

```dart
blocTest<TabsBloc, TabsState>(
  'MoveTabToPanel moves a tab to the target and stays on the current panel',
  build: buildLoadedBloc,
  act: (b) {
    final p1 = b.state.panels.single.id;
    b.add(const AddTab());                 // Panel 1 now has 2 tabs
    b.add(const AddPanel());               // Panel 2 created + active
    b.add(SetActivePanel(p1));             // back on Panel 1
    final movingId = b.state.panels.byId(p1)!.tabs.last.tabId;
    final p2 = b.state.panels[1].id;
    b.add(MoveTabToPanel(movingId, p2));
  },
  verify: (b) {
    expect(b.state.activePanelId, b.state.panels.first.id);     // unchanged
    expect(b.state.panels[1].tabs.length, 2);                   // Panel 2 grew
  },
);

blocTest<TabsBloc, TabsState>(
  'moving the last tab out of a panel auto-seeds a blank tab',
  build: buildLoadedBloc,
  act: (b) {
    b.add(const AddPanel());                       // Panel 2 active, 1 tab
    final p2 = b.state.panels.last.id;
    final p1 = b.state.panels.first.id;
    final onlyTab = b.state.panels.last.tabs.single.tabId;
    b.add(MoveTabToPanel(onlyTab, p1));            // empties Panel 2
    expect(b.state.panels.byId(p2)!.tabs.length, 1); // auto-seeded
  },
  verify: (_) {},
);

blocTest<TabsBloc, TabsState>(
  'MoveTabToNewPanel creates a panel containing only the moved tab',
  build: buildLoadedBloc,
  act: (b) {
    b.add(const AddTab());                          // Panel 1 has 2 tabs
    final moving = b.state.panels.single.tabs.last.tabId;
    b.add(MoveTabToNewPanel(moving));
  },
  verify: (b) {
    expect(b.state.panels.length, 2);
    expect(b.state.panels.last.tabs.length, 1);
    expect(b.state.panels.last.tabs.single.tabId, isNotEmpty);
    expect(b.state.activePanelId, b.state.panels.first.id);     // stayed put
  },
);
```

- [ ] **Step 2: Run to verify they fail**

Run: `fvm flutter test test/features/tabs/presentation/bloc/tabs_bloc_panels_test.dart`
Expected: FAIL — events undefined.

- [ ] **Step 3: Add events** to `tabs_event.dart`:

```dart
class MoveTabToPanel extends TabsEvent {
  const MoveTabToPanel(this.tabId, this.targetPanelId);
  final String tabId;
  final String targetPanelId;
  @override
  List<Object?> get props => [tabId, targetPanelId];
}

class MoveTabToNewPanel extends TabsEvent {
  const MoveTabToNewPanel(this.tabId, {this.name});
  final String tabId;
  final String? name;
  @override
  List<Object?> get props => [tabId, name];
}
```

- [ ] **Step 4: Register + implement handlers.** Constructor:

```dart
    on<MoveTabToPanel>(_onMoveTabToPanel);
    on<MoveTabToNewPanel>(_onMoveTabToNewPanel);
```

Handlers (a shared private `_detachTab` keeps DRY):

```dart
  /// Removes [tabId] from its owning panel, fixing the panel's active tab and
  /// auto-seeding a blank if it empties. Returns (updatedSource, movedTab) or
  /// null if the tab isn't found. Persistence of the source is the caller's job.
  ({PanelEntity source, HttpRequestTabEntity tab})? _detachTab(String tabId) {
    final source =
        state.panels.firstWhereOrNull((p) => p.tabs.any((t) => t.tabId == tabId));
    if (source == null) return null;
    final removedIdx = source.tabs.indexWhere((t) => t.tabId == tabId);
    final tab = source.tabs[removedIdx];
    final remaining = [...source.tabs]..removeAt(removedIdx);
    var updated = source.copyWith(tabs: remaining);
    if (source.activeTabId == tabId && remaining.isNotEmpty) {
      updated = updated.copyWith(
        activeTabId: remaining[removedIdx.clamp(0, remaining.length - 1)].tabId,
      );
    }
    updated = _ensureNonEmpty(updated);
    return (source: updated, tab: tab);
  }

  Future<void> _onMoveTabToPanel(
    MoveTabToPanel event,
    Emitter<TabsState> emit,
  ) async {
    final target = state.panels.byId(event.targetPanelId);
    if (target == null) return;
    final owner = state.panels
        .firstWhereOrNull((p) => p.tabs.any((t) => t.tabId == event.tabId));
    if (owner == null || owner.id == target.id) return;

    final detached = _detachTab(event.tabId);
    if (detached == null) return;
    final updatedTarget =
        target.copyWith(tabs: [...target.tabs, detached.tab]);

    var panels = _replacePanel(state.panels, detached.source);
    panels = _replacePanel(panels, updatedTarget);
    emit(_derive(panels, state.activePanelId)); // stay on current panel
    await _persistPanel(detached.source);
    await _persistPanel(updatedTarget);
  }

  Future<void> _onMoveTabToNewPanel(
    MoveTabToNewPanel event,
    Emitter<TabsState> emit,
  ) async {
    final detached = _detachTab(event.tabId);
    if (detached == null) return;
    final newPanel = PanelEntity(
      id: _uuid.v4(),
      name: event.name ?? _nextPanelName(),
      tabs: [detached.tab],
      activeTabId: detached.tab.tabId,
    );
    final panels = [..._replacePanel(state.panels, detached.source), newPanel];
    emit(_derive(panels, state.activePanelId)); // stay on current panel
    await _persistPanel(detached.source);
    await _persistPanel(newPanel);
    await _persistPanelMeta();
  }
```

> Note: a moved tab's *entity* is unchanged and already in the `tabs` box, so no `putTab` is needed — only the panels' `orderedTabIds` change (persisted via `_persistPanel`). `_ensureNonEmpty` handles the seeded blank's `putTab`.

- [ ] **Step 5: Run tests + analyze + bloc_lint**

Run: `fvm flutter test test/features/tabs/presentation/bloc/ && fvm flutter analyze && fvm dart run bloc_tools:bloc lint lib`
Expected: green/clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/tabs/presentation/bloc/ test/features/tabs/presentation/bloc/
git commit -m "feat(panels): move-tab-between-panels events (incl. move-to-new-panel + auto-seed)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase 3 — UI

### Task 7: `PanelSelector` widget + placement (desktop/tablet/phone)

**Files:**
- Create: `lib/features/tabs/presentation/widgets/panel_selector.dart`
- Modify: `lib/features/home/presentation/screens/main_screen.dart` (insert into `_buildTabBar` between `AddTabButton` and the `EnvironmentSelector` padding)
- Test: `test/features/tabs/presentation/widgets/panel_selector_test.dart`

**Interfaces:**
- Consumes: `TabsBloc` state (`panels`, `activePanelId`), events `SetActivePanel`, `AddPanel`, `RenamePanel`, `ReorderPanels`, `MoveTabToPanel`, `MoveTabToNewPanel`. The close affordance calls `closePanelWithSavePrompt(context, panelId)` from Task 8 (import it; Task 8 lands the function — if implementing 7 before 8, stub the close button to a TODO-free `ConfirmDialog` + `RemovePanel` and replace in Task 8).
- Produces: `class PanelSelector extends StatelessWidget { const PanelSelector({super.key}); }`.

- [ ] **Step 1: Write a failing widget test**

```dart
// Pump PanelSelector inside a BlocProvider<TabsBloc> with a fake bloc seeded
// with two panels (mirror existing widget-test harness in test/features/tabs).
testWidgets('shows active panel name and switches on selection', (tester) async {
  // seed bloc: panels [Panel 1 (active), Work]
  await tester.pumpWidget(_host(bloc));
  expect(find.text('Panel 1'), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('panel_selector_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('panel_row_${workPanelId}')));
  await tester.pumpAndSettle();

  verify(() => bloc.add(SetActivePanel(workPanelId))).called(1);
});

testWidgets('new panel footer dispatches AddPanel', (tester) async {
  await tester.pumpWidget(_host(bloc));
  await tester.tap(find.byKey(const ValueKey('panel_selector_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('panel_add_button')));
  await tester.pumpAndSettle();
  verify(() => bloc.add(const AddPanel())).called(1);
});

testWidgets('double-tap the name opens rename', (tester) async {
  await tester.pumpWidget(_host(bloc));
  final gesture = find.byKey(const ValueKey('panel_selector_button'));
  await tester.tap(gesture);
  await tester.tap(gesture); // double
  await tester.pumpAndSettle();
  expect(find.text('RENAME PANEL'), findsOneWidget);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/panel_selector_test.dart`
Expected: FAIL — `PanelSelector` missing.

- [ ] **Step 3: Implement `PanelSelector`.** Use a `BlocBuilder<TabsBloc, TabsState>` with `buildWhen: (p, n) => p.panels != n.panels || p.activePanelId != n.activePanelId`. The button (`GestureDetector` with `onTap` → open menu, `onDoubleTap` → rename active panel via `NamePromptDialog.show(context, title: 'RENAME PANEL', initialText: <name>, allowEmpty: true, onConfirm: (v) => bloc.add(RenamePanel(activeId, v)))`). Render compact (icon + short name) when `context.layoutMode == LayoutMode.phone`, full name (ellipsized) otherwise. All chrome via theme accessors (`context.appDecoration.panelBox`, `context.appTypography.titleWeight`, `context.appLayout`). The overlay is a `showMenu`/`PopupMenuButton`-style list (or a custom `OverlayEntry`) of `_PanelRow`s, each keyed `ValueKey('panel_row_$id')` with: tap→`SetActivePanel`, pencil `IconButton`→rename, close `IconButton`→`closePanelWithSavePrompt(context, id)` (hide when `panels.length == 1`), and a `ReorderableListView` for drag-reorder→`ReorderPanels`. Footer item keyed `ValueKey('panel_add_button')`→`AddPanel`. Wrap the button in a `DragTarget<String>` (drag-onto-selector lands in Task 9 — leave the `onAcceptWithDetails` calling `MoveTabToPanel`/opening the list; Task 9 adds the `Draggable` source on tabs). Button keyed `ValueKey('panel_selector_button')`.

  > Keep this file focused on the selector + its menu rows; the close orchestration lives in `panel_close_coordinator.dart` (Task 8).

- [ ] **Step 4: Place it in `_buildTabBar`** in `main_screen.dart` — between `const AddTabButton(),` and the `EnvironmentSelector` `Padding`:

```dart
            const AddTabButton(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.tabSpacing),
              child: const PanelSelector(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.tabSpacing),
              child: const EnvironmentSelector(),
            ),
```

(Add the import.)

- [ ] **Step 5: Run the widget test + analyze + custom_lint**

Run: `fvm flutter test test/features/tabs/presentation/widgets/panel_selector_test.dart && fvm flutter analyze && fvm dart run custom_lint`
Expected: PASS; clean (no hardcoded colors → `avoid_hardcoded_brand_colors` clean; no `sl<T>()` → `avoid_get_it_in_widgets` clean).

- [ ] **Step 6: Commit**

```bash
git add lib/features/tabs/presentation/widgets/panel_selector.dart lib/features/home/presentation/screens/main_screen.dart test/features/tabs/presentation/widgets/panel_selector_test.dart
git commit -m "feat(panels): PanelSelector dropdown (switch/add/rename/reorder) in the tab strip

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Close-panel save orchestration

**Files:**
- Create: `lib/features/tabs/presentation/widgets/panel_close_coordinator.dart`
- Modify: `lib/features/tabs/presentation/widgets/panel_selector.dart` (close button → `closePanelWithSavePrompt`)
- Test: `test/features/tabs/presentation/widgets/panel_close_coordinator_test.dart`

**Interfaces:**
- Consumes: `TabsBloc` (state + `RemovePanel`, `UpdateTab`), `CollectionsBloc` (saved configs via `CollectionsTreeHelper.findNode` + `UpdateNodeRequest`/`SaveRequestToCollection`), `TabDirtyChecker` (via `context.read<TabDirtyChecker>()`), dialogs `ConfirmDialog.show`, `NamePromptDialog.show`, `showResponsiveDialog`.
- Produces: `Future<void> closePanelWithSavePrompt(BuildContext context, String panelId)`.

- [ ] **Step 1: Write failing widget tests** covering: (a) no dirty tabs → confirm → `RemovePanel`; (b) dirty + "Discard all & close" → `RemovePanel`; (c) dirty + "Review & save" → save path dispatches save then `RemovePanel`; (d) "Cancel review" → no `RemovePanel`. Mirror the dialog-driven widget tests in `test/features/environments/.../environments_dialog_test.dart` (tap by visible label / key, then `verify(() => bloc.add(...))`).

```dart
testWidgets('no dirty tabs: confirm closes the panel', (tester) async {
  // dirtyChecker returns false for all tabs
  await tester.pumpWidget(_host(tabsBloc, collectionsBloc, dirtyChecker));
  await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CLOSE')); // ConfirmDialog confirm label
  await tester.pumpAndSettle();
  verify(() => tabsBloc.add(RemovePanel(panelId))).called(1);
});

testWidgets('dirty tabs: discard all closes the panel without saving', (tester) async {
  // dirtyChecker returns true for one tab
  await tester.pumpWidget(_host(tabsBloc, collectionsBloc, dirtyChecker));
  await tester.tap(find.byKey(const ValueKey('close_panel_trigger')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('DISCARD ALL & CLOSE'));
  await tester.pumpAndSettle();
  verify(() => tabsBloc.add(RemovePanel(panelId))).called(1);
  verifyNever(() => collectionsBloc.add(any()));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/panel_close_coordinator_test.dart`
Expected: FAIL — function missing.

- [ ] **Step 3: Implement `closePanelWithSavePrompt`.** Logic:
  1. Read `panel = context.read<TabsBloc>().state.panels.byId(panelId)`; bail if null or if it's the only panel (no-op).
  2. Compute dirty tabs: for each tab, `context.read<TabDirtyChecker>()(tab: tab, savedConfigs: <map built from CollectionsBloc state>)` — build `savedConfigs` exactly the way `main_screen.dart` does for the per-tab close (reuse that helper or replicate it: map of `nodeId → config` from `CollectionsTreeHelper` over `collectionsBloc.state.collections`).
  3. If no dirty: `ConfirmDialog.show(context, title: 'CLOSE PANEL?', message: 'Close "${panel.name}" and its ${panel.tabs.length} tabs?', confirmLabel: 'CLOSE', onConfirm: () => context.read<TabsBloc>().add(RemovePanel(panelId)))`.
  4. If dirty ≥ 1: show a summary dialog via `showResponsiveDialog` with three actions — `DISCARD ALL & CLOSE` (→ `RemovePanel`), `REVIEW & SAVE…` (→ step 5), `CANCEL` (pop, no-op). Title `'${panel.name.toUpperCase()} HAS ${dirty.length} UNSAVED TABS'`. Destructive action colored `Theme.of(context).colorScheme.error`.
  5. Review loop — iterate `dirty` sequentially with `await`: for each, `showResponsiveDialog` "SAVE CHANGES TO '<displayTitle>'?" with `SAVE` / `DISCARD` / `CANCEL REVIEW`. `CANCEL REVIEW` → return early (panel stays). `SAVE` → if `tab.collectionNodeId != null` and the node exists, `collectionsBloc.add(UpdateNodeRequest(tab.collectionNodeId!, tab.config.copyWith()))`; else `await NamePromptDialog.show(context, title: 'SAVE TO COLLECTION', initialText: 'NEW REQUEST', onConfirm: (name) { final id = const Uuid().v4(); collectionsBloc.add(SaveRequestToCollection(name, tab.config.copyWith(), id: id)); tabsBloc.add(UpdateTab(tab.copyWith(collectionName: name, collectionNodeId: id))); })`. After the loop completes, `context.read<TabsBloc>().add(RemovePanel(panelId))`.
  - Capture `ScaffoldMessenger`/blocs before awaits; guard `context.mounted` after each await (lint + correctness). Reuse the exact save dispatch shape from `request_view.dart:_handleSave/_showSaveDialog`.

- [ ] **Step 4: Wire the selector's close button** in `panel_selector.dart` to call `closePanelWithSavePrompt(context, id)` (replace any interim stub from Task 7).

- [ ] **Step 5: Run tests + analyze + custom_lint**

Run: `fvm flutter test test/features/tabs/presentation/widgets/panel_close_coordinator_test.dart && fvm flutter analyze && fvm dart run custom_lint`
Expected: PASS; clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/tabs/presentation/widgets/ test/features/tabs/presentation/widgets/panel_close_coordinator_test.dart
git commit -m "feat(panels): close-panel save orchestration (discard-all / review-and-save)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Move-to-panel — tab context-menu submenu + drag-onto-selector

**Files:**
- Modify: `lib/features/home/presentation/widgets/tab_widget.dart` (context menu + `Draggable<String>` wrapper), `lib/features/tabs/presentation/widgets/panel_selector.dart` (DragTarget acceptance)
- Test: append to `test/features/tabs/presentation/widgets/panel_selector_test.dart` + a tab-widget menu test (mirror existing `tab_widget` tests if present)

**Interfaces:**
- Consumes: `TabsBloc` state (`panels`), events `MoveTabToPanel`, `MoveTabToNewPanel`.

- [ ] **Step 1: Write failing tests** — (a) right-clicking a tab shows `MOVE TO PANEL` with the *other* panels + `New panel…`, and selecting one dispatches `MoveTabToPanel(tabId, targetId)`; selecting `New panel…` dispatches `MoveTabToNewPanel(tabId)`. (b) The selector accepts a dropped `tabId` (simulate via directly invoking the `DragTarget` `onAcceptWithDetails`, or a `tester.drag` from a tab to the selector) → `MoveTabToPanel`.

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/panel_selector_test.dart`
Expected: FAIL.

- [ ] **Step 3: Add the submenu** in `tab_widget.dart`'s `_showContextMenu` (before the final divider/COPY URL). Read panels from `context.read<TabsBloc>().state.panels`, exclude the panel owning this tab. Build a `PopupMenuItem` whose `onTap` opens a second `showMenu` anchored at the same position listing each other panel (→ `MoveTabToPanel(widget.tabId, panel.id)`) plus a `New panel…` entry (→ `MoveTabToNewPanel(widget.tabId)`). (Flutter's `PopupMenuItem` has no native submenu; the two-step `showMenu` is the established pattern — keep labels uppercase to match the menu.)

- [ ] **Step 4: Add the drag source** — wrap the tab's content in `Draggable<String>(data: widget.tabId, feedback: <small chip>, childWhenDragging: <dimmed>, child: <existing>)`, preserving the existing `ReorderableDragStartListener` for in-strip reordering (the `Draggable` long-press vs reorder drag must not conflict — use `Draggable` with `delay`/`LongPressDraggable<String>` to disambiguate from the horizontal reorder gesture).

- [ ] **Step 5: Accept the drop in `PanelSelector`** — the `DragTarget<String>` `onAcceptWithDetails` opens the panel list as a transient menu (or, simplest per spec, accepts directly onto the currently-shown row). On selecting a panel row while a drag is in progress, dispatch `MoveTabToPanel(draggedTabId, panelId)`; dropping on `+ New panel` → `MoveTabToNewPanel`.

- [ ] **Step 6: Run tests + analyze + custom_lint**

Run: `fvm flutter test test/features/tabs/ && fvm flutter analyze && fvm dart run custom_lint`
Expected: green/clean.

- [ ] **Step 7: Commit**

```bash
git add lib/features/home/presentation/widgets/tab_widget.dart lib/features/tabs/presentation/widgets/panel_selector.dart test/features/tabs/presentation/widgets/
git commit -m "feat(panels): move tab between panels via context menu + drag-onto-selector

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: compactPhone — panels in `TabSwitcherSheet` + `TabChip` label

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/tab_switcher_sheet.dart`, `lib/features/home/presentation/widgets/tab_chip.dart`
- Test: extend the existing `tab_switcher_sheet` / `tab_chip` tests (or create them if absent)

**Interfaces:**
- Consumes: `TabsBloc` (`panels`, `activePanelId`; events `SetActivePanel`, `AddPanel`, `RenamePanel`, `MoveTabToPanel`, `MoveTabToNewPanel`).

- [ ] **Step 1: Write failing tests** — (a) `TabChip` label shows the active panel name + counter (e.g. `Panel 2 · 2/5`). (b) Opening the sheet shows a panel-chip row including `+ New panel`; tapping a panel chip dispatches `SetActivePanel`; tapping `+ New panel` dispatches `AddPanel`. (c) A tab row's action affordance offers `Move to panel ▸`.

- [ ] **Step 2: Run to verify they fail**

Run: `fvm flutter test test/features/tabs/presentation/widgets/tab_switcher_sheet_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement.** In `tab_chip.dart`, change the label to include `state.activePanel?.name` + the within-panel counter (`activeIndex+1`/`tabs.length`), reading from `TabsBloc` with a narrow `buildWhen`. In `tab_switcher_sheet.dart`, add a top section: a horizontal scroll of panel chips (active highlighted; double-tap/pencil → `RenamePanel`; trailing `+ New panel` chip → `AddPanel`) above the existing tab list (which already shows the active panel's tabs since it reads `state.tabs`). Add a `Move to panel ▸` affordance to each `_TabRow` (a small popup listing other panels + `New panel…`). All chrome via theme accessors + `context.appShape.sheetRadius` for the sheet.

- [ ] **Step 4: Run tests + analyze + custom_lint**

Run: `fvm flutter test test/features/tabs/ && fvm flutter analyze && fvm dart run custom_lint`
Expected: green/clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tabs/presentation/widgets/tab_switcher_sheet.dart lib/features/home/presentation/widgets/tab_chip.dart test/features/tabs/presentation/widgets/
git commit -m "feat(panels): compact-phone panel UI in switcher sheet + chip label

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Keyboard shortcuts

**Files:**
- Modify: `lib/core/navigation/intents.dart`, `lib/main.dart`, `lib/features/home/presentation/screens/main_screen.dart`
- Test: extend `test/main_test.dart` (or wherever `appShortcuts` is tested) + a MainScreen actions test

**Interfaces:**
- Produces: `NewPanelIntent`, `NextPanelIntent`, `PrevPanelIntent`, `JumpToPanelIntent(int panelIndex)`.

- [ ] **Step 1: Write failing test** asserting `appShortcuts` contains the new bindings (mirror the existing test that checks tab shortcuts):

```dart
test('appShortcuts includes panel bindings', () {
  expect(
    appShortcuts.containsKey(
      const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true),
    ),
    isTrue,
  );
  expect(
    appShortcuts.values.whereType<JumpToPanelIntent>().length,
    9,
  );
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/main_test.dart`
Expected: FAIL.

- [ ] **Step 3: Add intents** to `intents.dart`:

```dart
/// Create a new panel (Cmd/Ctrl+Shift+N).
class NewPanelIntent extends Intent {
  const NewPanelIntent();
}

/// Activate the next panel, wrapping (Cmd/Ctrl+Shift+]).
class NextPanelIntent extends Intent {
  const NextPanelIntent();
}

/// Activate the previous panel, wrapping (Cmd/Ctrl+Shift+[).
class PrevPanelIntent extends Intent {
  const PrevPanelIntent();
}

/// Jump to the panel at [panelIndex] (0-based) (Cmd/Ctrl+Shift+1..9).
class JumpToPanelIntent extends Intent {
  const JumpToPanelIntent(this.panelIndex);
  final int panelIndex;
}
```

- [ ] **Step 4: Add bindings** to the `appShortcuts` builder in `main.dart` (both control + meta variants; reuse `_tabDigitKeys` for the jump loop with `shift: true`):

```dart
    const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
        const NewPanelIntent(),
    const SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true):
        const NewPanelIntent(),
    const SingleActivator(LogicalKeyboardKey.bracketRight, control: true, shift: true):
        const NextPanelIntent(),
    const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true, shift: true):
        const NextPanelIntent(),
    const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true, shift: true):
        const PrevPanelIntent(),
    const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true, shift: true):
        const PrevPanelIntent(),
```

And in the existing digit loop, add shift variants mapping to `JumpToPanelIntent(i)`:

```dart
    for (var i = 0; i < _tabDigitKeys.length; i++) ...{
      SingleActivator(_tabDigitKeys[i], control: true, shift: true):
          JumpToPanelIntent(i),
      SingleActivator(_tabDigitKeys[i], meta: true, shift: true):
          JumpToPanelIntent(i),
    },
```

- [ ] **Step 5: Add actions in `MainScreen`** (they need `TabsBloc` state). In the `Actions` map:

```dart
      NewPanelIntent: CallbackAction<NewPanelIntent>(
        onInvoke: (_) {
          context.read<TabsBloc>().add(const AddPanel());
          return null;
        },
      ),
      NextPanelIntent: CallbackAction<NextPanelIntent>(
        onInvoke: (_) {
          final s = context.read<TabsBloc>().state;
          if (s.panels.length < 2) return null;
          final i = s.panels.indexWhere((p) => p.id == s.activePanelId);
          final next = s.panels[(i + 1) % s.panels.length];
          context.read<TabsBloc>().add(SetActivePanel(next.id));
          return null;
        },
      ),
      PrevPanelIntent: CallbackAction<PrevPanelIntent>(
        onInvoke: (_) {
          final s = context.read<TabsBloc>().state;
          if (s.panels.length < 2) return null;
          final i = s.panels.indexWhere((p) => p.id == s.activePanelId);
          final prev = s.panels[(i - 1 + s.panels.length) % s.panels.length];
          context.read<TabsBloc>().add(SetActivePanel(prev.id));
          return null;
        },
      ),
      JumpToPanelIntent: CallbackAction<JumpToPanelIntent>(
        onInvoke: (intent) {
          final s = context.read<TabsBloc>().state;
          if (intent.panelIndex < s.panels.length) {
            context.read<TabsBloc>().add(
                  SetActivePanel(s.panels[intent.panelIndex].id),
                );
          }
          return null;
        },
      ),
```

- [ ] **Step 6: Run tests + analyze**

Run: `fvm flutter test test/main_test.dart && fvm flutter analyze`
Expected: green/clean.

- [ ] **Step 7: Commit**

```bash
git add lib/core/navigation/intents.dart lib/main.dart lib/features/home/presentation/screens/main_screen.dart test/
git commit -m "feat(panels): keyboard shortcuts (new/next/prev/jump panel)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase 4 — Integration Tests (every interaction path)

### Task 12: patrol_finders integration suite for panels

**Files:**
- Create: `integration_test/panels_test.dart` (+ reuse existing helpers in `integration_test/`)
- Modify: `integration_test/BACKLOG.md` (mark panel coverage)

**Interfaces:**
- Consumes: the full app under test; existing integration harness/helpers (pump app, find by `ValueKey`). Use the `ValueKey`s added in Tasks 7–10 (`panel_selector_button`, `panel_row_<id>`, `panel_add_button`, `close_panel_trigger`, etc.) — add any missing anchors to the widgets in this task.

Implement one `patrolTest`/`testWidgets` group per flow below. Each ends green. Commit once at the end (integration tests run together).

- [ ] **Step 1: Creating & switching** — (1) new panel via footer becomes active with one blank tab; (2) new panel via Ctrl/Cmd+Shift+N; (3) switch via dropdown row restores the panel's remembered active tab; (4) next/prev + jump-to-panel-N shortcuts switch panels.

- [ ] **Step 2: Renaming (every affordance)** — (5) double-click selector name; (6) pencil in a row; (7) `RENAME PANEL` menu entry; (8) empty submission resets to `Panel N`.

- [ ] **Step 3: Reordering** — (9) drag panel rows in the dropdown; assert order persists (verify via reopening the dropdown).

- [ ] **Step 4: Moving tabs** — (10) `MOVE TO PANEL ▸` submenu moves a tab (left source, appears in target); (11) `New panel…` creates a panel with only that tab, active panel unchanged; (12) drag a tab onto the selector → drop on a panel row; (13) drag → drop on `+ New panel`; (14) move the last tab out → source auto-seeds a blank.

- [ ] **Step 5: Closing panels** — (15) close with no dirty tabs → confirm; (16) dirty → Discard all; (17) dirty → Review & save (save linked, save unlinked, discard another); (18) dirty → Review & save → Cancel review keeps the panel; (19) closing the last panel is blocked.

- [ ] **Step 6: Auto-seed & active-tab memory** — (20) close a panel's last tab (not via panel close) → auto-seeds blank; (21) per-panel active tab remembered across switches.

- [ ] **Step 7: In-flight across panels** — (22) start a request in Panel A (use the existing mock/long-running endpoint harness), switch to B, switch back → response present in the originating tab.

- [ ] **Step 8: Persistence across restart** — (23) build several panels (custom names, custom order, specific active panel + per-panel active tabs, ≥1 dirty tab), restart the app (re-pump / re-init Hive via the suite's restart helper) → exact state restored, dirty tab still dirty.

- [ ] **Step 9: Responsiveness** — (24) resize to `compactPhone` (≤500 px) → strip collapses; reach panel UI in the `TabSwitcherSheet` (create/switch/rename/move); resize back → strip + selector return.

- [ ] **Step 10: Run the integration suite (macOS)**

Run: `fvm flutter test integration_test/panels_test.dart -d macos`
Expected: all flows green. (If the suite uses a runner script, follow `integration_test/BACKLOG.md`/README conventions.)

- [ ] **Step 11: Full regression + commit**

Run: `fvm flutter test` (full unit/widget suite) — expect green.

```bash
git add integration_test/
git commit -m "test(panels): integration coverage for every panel interaction path

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Phase 5 — Docs & Finalization

### Task 13: CLAUDE.md + wiki sync

**Files:**
- Modify: `CLAUDE.md`
- Modify (separate repo): `Getman.wiki.git` — new `Panels.md` + `_Sidebar.md` + shortcuts page

- [ ] **Step 1: Update `CLAUDE.md`** — add a typeId table row: `| 12 | PanelModel | panels | Panel structure (id/name/orderedTabIds/activeTabId); tab entities stay in tabs box |` and bump "next free" to 13. Add a §4.2 sub-note: panels are a panel-aware `TabsBloc` (`panels` + `activePanelId` in state; `tabs`/`activeIndex` are the active panel's view; ≥1 panel & ≥1 tab/panel invariants; per-panel tab order in `PanelModel.orderedTabIds`; panel order + active in `tabsMeta` under `panelOrder`/`activePanelId`). Note the new shortcuts.

- [ ] **Step 2: Commit the CLAUDE.md change**

```bash
git add CLAUDE.md
git commit -m "docs(panels): CLAUDE.md typeId 12 + panels architecture note

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 3: Update the wiki** — clone `https://github.com/thiagomiranda3/Getman.wiki.git`, add `Panels.md` (what panels are; the selector dropdown; add/rename [all affordances]/reorder/remove; moving tabs [menu + drag]; close-panel discard / review-and-save flow; the ≥1-tab rule; persistence; the new shortcuts — use verbatim UI labels), add it to `_Sidebar.md`, and add the three shortcut bindings to the shortcuts page. Commit + push (default branch `master`).

```bash
# in the wiki clone:
git add Panels.md _Sidebar.md <shortcuts-page>.md
git commit -m "Add Panels page + nav + shortcuts"
git push origin master
```

---

### Task 14: Full-gate verification + push

- [ ] **Step 1: Run the entire done-bar from a clean tree**

Run:
```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools tools/getman_lints integration_test
fvm flutter test
```
Expected: analyze "No issues found!", custom_lint "No issues found!", bloc lint "0 issues found", format reports 0 changed (or commit the formatting), full test suite green.

- [ ] **Step 2: Commit any formatting + push to remote dev**

```bash
git add -A
git commit -m "chore(panels): formatting + final gate

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" || echo "nothing to commit"
git push origin dev
```

---

## Self-Review

**Spec coverage** (each spec section → task):
- §3 data model → Tasks 1 (`PanelEntity`), 2 (`PanelModel`), 4 (`TabsState`).
- §4 invariants → Task 4 (≥1 tab auto-seed, derive), 5 (≥1 panel rejection).
- §5 events/behavior + migration → Tasks 4 (load/migration + existing events), 5 (lifecycle), 6 (move).
- §6 close orchestration → Task 8.
- §7 renaming affordances → Tasks 7 (selector double-click + pencil + menu) & 10 (phone).
- §8 UI/responsiveness → Tasks 7 (desktop/tablet/phone selector), 10 (compactPhone).
- §9 persistence → Tasks 3 (repo/datasource), 4/5/6 (immediate panel writes + close flush).
- §10 shortcuts → Task 11.
- §11 unit/widget tests → embedded in Tasks 1–11.
- §12 integration tests → Task 12.
- §13 docs → Task 13.

**Placeholder scan:** UI tasks (7–10) describe widget structure + give the critical wiring/keys/events and reference concrete sibling widgets (`AddTabButton`, `EnvironmentSelector`, `environments_dialog.dart`, `request_view.dart:_handleSave`) rather than pasting full theming boilerplate — this is deliberate (match existing chrome), not a TODO. All bloc/data tasks carry complete code.

**Type consistency:** Events (`AddPanel`/`RemovePanel`/`RenamePanel`/`SetActivePanel`/`ReorderPanels`/`MoveTabToPanel`/`MoveTabToNewPanel`), entity (`PanelEntity` fields id/name/tabs/activeTabId), model (`PanelModel` HiveFields 0–3 + `toEntity(Map)`/`fromEntity`), repo methods (`getPanels`/`getActivePanelId`/`putPanel`/`deletePanels`/`savePanelMeta`), and bloc helpers (`_derive`/`_activePanel`/`_findTab`/`_replacePanel`/`_replaceTabAcrossPanels`/`_ensureNonEmpty`/`_nextPanelName`/`_persistPanel`/`_persistPanelMeta`/`_detachTab`) are named identically across all tasks.
