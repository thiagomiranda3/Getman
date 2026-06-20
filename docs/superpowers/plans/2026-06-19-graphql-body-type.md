# GraphQL Body Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `graphql` request body type that sends `{"query": ..., "variables": ...}` as JSON, edited through a dual-pane (query + variables) body editor.

**Architecture:** Reuse the existing `body` field for the GraphQL query; add one new `graphqlVariables` String field to the request config (entity + Hive model typeId 1, `@HiveField(15)`). Adding `graphql` to the `BodyType` enum is compile-forced across every exhaustive `switch (BodyType)` — Task 1 handles all of them (send serializer, content-type, code-gen, Postman export/import, workspace mirror) and keeps the option hidden from the UI; Task 2 adds the editor and makes it user-visible.

**Tech Stack:** Flutter, `flutter_bloc`, `hive_ce` + `hive_ce_generator`, `dio`, `re_editor` (`CodeLineEditingController`).

## Global Constraints

- Flutter SDK invoked as `fvm flutter ...` (pinned via `.fvmrc`) — never plain `flutter`.
- Imports are `package:getman/...` everywhere (no relative imports).
- Verification bar (all must pass before a task is "done"): `fvm flutter analyze` (0 issues), `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test` clean, `fvm flutter test` 100% green.
- After any `@HiveType`/`@HiveField` change: `dart run build_runner build --delete-conflicting-outputs`, then re-run analyze + tests. The model change is compile-affecting — verify with `fvm flutter test` (real CFE compile), not just analyze.
- Never renumber an existing Hive `typeId`/`HiveField`. Next free `HiveField` on `HttpRequestConfig` (typeId 1) is **15**.
- Theme mandates (CLAUDE.md §4.8): no hardcoded sizes/colors/radii/weights in widgets — pull from `context.appLayout` / `appPalette` / `appShape` / `appTypography`.
- One concern per commit; commit message format `type(scope): summary` (no Co-Authored-By line — per user). TDD: failing test first where practical.

---

### Task 1: GraphQL send + persistence + export foundation

Adds the enum value, the `graphqlVariables` field, the send-path serialization (with the invalid-variables error), and satisfies every compile-forced exhaustive switch (content-type, code-gen, Postman export, Postman import record, workspace mirror). The GraphQL chip stays **hidden** from the body-type selector (no `_labels` entry) until Task 2, so no half-built UI ships between tasks.

**Files:**
- Modify: `lib/core/domain/entities/body_type.dart` — add `graphql` enum value.
- Modify: `lib/core/domain/entities/request_config_entity.dart` — add `graphqlVariables` field (constructor, `copyWith`, `props`).
- Modify: `lib/features/history/data/models/request_config_model.dart` — add `@HiveField(15)` + `fromEntity`/`toEntity`.
- Regenerate: `lib/features/history/data/models/request_config_model.g.dart` (via build_runner).
- Modify: `lib/core/error/exceptions.dart` — add `GraphqlVariablesException`.
- Modify: `lib/features/tabs/data/request_serializer.dart` — `buildBody` graphql case.
- Modify: `lib/features/tabs/data/repositories/tabs_repository_impl.dart` — map `GraphqlVariablesException` → status-0 `NetworkFailure`.
- Modify: `lib/core/utils/body_type_utils.dart` — graphql content-type rule.
- Modify: `lib/core/utils/code_gen_service.dart` — envelope normalizer + graphql case-label in all 6 target switches.
- Modify: `lib/core/utils/postman/postman_collection_mapper.dart` — `_configToBody` export + `_parseBody`/`_requestToConfig` import.
- Modify: `lib/core/utils/workspace/workspace_collection_serializer.dart` — persist `graphqlVariables`.
- Modify: `lib/features/tabs/presentation/widgets/request_editor_tabs.dart` — `_editorFor` graphql compile-stub + selector skips labels it doesn't have.
- Test: `test/features/tabs/data/request_serializer_test.dart` (extend), `test/core/utils/postman/postman_collection_mapper_test.dart` (extend), `test/core/utils/code_gen_service_test.dart` (extend), and a config entity↔model round-trip test (extend existing model test if present, else add `test/features/history/data/models/request_config_model_test.dart`).

**Interfaces:**
- Produces: `BodyType.graphql` (wire `'graphql'`); `HttpRequestConfigEntity.graphqlVariables` (String, default `''`) + `copyWith({String? graphqlVariables})`; `GraphqlVariablesException(String detail)`.
- Consumes: existing `EnvironmentResolver.resolve`, `BodyTypeUtils.applyContentType`, `HeaderUtils.{setHeader,hasCustomContentType}`, `FileBodyException` mapping pattern.

- [ ] **Step 1: Add the enum value**

In `lib/core/domain/entities/body_type.dart`, add `graphql` to the enum:

```dart
enum BodyType {
  none('none'),
  raw('raw'),
  urlencoded('urlencoded'),
  multipart('multipart'),
  binary('binary'),
  graphql('graphql')
  ;
```

- [ ] **Step 2: Add the entity field**

In `lib/core/domain/entities/request_config_entity.dart`:
- Add constructor param `this.graphqlVariables = ''` (place it right after `bodyFilePath`).
- Add the field declaration: `final String graphqlVariables;` (after `bodyFilePath`).
- Add `String? graphqlVariables,` to the `copyWith` signature and `graphqlVariables: graphqlVariables ?? this.graphqlVariables,` to its body.
- Add `graphqlVariables,` to `props` (after `bodyFilePath`).

- [ ] **Step 3: Add the Hive model field**

In `lib/features/history/data/models/request_config_model.dart`:
- Constructor: add `this.graphqlVariables = ''` after `bodyFilePath`.
- `fromEntity`: add `graphqlVariables: entity.graphqlVariables,`.
- Add the field after `kind`:

```dart
  @HiveField(15, defaultValue: '')
  String graphqlVariables;
```

- `toEntity`: add `graphqlVariables: graphqlVariables,`.

- [ ] **Step 4: Regenerate the adapter**

Run: `fvm dart run build_runner build --delete-conflicting-outputs`
Expected: regenerates `request_config_model.g.dart` with field 15; exits 0.

- [ ] **Step 5: Write the failing serializer tests**

In `test/features/tabs/data/request_serializer_test.dart`, add a group:

```dart
group('graphql body', () {
  test('builds {query, variables} envelope and forces application/json', () async {
    final config = HttpRequestConfigEntity(
      id: 'g1',
      bodyType: BodyType.graphql,
      body: 'query { me { id } }',
      graphqlVariables: '{"limit": 5}',
      headers: const {},
    );
    final headers = <String, String>{};
    final data = await RequestSerializer.buildBody(
      config: config, headers: headers, envVars: const {},
    );
    expect(data, {'query': 'query { me { id } }', 'variables': {'limit': 5}});
    expect(headers['Content-Type'], 'application/json');
  });

  test('blank variables become an empty object', () async {
    final config = HttpRequestConfigEntity(
      id: 'g2', bodyType: BodyType.graphql, body: 'query { x }',
      graphqlVariables: '  ', headers: const {},
    );
    final data = await RequestSerializer.buildBody(
      config: config, headers: <String, String>{}, envVars: const {},
    );
    expect(data, {'query': 'query { x }', 'variables': <String, dynamic>{}});
  });

  test('invalid variables JSON throws GraphqlVariablesException', () async {
    final config = HttpRequestConfigEntity(
      id: 'g3', bodyType: BodyType.graphql, body: 'query { x }',
      graphqlVariables: '{not json', headers: const {},
    );
    expect(
      () => RequestSerializer.buildBody(
        config: config, headers: <String, String>{}, envVars: const {},
      ),
      throwsA(isA<GraphqlVariablesException>()),
    );
  });

  test('resolves {{vars}} in query and variables', () async {
    final config = HttpRequestConfigEntity(
      id: 'g4', bodyType: BodyType.graphql,
      body: 'query { u(id: "{{id}}") }',
      graphqlVariables: '{"n": "{{name}}"}', headers: const {},
    );
    final data = await RequestSerializer.buildBody(
      config: config, headers: <String, String>{},
      envVars: const {'id': '42', 'name': 'ada'},
    );
    expect(data, {'query': 'query { u(id: "42") }', 'variables': {'n': 'ada'}});
  });
});
```

(Add `import 'package:getman/core/error/exceptions.dart';` if not already imported.)

- [ ] **Step 6: Run the serializer tests — expect compile failure**

Run: `fvm flutter test test/features/tabs/data/request_serializer_test.dart`
Expected: FAIL to compile — `GraphqlVariablesException` undefined and `buildBody` has no `graphql` case (non-exhaustive switch).

- [ ] **Step 7: Add the exception**

In `lib/core/error/exceptions.dart`, append:

```dart
/// Thrown when a GraphQL request's variables pane holds non-empty text that is
/// not valid JSON. Pure (no dart:io) so it can cross the data→network boundary;
/// the repository maps it to a status-0 NetworkFailure so the user sees a real
/// error response instead of an uncaught throw.
class GraphqlVariablesException implements Exception {
  GraphqlVariablesException(this.detail);
  final String detail;

  @override
  String toString() => 'GraphQL variables are not valid JSON: $detail';
}
```

- [ ] **Step 8: Implement the serializer graphql case**

In `lib/features/tabs/data/request_serializer.dart`:
- Add `import 'dart:convert';` at the top (with the other imports, alphabetically before the package imports).
- Add `import 'package:getman/core/error/exceptions.dart' ...` — it already imports `exceptions.dart` for `FileBodyException`, so no new import needed.
- Add this case to the `switch (config.bodyType)` in `buildBody`, after `BodyType.binary`:

```dart
      case BodyType.graphql:
        if (!HeaderUtils.hasCustomContentType(headers)) {
          BodyTypeUtils.applyContentType(headers, BodyType.graphql);
        }
        final varsText = r(config.graphqlVariables).trim();
        Object? variables;
        if (varsText.isEmpty) {
          variables = const <String, dynamic>{};
        } else {
          try {
            variables = jsonDecode(varsText);
          } on FormatException catch (e) {
            throw GraphqlVariablesException(e.message);
          }
        }
        return <String, dynamic>{'query': r(config.body), 'variables': variables};
```

Note: `HeaderUtils` is imported transitively via `body_type_utils.dart`? No — add `import 'package:getman/core/utils/header_utils.dart';` if `HeaderUtils` is not already imported. (Check: if absent, the graphql content-type guard can instead call `BodyTypeUtils.applyContentType` unconditionally, since `applyContentType`'s graphql rule from Step 11 is itself skip-if-custom — in that case drop the `if (!HeaderUtils...)` wrapper here and just call `BodyTypeUtils.applyContentType(headers, BodyType.graphql);`.) Prefer the simpler form: call `BodyTypeUtils.applyContentType(headers, BodyType.graphql);` directly (the rule is skip-if-custom in Step 11), avoiding a new import:

```dart
      case BodyType.graphql:
        BodyTypeUtils.applyContentType(headers, BodyType.graphql);
        final varsText = r(config.graphqlVariables).trim();
        Object? variables;
        if (varsText.isEmpty) {
          variables = const <String, dynamic>{};
        } else {
          try {
            variables = jsonDecode(varsText);
          } on FormatException catch (e) {
            throw GraphqlVariablesException(e.message);
          }
        }
        return <String, dynamic>{'query': r(config.body), 'variables': variables};
```

- [ ] **Step 9: Add the content-type rule**

In `lib/core/utils/body_type_utils.dart`, add a `graphql` case to `applyContentType` (skip-if-custom, like binary), and remove `graphql` from the no-op `none/raw` group:

```dart
      case BodyType.graphql:
        if (!HeaderUtils.hasCustomContentType(headers)) {
          HeaderUtils.setHeader(headers, 'Content-Type', 'application/json');
        }
      case BodyType.none:
      case BodyType.raw:
        break;
```

- [ ] **Step 10: Map the exception in the repository**

In `lib/features/tabs/data/repositories/tabs_repository_impl.dart`, add a second catch right after the `on FileBodyException` block:

```dart
    } on GraphqlVariablesException catch (e) {
      // Invalid GraphQL variables are a real, user-visible error — surface as a
      // status-0 NetworkFailure so the response panel + history show it.
      throw NetworkFailure(
        e.toString(),
        type: NetworkFailureType.unknown,
        statusCode: 0,
      );
```

(Ensure `package:getman/core/error/exceptions.dart` is imported — it is, for `FileBodyException`.)

- [ ] **Step 11: Run the serializer tests — expect pass**

Run: `fvm flutter test test/features/tabs/data/request_serializer_test.dart`
Expected: PASS (all 4 new cases). The build now compiles past the serializer; remaining exhaustive switches in code-gen / Postman still fail to compile — fixed next.

- [ ] **Step 12: Code-gen — envelope normalizer + shared graphql label**

In `lib/core/utils/code_gen_service.dart`:
- Ensure `import 'dart:convert';` is present (add if missing).
- Add a private helper:

```dart
  /// Builds the GraphQL wire body `{"query":...,"variables":...}` as a JSON
  /// string. Lenient (code-gen never fails): invalid/blank variables → `{}`.
  static String _graphqlEnvelope(String query, String variablesText) {
    Object? variables = const <String, dynamic>{};
    final t = variablesText.trim();
    if (t.isNotEmpty) {
      try {
        variables = jsonDecode(t);
      } on FormatException {
        variables = const <String, dynamic>{};
      }
    }
    return jsonEncode(<String, dynamic>{'query': query, 'variables': variables});
  }
```

- In `_effective(...)`, change the `rawBody:` argument so GraphQL bodies carry the envelope:

```dart
      bodyType: config.bodyType,
      rawBody: config.bodyType == BodyType.graphql
          ? _graphqlEnvelope(resolve(config.body), resolve(config.graphqlVariables))
          : resolve(config.body),
```

- In **each** of the 6 target switches (`_curl`, `_fetch`, `_python`, `_axios`/Node, `_go`, `_java` — search for `case BodyType.raw:`), add `case BodyType.graphql:` as a shared label immediately above the existing raw body so they share it:

```dart
      case BodyType.raw:
      case BodyType.graphql:
        // ... existing raw body, unchanged ...
```

Because `applyContentType` (called in `_effective`) now sets `application/json` for graphql, and `e.rawBody` carries the envelope, the raw formatter emits a correct GraphQL request with no further changes.

- [ ] **Step 13: Add a code-gen test**

In `test/core/utils/code_gen_service_test.dart`, add:

```dart
test('cURL emits the GraphQL JSON envelope with application/json', () {
  final config = HttpRequestConfigEntity(
    id: 'gq', method: 'POST', url: 'https://api.example.com/graphql',
    bodyType: BodyType.graphql, body: 'query { me { id } }',
    graphqlVariables: '{"x":1}', headers: const {},
  );
  final out = CodeGenService.generate(config, CodeGenTarget.curl);
  expect(out, contains('application/json'));
  expect(out, contains('"query"'));
  expect(out, contains('query { me { id } }'));
  expect(out, contains('"variables"'));
});
```

(Match the actual `CodeGenService.generate` signature / `CodeGenTarget` member names in the test file — adjust `CodeGenTarget.curl` if the enum value differs.)

- [ ] **Step 14: Postman export — `_configToBody` graphql case**

In `lib/core/utils/postman/postman_collection_mapper.dart`, add to the `_configToBody` switch (after `BodyType.binary`):

```dart
      case BodyType.graphql:
        return {
          'mode': 'graphql',
          'graphql': {
            'query': config.body,
            'variables': config.graphqlVariables,
          },
        };
```

- [ ] **Step 15: Postman import — record + `_parseBody` + `_requestToConfig`**

In the same file:
- Add `String graphqlVariables` to the `_parseBody` return record type.
- Add `graphqlVariables: ''` to **every** existing `return (...)` in `_parseBody` (the `raw`, `urlencoded`, `formdata`, `file`, and the trailing fallback).
- Add a `graphql` case to the `switch (body['mode'])`:

```dart
        case 'graphql':
          final gql = body['graphql'];
          final query = gql is Map ? gql['query'] : null;
          final vars = gql is Map ? gql['variables'] : null;
          return (
            bodyType: BodyType.graphql,
            body: query is String ? query : '',
            graphqlVariables: vars is String ? vars : '',
            formFields: const <MultipartFieldEntity>[],
            bodyFilePath: null,
          );
```

- In `_requestToConfig`, pass the new field to the entity:

```dart
      bodyType: body.bodyType,
      formFields: body.formFields,
      bodyFilePath: body.bodyFilePath,
      graphqlVariables: body.graphqlVariables,
```

- [ ] **Step 16: Add a Postman round-trip test**

In `test/core/utils/postman/postman_collection_mapper_test.dart`, add:

```dart
test('graphql body round-trips export -> import', () {
  final node = CollectionNodeEntity(
    id: 'n1', name: 'gql', isFolder: false,
    config: HttpRequestConfigEntity(
      id: 'c1', method: 'POST', url: 'https://api.example.com/graphql',
      bodyType: BodyType.graphql, body: 'query { me { id } }',
      graphqlVariables: '{"limit":5}',
    ),
  );
  final exported = PostmanCollectionMapper.toPostman([node], name: 'C');
  final imported = PostmanCollectionMapper.fromPostman(exported);
  final cfg = imported.single.config!;
  expect(cfg.bodyType, BodyType.graphql);
  expect(cfg.body, 'query { me { id } }');
  expect(cfg.graphqlVariables, '{"limit":5}');
});
```

(Match the actual `PostmanCollectionMapper.toPostman` / `fromPostman` names + return shape used elsewhere in this test file; adjust accessors accordingly.)

- [ ] **Step 17: Workspace mirror — persist the new field**

In `lib/core/utils/workspace/workspace_collection_serializer.dart`:
- In `_configToJson`, add after the `bodyType` line:

```dart
    if (c.graphqlVariables.isNotEmpty) 'graphqlVariables': c.graphqlVariables,
```

- In `_configFromJson`, add to the `HttpRequestConfigEntity(...)` args:

```dart
      graphqlVariables: (json['graphqlVariables'] as String?) ?? '',
```

- [ ] **Step 18: Editor compile-stub + selector tolerates missing labels**

In `lib/features/tabs/presentation/widgets/request_editor_tabs.dart`:
- In `BodyTabView._editorFor`, add a graphql branch that compiles but is unreachable from the UI (the chip is hidden this task):

```dart
      case BodyType.graphql:
        // Real dual-pane editor + visible chip land in Task 2.
        return _RawBodyEditor(controller: controller);
```

- In `_BodyTypeSelector.build`, guard the chip loop so a `BodyType` with no `_labels` entry is skipped (prevents the `_labels[type]!` null-bang from throwing now that `graphql` exists but is intentionally absent from `_labels`):

```dart
        children: [
          for (final type in BodyType.values)
            if (_labels.containsKey(type))
              _BodyTypeChip(
                // ... unchanged ...
              ),
        ],
```

Do **not** add `graphql` to `_labels` yet.

- [ ] **Step 19: Add the entity↔model round-trip test**

If `test/features/history/data/models/request_config_model_test.dart` exists, extend it; otherwise create it:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';

void main() {
  test('graphqlVariables survives entity -> model -> entity', () {
    final entity = HttpRequestConfigEntity(
      id: 'x', bodyType: BodyType.graphql,
      body: 'query { x }', graphqlVariables: '{"a":1}',
    );
    final back = HttpRequestConfig.fromEntity(entity).toEntity();
    expect(back.bodyType, BodyType.graphql);
    expect(back.graphqlVariables, '{"a":1}');
  });
}
```

- [ ] **Step 20: Full verification**

Run, in order:
- `fvm flutter analyze` → Expected: `No issues found!`
- `fvm dart run custom_lint` → Expected: no issues
- `fvm dart run bloc_tools:bloc lint lib` → Expected: no issues
- `fvm dart format lib test` → Expected: formats clean (0 changed, or commit the formatting)
- `fvm flutter test` → Expected: all green

- [ ] **Step 21: Commit**

```bash
git add lib test
git commit -m "feat(graphql): send + persist + export GraphQL bodies (M8 foundation)"
```

---

### Task 2: GraphQL dual-pane editor (make it user-visible)

Adds the second (variables) code controller to `request_view.dart`, threads it to a new `_GraphqlBodyEditor`, and reveals the `GRAPHQL` chip.

**Files:**
- Modify: `lib/features/tabs/presentation/screens/request_view.dart` — second controller + sync.
- Modify: `lib/features/tabs/presentation/widgets/request_config_section.dart` — accept + pass `variablesController`.
- Modify: `lib/features/tabs/presentation/widgets/unified_request_panel.dart` — accept + pass `variablesController`.
- Modify: `lib/features/tabs/presentation/widgets/request_editor_tabs.dart` — `BodyTabView.variablesController`, `_GraphqlBodyEditor`, `_labels` graphql entry, real `_editorFor` graphql branch.
- Test: `test/features/tabs/presentation/widgets/body_tab_view_test.dart` (extend or create).

**Interfaces:**
- Consumes: `BodyType.graphql`, `HttpRequestConfigEntity.graphqlVariables` (from Task 1).
- Produces: `BodyTabView({required CodeLineEditingController controller, required CodeLineEditingController variablesController, ...})`; `_GraphqlBodyEditor` (private).

- [ ] **Step 1: Write the failing widget test**

In `test/features/tabs/presentation/widgets/body_tab_view_test.dart`, add (or create following the existing test harness in this directory — pump `BodyTabView` inside a `BlocProvider<TabsBloc>`):

```dart
testWidgets('selecting GRAPHQL shows query + variables panes', (tester) async {
  // ... pump BodyTabView with a tab whose bodyType is BodyType.graphql,
  // passing both a controller and a variablesController ...
  expect(find.text('QUERY'), findsOneWidget);
  expect(find.text('VARIABLES (JSON)'), findsOneWidget);
});
```

- [ ] **Step 2: Run it — expect failure**

Run: `fvm flutter test test/features/tabs/presentation/widgets/body_tab_view_test.dart`
Expected: FAIL — `BodyTabView` has no `variablesController` param / labels not found.

- [ ] **Step 3: Add `variablesController` to `BodyTabView` + `_GraphqlBodyEditor` + label**

In `lib/features/tabs/presentation/widgets/request_editor_tabs.dart`:
- Add the field to `BodyTabView`:

```dart
class BodyTabView extends StatelessWidget {
  const BodyTabView({
    required this.tabId,
    required this.controller,
    required this.variablesController,
    super.key,
  });
  final String tabId;
  final CodeLineEditingController controller;
  final CodeLineEditingController variablesController;
```

- Add `BodyType.graphql: 'GRAPHQL'` to `_BodyTypeSelector._labels`.
- Replace the `_editorFor` graphql branch:

```dart
      case BodyType.graphql:
        return _GraphqlBodyEditor(
          queryController: controller,
          variablesController: variablesController,
        );
```

- Add the editor widget (after `_RawBodyEditor`):

```dart
/// Dual-pane GraphQL editor: QUERY on top (reuses the body controller),
/// VARIABLES (JSON) below (its own controller + beautify, since variables
/// are JSON).
class _GraphqlBodyEditor extends StatelessWidget {
  const _GraphqlBodyEditor({
    required this.queryController,
    required this.variablesController,
  });
  final CodeLineEditingController queryController;
  final CodeLineEditingController variablesController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _GraphqlPane(
            label: 'QUERY',
            child: JsonCodeEditor(controller: queryController),
          ),
        ),
        Expanded(
          flex: 2,
          child: _GraphqlPane(
            label: 'VARIABLES (JSON)',
            child: _RawBodyEditor(controller: variablesController),
          ),
        ),
      ],
    );
  }
}

class _GraphqlPane extends StatelessWidget {
  const _GraphqlPane({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.pagePadding,
            vertical: layout.isCompact ? 4 : 6,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.displayWeight,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
```

(`JsonCodeEditor` and `_RawBodyEditor` are already in this file / imported.)

- [ ] **Step 4: Thread the controller through the two layout sections**

In `lib/features/tabs/presentation/widgets/request_config_section.dart`:
- Add `required this.variablesController` + `final CodeLineEditingController variablesController;` to `RequestConfigSection`.
- Pass it: `BodyTabView(tabId: tabId, controller: bodyController, variablesController: variablesController)`.

In `lib/features/tabs/presentation/widgets/unified_request_panel.dart`:
- Add `required this.variablesController` + the field to `UnifiedRequestPanel`.
- Pass it to the `BodyTabView(...)` call: `variablesController: widget.variablesController`.

- [ ] **Step 5: Create + sync the variables controller in `request_view.dart`**

In `lib/features/tabs/presentation/screens/request_view.dart`:
- Add the field beside `_bodyController`:

```dart
  late final CodeLineEditingController _graphqlVarsController;
```

- In `initState`, after the body controller wiring:

```dart
    _graphqlVarsController = createJsonCodeController();
    _graphqlVarsController.addListener(_onGraphqlVarsChanged);
```

- In `didChangeDependencies`, after the body sync:

```dart
    if (tab != null &&
        _graphqlVarsController.text != tab.config.graphqlVariables) {
      _graphqlVarsController.text = tab.config.graphqlVariables;
    }
```

- Add the listener (mirror of `_onBodyChanged`):

```dart
  void _onGraphqlVarsChanged() {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.byId(widget.tabId);
    if (tab == null) return;
    final newText = _graphqlVarsController.text;
    if (tab.config.graphqlVariables == newText) return;
    tabsBloc.add(
      UpdateTab(
        tab.copyWith(
          config: tab.config.copyWith(graphqlVariables: newText),
        ),
      ),
    );
  }
```

- In `dispose`, before `super.dispose()`:

```dart
    _graphqlVarsController
      ..removeListener(_onGraphqlVarsChanged)
      ..dispose();
```

- Widen the `BlocConsumer` `listenWhen` to also fire on a variables change, and sync the controller in the `listener`:

```dart
          listenWhen: (prev, next) {
            final p = prev.tabs.byId(widget.tabId);
            final n = next.tabs.byId(widget.tabId);
            return p?.config.body != n?.config.body ||
                p?.config.graphqlVariables != n?.config.graphqlVariables;
          },
          listener: (context, state) {
            final tab = state.tabs.byId(widget.tabId);
            if (tab == null) return;
            if (_bodyController.text != tab.config.body) {
              _bodyController.text = tab.config.body;
            }
            if (_graphqlVarsController.text != tab.config.graphqlVariables) {
              _graphqlVarsController.text = tab.config.graphqlVariables;
            }
          },
```

- Pass `_graphqlVarsController` into both `UnifiedRequestPanel(...)` and `RequestConfigSection(...)`:

```dart
                            ? UnifiedRequestPanel(
                                tabId: widget.tabId,
                                bodyController: _bodyController,
                                variablesController: _graphqlVarsController,
                                responseController: _responseController,
                              )
                            : // ...
                                  final requestPane = RequestConfigSection(
                                    tabId: widget.tabId,
                                    bodyController: _bodyController,
                                    variablesController: _graphqlVarsController,
                                  );
```

- [ ] **Step 6: Run the widget test — expect pass**

Run: `fvm flutter test test/features/tabs/presentation/widgets/body_tab_view_test.dart`
Expected: PASS.

- [ ] **Step 7: Full verification**

Run: `fvm flutter analyze` (0 issues), `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test`, `fvm flutter test` (all green).

- [ ] **Step 8: Manual smoke (optional but recommended)**

Run: `fvm flutter run -d macos`, add a tab, BODY → GRAPHQL, type a query + variables, send to a public GraphQL endpoint (e.g. `https://countries.trevorblades.com/`), confirm a 200 response.

- [ ] **Step 9: Commit**

```bash
git add lib test
git commit -m "feat(graphql): dual-pane query + variables body editor"
```

---

### Task 3: Wiki docs

Update the user-facing wiki to document the GraphQL body type (CLAUDE.md §7 keep-the-wiki-in-sync mandate).

**Files:**
- Clone `https://github.com/thiagomiranda3/Getman.wiki.git` (separate repo).
- Modify: the Body types page (e.g. `Request-Bodies.md` or equivalent — match the existing page name from `_Sidebar.md`).

- [ ] **Step 1: Clone the wiki**

Run: `git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki`

- [ ] **Step 2: Find the body-types page**

Run: `ls /tmp/getman-wiki && cat /tmp/getman-wiki/_Sidebar.md`
Identify the page that documents body types (RAW / FORM / MULTIPART / BINARY).

- [ ] **Step 3: Add a GraphQL section**

Document: select **BODY → GRAPHQL**; top pane is the **QUERY**, bottom pane is **VARIABLES (JSON)**; the request is sent as `{"query": ..., "variables": ...}` with `Content-Type: application/json`; `{{variables}}` resolve in both panes; invalid variables JSON shows a local error instead of sending. Use the verbatim UI labels (`GRAPHQL`, `QUERY`, `VARIABLES (JSON)`).

- [ ] **Step 4: Commit + push the wiki**

```bash
cd /tmp/getman-wiki
git add -A
git commit -m "docs: document GraphQL body type"
git push origin master
```

---

## Self-Review

**Spec coverage:**
- §1 data model → Task 1 Steps 1–4 (enum, entity, model, build_runner). ✓
- §2 send path (envelope, content-type, invalid-variables error + repo mapping) → Task 1 Steps 7–11. ✓
- §3 editor UI (dual pane, second controller, threading) → Task 2. ✓
- §4 integration (code-gen, Postman export+import, workspace mirror, cURL/OpenAPI out of scope, dedup unchanged) → Task 1 Steps 12–17. ✓
- §5 tests (serializer, entity/model round-trip, Postman round-trip, code-gen, widget) → Task 1 Steps 5/13/16/19, Task 2 Step 1. ✓
- §5 docs (wiki) → Task 3. ✓

**Placeholder scan:** No TBD/TODO; every code step shows the code. The two "match the actual signature" notes (code-gen test Step 13, Postman test Step 16) are real-codebase adapters, not placeholders — the surrounding test files already use those APIs.

**Type consistency:** `graphqlVariables` (String) used identically in entity, model, copyWith, serializer, code-gen, Postman record, workspace, controller sync. `GraphqlVariablesException(String detail)` consistent between exceptions.dart, serializer throw, repo catch. `BodyType.graphql` wire `'graphql'` consistent across all surfaces. `_GraphqlBodyEditor({queryController, variablesController})` matches `_editorFor` call. ✓
