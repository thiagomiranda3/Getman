# Collection-scoped Variables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any folder in the collections tree define its own `{{variables}}` (with secret flags), inherited by the requests inside it, overlaid by the active global environment at send time.

**Architecture:** Variables live on `CollectionNodeEntity` (Hive `typeId 3`). A request resolves variables from every ancestor folder on its path (deepest folder wins), then the active environment overlays that (environment wins). The send pipeline is untouched — dispatch sites just hand it a richer `Map<String,String>` computed by a new pure `RequestVariableResolver`. A `CollectionVariablesDialog` (reusing `KeyValueListEditor`) edits them from a folder's "VARIABLES" menu item.

**Tech Stack:** Flutter, `flutter_bloc`, `hive_ce` (+ `hive_ce_generator`), `equatable`, `bloc_test` + `mocktail` (tests). Design spec: `docs/superpowers/specs/2026-06-16-collection-scoped-variables-design.md`.

## Global Constraints

- Always invoke Flutter/Dart via **`fvm`** (`fvm flutter ...`, `fvm dart ...`), never plain `flutter`/`dart`.
- **Done-bar (run before claiming any task done):** all of `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib` report **0 issues**, `fvm dart format lib test tools` is clean, and `fvm flutter test` is 100% green. These are independent passes — a clean `analyze` does NOT imply the others.
- All imports are `package:getman/...` (no relative imports).
- **Never hardcode** sizes/colors/radii/weights in widgets — pull from `context.appLayout` / `appPalette` / `appShape` / `appTypography` / `appDecoration`.
- **Never renumber an existing Hive `typeId`.** New `CollectionNode` fields use `@HiveField(8)` and `@HiveField(9)`; next free becomes 10.
- After any `@HiveField`/`@HiveType` change, regenerate with `fvm dart run build_runner build --delete-conflicting-outputs` and commit the regenerated `.g.dart`.
- Domain layer (`domain/`) imports only pure Dart + `equatable` — no Flutter, no Hive, no `data/`.
- BLoCs use `dart:developer` `log(...)`, never `debugPrint`/`print`.
- Resolution precedence (lowest→highest): **collection layer (deepest folder wins) → active environment → dynamic `{{$...}}` vars.** History keeps the templated (unresolved) config — never resolve in the history write path.
- Keep the GitHub wiki in sync (Task 11).

---

### Task 1: Data model — `variables` + `secretKeys` on node entity & Hive model

**Files:**
- Modify: `lib/features/collections/domain/entities/collection_node_entity.dart`
- Modify: `lib/features/collections/data/models/collection_node_model.dart`
- Regen: `lib/features/collections/data/models/collection_node_model.g.dart`
- Create: `test/features/collections/data/models/collection_node_model_test.dart`
- Modify: `CLAUDE.md` (typeId table note)

**Interfaces:**
- Produces: `CollectionNodeEntity.variables` (`Map<String,String>`, default `const {}`), `CollectionNodeEntity.secretKeys` (`Set<String>`, default `const {}`), both threaded through `copyWith`/`props`. `CollectionNode` Hive model fields `@HiveField(8) variables`, `@HiveField(9) secretKeys` (stored `List<String>`), round-tripped by `fromEntity`/`toEntity`.

- [ ] **Step 1: Write the failing model round-trip test**

Create `test/features/collections/data/models/collection_node_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

void main() {
  test('CollectionNode round-trips variables and secretKeys', () {
    const entity = CollectionNodeEntity(
      id: 'f1',
      name: 'API',
      variables: {'base_url': 'https://api.example.com', 'token': 'sk-1'},
      secretKeys: {'token'},
    );

    final restored = CollectionNode.fromEntity(entity).toEntity();

    expect(restored.variables, entity.variables);
    expect(restored.secretKeys, entity.secretKeys);
    expect(restored, entity); // Equatable includes the new fields
  });

  test('CollectionNodeEntity.copyWith replaces variables and secretKeys', () {
    const entity = CollectionNodeEntity(id: 'f1', name: 'API');
    final next = entity.copyWith(
      variables: {'k': 'v'},
      secretKeys: {'k'},
    );
    expect(next.variables, {'k': 'v'});
    expect(next.secretKeys, {'k'});
    expect(entity.variables, isEmpty); // original untouched
  });
}
```

- [ ] **Step 2: Run the test, verify it fails to compile**

Run: `fvm flutter test test/features/collections/data/models/collection_node_model_test.dart`
Expected: FAIL — `The named parameter 'variables' isn't defined`.

- [ ] **Step 3: Add the fields to the entity**

In `lib/features/collections/domain/entities/collection_node_entity.dart`, add constructor params, fields, `copyWith` params/usage, and `props`:

```dart
  const CollectionNodeEntity({
    required this.id,
    required this.name,
    this.isFolder = true,
    this.children = const [],
    this.config,
    this.isFavorite = false,
    this.description,
    this.examples = const [],
    this.variables = const {},
    this.secretKeys = const {},
  });
```

Add fields after `examples`:

```dart
  /// Collection-scoped variables for a folder. A request inherits the merge of
  /// every ancestor folder's variables (deepest wins), overlaid by the active
  /// environment at send time. Empty for leaf (request) nodes.
  final Map<String, String> variables;

  /// Names within [variables] flagged secret (masked in the editor + on export).
  final Set<String> secretKeys;
```

Add to `copyWith` params and body:

```dart
  CollectionNodeEntity copyWith({
    String? name,
    bool? isFolder,
    List<CollectionNodeEntity>? children,
    HttpRequestConfigEntity? config,
    bool? isFavorite,
    String? description,
    List<SavedExampleEntity>? examples,
    Map<String, String>? variables,
    Set<String>? secretKeys,
  }) {
    return CollectionNodeEntity(
      id: id,
      name: name ?? this.name,
      isFolder: isFolder ?? this.isFolder,
      children: children ?? this.children,
      config: config ?? this.config,
      isFavorite: isFavorite ?? this.isFavorite,
      description: description ?? this.description,
      examples: examples ?? this.examples,
      variables: variables ?? this.variables,
      secretKeys: secretKeys ?? this.secretKeys,
    );
  }
```

Add both to `props`:

```dart
  @override
  List<Object?> get props => [
    id,
    name,
    isFolder,
    children,
    config,
    isFavorite,
    description,
    examples,
    variables,
    secretKeys,
  ];
```

- [ ] **Step 4: Add the fields to the Hive model**

In `lib/features/collections/data/models/collection_node_model.dart`, add constructor params (after `examples`), `fromEntity` mapping, the two `@HiveField`s, and `toEntity` mapping.

Constructor:

```dart
  CollectionNode({
    required this.name,
    String? id,
    this.isFolder = true,
    List<CollectionNode>? children,
    this.config,
    this.isFavorite = false,
    this.description,
    List<SavedExampleModel>? examples,
    Map<String, String>? variables,
    List<String>? secretKeys,
  }) : id = id ?? const Uuid().v4(),
       children = children ?? [],
       examples = examples ?? [],
       variables = variables ?? {},
       secretKeys = secretKeys ?? [];
```

`fromEntity` (add the two trailing args):

```dart
        examples: entity.examples.map(SavedExampleModel.fromEntity).toList(),
        variables: Map<String, String>.from(entity.variables),
        secretKeys: entity.secretKeys.toList(),
      );
```

Fields (after `examples` at HiveField 7):

```dart
  @HiveField(8)
  Map<String, String> variables;

  @HiveField(9)
  List<String> secretKeys;
```

`toEntity` (add the two trailing args):

```dart
    examples: examples.map((e) => e.toEntity()).toList(),
    variables: Map<String, String>.from(variables),
    secretKeys: secretKeys.toSet(),
  );
```

- [ ] **Step 5: Regenerate the Hive adapter**

Run: `fvm dart run build_runner build --delete-conflicting-outputs`
Expected: succeeds; `collection_node_model.g.dart` now reads/writes fields 8 and 9.

- [ ] **Step 6: Run the test, verify it passes**

Run: `fvm flutter test test/features/collections/data/models/collection_node_model_test.dart`
Expected: PASS (both tests).

- [ ] **Step 7: Update CLAUDE.md typeId note**

In `CLAUDE.md` §3, update the `CollectionNode` row to mention the new fields and bump "next free". Change the typeId-3 Notes cell to end with:
`... List<SavedExampleModel> examples at HiveField(7); Map<String,String> variables at HiveField(8); List<String> secretKeys at HiveField(9) (next free: 10)`.

- [ ] **Step 8: Run the full done-bar and commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`
Expected: 0 analyzer/lint issues, format clean, all tests green.

```bash
git add lib/features/collections/domain/entities/collection_node_entity.dart \
        lib/features/collections/data/models/collection_node_model.dart \
        lib/features/collections/data/models/collection_node_model.g.dart \
        test/features/collections/data/models/collection_node_model_test.dart \
        CLAUDE.md
git commit -m "feat(collections): add variables + secretKeys to collection node model"
```

---

### Task 2: Pure tree logic — `setVariablesInTree` + `collectVariables`

**Files:**
- Modify: `lib/features/collections/domain/logic/collections_tree_helper.dart`
- Modify: `test/collections_tree_helper_test.dart`

**Interfaces:**
- Consumes: `CollectionNodeEntity.variables` / `secretKeys` (Task 1).
- Produces:
  - `CollectionsTreeHelper.setVariablesInTree(List<CollectionNodeEntity> nodes, String id, Map<String,String> variables, Set<String> secretKeys) → List<CollectionNodeEntity>`
  - `CollectionsTreeHelper.collectVariables(List<CollectionNodeEntity> nodes, String leafId) → ({Map<String,String> variables, Set<String> secretKeys})` — root→leaf merge, deepest wins, winning layer decides secret-ness; empty maps if `leafId` missing.

- [ ] **Step 1: Write the failing tests**

Append to `test/collections_tree_helper_test.dart` inside `void main()` (add a new `group`):

```dart
  group('variables', () {
    CollectionNodeEntity folderWithVars(
      String id,
      String name, {
      Map<String, String> variables = const {},
      Set<String> secretKeys = const {},
      List<CollectionNodeEntity> children = const [],
    }) => CollectionNodeEntity(
      id: id,
      name: name,
      variables: variables,
      secretKeys: secretKeys,
      children: children,
    );

    test('setVariablesInTree replaces both maps on the target node', () {
      final tree = [folderWithVars('f1', 'API')];
      final next = CollectionsTreeHelper.setVariablesInTree(
        tree,
        'f1',
        {'base': 'x'},
        {'base'},
      );
      final node = CollectionsTreeHelper.findNode(next, 'f1')!;
      expect(node.variables, {'base': 'x'});
      expect(node.secretKeys, {'base'});
      // input untouched (pure)
      expect(tree.first.variables, isEmpty);
    });

    test('collectVariables merges ancestors, deepest folder wins', () {
      final leaf = CollectionNodeEntity(id: 'L', name: 'req', isFolder: false);
      final inner = folderWithVars(
        'f2',
        'inner',
        variables: {'b': '20', 'c': '3'},
        secretKeys: {'c'},
        children: [leaf],
      );
      final outer = folderWithVars(
        'f1',
        'outer',
        variables: {'a': '1', 'b': '2'},
        secretKeys: {'b'},
        children: [inner],
      );

      final r = CollectionsTreeHelper.collectVariables([outer], 'L');

      expect(r.variables, {'a': '1', 'b': '20', 'c': '3'});
      // b overridden by a non-secret deeper layer -> no longer secret; c secret.
      expect(r.secretKeys, {'c'});
    });

    test('collectVariables returns empty maps for a missing id', () {
      final r = CollectionsTreeHelper.collectVariables(const [], 'nope');
      expect(r.variables, isEmpty);
      expect(r.secretKeys, isEmpty);
    });
  });
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `fvm flutter test test/collections_tree_helper_test.dart`
Expected: FAIL — `setVariablesInTree`/`collectVariables` not defined.

- [ ] **Step 3: Implement the helpers**

In `lib/features/collections/domain/logic/collections_tree_helper.dart`, add after `describeInTree` (uses the existing `_updateNodeById`):

```dart
  /// Sets the collection-scoped [variables] + [secretKeys] on the node with
  /// [id]. No-op if the id is missing.
  static List<CollectionNodeEntity> setVariablesInTree(
    List<CollectionNodeEntity> nodes,
    String id,
    Map<String, String> variables,
    Set<String> secretKeys,
  ) => _updateNodeById(
    nodes,
    id,
    (node) => node.copyWith(variables: variables, secretKeys: secretKeys),
  );

  /// Merges the variables of every node on the path from a root down to
  /// [leafId] (root first, deepest last) — the deepest layer wins on name
  /// clashes, and the layer that supplies the winning value decides whether the
  /// name is secret. Returns empty maps if [leafId] is not found.
  static ({Map<String, String> variables, Set<String> secretKeys})
  collectVariables(List<CollectionNodeEntity> nodes, String leafId) {
    final path = _pathTo(nodes, leafId);
    if (path == null) {
      return (variables: const {}, secretKeys: const {});
    }
    final variables = <String, String>{};
    final secretKeys = <String>{};
    for (final node in path) {
      node.variables.forEach((key, value) {
        variables[key] = value;
        if (node.secretKeys.contains(key)) {
          secretKeys.add(key);
        } else {
          secretKeys.remove(key);
        }
      });
    }
    return (variables: variables, secretKeys: secretKeys);
  }

  /// The chain of nodes from a root down to and including the node with [id],
  /// or null if not found.
  static List<CollectionNodeEntity>? _pathTo(
    List<CollectionNodeEntity> nodes,
    String id,
  ) {
    for (final node in nodes) {
      if (node.id == id) return [node];
      final sub = _pathTo(node.children, id);
      if (sub != null) return [node, ...sub];
    }
    return null;
  }
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `fvm flutter test test/collections_tree_helper_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the done-bar and commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`

```bash
git add lib/features/collections/domain/logic/collections_tree_helper.dart \
        test/collections_tree_helper_test.dart
git commit -m "feat(collections): tree helpers for setting + collecting node variables"
```

---

### Task 3: `RequestVariableResolver` — merge collection layer under the environment

**Files:**
- Create: `lib/core/utils/request_variable_resolver.dart`
- Create: `test/core/utils/request_variable_resolver_test.dart`

**Interfaces:**
- Consumes: `CollectionsTreeHelper.collectVariables` (Task 2); `ActiveEnvironmentHelper.variablesFor` (existing); `EnvironmentEntity`, `CollectionNodeEntity`.
- Produces: `RequestVariableResolver.variablesFor({required List<EnvironmentEntity> environments, required String? activeEnvironmentId, required List<CollectionNodeEntity> collections, required String? collectionNodeId}) → Map<String,String>` — collection layer overlaid by env (env wins).

- [ ] **Step 1: Write the failing test**

Create `test/core/utils/request_variable_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/request_variable_resolver.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

void main() {
  CollectionNodeEntity leaf(String id) =>
      CollectionNodeEntity(id: id, name: 'r', isFolder: false);

  final tree = [
    CollectionNodeEntity(
      id: 'f1',
      name: 'API',
      variables: const {'base': 'collection', 'only_c': 'c'},
      children: [leaf('L')],
    ),
  ];

  final envs = [
    EnvironmentEntity(
      id: 'e1',
      name: 'Prod',
      variables: const {'base': 'env', 'only_e': 'e'},
    ),
  ];

  test('environment overlays collection (env wins on clash)', () {
    final r = RequestVariableResolver.variablesFor(
      environments: envs,
      activeEnvironmentId: 'e1',
      collections: tree,
      collectionNodeId: 'L',
    );
    expect(r['base'], 'env'); // env wins
    expect(r['only_c'], 'c'); // collection-only survives
    expect(r['only_e'], 'e'); // env-only survives
  });

  test('no active environment -> collection layer only', () {
    final r = RequestVariableResolver.variablesFor(
      environments: envs,
      activeEnvironmentId: null,
      collections: tree,
      collectionNodeId: 'L',
    );
    expect(r, {'base': 'collection', 'only_c': 'c'});
  });

  test('unlinked tab (null node id) -> environment only', () {
    final r = RequestVariableResolver.variablesFor(
      environments: envs,
      activeEnvironmentId: 'e1',
      collections: tree,
      collectionNodeId: null,
    );
    expect(r, {'base': 'env', 'only_e': 'e'});
  });

  test('neither layer -> empty', () {
    final r = RequestVariableResolver.variablesFor(
      environments: const [],
      activeEnvironmentId: null,
      collections: const [],
      collectionNodeId: null,
    );
    expect(r, isEmpty);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `fvm flutter test test/core/utils/request_variable_resolver_test.dart`
Expected: FAIL — target of URI doesn't exist.

- [ ] **Step 3: Implement the resolver**

Create `lib/core/utils/request_variable_resolver.dart`:

```dart
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';

/// Computes the variable map that applies to a request: the collection layer
/// (merge of the request's ancestor folders, deepest wins) overlaid by the
/// active environment (environment wins). Pure Dart — lives in core/utils
/// beside the Postman mappers, which likewise bridge feature entities.
class RequestVariableResolver {
  const RequestVariableResolver._();

  static Map<String, String> variablesFor({
    required List<EnvironmentEntity> environments,
    required String? activeEnvironmentId,
    required List<CollectionNodeEntity> collections,
    required String? collectionNodeId,
  }) {
    final env = ActiveEnvironmentHelper.variablesFor(
      environments,
      activeEnvironmentId,
    );
    if (collectionNodeId == null) return env;
    final collection = CollectionsTreeHelper.collectVariables(
      collections,
      collectionNodeId,
    ).variables;
    if (collection.isEmpty) return env;
    return {...collection, ...env};
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `fvm flutter test test/core/utils/request_variable_resolver_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the done-bar and commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`

```bash
git add lib/core/utils/request_variable_resolver.dart \
        test/core/utils/request_variable_resolver_test.dart
git commit -m "feat(core): RequestVariableResolver merges collection vars under env"
```

---

### Task 4: `classifyLayered` — hover tooltip understands the collection layer

**Files:**
- Modify: `lib/core/utils/variable_resolution_helper.dart`
- Modify: `test/core/utils/variable_resolution_helper_test.dart`

**Interfaces:**
- Consumes: existing `ResolvedVariable`, `VariableValueKind`, `EnvironmentResolver`.
- Produces: `VariableResolutionHelper.classifyLayered({required String name, required Map<String,String> collectionVariables, required Set<String> collectionSecrets, required Map<String,String> environmentVariables, required Set<String> environmentSecrets, required String? environmentName}) → ResolvedVariable`. A collection-sourced value sets `environmentName` to the literal `'Collection'` so the existing popover renders `from Collection`. Environment wins over collection; dynamic vars are the final fallback.

- [ ] **Step 1: Write the failing tests**

Append a new group to `test/core/utils/variable_resolution_helper_test.dart`:

```dart
  group('VariableResolutionHelper.classifyLayered', () {
    test('environment value wins over collection', () {
      final r = VariableResolutionHelper.classifyLayered(
        name: 'base',
        collectionVariables: const {'base': 'collection'},
        collectionSecrets: const {},
        environmentVariables: const {'base': 'env'},
        environmentSecrets: const {},
        environmentName: 'Prod',
      );
      expect(r.kind, VariableValueKind.resolved);
      expect(r.value, 'env');
      expect(r.environmentName, 'Prod');
    });

    test('collection-only value resolves with Collection source', () {
      final r = VariableResolutionHelper.classifyLayered(
        name: 'only_c',
        collectionVariables: const {'only_c': 'c'},
        collectionSecrets: const {},
        environmentVariables: const {},
        environmentSecrets: const {},
        environmentName: 'Prod',
      );
      expect(r.kind, VariableValueKind.resolved);
      expect(r.value, 'c');
      expect(r.environmentName, 'Collection');
    });

    test('collection secret is masked as secret kind', () {
      final r = VariableResolutionHelper.classifyLayered(
        name: 'tok',
        collectionVariables: const {'tok': 's3cret'},
        collectionSecrets: const {'tok'},
        environmentVariables: const {},
        environmentSecrets: const {},
        environmentName: null,
      );
      expect(r.kind, VariableValueKind.secret);
      expect(r.value, 's3cret');
      expect(r.environmentName, 'Collection');
    });

    test('unknown name falls back to dynamic then unresolved', () {
      final dyn = VariableResolutionHelper.classifyLayered(
        name: r'$guid',
        collectionVariables: const {},
        collectionSecrets: const {},
        environmentVariables: const {},
        environmentSecrets: const {},
        environmentName: 'Prod',
      );
      expect(dyn.kind, VariableValueKind.dynamicValue);

      final missing = VariableResolutionHelper.classifyLayered(
        name: 'nope',
        collectionVariables: const {},
        collectionSecrets: const {},
        environmentVariables: const {},
        environmentSecrets: const {},
        environmentName: 'Prod',
      );
      expect(missing.kind, VariableValueKind.unresolved);
    });
  });
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `fvm flutter test test/core/utils/variable_resolution_helper_test.dart`
Expected: FAIL — `classifyLayered` not defined.

- [ ] **Step 3: Implement `classifyLayered`**

In `lib/core/utils/variable_resolution_helper.dart`, add inside `VariableResolutionHelper` (after `classify`):

```dart
  /// Like [classify] but aware of both layers: the active environment overrides
  /// the collection layer (env wins). A collection-sourced value reports its
  /// source as `'Collection'` via [ResolvedVariable.environmentName] so the
  /// hover tooltip renders `from Collection`.
  static ResolvedVariable classifyLayered({
    required String name,
    required Map<String, String> collectionVariables,
    required Set<String> collectionSecrets,
    required Map<String, String> environmentVariables,
    required Set<String> environmentSecrets,
    required String? environmentName,
  }) {
    if (environmentVariables.containsKey(name)) {
      return ResolvedVariable(
        name: name,
        kind: environmentSecrets.contains(name)
            ? VariableValueKind.secret
            : VariableValueKind.resolved,
        value: environmentVariables[name],
        environmentName: environmentName,
      );
    }
    if (collectionVariables.containsKey(name)) {
      return ResolvedVariable(
        name: name,
        kind: collectionSecrets.contains(name)
            ? VariableValueKind.secret
            : VariableValueKind.resolved,
        value: collectionVariables[name],
        environmentName: 'Collection',
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
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `fvm flutter test test/core/utils/variable_resolution_helper_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the done-bar and commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`

```bash
git add lib/core/utils/variable_resolution_helper.dart \
        test/core/utils/variable_resolution_helper_test.dart
git commit -m "feat(core): classifyLayered for collection-aware variable tooltip"
```

---

### Task 5: `UpdateNodeVariables` event + bloc handler

**Files:**
- Modify: `lib/features/collections/presentation/bloc/collections_event.dart`
- Modify: `lib/features/collections/presentation/bloc/collections_bloc.dart`
- Modify: `test/features/collections/presentation/bloc/collections_bloc_test.dart`

**Interfaces:**
- Consumes: `CollectionsTreeHelper.setVariablesInTree` (Task 2); existing `_commit`, `findNode`.
- Produces: `UpdateNodeVariables(String id, Map<String,String> variables, Set<String> secretKeys)` event; handler `_onUpdateNodeVariables` registered in the bloc constructor.

- [ ] **Step 1: Write the failing bloc test**

Append to `void main()` in `test/features/collections/presentation/bloc/collections_bloc_test.dart` (the file already defines `folder(...)`, `leaf(...)`, `build(...)`, `repo`):

```dart
  group('UpdateNodeVariables', () {
    blocTest<CollectionsBloc, CollectionsState>(
      'sets variables + secretKeys on the target folder',
      build: build,
      seed: () => CollectionsState(
        collections: [folder('f1', 'API')],
      ),
      act: (bloc) => bloc.add(
        const UpdateNodeVariables('f1', {'base': 'x'}, {'base'}),
      ),
      expect: () => [
        isA<CollectionsState>().having(
          (s) => CollectionsTreeHelper.findNode(s.collections, 'f1')!.variables,
          'variables',
          {'base': 'x'},
        ),
      ],
    );

    blocTest<CollectionsBloc, CollectionsState>(
      'is a no-op for an unknown id',
      build: build,
      seed: () => CollectionsState(collections: [folder('f1', 'API')]),
      act: (bloc) =>
          bloc.add(const UpdateNodeVariables('ghost', {'a': 'b'}, {})),
      expect: () => const <CollectionsState>[],
    );
  });
```

If `blocTest`/`CollectionsState` are not already imported in this file, add:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
```

(Confirm against the file's existing imports before adding — do not duplicate.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `fvm flutter test test/features/collections/presentation/bloc/collections_bloc_test.dart`
Expected: FAIL — `UpdateNodeVariables` undefined.

- [ ] **Step 3: Add the event**

In `lib/features/collections/presentation/bloc/collections_event.dart`, add after `UpdateNodeDescription`:

```dart
/// Sets the collection-scoped variables (and their secret flags) on a folder.
class UpdateNodeVariables extends CollectionsEvent {
  const UpdateNodeVariables(this.id, this.variables, this.secretKeys);
  final String id;
  final Map<String, String> variables;
  final Set<String> secretKeys;
  @override
  List<Object?> get props => [id, variables, secretKeys];
}
```

- [ ] **Step 4: Register + implement the handler**

In `lib/features/collections/presentation/bloc/collections_bloc.dart`, add the registration next to `on<UpdateNodeDescription>(...)`:

```dart
    on<UpdateNodeVariables>(_onUpdateNodeVariables);
```

Add the handler beside `_onUpdateNodeDescription`:

```dart
  Future<void> _onUpdateNodeVariables(
    UpdateNodeVariables event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.id) == null) {
      return Future.value();
    }
    return _commit(
      emit,
      CollectionsTreeHelper.setVariablesInTree(
        state.collections,
        event.id,
        event.variables,
        event.secretKeys,
      ),
    );
  }
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `fvm flutter test test/features/collections/presentation/bloc/collections_bloc_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the done-bar and commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`

```bash
git add lib/features/collections/presentation/bloc/collections_event.dart \
        lib/features/collections/presentation/bloc/collections_bloc.dart \
        test/features/collections/presentation/bloc/collections_bloc_test.dart
git commit -m "feat(collections): UpdateNodeVariables event + handler"
```

---

### Task 6: `CollectionVariablesDialog`

**Files:**
- Create: `lib/features/collections/presentation/widgets/collection_variables_dialog.dart`
- Create: `test/features/collections/presentation/widgets/collection_variables_dialog_test.dart`

**Interfaces:**
- Consumes: `UpdateNodeVariables` (Task 5); `KeyValueListEditor`, `ResponsiveDialogScaffold`, `stringMapEquality`.
- Produces: `CollectionVariablesDialog` widget + `CollectionVariablesDialog.show(BuildContext, CollectionNodeEntity)`. On SAVE it dispatches `UpdateNodeVariables(node.id, variables, secretKeys)` (secretKeys pruned to live keys) on the `CollectionsBloc` read from context, then closes.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/collections/presentation/widgets/collection_variables_dialog_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/collections/presentation/widgets/collection_variables_dialog.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

void main() {
  testWidgets('SAVE dispatches UpdateNodeVariables for the node', (
    tester,
  ) async {
    final bloc = MockCollectionsBloc();
    when(() => bloc.state).thenReturn(const CollectionsState());

    const node = CollectionNodeEntity(
      id: 'f1',
      name: 'API',
      variables: {'base': 'x'},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
        home: BlocProvider<CollectionsBloc>.value(
          value: bloc,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      CollectionVariablesDialog.show(context, node),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    final captured = verify(() => bloc.add(captureAny())).captured;
    final event = captured.whereType<UpdateNodeVariables>().single;
    expect(event.id, 'f1');
    expect(event.variables, {'base': 'x'});
  });
}
```

(Confirm the `resolveTheme` signature against `lib/core/theme/theme_registry.dart`; adjust the builder call if it differs.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/collection_variables_dialog_test.dart`
Expected: FAIL — target of URI doesn't exist.

- [ ] **Step 3: Implement the dialog**

Create `lib/features/collections/presentation/widgets/collection_variables_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';

/// Editor for a folder's collection-scoped variables (with per-row secret
/// toggles). Local state is committed on SAVE via [UpdateNodeVariables].
class CollectionVariablesDialog extends StatefulWidget {
  const CollectionVariablesDialog({required this.node, super.key});
  final CollectionNodeEntity node;

  static Future<void> show(BuildContext context, CollectionNodeEntity node) {
    return showResponsiveDialog<void>(
      context,
      builder: (_) => CollectionVariablesDialog(node: node),
    );
  }

  @override
  State<CollectionVariablesDialog> createState() =>
      _CollectionVariablesDialogState();
}

class _CollectionVariablesDialogState extends State<CollectionVariablesDialog> {
  late Map<String, String> _variables;
  late Set<String> _secretKeys;

  @override
  void initState() {
    super.initState();
    _variables = Map<String, String>.from(widget.node.variables);
    _secretKeys = Set<String>.from(widget.node.secretKeys);
  }

  void _save() {
    final bloc = context.read<CollectionsBloc>();
    Navigator.pop(context);
    bloc.add(
      UpdateNodeVariables(
        widget.node.id,
        _variables,
        // Never persist secret flags for variables that no longer exist.
        _secretKeys.intersection(_variables.keys.toSet()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ResponsiveDialogScaffold(
      title: Text('VARIABLES — ${widget.node.name}'),
      content: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: layout.dialogMaxHeight),
          child: KeyValueListEditor<Map<String, String>>(
            items: _variables,
            fieldPrefix: 'collection_var',
            decode: (variables) => [
              for (final e in variables.entries) (e.key, e.value),
            ],
            encode: (rows) => {
              for (final (key, value) in rows)
                if (key.trim().isNotEmpty) key.trim(): value,
            },
            equals: stringMapEquality.equals,
            secretKeys: _secretKeys,
            onSecretKeysChanged: (keys) => setState(() => _secretKeys = keys),
            onChanged: (variables) => setState(() {
              _variables = variables;
              _secretKeys = _secretKeys.intersection(variables.keys.toSet());
            }),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(onPressed: _save, child: const Text('SAVE')),
      ],
    );
  }
}
```

NOTE: if `layout.dialogMaxHeight` does not exist on `AppLayout`, replace the `ConstrainedBox` constraint with an existing sizing field (e.g. wrap the editor in `SizedBox(height: 320, ...)`) rather than hardcoding — check `lib/core/theme/app_theme.dart` for the available `AppLayout` fields and pick the closest existing one. The `KeyValueListEditor` needs a bounded height because it builds a scrollable list.

- [ ] **Step 4: Run the test, verify it passes**

Run: `fvm flutter test test/features/collections/presentation/widgets/collection_variables_dialog_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the done-bar and commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`

```bash
git add lib/features/collections/presentation/widgets/collection_variables_dialog.dart \
        test/features/collections/presentation/widgets/collection_variables_dialog_test.dart
git commit -m "feat(collections): CollectionVariablesDialog editor"
```

---

### Task 7: "VARIABLES" entry points (desktop menu + phone action sheet)

**Files:**
- Modify: `lib/features/collections/presentation/widgets/collection_node_menu.dart`
- Modify: `lib/features/collections/presentation/widgets/node_action_sheet.dart`

**Interfaces:**
- Consumes: `CollectionVariablesDialog.show` (Task 6). Both entry points are shown only when `node.isFolder`.

This task has no new unit test (UI wiring of an existing, tested dialog); verification is the done-bar plus a manual smoke check.

- [ ] **Step 1: Add the desktop menu item**

In `lib/features/collections/presentation/widgets/collection_node_menu.dart`:

Add the import:

```dart
import 'package:getman/features/collections/presentation/widgets/collection_variables_dialog.dart';
```

Add a case in the `onSelected` switch (after the `'describe'` case):

```dart
          case 'variables':
            unawaited(CollectionVariablesDialog.show(context, node));
```

Add a `PopupMenuItem` in `itemBuilder` guarded by `node.isFolder` (place it after the `describe` item, before `add_subfolder`):

```dart
        if (node.isFolder)
          PopupMenuItem(
            value: 'variables',
            child: Text(
              'VARIABLES',
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
```

- [ ] **Step 2: Add the phone action-sheet item**

In `lib/features/collections/presentation/widgets/node_action_sheet.dart`:

Add the import:

```dart
import 'package:getman/features/collections/presentation/widgets/collection_variables_dialog.dart';
```

Add an `_Action` guarded by `node.isFolder` (place it after the `ADD SUBFOLDER` action):

```dart
          if (node.isFolder)
            _Action(
              icon: Icons.data_object,
              label: 'VARIABLES',
              onTap: () {
                Navigator.of(context).pop();
                unawaited(CollectionVariablesDialog.show(context, node));
              },
            ),
```

- [ ] **Step 3: Run the done-bar**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`
Expected: 0 issues, all green.

- [ ] **Step 4: Manual smoke check**

Run: `fvm flutter run -d macos`. Right-click (desktop) a folder → **VARIABLES** opens the dialog; add `base = https://x`, SAVE; reopen to confirm it persisted. Repeat on the phone layout (narrow window) via the action sheet.

- [ ] **Step 5: Commit**

```bash
git add lib/features/collections/presentation/widgets/collection_node_menu.dart \
        lib/features/collections/presentation/widgets/node_action_sheet.dart
git commit -m "feat(collections): VARIABLES entry point in node menu + action sheet"
```

---

### Task 8: Wire dispatch sites to the merged resolver

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/url_bar.dart`
- Modify: `lib/features/home/presentation/screens/main_screen.dart`

**Interfaces:**
- Consumes: `RequestVariableResolver.variablesFor` (Task 3); `VariableResolutionHelper.classifyLayered` (Task 4); `CollectionsTreeHelper.collectVariables` (Task 2).

The merge logic is unit-tested in Tasks 2–4; this task is mechanical wiring. Verification is the done-bar (existing tests must stay green) plus a manual send-with-collection-var check. `RealtimeButton` needs **no change** — it receives the already-merged `activeVars` from `url_bar`'s `_activeVariables`.

- [ ] **Step 1: Update `url_bar` imports**

In `lib/features/tabs/presentation/widgets/url_bar.dart`, add (alongside the existing env imports):

```dart
import 'package:getman/core/utils/request_variable_resolver.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
```

(`ActiveEnvironmentHelper` and `VariableResolutionHelper` are already imported; keep them.)

- [ ] **Step 2: Merge the collection layer into `_activeVariables`**

Replace the body of `_activeVariables` (currently returns `ActiveEnvironmentHelper.variablesFor(...)`):

```dart
  Map<String, String> _activeVariables(BuildContext context) {
    final envState = context.read<EnvironmentsBloc>().state;
    final settings = context.read<SettingsBloc>().state.settings;
    final collections = context.read<CollectionsBloc>().state.collections;
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    return RequestVariableResolver.variablesFor(
      environments: envState.environments,
      activeEnvironmentId: settings.activeEnvironmentId,
      collections: collections,
      collectionNodeId: tab?.collectionNodeId,
    );
  }
```

This is consumed by the SEND button, the highlighter (`_syncHighlight` → `updateVariables`), and `RealtimeButton`'s `activeVars` — all three now see collection vars automatically.

- [ ] **Step 3: Make the hover popover collection-aware**

Replace the body of `_showVariablePopover` so it classifies through both layers:

```dart
  void _showVariablePopover(String name, Offset globalPosition) {
    if (!mounted) return;
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
    final data = VariableResolutionHelper.classifyLayered(
      name: name,
      collectionVariables: collected.variables,
      collectionSecrets: collected.secretKeys,
      environmentVariables: env?.variables ?? const {},
      environmentSecrets: env?.secretKeys ?? const {},
      environmentName: env?.name,
    );
    _hoverController.showFor(context, data, globalPosition);
  }
```

- [ ] **Step 4: Update `main_screen`'s `SendRequestIntent`**

In `lib/features/home/presentation/screens/main_screen.dart`, add the import:

```dart
import 'package:getman/core/utils/request_variable_resolver.dart';
```

(`CollectionsBloc` is already imported — see its use near line 122.) Replace the `envVars` computation inside the `SendRequestIntent` callback:

```dart
                      final envVars = RequestVariableResolver.variablesFor(
                        environments:
                            context.read<EnvironmentsBloc>().state.environments,
                        activeEnvironmentId: context
                            .read<SettingsBloc>()
                            .state
                            .settings
                            .activeEnvironmentId,
                        collections:
                            context.read<CollectionsBloc>().state.collections,
                        collectionNodeId:
                            tabs[activeIndex].collectionNodeId,
                      );
```

If `ActiveEnvironmentHelper` is now unused in `main_screen.dart`, remove its import (the analyzer flags unused imports under `very_good_analysis`).

- [ ] **Step 5: Run the done-bar**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`
Expected: 0 issues, all green.

- [ ] **Step 6: Manual end-to-end check**

Run: `fvm flutter run -d macos`. Create a folder, set `base = https://httpbin.org` in its VARIABLES, save a request `{{base}}/get` inside it, and SEND with **No Environment** active → it resolves to httpbin. Then select an environment that also defines `base` → the environment value wins (Postman precedence). Hover `{{base}}` with no env → tooltip reads `from Collection`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/tabs/presentation/widgets/url_bar.dart \
        lib/features/home/presentation/screens/main_screen.dart
git commit -m "feat(tabs): resolve collection variables at send + highlight + hover"
```

---

### Task 9: Postman v2.1 import/export of collection + folder variables

**Files:**
- Modify: `lib/core/utils/postman/postman_collection_mapper.dart`
- Modify: `test/core/utils/postman/postman_collection_mapper_test.dart`

**Interfaces:**
- Consumes: `CollectionNodeEntity.variables`/`secretKeys` (Task 1).
- Produces: folder items gain a `variable` array; the root collection gains a top-level `variable` array; secrets export as `{key, value:'', type:'secret'}` and import back into `secretKeys`. `disabled == true` entries are skipped on import.

- [ ] **Step 1: Write the failing round-trip test**

Append to `test/core/utils/postman/postman_collection_mapper_test.dart` (new group in `void main()`):

```dart
  group('collection variables', () {
    test('round-trips folder + nested variables, masking secrets', () {
      const inner = CollectionNodeEntity(
        id: 'f2',
        name: 'inner',
        variables: {'token': 'sk-secret', 'page': '2'},
        secretKeys: {'token'},
      );
      const root = CollectionNodeEntity(
        id: 'f1',
        name: 'API',
        variables: {'base': 'https://api.example.com'},
        children: [inner],
      );

      final json = PostmanCollectionMapper.toJson(root);
      expect(json, contains('"variable"'));

      final restored = PostmanCollectionMapper.fromJson(json);

      // Root collection vars land on the imported root folder.
      expect(restored.variables['base'], 'https://api.example.com');

      final restoredInner = restored.children.firstWhere(
        (c) => c.name == 'inner',
      );
      expect(restoredInner.variables['page'], '2');
      // secret value is masked on export -> empty on import, key still secret.
      expect(restoredInner.variables['token'], '');
      expect(restoredInner.secretKeys, contains('token'));
    });
  });
```

(Adjust the `CollectionNodeEntity` import if the test file does not already import it.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `fvm flutter test test/core/utils/postman/postman_collection_mapper_test.dart`
Expected: FAIL — `variable` not emitted / `variables` empty after import.

- [ ] **Step 3: Add the export side**

In `lib/core/utils/postman/postman_collection_mapper.dart`:

Add a shared encoder helper (private static):

```dart
  static List<Map<String, dynamic>> _variablesToPostman(
    Map<String, String> variables,
    Set<String> secretKeys,
  ) {
    return [
      for (final e in variables.entries)
        if (secretKeys.contains(e.key))
          {'key': e.key, 'value': '', 'type': 'secret'}
        else
          {'key': e.key, 'value': e.value, 'type': 'default'},
    ];
  }
```

In `toJson`, add a top-level `variable` array when the root folder has vars. Replace the `collection` map literal with:

```dart
    final collection = <String, dynamic>{
      'info': {
        '_postman_id': _uuid.v4(),
        'name': rootNode.name,
        'schema': _schemaV21,
        '_exporter_id': 'getman',
      },
      'item': items,
    };
    if (rootNode.isFolder && rootNode.variables.isNotEmpty) {
      collection['variable'] = _variablesToPostman(
        rootNode.variables,
        rootNode.secretKeys,
      );
    }
    return const JsonEncoder.withIndent('  ').convert(collection);
```

In `_nodeToItem`, attach folder vars to folder items:

```dart
  static Map<String, dynamic> _nodeToItem(CollectionNodeEntity node) {
    if (node.isFolder) {
      final item = <String, dynamic>{
        'name': node.name,
        'item': node.children.map(_nodeToItem).toList(),
      };
      if (node.variables.isNotEmpty) {
        item['variable'] = _variablesToPostman(node.variables, node.secretKeys);
      }
      return item;
    }
    return {
      'name': node.name,
      'request': _configToRequest(node.config),
    };
  }
```

- [ ] **Step 4: Add the import side**

Add a shared decoder helper (private static):

```dart
  static ({Map<String, String> variables, Set<String> secretKeys})
  _variablesFromPostman(dynamic raw) {
    final variables = <String, String>{};
    final secretKeys = <String>{};
    if (raw is List) {
      for (final entry in raw.whereType<Map<dynamic, dynamic>>()) {
        if (entry['disabled'] == true) continue;
        final key = entry['key'];
        if (key is! String || key.isEmpty) continue;
        final value = entry['value'];
        variables[key] = value is String ? value : (value?.toString() ?? '');
        if (entry['type'] == 'secret') secretKeys.add(key);
      }
    }
    return (variables: variables, secretKeys: secretKeys);
  }
```

In `fromJson`, parse the top-level `variable` array onto the returned root folder:

```dart
    final vars = _variablesFromPostman(parsed['variable']);
    return CollectionNodeEntity(
      id: _uuid.v4(),
      name: name,
      children: children,
      variables: vars.variables,
      secretKeys: vars.secretKeys,
    );
```

In `_itemToNode`, for the folder branch (the `nestedItems is List` case), parse `item['variable']`:

```dart
    if (nestedItems is List) {
      final children = nestedItems
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => _itemToNode(m.cast<String, dynamic>()))
          .toList();
      final vars = _variablesFromPostman(item['variable']);
      return CollectionNodeEntity(
        id: _uuid.v4(),
        name: name,
        children: children,
        variables: vars.variables,
        secretKeys: vars.secretKeys,
      );
    }
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `fvm flutter test test/core/utils/postman/postman_collection_mapper_test.dart`
Expected: PASS (and the pre-existing mapper tests stay green).

- [ ] **Step 6: Run the done-bar and commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`

```bash
git add lib/core/utils/postman/postman_collection_mapper.dart \
        test/core/utils/postman/postman_collection_mapper_test.dart
git commit -m "feat(postman): import/export collection + folder variables"
```

---

### Task 10: Git workspace mirror round-trips folder variables

**Files:**
- Modify: `lib/core/utils/workspace/workspace_collection_serializer.dart`
- Modify: `test/core/utils/workspace/workspace_collection_serializer_test.dart`

**Interfaces:**
- Consumes: `CollectionNodeEntity.variables`/`secretKeys` (Task 1).
- Produces: `folderToJson` emits `variables` (secret values masked to empty) + `secretKeys`; `folderFromJson` reads them back. Non-secret values round-trip fully; secret values do not (documented limitation — avoids committing secrets to git).

- [ ] **Step 1: Write the failing test**

Append to `test/core/utils/workspace/workspace_collection_serializer_test.dart` (new group in `void main()`):

```dart
  group('folder variables', () {
    test('round-trips variables; masks secret values', () {
      const folder = CollectionNodeEntity(
        id: 'f1',
        name: 'API',
        variables: {'base': 'https://api.example.com', 'token': 'sk-secret'},
        secretKeys: {'token'},
      );

      final json = WorkspaceCollectionSerializer.folderToJson(folder, const []);
      final restored = WorkspaceCollectionSerializer.folderFromJson(
        json,
        const [],
      );

      expect(restored.variables['base'], 'https://api.example.com');
      expect(restored.variables['token'], ''); // secret masked
      expect(restored.secretKeys, contains('token'));
    });
  });
```

(Add the `CollectionNodeEntity` import to the test if absent.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `fvm flutter test test/core/utils/workspace/workspace_collection_serializer_test.dart`
Expected: FAIL — `variables` empty / `secretKeys` empty after round-trip.

- [ ] **Step 3: Update `folderToJson` / `folderFromJson`**

In `lib/core/utils/workspace/workspace_collection_serializer.dart`, change `folderToJson` to emit masked variables + secret keys when present:

```dart
  static Map<String, dynamic> folderToJson(
    CollectionNodeEntity folder,
    List<String> childOrder,
  ) {
    final json = <String, dynamic>{
      'id': folder.id,
      'name': folder.name,
      'isFavorite': folder.isFavorite,
      'childOrder': childOrder,
    };
    if (folder.variables.isNotEmpty) {
      // Secret values are masked to empty so secrets never land in git.
      json['variables'] = {
        for (final e in folder.variables.entries)
          e.key: folder.secretKeys.contains(e.key) ? '' : e.value,
      };
      if (folder.secretKeys.isNotEmpty) {
        json['secretKeys'] = folder.secretKeys.toList();
      }
    }
    return json;
  }
```

Change `folderFromJson` to read them back:

```dart
  static CollectionNodeEntity folderFromJson(
    Map<String, dynamic> json,
    List<CollectionNodeEntity> children,
  ) {
    final rawVars = json['variables'];
    final variables = rawVars is Map
        ? rawVars.map((k, v) => MapEntry('$k', v is String ? v : '${v ?? ''}'))
        : const <String, String>{};
    final secretKeys = ((json['secretKeys'] as List?) ?? const [])
        .map((e) => '$e')
        .toSet();
    return CollectionNodeEntity(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Folder',
      isFavorite: json['isFavorite'] == true,
      children: children,
      variables: variables,
      secretKeys: secretKeys,
    );
  }
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `fvm flutter test test/core/utils/workspace/workspace_collection_serializer_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the done-bar and commit**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`

```bash
git add lib/core/utils/workspace/workspace_collection_serializer.dart \
        test/core/utils/workspace/workspace_collection_serializer_test.dart
git commit -m "feat(workspace): round-trip folder variables (secrets masked)"
```

---

### Task 11: Wiki sync

**Files:**
- External repo: `Getman.wiki.git` (`https://github.com/thiagomiranda3/Getman.wiki.git`)

Per the §7 mandate, document the feature in the GitHub wiki as part of this work.

- [ ] **Step 1: Clone the wiki repo (outside the app repo)**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

- [ ] **Step 2: Edit the Environments page (and Collections page if present)**

In `/tmp/getman-wiki`, update the Environments page (e.g. `Environments.md`) and the Collections page with a "Collection variables" section. Use verbatim UI labels. Cover:
- Any folder can hold variables; open them via the folder's **VARIABLES** menu item (desktop) or action sheet (phone).
- A request inherits variables from **all** ancestor folders; the **deepest** folder wins on name clashes.
- The **active environment overrides** collection variables (`Environment > Collection`), matching Postman.
- Variables support the **secret** lock/reveal toggle, same as environment variables.
- Collection variables export/import with Postman v2.1 collections (secret values masked on export) and round-trip through the git workspace mirror (secret values masked there too).

If you add a new page, also add it to `_Sidebar.md`.

- [ ] **Step 3: Commit + push the wiki**

```bash
cd /tmp/getman-wiki
git add -A
git commit -m "docs: collection-scoped variables"
git push origin master
```

- [ ] **Step 4: Final full done-bar in the app repo**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`
Expected: 0 issues across all three analysis passes, format clean, all tests green.

---

## Self-Review

**Spec coverage:**
- Data model (entity + Hive field 8/9 + regen) → Task 1 ✓
- Nested merge / deepest-wins / secret tracking → Task 2 (`collectVariables`) ✓
- Env-overlays-collection precedence → Task 3 (`RequestVariableResolver`) ✓
- Highlight + hover source label → Task 4 (`classifyLayered`) + Task 8 ✓
- Editor UI + "VARIABLES" entry points → Tasks 6, 7 ✓
- `UpdateNodeVariables` event/handler → Task 5 ✓
- Send-time resolution at all 3 dispatch sites → Task 8 ✓
- Postman v2.1 import/export + secret masking → Task 9 ✓
- Git workspace mirror round-trip → Task 10 ✓
- Wiki → Task 11 ✓
- History keeps templated config → unchanged (send pipeline untouched) ✓

**Deviation from spec (intentional):** the spec's `RequestVariableResolver.secretKeysFor` is dropped — the hover tooltip gets its layers directly from `collectVariables` + the active environment and resolves secret-ness inside `classifyLayered`, so a separate merged-secrets accessor isn't needed. Source-label parity is achieved by reusing `ResolvedVariable.environmentName` (`'Collection'`) rather than adding a new field, so the popover widget needs no change.

**Placeholder scan:** none — every code step shows full code. Two guarded fallbacks are explicitly flagged for the implementer to confirm against the live API (`AppLayout.dialogMaxHeight` in Task 6; `resolveTheme` builder signature in the Task 6 test) — both name the file to check and a concrete fallback.

**Type consistency:** `collectVariables` returns `({Map<String,String> variables, Set<String> secretKeys})` and is consumed with `.variables` (Tasks 3, 8) and `.variables`/`.secretKeys` (Task 8 popover) consistently. `UpdateNodeVariables(id, variables, secretKeys)` positional signature is identical in the event (Task 5), bloc test (Task 5), and dialog (Task 6). `_variablesToPostman` / `_variablesFromPostman` (Task 9) and `RequestVariableResolver.variablesFor` named params match across definition and call sites.
