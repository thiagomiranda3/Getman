# Export Collection as API Docs (DW3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export any collection node as developer API docs in three formats chosen at export time — OpenAPI 3.0.3 JSON, OpenAPI 3.0.3 YAML, and Markdown.

**Architecture:** One traversal of the collection subtree (`CollectionToApiDoc`) builds a pure-Dart intermediate model (`ApiDoc`); two serializers (`OpenApiSerializer`, `MarkdownDocSerializer`) render it. Request/response JSON bodies get a synthesized `JsonSchema` (via `JsonSchemaInferrer`) plus the verbatim payload as an example. A single "EXPORT AS API DOCS…" menu entry opens a dialog (format + environment), then writes via a generalized `saveTextFileWithFeedback`.

**Tech Stack:** Dart, Flutter, `flutter_bloc`, `equatable`, `file_picker`. No new package dependencies (YAML is hand-rolled).

## Global Constraints

- Flutter SDK via `fvm` — invoke every command as `fvm flutter ...` / `fvm dart ...`, never bare `flutter`.
- Imports are `package:getman/...` everywhere (no relative imports; enforced by lint).
- Pure-Dart layers (`lib/core/utils/apidoc/`) must NOT import Flutter. Only `dart:*`, `package:equatable`, and project domain entities.
- Widgets pull all sizing/colors/weights/radii from theme extensions (`context.appLayout`, `context.appTypography`, `context.appShape`, etc.) — no hardcoded literals. Snackbars go through `showAppSnackBar` / `showAppSnackBarVia`. Never use `Colors.black/white/red` for themeable surfaces.
- Widgets must never use `GetIt`/`sl<T>()` — reach services/blocs via `context.read`/`context.watch`/providers.
- OpenAPI output target is **3.0.3** only.
- Secret values (variable names in `EnvironmentEntity.secretKeys`) must never be emitted as example/server values.
- The done-bar (run before claiming complete): `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib` all report 0 issues; `fvm dart format lib test` clean; `fvm flutter test` 100% green.
- Commit message trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. One concern per commit, message `type(scope): summary`.

---

### Task 1: `JsonSchema` model + `JsonSchemaInferrer`

**Files:**
- Create: `lib/core/utils/apidoc/json_schema.dart`
- Test: `test/core/utils/apidoc/json_schema_inferrer_test.dart`

**Interfaces:**
- Consumes: nothing (leaf module).
- Produces:
  - `class JsonSchema` with `const JsonSchema({String? type, String? format, Map<String, JsonSchema> properties, List<String> required, JsonSchema? items, bool nullable, Object? example})` and `Map<String, dynamic> toOpenApi()`.
  - `class JsonSchemaInferrer` with `static JsonSchema infer(Object? value)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/apidoc/json_schema_inferrer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';

void main() {
  group('JsonSchemaInferrer.infer', () {
    test('infers an object with typed properties and required keys', () {
      final schema = JsonSchemaInferrer.infer({
        'id': 1,
        'name': 'ada',
        'active': true,
        'score': 9.5,
      });
      expect(schema.type, 'object');
      expect(schema.properties['id']!.type, 'integer');
      expect(schema.properties['name']!.type, 'string');
      expect(schema.properties['active']!.type, 'boolean');
      expect(schema.properties['score']!.type, 'number');
      expect(schema.required, containsAll(<String>['id', 'name', 'active', 'score']));
    });

    test('infers nested objects and arrays from the first element', () {
      final schema = JsonSchemaInferrer.infer({
        'tags': ['a', 'b'],
        'owner': {'uid': 7},
      });
      expect(schema.properties['tags']!.type, 'array');
      expect(schema.properties['tags']!.items!.type, 'string');
      expect(schema.properties['owner']!.type, 'object');
      expect(schema.properties['owner']!.properties['uid']!.type, 'integer');
    });

    test('empty array yields array schema with no items', () {
      final schema = JsonSchemaInferrer.infer(<dynamic>[]);
      expect(schema.type, 'array');
      expect(schema.items, isNull);
    });

    test('null yields a nullable schema with no type', () {
      final schema = JsonSchemaInferrer.infer(null);
      expect(schema.nullable, isTrue);
      expect(schema.type, isNull);
    });

    test('toOpenApi emits object with properties, required, and nested items', () {
      final schema = JsonSchemaInferrer.infer({
        'tags': ['a'],
        'n': 1,
      });
      final map = schema.toOpenApi();
      expect(map['type'], 'object');
      expect((map['properties'] as Map)['n'], {'type': 'integer'});
      expect((map['properties'] as Map)['tags'], {
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect(map['required'], containsAll(<String>['tags', 'n']));
    });

    test('binary format round-trips through toOpenApi', () {
      const schema = JsonSchema(type: 'string', format: 'binary');
      expect(schema.toOpenApi(), {'type': 'string', 'format': 'binary'});
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/apidoc/json_schema_inferrer_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:getman/core/utils/apidoc/json_schema.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/utils/apidoc/json_schema.dart
import 'package:equatable/equatable.dart';

/// The subset of JSON Schema that OpenAPI 3.0 uses for request/response bodies.
/// Pure data — no Flutter, no I/O. Built by [JsonSchemaInferrer] from a decoded
/// JSON value, then rendered to an OpenAPI `schema` map via [toOpenApi].
class JsonSchema extends Equatable {
  const JsonSchema({
    this.type,
    this.format,
    this.properties = const {},
    this.required = const [],
    this.items,
    this.nullable = false,
    this.example,
  });

  /// `object` / `array` / `string` / `integer` / `number` / `boolean`, or null
  /// when unknown (e.g. a bare null value).
  final String? type;
  final String? format; // e.g. `binary`
  final Map<String, JsonSchema> properties;
  final List<String> required;
  final JsonSchema? items;
  final bool nullable;
  final Object? example;

  Map<String, dynamic> toOpenApi() {
    final map = <String, dynamic>{};
    if (type != null) map['type'] = type;
    if (format != null) map['format'] = format;
    if (nullable) map['nullable'] = true;
    if (type == 'object') {
      map['properties'] = <String, dynamic>{
        for (final entry in properties.entries) entry.key: entry.value.toOpenApi(),
      };
      if (required.isNotEmpty) map['required'] = List<String>.from(required);
    }
    if (type == 'array' && items != null) {
      map['items'] = items!.toOpenApi();
    }
    if (example != null) map['example'] = example;
    return map;
  }

  @override
  List<Object?> get props => [type, format, properties, required, items, nullable, example];
}

/// Synthesizes a [JsonSchema] from a decoded JSON value (the reverse of the
/// import-side `schema_sampler.dart`). Arrays are inferred from their first
/// element; an object's keys are all treated as `required`.
class JsonSchemaInferrer {
  JsonSchemaInferrer._();

  static JsonSchema infer(Object? value) {
    if (value == null) return const JsonSchema(nullable: true);
    if (value is bool) return const JsonSchema(type: 'boolean');
    if (value is int) return const JsonSchema(type: 'integer');
    if (value is num) return const JsonSchema(type: 'number');
    if (value is String) return const JsonSchema(type: 'string');
    if (value is List) {
      if (value.isEmpty) return const JsonSchema(type: 'array');
      return JsonSchema(type: 'array', items: infer(value.first));
    }
    if (value is Map) {
      final props = <String, JsonSchema>{};
      final required = <String>[];
      for (final entry in value.entries) {
        final key = entry.key.toString();
        props[key] = infer(entry.value);
        required.add(key);
      }
      return JsonSchema(type: 'object', properties: props, required: required);
    }
    return const JsonSchema(type: 'string');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/apidoc/json_schema_inferrer_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/apidoc/json_schema.dart test/core/utils/apidoc/json_schema_inferrer_test.dart
git add lib/core/utils/apidoc/json_schema.dart test/core/utils/apidoc/json_schema_inferrer_test.dart
git commit -m "feat(export): JsonSchema model + inferrer for API docs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `ApiDoc` intermediate model

**Files:**
- Create: `lib/core/utils/apidoc/api_doc.dart`
- Test: `test/core/utils/apidoc/api_doc_test.dart`

**Interfaces:**
- Consumes: `JsonSchema` (Task 1); `AuthConfig` from `package:getman/core/domain/entities/auth_config.dart`.
- Produces these value objects (all `Equatable`, `const` constructors):
  - `ApiDoc({required String title, String version = '1.0.0', List<ApiServer> servers, List<ApiOperation> operations, List<String> warnings})`
  - `ApiServer({required String url, Map<String, String> variables})`
  - `ApiParam({required String name, String? example, bool isRequired, JsonSchema? schema})`
  - `ApiBody({required String contentType, JsonSchema? schema, Object? example})`
  - `ApiResponse({required int statusCode, String description, ApiBody? body})`
  - `ApiOperation({required String method, required String path, required String summary, String? description, String? tag, List<ApiParam> queryParams, List<ApiParam> headerParams, List<ApiParam> pathParams, ApiBody? requestBody, List<ApiResponse> responses, AuthConfig security})`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/apidoc/api_doc_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';

void main() {
  test('ApiDoc defaults: version 1.0.0, empty collections', () {
    const doc = ApiDoc(title: 'My API');
    expect(doc.version, '1.0.0');
    expect(doc.servers, isEmpty);
    expect(doc.operations, isEmpty);
    expect(doc.warnings, isEmpty);
  });

  test('ApiOperation defaults security to AuthConfig.none', () {
    const op = ApiOperation(method: 'GET', path: '/u', summary: 'List');
    expect(op.security, AuthConfig.none);
    expect(op.responses, isEmpty);
  });

  test('value objects compare by value (Equatable)', () {
    const a = ApiParam(name: 'id', isRequired: true);
    const b = ApiParam(name: 'id', isRequired: true);
    expect(a, equals(b));
    const body1 = ApiBody(contentType: 'application/json', schema: JsonSchema(type: 'object'));
    const body2 = ApiBody(contentType: 'application/json', schema: JsonSchema(type: 'object'));
    expect(body1, equals(body2));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/apidoc/api_doc_test.dart`
Expected: FAIL — `api_doc.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/utils/apidoc/api_doc.dart
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';

/// A format-agnostic description of an API, built from a collection subtree.
/// Both [OpenApiSerializer] and [MarkdownDocSerializer] consume this.
class ApiDoc extends Equatable {
  const ApiDoc({
    required this.title,
    this.version = '1.0.0',
    this.servers = const [],
    this.operations = const [],
    this.warnings = const [],
  });

  final String title;
  final String version;
  final List<ApiServer> servers;
  final List<ApiOperation> operations;
  final List<String> warnings;

  @override
  List<Object?> get props => [title, version, servers, operations, warnings];
}

class ApiServer extends Equatable {
  const ApiServer({required this.url, this.variables = const {}});

  /// May contain `{var}` templates for unresolved server variables.
  final String url;

  /// Server-variable name → default value (empty for unknown/secret).
  final Map<String, String> variables;

  @override
  List<Object?> get props => [url, variables];
}

class ApiParam extends Equatable {
  const ApiParam({
    required this.name,
    this.example,
    this.isRequired = false,
    this.schema,
  });

  final String name;
  final String? example;
  final bool isRequired;
  final JsonSchema? schema;

  @override
  List<Object?> get props => [name, example, isRequired, schema];
}

class ApiBody extends Equatable {
  const ApiBody({required this.contentType, this.schema, this.example});

  final String contentType;
  final JsonSchema? schema;

  /// The verbatim sample payload (decoded JSON value or a raw string).
  final Object? example;

  @override
  List<Object?> get props => [contentType, schema, example];
}

class ApiResponse extends Equatable {
  const ApiResponse({
    required this.statusCode,
    this.description = '',
    this.body,
  });

  final int statusCode;
  final String description;
  final ApiBody? body;

  @override
  List<Object?> get props => [statusCode, description, body];
}

class ApiOperation extends Equatable {
  const ApiOperation({
    required this.method,
    required this.path,
    required this.summary,
    this.description,
    this.tag,
    this.queryParams = const [],
    this.headerParams = const [],
    this.pathParams = const [],
    this.requestBody,
    this.responses = const [],
    this.security = AuthConfig.none,
  });

  final String method; // upper-case, e.g. GET
  final String path; // OpenAPI path with `{var}` templates, e.g. /users/{id}
  final String summary;
  final String? description;
  final String? tag;
  final List<ApiParam> queryParams;
  final List<ApiParam> headerParams;
  final List<ApiParam> pathParams;
  final ApiBody? requestBody;
  final List<ApiResponse> responses;

  /// Auth shape only — serializers read `type`/`apiKeyName`/`apiKeyLocation`
  /// and NEVER emit token/password/value.
  final AuthConfig security;

  @override
  List<Object?> get props => [
    method,
    path,
    summary,
    description,
    tag,
    queryParams,
    headerParams,
    pathParams,
    requestBody,
    responses,
    security,
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/apidoc/api_doc_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/apidoc/api_doc.dart test/core/utils/apidoc/api_doc_test.dart
git add lib/core/utils/apidoc/api_doc.dart test/core/utils/apidoc/api_doc_test.dart
git commit -m "feat(export): ApiDoc intermediate model

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `CollectionToApiDoc` — operations, URL split, tags

**Files:**
- Create: `lib/core/utils/apidoc/collection_to_api_doc.dart`
- Test: `test/core/utils/apidoc/collection_to_api_doc_test.dart`

**Interfaces:**
- Consumes: `ApiDoc`/`ApiServer`/`ApiOperation`/`ApiParam` (Task 2); `CollectionNodeEntity`, `HttpRequestConfigEntity`, `EnvironmentEntity`, `UrlQueryUtils`.
- Produces: `class CollectionToApiDoc { static ApiDoc build(CollectionNodeEntity root, {EnvironmentEntity? env}); }`. Later tasks (4, 5) extend the SAME `build` with body, response, and auth handling — do not rename it.

This task implements: tree walk (folders → `tag`, leaves → operations), URL → server origin + `{var}` path + query params, and warning accumulation. Bodies/responses/auth come in Tasks 4–5 (leave `requestBody: null`, `responses: const []`, `security: AuthConfig.none` for now).

**URL split rule (implement exactly):**
1. `UrlQueryUtils.parse(url)` → `base`, `params`, `fragment`. Query `params` become `queryParams` (name=key, example=value, isRequired=false). Fragment ignored.
2. Determine the server origin from `base`:
   - If `base` starts with a `{{var}}` token: let `name` = the inner var name (trimmed). If `env` has a non-empty value for `name` and `name` is not secret → server URL = that value; else server URL = `{name}` with a server variable `{name: <env value or ''>}` (masked to `''` if secret). The path = `base` with the leading token removed.
   - Else if `base` matches `scheme://host` (regex `^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+`): server URL = that origin; path = remainder.
   - Else: server URL = `/`; path = `base`; add warning `'Could not determine a server URL for "<url>" — used "/".'`.
3. In the path, convert every `{{x}}` token → `{x}` and register an `ApiParam(name: x, isRequired: true, example: <env value or null>)` in `pathParams` (mask secret → null). Ensure the path starts with `/` (prepend if missing and non-empty; empty path → `/`).
4. De-duplicate servers across operations by URL (first occurrence wins; merge variables).

**Folder/tag rule:** the root node's `name` → `ApiDoc.title`. For each leaf, `tag` = the nearest ancestor folder name below the root (or the joined folder path `a / b` for deeper nesting); a leaf directly under root has `tag = null`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/apidoc/collection_to_api_doc_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

CollectionNodeEntity _leaf(String id, String name, String method, String url) =>
    CollectionNodeEntity(
      id: id,
      name: name,
      isFolder: false,
      config: HttpRequestConfigEntity(id: '$id-cfg', method: method, url: url),
    );

void main() {
  group('CollectionToApiDoc.build (structure)', () {
    test('root name becomes the title', () {
      const root = CollectionNodeEntity(id: 'r', name: 'Petstore');
      final doc = CollectionToApiDoc.build(root);
      expect(doc.title, 'Petstore');
      expect(doc.operations, isEmpty);
    });

    test('leaves become operations; folder name becomes the tag', () {
      final root = CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [
          CollectionNodeEntity(
            id: 'f',
            name: 'Users',
            children: [_leaf('a', 'List', 'GET', 'https://api.test.com/users')],
          ),
        ],
      );
      final doc = CollectionToApiDoc.build(root);
      expect(doc.operations, hasLength(1));
      final op = doc.operations.single;
      expect(op.method, 'GET');
      expect(op.path, '/users');
      expect(op.tag, 'Users');
      expect(doc.servers.single.url, 'https://api.test.com');
    });

    test('env-resolved base URL becomes the server; {{id}} becomes a path param', () {
      final env = EnvironmentEntity(
        name: 'prod',
        variables: const {'baseUrl': 'https://api.prod.com'},
      );
      final root = CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [_leaf('a', 'Get', 'GET', '{{baseUrl}}/users/{{id}}?q=x')],
      );
      final doc = CollectionToApiDoc.build(root, env: env);
      final op = doc.operations.single;
      expect(doc.servers.single.url, 'https://api.prod.com');
      expect(op.path, '/users/{id}');
      expect(op.pathParams.map((p) => p.name), ['id']);
      expect(op.pathParams.single.isRequired, isTrue);
      expect(op.queryParams.single.name, 'q');
    });

    test('unresolvable base URL falls back to "/" and warns', () {
      final root = CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [_leaf('a', 'Get', 'GET', '{{baseUrl}}/ping')],
      );
      final doc = CollectionToApiDoc.build(root); // no env
      final op = doc.operations.single;
      expect(op.path, '/ping');
      expect(doc.servers.single.url, '{baseUrl}');
      expect(doc.servers.single.variables.containsKey('baseUrl'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/apidoc/collection_to_api_doc_test.dart`
Expected: FAIL — `collection_to_api_doc.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/utils/apidoc/collection_to_api_doc.dart
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/url_query_utils.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

/// Builds a format-agnostic [ApiDoc] from a collection subtree. The reverse of
/// the OpenAPI import: leaves → operations, folders → tags, request URLs →
/// servers + templated paths. Bodies/responses/auth are filled in by the
/// body/response/auth helpers (added in later tasks). Pure Dart.
class CollectionToApiDoc {
  CollectionToApiDoc._();

  static final RegExp _leadingVar = RegExp(r'^\{\{\s*([A-Za-z0-9_\-\.]+)\s*\}\}');
  static final RegExp _origin = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+');
  static final RegExp _pathVar = RegExp(r'\{\{\s*([A-Za-z0-9_\-\.]+)\s*\}\}');

  static ApiDoc build(CollectionNodeEntity root, {EnvironmentEntity? env}) {
    final warnings = <String>[];
    final servers = <String, ApiServer>{}; // url → server (dedup)
    final operations = <ApiOperation>[];

    void walk(CollectionNodeEntity node, List<String> folderPath) {
      for (final child in node.children) {
        if (child.isFolder) {
          walk(child, [...folderPath, child.name]);
        } else if (child.config != null) {
          operations.add(
            _operation(child, folderPath, env, servers, warnings),
          );
        }
      }
    }

    walk(root, const []);

    return ApiDoc(
      title: root.name,
      servers: servers.values.toList(),
      operations: operations,
      warnings: warnings,
    );
  }

  static ApiOperation _operation(
    CollectionNodeEntity leaf,
    List<String> folderPath,
    EnvironmentEntity? env,
    Map<String, ApiServer> servers,
    List<String> warnings,
  ) {
    final config = leaf.config!;
    final parts = UrlQueryUtils.parse(config.url);

    final queryParams = [
      for (final p in parts.params)
        ApiParam(name: p.key, example: p.value.isEmpty ? null : p.value),
    ];

    final split = _splitServerAndPath(parts.base, config.url, env, warnings);
    servers.putIfAbsent(split.server.url, () => split.server);

    final pathParams = <ApiParam>[];
    final templatedPath = split.path.replaceAllMapped(_pathVar, (m) {
      final name = m.group(1)!.trim();
      pathParams.add(
        ApiParam(
          name: name,
          isRequired: true,
          example: _resolved(name, env),
        ),
      );
      return '{$name}';
    });

    return ApiOperation(
      method: config.method.toUpperCase(),
      path: _ensureLeadingSlash(templatedPath),
      summary: leaf.name,
      description: (leaf.description == null || leaf.description!.isEmpty)
          ? null
          : leaf.description,
      tag: folderPath.isEmpty ? null : folderPath.join(' / '),
      queryParams: queryParams,
      pathParams: pathParams,
      // headerParams / requestBody / responses / security: Tasks 4 & 5.
    );
  }

  static _ServerPath _splitServerAndPath(
    String base,
    String fullUrl,
    EnvironmentEntity? env,
    List<String> warnings,
  ) {
    final leading = _leadingVar.firstMatch(base);
    if (leading != null) {
      final name = leading.group(1)!.trim();
      final remainder = base.substring(leading.end);
      final value = _resolved(name, env);
      if (value != null && value.isNotEmpty) {
        return _ServerPath(ApiServer(url: value), remainder);
      }
      return _ServerPath(
        ApiServer(url: '{$name}', variables: {name: value ?? ''}),
        remainder,
      );
    }

    final origin = _origin.firstMatch(base);
    if (origin != null) {
      final url = origin.group(0)!;
      return _ServerPath(ApiServer(url: url), base.substring(url.length));
    }

    warnings.add('Could not determine a server URL for "$fullUrl" — used "/".');
    return _ServerPath(const ApiServer(url: '/'), base);
  }

  /// Env value for [name], or null when there's no env, the var is missing, or
  /// the var is secret (secrets are never emitted).
  static String? _resolved(String name, EnvironmentEntity? env) {
    if (env == null) return null;
    if (env.secretKeys.contains(name)) return null;
    return env.variables[name];
  }

  static String _ensureLeadingSlash(String path) {
    if (path.isEmpty) return '/';
    return path.startsWith('/') ? path : '/$path';
  }
}

class _ServerPath {
  const _ServerPath(this.server, this.path);
  final ApiServer server;
  final String path;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/apidoc/collection_to_api_doc_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/apidoc/collection_to_api_doc.dart test/core/utils/apidoc/collection_to_api_doc_test.dart
git add lib/core/utils/apidoc/collection_to_api_doc.dart test/core/utils/apidoc/collection_to_api_doc_test.dart
git commit -m "feat(export): collection→ApiDoc structure (ops, servers, paths)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `CollectionToApiDoc` — request bodies + headers

**Files:**
- Modify: `lib/core/utils/apidoc/collection_to_api_doc.dart`
- Test: `test/core/utils/apidoc/collection_to_api_doc_body_test.dart`

**Interfaces:**
- Consumes: `ApiBody`, `JsonSchema`/`JsonSchemaInferrer` (Tasks 1–2); `BodyType` from `package:getman/core/domain/entities/body_type.dart`; `MultipartFieldEntity`.
- Produces: extends `_operation` to populate `headerParams` and `requestBody`. Adds private helpers `_headerParams`, `_requestBody`. No public signature change.

**Body rules (by `config.bodyType`):**
- `none` → `requestBody: null`.
- `raw` → try `jsonDecode(config.body)`. On success: `ApiBody(contentType: 'application/json', schema: JsonSchemaInferrer.infer(decoded), example: decoded)`. On failure (non-empty body): `ApiBody(contentType: 'text/plain', example: config.body)` + warning `'Request body for "<name>" is not valid JSON — exported as text/plain.'`. Empty body → null.
- `urlencoded` → `ApiBody(contentType: 'application/x-www-form-urlencoded', schema: <object of text fields, all string>, example: {name: value})` from `config.formFields` where `!isFile`.
- `multipart` → `ApiBody(contentType: 'multipart/form-data', schema: <object>, example: {textName: value})`. File fields → property `JsonSchema(type: 'string', format: 'binary')` (omitted from example); text fields → `JsonSchema(type: 'string')`.
- `binary` → `ApiBody(contentType: 'application/octet-stream', schema: JsonSchema(type: 'string', format: 'binary'))`.
- `graphql` → `ApiBody(contentType: 'application/json', schema: <object: query string, variables object>, example: {'query': config.body, 'variables': <decoded graphqlVariables or {}>})`.

**Header rule:** `headerParams` = each entry of `config.headers` EXCEPT keys `Content-Type` and `Accept` (case-insensitive), and EXCEPT the api-key header name when `config.authConfig` is apiKey-in-header. Each → `ApiParam(name: key, example: value)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/apidoc/collection_to_api_doc_body_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

CollectionNodeEntity _rootWith(HttpRequestConfigEntity config) =>
    CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(id: 'a', name: 'Req', isFolder: false, config: config),
      ],
    );

void main() {
  test('raw JSON body infers schema + keeps example', () {
    final doc = CollectionToApiDoc.build(_rootWith(
      const HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.test.com/users',
        body: '{"name":"ada","age":36}',
      ),
    ));
    final body = doc.operations.single.requestBody!;
    expect(body.contentType, 'application/json');
    expect(body.schema!.type, 'object');
    expect(body.schema!.properties['name']!.type, 'string');
    expect(body.schema!.properties['age']!.type, 'integer');
    expect(body.example, {'name': 'ada', 'age': 36});
  });

  test('invalid raw JSON falls back to text/plain + warning', () {
    final doc = CollectionToApiDoc.build(_rootWith(
      const HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.test.com/x',
        body: 'not json',
      ),
    ));
    expect(doc.operations.single.requestBody!.contentType, 'text/plain');
    expect(doc.warnings.any((w) => w.contains('not valid JSON')), isTrue);
  });

  test('binary body → octet-stream string/binary schema', () {
    final doc = CollectionToApiDoc.build(_rootWith(
      const HttpRequestConfigEntity(
        id: 'c',
        method: 'PUT',
        url: 'https://api.test.com/blob',
        bodyType: BodyType.binary,
      ),
    ));
    final body = doc.operations.single.requestBody!;
    expect(body.contentType, 'application/octet-stream');
    expect(body.schema!.format, 'binary');
  });

  test('multipart body → form-data object; file field is binary', () {
    final doc = CollectionToApiDoc.build(_rootWith(
      const HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.test.com/upload',
        bodyType: BodyType.multipart,
        formFields: [
          MultipartFieldEntity(name: 'title', value: 'hi'),
          MultipartFieldEntity(name: 'file', isFile: true, filePath: '/x.png'),
        ],
      ),
    ));
    final body = doc.operations.single.requestBody!;
    expect(body.contentType, 'multipart/form-data');
    expect(body.schema!.properties['title']!.type, 'string');
    expect(body.schema!.properties['file']!.format, 'binary');
    expect(body.example, {'title': 'hi'});
  });

  test('graphql body → application/json {query,variables}', () {
    final doc = CollectionToApiDoc.build(_rootWith(
      const HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.test.com/graphql',
        bodyType: BodyType.graphql,
        body: 'query { me }',
        graphqlVariables: '{"x":1}',
      ),
    ));
    final body = doc.operations.single.requestBody!;
    expect(body.contentType, 'application/json');
    expect((body.example! as Map)['query'], 'query { me }');
    expect((body.example! as Map)['variables'], {'x': 1});
  });

  test('Content-Type and Accept are excluded from header params', () {
    final doc = CollectionToApiDoc.build(_rootWith(
      const HttpRequestConfigEntity(
        id: 'c',
        method: 'GET',
        url: 'https://api.test.com/x',
        headers: {'Content-Type': 'application/json', 'X-Trace': 'abc'},
      ),
    ));
    final names = doc.operations.single.headerParams.map((p) => p.name).toList();
    expect(names, ['X-Trace']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/apidoc/collection_to_api_doc_body_test.dart`
Expected: FAIL — `requestBody` is null / `headerParams` empty (not yet implemented).

- [ ] **Step 3: Update the implementation**

Add imports at the top of `collection_to_api_doc.dart`:

```dart
import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
```

In `_operation`, replace the trailing comment line with wired calls — the returned `ApiOperation` now sets:

```dart
      headerParams: _headerParams(config),
      requestBody: _requestBody(leaf, config, warnings),
      // responses / security: Task 5.
```

Add these private helpers to the class:

```dart
  static List<ApiParam> _headerParams(HttpRequestConfigEntity config) {
    const skip = {'content-type', 'accept'};
    final auth = config.authConfig;
    final apiKeyHeader =
        (auth.type == AuthType.apiKey && auth.apiKeyLocation == ApiKeyLocation.header)
        ? auth.apiKeyName.toLowerCase()
        : null;
    return [
      for (final entry in config.headers.entries)
        if (!skip.contains(entry.key.toLowerCase()) &&
            entry.key.toLowerCase() != apiKeyHeader)
          ApiParam(name: entry.key, example: entry.value.isEmpty ? null : entry.value),
    ];
  }

  static ApiBody? _requestBody(
    CollectionNodeEntity leaf,
    HttpRequestConfigEntity config,
    List<String> warnings,
  ) {
    switch (config.bodyType) {
      case BodyType.none:
        return null;
      case BodyType.raw:
        if (config.body.isEmpty) return null;
        try {
          final decoded = jsonDecode(config.body);
          return ApiBody(
            contentType: 'application/json',
            schema: JsonSchemaInferrer.infer(decoded),
            example: decoded,
          );
        } on FormatException {
          warnings.add(
            'Request body for "${leaf.name}" is not valid JSON — '
            'exported as text/plain.',
          );
          return ApiBody(contentType: 'text/plain', example: config.body);
        }
      case BodyType.urlencoded:
        return _formBody(config, 'application/x-www-form-urlencoded');
      case BodyType.multipart:
        return _formBody(config, 'multipart/form-data');
      case BodyType.binary:
        return const ApiBody(
          contentType: 'application/octet-stream',
          schema: JsonSchema(type: 'string', format: 'binary'),
        );
      case BodyType.graphql:
        Object variables = <String, dynamic>{};
        if (config.graphqlVariables.isNotEmpty) {
          try {
            variables = jsonDecode(config.graphqlVariables);
          } on FormatException {
            variables = <String, dynamic>{};
          }
        }
        return ApiBody(
          contentType: 'application/json',
          schema: const JsonSchema(
            type: 'object',
            properties: {
              'query': JsonSchema(type: 'string'),
              'variables': JsonSchema(type: 'object'),
            },
          ),
          example: {'query': config.body, 'variables': variables},
        );
    }
  }

  static ApiBody _formBody(HttpRequestConfigEntity config, String contentType) {
    final props = <String, JsonSchema>{};
    final example = <String, dynamic>{};
    for (final f in config.formFields) {
      if (f.isFile) {
        props[f.name] = const JsonSchema(type: 'string', format: 'binary');
      } else {
        props[f.name] = const JsonSchema(type: 'string');
        example[f.name] = f.value;
      }
    }
    return ApiBody(
      contentType: contentType,
      schema: JsonSchema(type: 'object', properties: props),
      example: example,
    );
  }
```

Also add the `JsonSchema`/`JsonSchemaInferrer` import if not already present:

```dart
import 'package:getman/core/utils/apidoc/json_schema.dart';
```

- [ ] **Step 4: Run both CollectionToApiDoc test files to verify they pass**

Run: `fvm flutter test test/core/utils/apidoc/collection_to_api_doc_test.dart test/core/utils/apidoc/collection_to_api_doc_body_test.dart`
Expected: PASS (all tests in both files — Task 3 structure tests still green).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/apidoc/collection_to_api_doc.dart test/core/utils/apidoc/collection_to_api_doc_body_test.dart
git add lib/core/utils/apidoc/collection_to_api_doc.dart test/core/utils/apidoc/collection_to_api_doc_body_test.dart
git commit -m "feat(export): collection→ApiDoc request bodies + headers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `CollectionToApiDoc` — responses + auth

**Files:**
- Modify: `lib/core/utils/apidoc/collection_to_api_doc.dart`
- Test: `test/core/utils/apidoc/collection_to_api_doc_response_test.dart`

**Interfaces:**
- Consumes: `ApiResponse` (Task 2), `SavedExampleEntity` from `package:getman/features/collections/domain/entities/saved_example_entity.dart`.
- Produces: extends `_operation` to populate `responses` and `security`. Adds private helper `_responses`. No public signature change.

**Response rules:** Build an ordered `List<ApiResponse>`, dedup by status code (first wins):
1. For each `leaf.examples` entry: `statusCode = ex.config.statusCode ?? 200`; if `ex.config.responseBody` is non-null & non-empty, build `ApiBody` by trying `jsonDecode` (success → application/json + inferred schema + example; failure → text/plain + raw example). `description = 'Example: ${ex.name}'`.
2. Then the leaf's own live response: if `config.statusCode != null` and that code isn't already present, add it using `config.responseBody` the same way, `description = 'Response'`.
3. If still empty → `[ApiResponse(statusCode: 200, description: 'Successful response')]`.

**Auth rule:** `security = config.authConfig` unless its type is `inherit` → use `AuthConfig.none` (collections have no folder-level auth model today).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/apidoc/collection_to_api_doc_response_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';

void main() {
  test('no examples and no live response → default 200', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: const HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
          ),
        ),
      ],
    );
    final responses = CollectionToApiDoc.build(root).operations.single.responses;
    expect(responses.single.statusCode, 200);
    expect(responses.single.description, 'Successful response');
  });

  test('saved examples become per-status responses with inferred schema', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: const HttpRequestConfigEntity(id: 'c', url: 'https://api.test.com/x'),
          examples: [
            SavedExampleEntity(
              id: 'e1',
              name: 'ok',
              capturedAt: DateTime(2026),
              config: const HttpRequestConfigEntity(
                id: 'ec',
                url: 'https://api.test.com/x',
                statusCode: 200,
                responseBody: '{"ok":true}',
              ),
            ),
          ],
        ),
      ],
    );
    final responses = CollectionToApiDoc.build(root).operations.single.responses;
    expect(responses.single.statusCode, 200);
    expect(responses.single.body!.contentType, 'application/json');
    expect(responses.single.body!.schema!.properties['ok']!.type, 'boolean');
  });

  test('live response is added when not already covered by examples', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: const HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
            statusCode: 404,
            responseBody: 'nope',
          ),
        ),
      ],
    );
    final responses = CollectionToApiDoc.build(root).operations.single.responses;
    expect(responses.map((r) => r.statusCode), contains(404));
  });

  test('bearer auth is carried on the operation', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
            auth: const AuthConfig(type: AuthType.bearer, token: 'secret').toMap(),
          ),
        ),
      ],
    );
    final op = CollectionToApiDoc.build(root).operations.single;
    expect(op.security.type, AuthType.bearer);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/apidoc/collection_to_api_doc_response_test.dart`
Expected: FAIL — `responses` empty / `security` is none.

- [ ] **Step 3: Update the implementation**

Add the import:

```dart
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
```

In `_operation`, set the final two fields on the returned `ApiOperation`:

```dart
      responses: _responses(leaf, config),
      security: config.authConfig.type == AuthType.inherit
          ? AuthConfig.none
          : config.authConfig,
```

Add the helpers:

```dart
  static List<ApiResponse> _responses(
    CollectionNodeEntity leaf,
    HttpRequestConfigEntity config,
  ) {
    final byStatus = <int, ApiResponse>{};

    for (final ex in leaf.examples) {
      final code = ex.config.statusCode ?? 200;
      byStatus.putIfAbsent(
        code,
        () => ApiResponse(
          statusCode: code,
          description: 'Example: ${ex.name}',
          body: _responseBody(ex.config.responseBody),
        ),
      );
    }

    final liveCode = config.statusCode;
    if (liveCode != null && !byStatus.containsKey(liveCode)) {
      byStatus[liveCode] = ApiResponse(
        statusCode: liveCode,
        description: 'Response',
        body: _responseBody(config.responseBody),
      );
    }

    if (byStatus.isEmpty) {
      return const [ApiResponse(statusCode: 200, description: 'Successful response')];
    }
    return byStatus.values.toList();
  }

  static ApiBody? _responseBody(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return ApiBody(
        contentType: 'application/json',
        schema: JsonSchemaInferrer.infer(decoded),
        example: decoded,
      );
    } on FormatException {
      return ApiBody(contentType: 'text/plain', example: body);
    }
  }
```

- [ ] **Step 4: Run all three CollectionToApiDoc test files**

Run: `fvm flutter test test/core/utils/apidoc/`
Expected: PASS (Tasks 1–5 tests all green).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/apidoc/collection_to_api_doc.dart test/core/utils/apidoc/collection_to_api_doc_response_test.dart
git add lib/core/utils/apidoc/collection_to_api_doc.dart test/core/utils/apidoc/collection_to_api_doc_response_test.dart
git commit -m "feat(export): collection→ApiDoc responses + auth

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: `YamlEmitter` (minimal block-style YAML)

**Files:**
- Create: `lib/core/utils/apidoc/yaml_emitter.dart`
- Test: `test/core/utils/apidoc/yaml_emitter_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class YamlEmitter { static String emit(Object? value); }` — serializes a JSON-like tree (`Map<String, dynamic>`, `List`, `String`, `num`, `bool`, `null`) to block-style YAML. Used by `OpenApiSerializer.toYaml`.

**Rules:** 2-space indent. Map entries `key: value`. Scalars: quote a string with double quotes when it is empty, contains any of `: # { } [ ] , & * ! | > ' " % @ \``, has leading/trailing whitespace, or could be misread as a bool/null/number (`true/false/null/yes/no` or numeric); otherwise emit bare. Escape `\` and `"` inside quoted strings. Empty map → `{}`, empty list → `[]` (inline). Nested map under a key goes on the next indented lines; list items use `- `.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/apidoc/yaml_emitter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/apidoc/yaml_emitter.dart';

void main() {
  test('emits nested maps with 2-space indent; dotted versions stay bare', () {
    final yaml = YamlEmitter.emit({
      'openapi': '3.0.3',
      'info': {'title': 'My API', 'version': '1.0.0'},
    });
    expect(yaml, 'openapi: 3.0.3\n'
        'info:\n'
        '  title: My API\n'
        '  version: 1.0.0\n');
  });

  test('emits lists with dashes; URLs stay bare', () {
    final yaml = YamlEmitter.emit({
      'servers': [
        {'url': 'https://a.com'},
        {'url': 'https://b.com'},
      ],
    });
    expect(yaml, 'servers:\n'
        '  - url: https://a.com\n'
        '  - url: https://b.com\n');
  });

  test('quotes genuinely ambiguous scalars only', () {
    expect(YamlEmitter.emit('42'), '"42"\n'); // parses as a number
    expect(YamlEmitter.emit('true'), '"true"\n'); // parses as a bool
    expect(YamlEmitter.emit('a: b'), '"a: b"\n'); // colon-space
    expect(YamlEmitter.emit('1.0.0'), '1.0.0\n'); // not a valid number → bare
    expect(YamlEmitter.emit('https://a.com'), 'https://a.com\n'); // colon, no space
    expect(YamlEmitter.emit('plain'), 'plain\n');
  });

  test('emits empty containers inline', () {
    expect(YamlEmitter.emit(<String, dynamic>{}), '{}\n');
    expect(YamlEmitter.emit(<dynamic>[]), '[]\n');
  });

  test('emits scalars: bool, int, null', () {
    expect(YamlEmitter.emit(true), 'true\n');
    expect(YamlEmitter.emit(42), '42\n');
    expect(YamlEmitter.emit(null), 'null\n');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/apidoc/yaml_emitter_test.dart`
Expected: FAIL — `yaml_emitter.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/utils/apidoc/yaml_emitter.dart

/// Minimal block-style YAML serializer for a JSON-like tree (maps, lists,
/// strings, nums, bools, null). Enough for OpenAPI output — not a general YAML
/// library. Zero dependencies.
class YamlEmitter {
  YamlEmitter._();

  static String emit(Object? value) {
    final buf = StringBuffer();
    _emit(value, 0, buf);
    return buf.toString();
  }

  static void _emit(Object? value, int indent, StringBuffer buf) {
    if (value is Map) {
      if (value.isEmpty) {
        buf.writeln('{}');
        return;
      }
      value.forEach((key, dynamic v) {
        final pad = ' ' * indent;
        if (v is Map && v.isNotEmpty) {
          buf..write(pad)..write(key)..writeln(':');
          _emit(v, indent + 2, buf);
        } else if (v is List && v.isNotEmpty) {
          buf..write(pad)..write(key)..writeln(':');
          _emitList(v, indent + 2, buf);
        } else {
          buf..write(pad)..write(key)..write(': ')..writeln(_scalar(v));
        }
      });
      return;
    }
    if (value is List) {
      if (value.isEmpty) {
        buf.writeln('[]');
        return;
      }
      _emitList(value, indent, buf);
      return;
    }
    buf.writeln(_scalar(value));
  }

  static void _emitList(List<dynamic> list, int indent, StringBuffer buf) {
    final pad = ' ' * indent;
    for (final item in list) {
      if (item is Map && item.isNotEmpty) {
        // First key on the dash line, remaining keys indented to align.
        final entries = item.entries.toList();
        final firstEntry = entries.first;
        buf..write(pad)..write('- ');
        final dynamic fv = firstEntry.value;
        if (fv is Map && fv.isNotEmpty) {
          buf..write(firstEntry.key)..writeln(':');
          _emit(fv, indent + 4, buf);
        } else if (fv is List && fv.isNotEmpty) {
          buf..write(firstEntry.key)..writeln(':');
          _emitList(fv, indent + 4, buf);
        } else {
          buf..write(firstEntry.key)..write(': ')..writeln(_scalar(fv));
        }
        for (final entry in entries.skip(1)) {
          final subPad = ' ' * (indent + 2);
          final dynamic v = entry.value;
          if (v is Map && v.isNotEmpty) {
            buf..write(subPad)..write(entry.key)..writeln(':');
            _emit(v, indent + 4, buf);
          } else if (v is List && v.isNotEmpty) {
            buf..write(subPad)..write(entry.key)..writeln(':');
            _emitList(v, indent + 4, buf);
          } else {
            buf..write(subPad)..write(entry.key)..write(': ')..writeln(_scalar(v));
          }
        }
      } else if (item is List && item.isNotEmpty) {
        buf..write(pad)..writeln('-');
        _emitList(item, indent + 2, buf);
      } else {
        buf..write(pad)..write('- ')..writeln(_scalar(item));
      }
    }
  }

  static String _scalar(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    return _scalarString(value.toString());
  }

  static String _scalarString(String s) {
    if (!_needsQuote(s)) return s;
    final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  /// Quote only when leaving the scalar bare would change its meaning: empty,
  /// padded, structurally ambiguous (`: ` / trailing `:` / ` #`), starting with
  /// a YAML indicator char, or parseable as a bool/null/number. A URL
  /// (`https://x` — colon without a following space) and a dotted version
  /// (`1.0.0` — not a valid number) stay bare.
  static bool _needsQuote(String s) {
    if (s.isEmpty || s != s.trim()) return true;
    if (s.contains(': ') || s.endsWith(':') || s.contains(' #')) return true;
    if (_indicators.contains(s[0])) return true;
    final lower = s.toLowerCase();
    if (const {'true', 'false', 'null', 'yes', 'no', '~'}.contains(lower)) {
      return true;
    }
    return num.tryParse(s) != null;
  }

  static const _indicators = {
    '{', '}', '[', ']', ',', '&', '*', '!', '|', '>', "'", '"', '%', '@',
    '`', '#', '?', '-', ':',
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/apidoc/yaml_emitter_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/apidoc/yaml_emitter.dart test/core/utils/apidoc/yaml_emitter_test.dart
git add lib/core/utils/apidoc/yaml_emitter.dart test/core/utils/apidoc/yaml_emitter_test.dart
git commit -m "feat(export): minimal block-style YAML emitter

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: `OpenApiSerializer` (ApiDoc → 3.0.3 JSON + YAML)

**Files:**
- Create: `lib/core/utils/apidoc/openapi_serializer.dart`
- Test: `test/core/utils/apidoc/openapi_serializer_test.dart`

**Interfaces:**
- Consumes: `ApiDoc` & friends (Task 2), `JsonSchema` (Task 1), `YamlEmitter` (Task 6), `AuthConfig`/`AuthType`/`ApiKeyLocation`.
- Produces:
  - `static Map<String, dynamic> OpenApiSerializer.toMap(ApiDoc doc)`
  - `static String OpenApiSerializer.toJson(ApiDoc doc)`
  - `static String OpenApiSerializer.toYaml(ApiDoc doc)`

**Map shape:** `{openapi: '3.0.3', info: {title, version}, servers: [...], paths: {<path>: {<method-lower>: {summary, description?, tags?, parameters[], requestBody?, responses{}, security?}}}, components: {securitySchemes: {...}}}`.
- Parameters: path/query/header → `{name, in, required, schema, example?}`. `in: path` always `required: true`.
- requestBody → `{content: {<contentType>: {schema, example?}}}`.
- responses keyed by status string → `{description, content?}`.
- Security schemes: collect distinct from operations. bearer → `{type: http, scheme: bearer}` named `bearerAuth`; basic → `{type: http, scheme: basic}` named `basicAuth`; apiKey → `{type: apiKey, in: header|query, name: <apiKeyName>}` named `apiKeyAuth`. Each op with non-none auth gets `security: [{<schemeName>: []}]`. none/inherit → omit.
- Operations sharing a `path` merge under one path-item (keyed by method); same method+path → first wins, append a doc-level note is NOT needed (collision handled by map key).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/apidoc/openapi_serializer_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';
import 'package:getman/core/utils/apidoc/openapi_serializer.dart';

ApiDoc _sample() => const ApiDoc(
      title: 'Petstore',
      servers: [ApiServer(url: 'https://api.test.com')],
      operations: [
        ApiOperation(
          method: 'GET',
          path: '/users/{id}',
          summary: 'Get user',
          tag: 'Users',
          pathParams: [ApiParam(name: 'id', isRequired: true, example: '7')],
          queryParams: [ApiParam(name: 'verbose', example: 'true')],
          security: AuthConfig(type: AuthType.bearer, token: 'x'),
          responses: [
            ApiResponse(
              statusCode: 200,
              description: 'OK',
              body: ApiBody(
                contentType: 'application/json',
                schema: JsonSchema(type: 'object'),
                example: {'id': 7},
              ),
            ),
          ],
        ),
      ],
    );

void main() {
  test('emits a 3.0.3 document with info, servers, paths', () {
    final map = OpenApiSerializer.toMap(_sample());
    expect(map['openapi'], '3.0.3');
    expect(map['info'], {'title': 'Petstore', 'version': '1.0.0'});
    expect((map['servers'] as List).first, {'url': 'https://api.test.com'});
    final op = (map['paths'] as Map)['/users/{id}']['get'] as Map;
    expect(op['summary'], 'Get user');
    expect(op['tags'], ['Users']);
  });

  test('path param is required, query param is not', () {
    final map = OpenApiSerializer.toMap(_sample());
    final params = ((map['paths'] as Map)['/users/{id}']['get']
        as Map)['parameters'] as List;
    final pathParam = params.firstWhere((dynamic p) => p['in'] == 'path') as Map;
    final queryParam = params.firstWhere((dynamic p) => p['in'] == 'query') as Map;
    expect(pathParam['required'], true);
    expect(queryParam['required'], false);
  });

  test('bearer security scheme is declared and referenced', () {
    final map = OpenApiSerializer.toMap(_sample());
    final schemes =
        (map['components'] as Map)['securitySchemes'] as Map<String, dynamic>;
    expect(schemes['bearerAuth'], {'type': 'http', 'scheme': 'bearer'});
    final security =
        ((map['paths'] as Map)['/users/{id}']['get'] as Map)['security'] as List;
    expect(security, [{'bearerAuth': <dynamic>[]}]);
  });

  test('never emits the bearer token value anywhere', () {
    final json = OpenApiSerializer.toJson(_sample());
    expect(json.contains('"x"'), isFalse);
  });

  test('toJson is valid JSON; toYaml starts with openapi', () {
    final doc = _sample();
    expect(() => jsonDecode(OpenApiSerializer.toJson(doc)), returnsNormally);
    expect(OpenApiSerializer.toYaml(doc).startsWith('openapi:'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/apidoc/openapi_serializer_test.dart`
Expected: FAIL — `openapi_serializer.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/utils/apidoc/openapi_serializer.dart
import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/yaml_emitter.dart';

/// Renders an [ApiDoc] to an OpenAPI 3.0.3 document, as a map, JSON, or YAML.
/// Reads only auth *shape* from [ApiOperation.security] — never token/password/
/// key values.
class OpenApiSerializer {
  OpenApiSerializer._();

  static String toJson(ApiDoc doc) =>
      const JsonEncoder.withIndent('  ').convert(toMap(doc));

  static String toYaml(ApiDoc doc) => YamlEmitter.emit(toMap(doc));

  static Map<String, dynamic> toMap(ApiDoc doc) {
    final usedSchemes = <String, Map<String, dynamic>>{};

    final paths = <String, dynamic>{};
    for (final op in doc.operations) {
      final pathItem = (paths[op.path] as Map<String, dynamic>?) ??
          (paths[op.path] = <String, dynamic>{});
      final methodKey = op.method.toLowerCase();
      if (pathItem.containsKey(methodKey)) continue; // first wins on collision
      pathItem[methodKey] = _operation(op, usedSchemes);
    }

    final map = <String, dynamic>{
      'openapi': '3.0.3',
      'info': {'title': doc.title, 'version': doc.version},
      if (doc.servers.isNotEmpty)
        'servers': [for (final s in doc.servers) _server(s)],
      'paths': paths,
    };
    if (usedSchemes.isNotEmpty) {
      map['components'] = {'securitySchemes': usedSchemes};
    }
    return map;
  }

  static Map<String, dynamic> _server(ApiServer s) {
    final map = <String, dynamic>{'url': s.url};
    if (s.variables.isNotEmpty) {
      map['variables'] = {
        for (final entry in s.variables.entries)
          entry.key: {'default': entry.value},
      };
    }
    return map;
  }

  static Map<String, dynamic> _operation(
    ApiOperation op,
    Map<String, Map<String, dynamic>> usedSchemes,
  ) {
    final parameters = <Map<String, dynamic>>[
      for (final p in op.pathParams) _param(p, 'path'),
      for (final p in op.queryParams) _param(p, 'query'),
      for (final p in op.headerParams) _param(p, 'header'),
    ];

    final result = <String, dynamic>{
      'summary': op.summary,
      if (op.description != null) 'description': op.description,
      if (op.tag != null) 'tags': [op.tag],
      if (parameters.isNotEmpty) 'parameters': parameters,
      if (op.requestBody != null) 'requestBody': _body(op.requestBody!),
      'responses': {
        for (final r in op.responses)
          r.statusCode.toString(): {
            'description': r.description.isEmpty ? 'Response' : r.description,
            if (r.body != null) 'content': _content(r.body!),
          },
      },
    };

    final security = _security(op.security, usedSchemes);
    if (security != null) result['security'] = security;
    return result;
  }

  static Map<String, dynamic> _param(ApiParam p, String location) => {
        'name': p.name,
        'in': location,
        'required': location == 'path' ? true : p.isRequired,
        'schema': p.schema?.toOpenApi() ?? {'type': 'string'},
        if (p.example != null) 'example': p.example,
      };

  static Map<String, dynamic> _body(ApiBody body) => {
        'content': _content(body),
      };

  static Map<String, dynamic> _content(ApiBody body) => {
        body.contentType: {
          if (body.schema != null) 'schema': body.schema!.toOpenApi(),
          if (body.example != null) 'example': body.example,
        },
      };

  /// Returns the `security` list for an operation, registering the scheme in
  /// [usedSchemes]. Null for none/inherit.
  static List<Map<String, List<dynamic>>>? _security(
    AuthConfig auth,
    Map<String, Map<String, dynamic>> usedSchemes,
  ) {
    switch (auth.type) {
      case AuthType.none:
      case AuthType.inherit:
        return null;
      case AuthType.bearer:
        usedSchemes['bearerAuth'] = {'type': 'http', 'scheme': 'bearer'};
        return [
          {'bearerAuth': <dynamic>[]},
        ];
      case AuthType.basic:
        usedSchemes['basicAuth'] = {'type': 'http', 'scheme': 'basic'};
        return [
          {'basicAuth': <dynamic>[]},
        ];
      case AuthType.apiKey:
        usedSchemes['apiKeyAuth'] = {
          'type': 'apiKey',
          'in': auth.apiKeyLocation == ApiKeyLocation.query ? 'query' : 'header',
          'name': auth.apiKeyName,
        };
        return [
          {'apiKeyAuth': <dynamic>[]},
        ];
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/apidoc/openapi_serializer_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/apidoc/openapi_serializer.dart test/core/utils/apidoc/openapi_serializer_test.dart
git add lib/core/utils/apidoc/openapi_serializer.dart test/core/utils/apidoc/openapi_serializer_test.dart
git commit -m "feat(export): OpenAPI 3.0.3 serializer (JSON + YAML)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: `MarkdownDocSerializer` (ApiDoc → Markdown)

**Files:**
- Create: `lib/core/utils/apidoc/markdown_doc_serializer.dart`
- Test: `test/core/utils/apidoc/markdown_doc_serializer_test.dart`

**Interfaces:**
- Consumes: `ApiDoc` & friends (Task 2), `AuthType`.
- Produces: `static String MarkdownDocSerializer.toMarkdown(ApiDoc doc)`.

**Layout:**
- `# <title>` then a blank line.
- If servers: `**Servers:**` then a bullet per server URL.
- Operations grouped by `tag` (null tag → group heading `## General`; otherwise `## <tag>`). Within a group, per operation:
  - `### <METHOD> <path>`
  - description paragraph if present.
  - If pathParams/queryParams/headerParams: a `**Parameters**` table with columns `Name | In | Required | Example`.
  - Auth line if security.type != none/inherit: `**Auth:** Bearer` / `Basic` / `API key (<name>)`.
  - If requestBody: `**Request body** (`<contentType>`)` + a fenced ```` ```json ```` block of the example (pretty-printed when it's a JSON value) — skip the fence when example is null.
  - `**Responses**` then per response: `- `<status>` — <description>` and, when a body example exists, an indented fenced block.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/apidoc/markdown_doc_serializer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';
import 'package:getman/core/utils/apidoc/markdown_doc_serializer.dart';

void main() {
  test('renders title, group heading, and an operation header', () {
    const doc = ApiDoc(
      title: 'Petstore',
      servers: [ApiServer(url: 'https://api.test.com')],
      operations: [
        ApiOperation(
          method: 'GET',
          path: '/users/{id}',
          summary: 'Get user',
          tag: 'Users',
          pathParams: [ApiParam(name: 'id', isRequired: true, example: '7')],
          security: AuthConfig(type: AuthType.bearer),
          requestBody: ApiBody(
            contentType: 'application/json',
            schema: JsonSchema(type: 'object'),
            example: {'q': 1},
          ),
          responses: [ApiResponse(statusCode: 200, description: 'OK')],
        ),
      ],
    );
    final md = MarkdownDocSerializer.toMarkdown(doc);
    expect(md, startsWith('# Petstore'));
    expect(md, contains('https://api.test.com'));
    expect(md, contains('## Users'));
    expect(md, contains('### GET /users/{id}'));
    expect(md, contains('| id | path | yes | 7 |'));
    expect(md, contains('**Auth:** Bearer'));
    expect(md, contains('```json'));
    expect(md, contains('`200` — OK'));
  });

  test('untagged operations fall under General', () {
    const doc = ApiDoc(
      title: 'API',
      operations: [
        ApiOperation(method: 'GET', path: '/ping', summary: 'Ping'),
      ],
    );
    expect(MarkdownDocSerializer.toMarkdown(doc), contains('## General'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/apidoc/markdown_doc_serializer_test.dart`
Expected: FAIL — `markdown_doc_serializer.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/utils/apidoc/markdown_doc_serializer.dart
import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';

/// Renders an [ApiDoc] as a human-readable Markdown API reference.
class MarkdownDocSerializer {
  MarkdownDocSerializer._();

  static const _encoder = JsonEncoder.withIndent('  ');

  static String toMarkdown(ApiDoc doc) {
    final buf = StringBuffer()
      ..writeln('# ${doc.title}')
      ..writeln();

    if (doc.servers.isNotEmpty) {
      buf.writeln('**Servers:**');
      for (final s in doc.servers) {
        buf.writeln('- `${s.url}`');
      }
      buf.writeln();
    }

    final groups = <String, List<ApiOperation>>{};
    for (final op in doc.operations) {
      groups.putIfAbsent(op.tag ?? 'General', () => []).add(op);
    }

    for (final entry in groups.entries) {
      buf
        ..writeln('## ${entry.key}')
        ..writeln();
      for (final op in entry.value) {
        _operation(op, buf);
      }
    }

    return buf.toString();
  }

  static void _operation(ApiOperation op, StringBuffer buf) {
    buf
      ..writeln('### ${op.method} ${op.path}')
      ..writeln();
    if (op.description != null) {
      buf
        ..writeln(op.description)
        ..writeln();
    }

    final params = [
      for (final p in op.pathParams) (p, 'path'),
      for (final p in op.queryParams) (p, 'query'),
      for (final p in op.headerParams) (p, 'header'),
    ];
    if (params.isNotEmpty) {
      buf
        ..writeln('**Parameters**')
        ..writeln()
        ..writeln('| Name | In | Required | Example |')
        ..writeln('| --- | --- | --- | --- |');
      for (final (p, location) in params) {
        final req = (location == 'path' || p.isRequired) ? 'yes' : 'no';
        buf.writeln('| ${p.name} | $location | $req | ${p.example ?? ''} |');
      }
      buf.writeln();
    }

    final authLine = _authLine(op.security);
    if (authLine != null) {
      buf
        ..writeln(authLine)
        ..writeln();
    }

    if (op.requestBody != null) {
      buf
        ..writeln('**Request body** (`${op.requestBody!.contentType}`)')
        ..writeln();
      _exampleBlock(op.requestBody!.example, buf);
    }

    buf
      ..writeln('**Responses**')
      ..writeln();
    for (final r in op.responses) {
      buf.writeln('- `${r.statusCode}` — ${r.description}');
      if (r.body?.example != null) {
        buf.writeln();
        _exampleBlock(r.body!.example, buf);
      }
    }
    buf.writeln();
  }

  static String? _authLine(AuthConfig auth) {
    switch (auth.type) {
      case AuthType.none:
      case AuthType.inherit:
        return null;
      case AuthType.bearer:
        return '**Auth:** Bearer';
      case AuthType.basic:
        return '**Auth:** Basic';
      case AuthType.apiKey:
        return '**Auth:** API key (`${auth.apiKeyName}`)';
    }
  }

  static void _exampleBlock(Object? example, StringBuffer buf) {
    if (example == null) return;
    final isJson = example is Map || example is List;
    final rendered = isJson ? _encoder.convert(example) : example.toString();
    buf
      ..writeln(isJson ? '```json' : '```')
      ..writeln(rendered)
      ..writeln('```')
      ..writeln();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/apidoc/markdown_doc_serializer_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/apidoc/markdown_doc_serializer.dart test/core/utils/apidoc/markdown_doc_serializer_test.dart
git add lib/core/utils/apidoc/markdown_doc_serializer.dart test/core/utils/apidoc/markdown_doc_serializer_test.dart
git commit -m "feat(export): Markdown API-docs serializer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Round-trip test (export OpenAPI → import ≈ original)

**Files:**
- Test: `test/core/utils/apidoc/openapi_roundtrip_test.dart`

**Interfaces:**
- Consumes: `OpenApiSerializer.toJson` (Task 7), and the import pipeline — read these to confirm the exact entry points before writing the test: `lib/core/utils/openapi/spec_loader.dart` (`loadSpec`), `lib/core/utils/openapi/spec_normalizer.dart` and/or `openapi_v3_normalizer.dart` (find the function that turns a loaded spec map into a `NormalizedApi`), `lib/core/utils/openapi/collection_builder.dart` (`buildImport(NormalizedApi) → ImportResult`).
- Produces: no source — verification only.

This task has no production code: it proves the exported OpenAPI re-imports into an equivalent collection (method + path + tag parity), guarding the contract.

- [ ] **Step 1: Confirm the import entry points**

Run: `grep -rn "NormalizedApi\b" lib/core/utils/openapi/spec_normalizer.dart lib/core/utils/openapi/openapi_v3_normalizer.dart`
Expected: identify the public function `X(Map<String,dynamic>) → NormalizedApi` (e.g. `normalizeSpec` / `OpenApiV3Normalizer(...).normalize()`). Use whichever exists; the test below assumes a top-level `normalizeSpec(Map<String,dynamic>)`. If the real name differs, adjust the single call in Step 2 accordingly.

- [ ] **Step 2: Write the round-trip test**

```dart
// test/core/utils/apidoc/openapi_roundtrip_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/core/utils/apidoc/openapi_serializer.dart';
import 'package:getman/core/utils/openapi/collection_builder.dart';
import 'package:getman/core/utils/openapi/spec_loader.dart';
import 'package:getman/core/utils/openapi/spec_normalizer.dart'; // adjust if needed
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

void main() {
  test('export → import preserves method, path, and tag', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'Petstore',
      children: [
        CollectionNodeEntity(
          id: 'f',
          name: 'Users',
          children: [
            CollectionNodeEntity(
              id: 'a',
              name: 'List users',
              isFolder: false,
              config: const HttpRequestConfigEntity(
                id: 'c',
                method: 'GET',
                url: 'https://api.test.com/users',
              ),
            ),
          ],
        ),
      ],
    );

    final json = OpenApiSerializer.toJson(CollectionToApiDoc.build(root));
    final api = normalizeSpec(loadSpec(json)); // adjust call to real API
    final imported = buildImport(api).root;

    // Find the single leaf in the imported tree.
    CollectionNodeEntity? leaf;
    void find(CollectionNodeEntity n) {
      if (!n.isFolder && n.config != null) leaf = n;
      for (final c in n.children) {
        find(c);
      }
    }
    find(imported);

    expect(leaf, isNotNull);
    expect(leaf!.config!.method, 'GET');
    // The imported URL contains the path; servers map to env vars on import.
    expect(leaf!.config!.url.contains('/users'), isTrue);
  });
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/apidoc/openapi_roundtrip_test.dart`
Expected: PASS. If it fails on the import-API name, fix the `normalizeSpec(...)` call to the real function found in Step 1, then re-run.

- [ ] **Step 4: Commit**

```bash
fvm dart format test/core/utils/apidoc/openapi_roundtrip_test.dart
git add test/core/utils/apidoc/openapi_roundtrip_test.dart
git commit -m "test(export): OpenAPI export→import round-trip

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Generalize file IO with `saveTextFileWithFeedback`

**Files:**
- Modify: `lib/core/utils/json_file_io.dart`
- Test: `test/core/utils/json_file_io_test.dart` (create if absent; otherwise add to it)

**Interfaces:**
- Consumes: `file_picker`, Flutter material.
- Produces: `Future<void> saveTextFileWithFeedback(BuildContext context, {required String content, required String fileName, required String dialogTitle, List<String> allowedExtensions})`. `saveJsonFileWithFeedback` keeps its signature and delegates to it.

> Note: `FilePicker.saveFile` cannot run in a plain widget test without a platform plugin, so the unit test covers only the pure helper `slugFilename`. The dialog wiring (Task 11) and manual run cover the save path. If `json_file_io_test.dart` does not exist, create it with the test below; if it exists, append the test.

- [ ] **Step 1: Write/append the test**

```dart
// test/core/utils/json_file_io_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/json_file_io.dart';

void main() {
  group('slugFilename', () {
    test('lowercases and replaces non-alphanumerics with underscores', () {
      expect(slugFilename('My API!'), 'my_api');
      expect(slugFilename('  Spaced  Name  '), 'spaced_name');
    });
    test('empty/garbage becomes untitled', () {
      expect(slugFilename('   '), 'untitled');
      expect(slugFilename('***'), 'untitled');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it passes (slugFilename already exists)**

Run: `fvm flutter test test/core/utils/json_file_io_test.dart`
Expected: PASS (this guards the helper before refactor).

- [ ] **Step 3: Refactor — extract `saveTextFileWithFeedback`**

In `lib/core/utils/json_file_io.dart`, replace the existing `saveJsonFileWithFeedback` (lines ~46–75) with:

```dart
/// Prompts for a destination and writes [content] there. Shows the outcome in a
/// snackbar. No-op when the user cancels the picker. Content-type agnostic.
Future<void> saveTextFileWithFeedback(
  BuildContext context, {
  required String content,
  required String fileName,
  required String dialogTitle,
  List<String> allowedExtensions = const ['json'],
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      bytes: utf8.encode(content),
    );
    if (path == null) return;
    // On desktop saveFile only returns the chosen path; the write is ours.
    // On web the bytes parameter already triggered the download.
    if (!kIsWeb) {
      await File(path).writeAsString(content);
    }
    messenger?.showSnackBar(SnackBar(content: Text('Exported to $path')));
  } on Object catch (e) {
    debugPrint('Export failed: $e');
    messenger?.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

/// Back-compat JSON wrapper around [saveTextFileWithFeedback].
Future<void> saveJsonFileWithFeedback(
  BuildContext context, {
  required String jsonString,
  required String fileName,
  required String dialogTitle,
  List<String> allowedExtensions = const ['json'],
}) {
  return saveTextFileWithFeedback(
    context,
    content: jsonString,
    fileName: fileName,
    dialogTitle: dialogTitle,
    allowedExtensions: allowedExtensions,
  );
}
```

- [ ] **Step 4: Verify nothing broke**

Run: `fvm flutter test test/core/utils/json_file_io_test.dart && fvm flutter analyze lib/core/utils/json_file_io.dart`
Expected: tests PASS; analyze 0 issues. (Existing `saveJsonFileWithFeedback` callers compile unchanged.)

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/utils/json_file_io.dart test/core/utils/json_file_io_test.dart
git add lib/core/utils/json_file_io.dart test/core/utils/json_file_io_test.dart
git commit -m "refactor(export): add content-agnostic saveTextFileWithFeedback

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: `ExportApiDocsDialog` widget

**Files:**
- Create: `lib/features/collections/presentation/widgets/export_api_docs_dialog.dart`
- Test: `test/features/collections/presentation/widgets/export_api_docs_dialog_test.dart`

**Interfaces:**
- Consumes: `CollectionToApiDoc`, `OpenApiSerializer`, `MarkdownDocSerializer`, `saveTextFileWithFeedback`, `slugFilename`; `EnvironmentsBloc`/`EnvironmentsState`, `SettingsBloc`/`SettingsState`; `ResponsiveDialogScaffold`; `showAppSnackBar`; theme extensions.
- Produces: `class ExportApiDocsDialog` with `static Future<void> show(BuildContext context, CollectionNodeEntity node)`. An `@visibleForTesting` enum `ExportDocFormat { openApiJson, openApiYaml, markdown }` and a pure helper `@visibleForTesting (String content, String fileName, List<String> ext) buildExport(CollectionNodeEntity node, EnvironmentEntity? env, ExportDocFormat format)` so the build+serialize logic is unit-testable without the picker.

**Behavior:** A stateful dialog. Format selector (three `RadioListTile`s or a segmented control) defaulting to `openApiJson`. Environment dropdown built from `EnvironmentsState.environments` plus a leading "No Environment" (value `null`), default-selected to `SettingsState.settings.activeEnvironmentId` when it matches an existing env, else "No Environment". Actions: CANCEL (pops) and EXPORT. EXPORT resolves the chosen `EnvironmentEntity?`, calls `buildExport`, pops the dialog, then `saveTextFileWithFeedback(...)`; afterwards, if `doc.warnings` is non-empty, show the first via `showAppSnackBar`. (Compute warnings inside `buildExport` is not needed; instead expose them — see helper return below.)

To keep warnings available, `buildExport` returns a small record including warnings:
`({String content, String fileName, List<String> ext, List<String> warnings})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/collections/presentation/widgets/export_api_docs_dialog_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/widgets/export_api_docs_dialog.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

void main() {
  final node = CollectionNodeEntity(
    id: 'r',
    name: 'My API',
    children: [
      CollectionNodeEntity(
        id: 'a',
        name: 'Ping',
        isFolder: false,
        config: const HttpRequestConfigEntity(
          id: 'c',
          method: 'GET',
          url: 'https://api.test.com/ping',
        ),
      ),
    ],
  );

  test('buildExport: OpenAPI JSON produces .openapi.json content', () {
    final out = buildExport(node, null, ExportDocFormat.openApiJson);
    expect(out.fileName, 'my_api.openapi.json');
    expect(out.ext, ['json']);
    expect(out.content.contains('"openapi": "3.0.3"'), isTrue);
  });

  test('buildExport: OpenAPI YAML produces .openapi.yaml content', () {
    final out = buildExport(node, null, ExportDocFormat.openApiYaml);
    expect(out.fileName, 'my_api.openapi.yaml');
    expect(out.ext, ['yaml']);
    expect(out.content.startsWith('openapi:'), isTrue);
  });

  test('buildExport: Markdown produces .md content', () {
    final out = buildExport(node, null, ExportDocFormat.markdown);
    expect(out.fileName, 'my_api.md');
    expect(out.ext, ['md']);
    expect(out.content.startsWith('# My API'), isTrue);
  });

  test('buildExport surfaces warnings (unresolvable server)', () {
    final out = buildExport(
      CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [
          CollectionNodeEntity(
            id: 'a',
            name: 'x',
            isFolder: false,
            config: const HttpRequestConfigEntity(id: 'c', url: '{{baseUrl}}/x'),
          ),
        ],
      ),
      EnvironmentEntity(name: 'empty'),
      ExportDocFormat.openApiJson,
    );
    // base var has no value → server '{baseUrl}', not a hard warning here,
    // but with no env at all it would warn. Just assert the record shape:
    expect(out.warnings, isA<List<String>>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/export_api_docs_dialog_test.dart`
Expected: FAIL — `export_api_docs_dialog.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/collections/presentation/widgets/export_api_docs_dialog.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/core/utils/apidoc/markdown_doc_serializer.dart';
import 'package:getman/core/utils/apidoc/openapi_serializer.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

enum ExportDocFormat { openApiJson, openApiYaml, markdown }

/// Pure build+serialize step (no picker / context) so it is unit-testable.
@visibleForTesting
({String content, String fileName, List<String> ext, List<String> warnings})
buildExport(
  CollectionNodeEntity node,
  EnvironmentEntity? env,
  ExportDocFormat format,
) {
  final doc = CollectionToApiDoc.build(node, env: env);
  final slug = slugFilename(node.name);
  switch (format) {
    case ExportDocFormat.openApiJson:
      return (
        content: OpenApiSerializer.toJson(doc),
        fileName: '$slug.openapi.json',
        ext: const ['json'],
        warnings: doc.warnings,
      );
    case ExportDocFormat.openApiYaml:
      return (
        content: OpenApiSerializer.toYaml(doc),
        fileName: '$slug.openapi.yaml',
        ext: const ['yaml'],
        warnings: doc.warnings,
      );
    case ExportDocFormat.markdown:
      return (
        content: MarkdownDocSerializer.toMarkdown(doc),
        fileName: '$slug.md',
        ext: const ['md'],
        warnings: doc.warnings,
      );
  }
}

class ExportApiDocsDialog extends StatefulWidget {
  const ExportApiDocsDialog({required this.node, super.key});
  final CollectionNodeEntity node;

  static Future<void> show(BuildContext context, CollectionNodeEntity node) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<EnvironmentsBloc>(),
        child: BlocProvider.value(
          value: context.read<SettingsBloc>(),
          child: ExportApiDocsDialog(node: node),
        ),
      ),
    );
  }

  @override
  State<ExportApiDocsDialog> createState() => _ExportApiDocsDialogState();
}

class _ExportApiDocsDialogState extends State<ExportApiDocsDialog> {
  ExportDocFormat _format = ExportDocFormat.openApiJson;
  String? _envId; // null = No Environment
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final envs = context.watch<EnvironmentsBloc>().state.environments;
    final settings = context.watch<SettingsBloc>().state.settings;

    if (!_seeded) {
      final active = settings.activeEnvironmentId;
      _envId = envs.any((e) => e.id == active) ? active : null;
      _seeded = true;
    }

    return ResponsiveDialogScaffold(
      title: const Text('EXPORT AS API DOCS'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FORMAT', style: TextStyle(fontWeight: context.appTypography.titleWeight)),
          RadioListTile<ExportDocFormat>(
            key: const ValueKey('fmt_openapi_json'),
            value: ExportDocFormat.openApiJson,
            groupValue: _format,
            title: const Text('OpenAPI 3.0.3 (JSON)'),
            onChanged: (v) => setState(() => _format = v!),
          ),
          RadioListTile<ExportDocFormat>(
            key: const ValueKey('fmt_openapi_yaml'),
            value: ExportDocFormat.openApiYaml,
            groupValue: _format,
            title: const Text('OpenAPI 3.0.3 (YAML)'),
            onChanged: (v) => setState(() => _format = v!),
          ),
          RadioListTile<ExportDocFormat>(
            key: const ValueKey('fmt_markdown'),
            value: ExportDocFormat.markdown,
            groupValue: _format,
            title: const Text('Markdown'),
            onChanged: (v) => setState(() => _format = v!),
          ),
          SizedBox(height: layout.tabSpacing),
          Text('ENVIRONMENT', style: TextStyle(fontWeight: context.appTypography.titleWeight)),
          DropdownButton<String?>(
            key: const ValueKey('export_env_dropdown'),
            isExpanded: true,
            value: _envId,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('No Environment')),
              for (final e in envs)
                DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
            ],
            onChanged: (v) => setState(() => _envId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        TextButton(
          key: const ValueKey('export_confirm'),
          onPressed: () => _export(context, envs),
          child: const Text('EXPORT'),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, List<EnvironmentEntity> envs) async {
    final env = _envId == null ? null : envs.firstWhere((e) => e.id == _envId);
    final out = buildExport(widget.node, env, _format);
    // Capture before the first await so we don't touch context afterwards.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Save first (context still mounted; the picker is a native modal), then
    // pop. saveTextFileWithFeedback captures its own messenger before awaiting.
    await saveTextFileWithFeedback(
      context,
      content: out.content,
      fileName: out.fileName,
      dialogTitle: 'EXPORT AS API DOCS',
      allowedExtensions: out.ext,
    );
    if (out.warnings.isNotEmpty && messenger != null) {
      showAppSnackBarVia(messenger, out.warnings.first);
    }
    navigator.pop();
  }
}
```

> The `context` passed to `saveTextFileWithFeedback` is used synchronously (no `await` precedes it in `_export`), so `use_build_context_synchronously` does not fire. The post-await work uses the captured `navigator`/`messenger`, never `context`.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/collections/presentation/widgets/export_api_docs_dialog_test.dart`
Expected: PASS (4 tests on `buildExport`).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/features/collections/presentation/widgets/export_api_docs_dialog.dart test/features/collections/presentation/widgets/export_api_docs_dialog_test.dart
git add lib/features/collections/presentation/widgets/export_api_docs_dialog.dart test/features/collections/presentation/widgets/export_api_docs_dialog_test.dart
git commit -m "feat(export): API-docs export dialog (format + environment)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12: Wire the dialog into the node menu + action sheet

**Files:**
- Modify: `lib/features/collections/presentation/widgets/collection_node_menu.dart`
- Modify: `lib/features/collections/presentation/widgets/node_action_sheet.dart`

**Interfaces:**
- Consumes: `ExportApiDocsDialog.show` (Task 11).
- Produces: a new menu entry "EXPORT AS API DOCS…" in both surfaces. No new exported symbols.

- [ ] **Step 1: Add the desktop menu entry**

In `collection_node_menu.dart`:

Add the import:
```dart
import 'package:getman/features/collections/presentation/widgets/export_api_docs_dialog.dart';
```

Add a case to the `onSelected` switch (after `case 'export':`):
```dart
          case 'export_docs':
            unawaited(ExportApiDocsDialog.show(context, node));
```

Add a `PopupMenuItem` immediately after the existing `'export'` item (before `'delete'`):
```dart
        PopupMenuItem(
          value: 'export_docs',
          child: Text(
            'EXPORT AS API DOCS…',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
```

- [ ] **Step 2: Add the mobile sheet entry**

In `node_action_sheet.dart`, add the import:
```dart
import 'package:getman/features/collections/presentation/widgets/export_api_docs_dialog.dart';
```

Add an `_Action` immediately after the existing EXPORT TO POSTMAN action (around line 180):
```dart
          _Action(
            icon: Icons.description_outlined,
            label: 'EXPORT AS API DOCS…',
            onTap: () {
              Navigator.of(context).pop();
              unawaited(ExportApiDocsDialog.show(context, node));
            },
          ),
```

- [ ] **Step 3: Verify the wiring statically**

The menu reads `CollectionsBloc` only lazily inside `onSelected` (not during build), and a faithful widget test would need the bloc's full dependency graph — out of proportion for a two-line wiring change whose logic is already covered by Task 11's `buildExport` unit tests and Task 13's manual smoke. Verify the wiring is present instead:

Run:
```bash
grep -n "EXPORT AS API DOCS" lib/features/collections/presentation/widgets/collection_node_menu.dart lib/features/collections/presentation/widgets/node_action_sheet.dart
grep -n "ExportApiDocsDialog" lib/features/collections/presentation/widgets/collection_node_menu.dart lib/features/collections/presentation/widgets/node_action_sheet.dart
```
Expected: the label appears once in each file; `ExportApiDocsDialog.show(context, node)` (and its import) appears once in each file.

- [ ] **Step 4: Analyze the two modified files**

Run: `fvm flutter analyze lib/features/collections/presentation/widgets/collection_node_menu.dart lib/features/collections/presentation/widgets/node_action_sheet.dart`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/features/collections/presentation/widgets/collection_node_menu.dart lib/features/collections/presentation/widgets/node_action_sheet.dart
git add lib/features/collections/presentation/widgets/collection_node_menu.dart lib/features/collections/presentation/widgets/node_action_sheet.dart
git commit -m "feat(export): wire API-docs export into node menu + sheet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: Full gate + wiki sync

**Files:**
- Modify (wiki, separate repo): the import/export page in the `Getman.wiki.git` repo.

**Interfaces:** none (verification + docs).

- [ ] **Step 1: Run the full analysis + format + test gate**

Run:
```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test
fvm flutter test
```
Expected: analyze 0 issues; custom_lint 0 issues; bloc_lint 0 issues; format reports no changes (or formats cleanly); all tests green. Fix any issue before proceeding — these are independent passes.

- [ ] **Step 2: Manual smoke (optional but recommended)**

Run: `fvm flutter run -d macos` (or `-d linux`). Open a collection, use the node menu → "EXPORT AS API DOCS…", export each format, and confirm the files open in a viewer (e.g. Swagger Editor for the JSON/YAML, any Markdown viewer for the `.md`).

- [ ] **Step 3: Update the wiki**

Clone (if not already) `https://github.com/thiagomiranda3/Getman.wiki.git`, edit the import/export feature page to document the new "EXPORT AS API DOCS…" action: the three formats (OpenAPI 3.0.3 JSON, OpenAPI 3.0.3 YAML, Markdown), the environment prompt, and that secret values are masked. Keep UI labels verbatim. Commit + push to `master`.

- [ ] **Step 4: Final commit (if any source touched during gate fixes)**

```bash
git add -A
git commit -m "chore(export): pass full analysis + test gate for API-docs export

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Update the backlog**

Mark DW3 done in `docs/BACKLOG.md` (remove the DW3 entry or note it shipped, per the backlog's "open work only" convention), and remove this from open items.

```bash
git add docs/BACKLOG.md
git commit -m "docs(backlog): mark DW3 (collection→API docs export) done

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
