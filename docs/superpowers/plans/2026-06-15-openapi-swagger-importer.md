# OpenAPI / Swagger Importer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import OpenAPI 3.x and Swagger 2.0 specs (JSON or YAML, via file / paste / remote-URL) into a new Getman collection plus one environment per declared server, with a selectable preview.

**Architecture:** A pure-Dart pipeline under `lib/core/utils/openapi/` — `spec_loader` (decode JSON/YAML) → `spec_normalizer` (version-sniff + `$ref`-resolve both formats into one `NormalizedApi`) → `collection_builder` (build `CollectionNodeEntity` tree + `List<EnvironmentEntity>` = `ImportResult`). A `SpecImportDialog` (multi-step: source → selectable preview → commit) produces a pruned `ImportResult` via a callback; `collections_list.dart` is the coordinator that dispatches `ImportCollections` + `ImportEnvironments` to the two blocs (no bloc→bloc coupling). Mirrors the existing Postman-import structure (no domain/data split — output is domain entities).

**Tech Stack:** Flutter + flutter_bloc, `yaml` (new dep), `uuid`, `file_picker`, `dio` (via `NetworkService`). Tests: `flutter_test` + `mocktail` (no `bloc_test`).

---

## Design decisions locked in (made during planning — do not re-litigate)

These resolve the spec's open implementation-time questions with safe, deterministic defaults:

1. **Auth credential values are left BLANK** (never pre-filled with `{{var}}`). Send-time substitution of auth credential fields is unverified, and a literal `{{token}}` sent on the wire would be worse than an empty value. Instead we set the auth *type/shape* and create a **labeled empty secret env var** per scheme so the user has an obvious slot to fill. (Resolves spec §6 "implementation-time check".)
2. **`{{baseUrl}}` is concrete**, not nested. Server variables are substituted to their defaults when building `baseUrl` (e.g. `https://{host}/v1` + `host=api.example.com` → `baseUrl=https://api.example.com/v1`). We do **not** also emit separate `{{host}}` env vars, because the resolver is single-pass and a `{{baseUrl}}` whose value contains `{{host}}` would not resolve transitively. (Minor deviation from spec §6 parenthetical, justified by resolver semantics.)
3. **Query params are encoded into the URL** via `UrlQueryUtils.replaceQuery` (the codebase stores query in the URL string; `HttpRequestConfigEntity` has no separate query field).
4. **Environments are not individually selectable** — the preview shows them as a summary; only request leaves have checkboxes. All declared servers always become environments.
5. **Dialog is bloc-agnostic**: `SpecImportDialog.show(context, {required NetworkService networkService, required void Function(ImportResult) onImport})`. The caller reads the two blocs and dispatches. Keeps the dialog unit-testable without bloc mocks.

---

## File structure

**Create (pure logic — `lib/core/utils/openapi/`):**
- `normalized_api.dart` — intermediate model + `ImportResult` (all `Equatable` value objects).
- `ref_resolver.dart` — internal `$ref` resolution with cycle guard.
- `schema_sampler.dart` — sample JSON value from a (resolved) JSON-Schema map.
- `spec_loader.dart` — decode a spec string (JSON or YAML) to `Map<String, dynamic>`.
- `auth_mapper.dart` — `NormalizedSecurityScheme?` → `NormalizedAuth` (AuthConfig + secret var name + warning).
- `openapi_v3_normalizer.dart` — OpenAPI 3.x map → `NormalizedApi`.
- `swagger_v2_normalizer.dart` — Swagger 2.0 map → `NormalizedApi`.
- `spec_normalizer.dart` — version sniff + dispatch; throws `FormatException` on unknown.
- `collection_builder.dart` — `NormalizedApi` → `ImportResult`.
- `import_selection.dart` — leaf-id collection + tree pruning by selected leaf ids.

**Create (UI):**
- `lib/features/collections/presentation/widgets/spec_import_dialog.dart` — the multi-step dialog.

**Modify:**
- `pubspec.yaml` — add `yaml`.
- `lib/features/collections/presentation/widgets/collections_list.dart` — convert the single Postman import button into a menu with "From Postman" + "From OpenAPI / Swagger"; add the coordinator handler.

**Tests (mirror under `test/`):**
- `test/core/utils/openapi/*_test.dart` (one per pure module).
- `test/features/collections/presentation/widgets/spec_import_dialog_test.dart`.

**Wiki (separate `Getman.wiki.git` repo):** an "Importing APIs" section + `_Sidebar.md` entry.

---

## Task 1: Add `yaml` dependency + `spec_loader.dart`

**Files:**
- Modify: `pubspec.yaml` (dependencies section)
- Create: `lib/core/utils/openapi/spec_loader.dart`
- Test: `test/core/utils/openapi/spec_loader_test.dart`

- [ ] **Step 1: Add the dependency**

Run: `fvm flutter pub add yaml`
Expected: `pubspec.yaml` gains `yaml: ^3.1.2` (or current), `pub get` succeeds. Verify `fvm flutter analyze` still says `No issues found!` (the analyzer stack is pinned to 8.4 — `yaml` has no analyzer constraint, so this is safe).

- [ ] **Step 2: Write the failing test**

```dart
// test/core/utils/openapi/spec_loader_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/spec_loader.dart';

void main() {
  group('loadSpec', () {
    test('decodes JSON to a Map', () {
      final map = loadSpec('{"openapi":"3.0.0","info":{"title":"X"}}');
      expect(map['openapi'], '3.0.0');
      expect((map['info'] as Map)['title'], 'X');
    });

    test('decodes YAML to a Map with nested maps/lists normalized', () {
      const yaml = '''
openapi: 3.0.0
info:
  title: X
servers:
  - url: https://api.example.com
''';
      final map = loadSpec(yaml);
      expect(map['openapi'], '3.0.0');
      expect((map['info'] as Map)['title'], 'X');
      final servers = map['servers'] as List;
      expect((servers.first as Map)['url'], 'https://api.example.com');
    });

    test('JSON and equivalent YAML produce equal structures', () {
      final fromJson = loadSpec('{"a":{"b":[1,2]}}');
      final fromYaml = loadSpec('a:\n  b:\n    - 1\n    - 2\n');
      expect(fromJson.toString(), fromYaml.toString());
    });

    test('throws FormatException on garbage', () {
      expect(() => loadSpec(':::not valid:::\n\t['), throwsFormatException);
    });

    test('throws FormatException when the root is not a map', () {
      expect(() => loadSpec('[1,2,3]'), throwsFormatException);
    });
  });
}
```

- [ ] **Step 3: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/spec_loader_test.dart`
Expected: FAIL — `spec_loader.dart` does not exist.

- [ ] **Step 4: Implement**

```dart
// lib/core/utils/openapi/spec_loader.dart
import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Decodes an OpenAPI/Swagger spec [source] (JSON *or* YAML) into a plain,
/// mutable `Map<String, dynamic>` tree (YAML `Map`/`List` nodes converted to
/// Dart `Map`/`List`). Throws [FormatException] if the source can't be parsed
/// or its root is not a map.
Map<String, dynamic> loadSpec(String source) {
  final trimmed = source.trimLeft();
  Object? decoded;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON spec: ${e.message}');
    }
  } else {
    try {
      decoded = _normalizeYaml(loadYaml(source));
    } on Object catch (e) {
      throw FormatException('Invalid YAML spec: $e');
    }
  }
  if (decoded is! Map) {
    throw const FormatException('Spec root must be an object.');
  }
  return Map<String, dynamic>.from(decoded);
}

/// Recursively converts `YamlMap`/`YamlList` into mutable `Map`/`List`.
Object? _normalizeYaml(Object? node) {
  if (node is YamlMap) {
    return <String, dynamic>{
      for (final entry in node.entries)
        entry.key.toString(): _normalizeYaml(entry.value),
    };
  }
  if (node is YamlList) {
    return node.map(_normalizeYaml).toList();
  }
  return node;
}
```

- [ ] **Step 5: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/spec_loader_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/utils/openapi/spec_loader.dart test/core/utils/openapi/spec_loader_test.dart
git commit -m "$(cat <<'EOF'
feat(import): spec loader for JSON/YAML OpenAPI specs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `normalized_api.dart` — intermediate model + `ImportResult`

**Files:**
- Create: `lib/core/utils/openapi/normalized_api.dart`
- Test: `test/core/utils/openapi/normalized_api_test.dart`

These are pure `Equatable` value objects shared by every later task. No behavior beyond equality.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/normalized_api_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';

void main() {
  test('value equality holds for NormalizedOperation', () {
    const a = NormalizedOperation(method: 'GET', path: '/u', name: 'list');
    const b = NormalizedOperation(method: 'GET', path: '/u', name: 'list');
    expect(a, b);
  });

  test('NormalizedSecurityScheme carries kind + apiKeyName', () {
    const s = NormalizedSecurityScheme(
      kind: SecuritySchemeKind.apiKeyHeader,
      apiKeyName: 'X-Key',
    );
    expect(s.kind, SecuritySchemeKind.apiKeyHeader);
    expect(s.apiKeyName, 'X-Key');
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/normalized_api_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/openapi/normalized_api.dart
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

/// A version-agnostic view of an OpenAPI 3.x / Swagger 2.0 spec.
class NormalizedApi extends Equatable {
  const NormalizedApi({
    required this.title,
    this.servers = const [],
    this.operations = const [],
  });

  final String title;
  final List<NormalizedServer> servers;
  final List<NormalizedOperation> operations;

  @override
  List<Object?> get props => [title, servers, operations];
}

class NormalizedServer extends Equatable {
  const NormalizedServer({
    required this.url,
    this.description,
    this.variables = const {},
  });

  /// May contain `{var}` server-variable templates.
  final String url;
  final String? description;

  /// Server-variable name → default value.
  final Map<String, String> variables;

  @override
  List<Object?> get props => [url, description, variables];
}

class NormalizedParam extends Equatable {
  const NormalizedParam({required this.name, this.value = ''});
  final String name;
  final String value;

  @override
  List<Object?> get props => [name, value];
}

class NormalizedBody extends Equatable {
  const NormalizedBody({
    required this.bodyType,
    this.raw = '',
    this.contentType,
    this.formFields = const [],
  });

  final BodyType bodyType;
  final String raw;
  final String? contentType;
  final List<MultipartFieldEntity> formFields;

  @override
  List<Object?> get props => [bodyType, raw, contentType, formFields];
}

enum SecuritySchemeKind {
  bearer,
  basic,
  apiKeyHeader,
  apiKeyQuery,
  oauth2,
  unsupported,
}

class NormalizedSecurityScheme extends Equatable {
  const NormalizedSecurityScheme({required this.kind, this.apiKeyName});
  final SecuritySchemeKind kind;

  /// The header/query parameter name for `apiKey` schemes.
  final String? apiKeyName;

  @override
  List<Object?> get props => [kind, apiKeyName];
}

class NormalizedOperation extends Equatable {
  const NormalizedOperation({
    required this.method,
    required this.path,
    required this.name,
    this.tag,
    this.queryParams = const [],
    this.headerParams = const [],
    this.body,
    this.security,
    this.warnings = const [],
  });

  final String method;

  /// Original path with `{param}` templates (e.g. `/users/{id}`).
  final String path;
  final String name;
  final String? tag;
  final List<NormalizedParam> queryParams;
  final List<NormalizedParam> headerParams;
  final NormalizedBody? body;
  final NormalizedSecurityScheme? security;
  final List<String> warnings;

  @override
  List<Object?> get props =>
      [method, path, name, tag, queryParams, headerParams, body, security,
       warnings];
}

/// The mapped auth for one operation: a Getman [AuthConfig] plus an optional
/// secret env-var name to seed (empty) into every created environment, plus an
/// optional human warning (e.g. unsupported OAuth2).
class NormalizedAuth extends Equatable {
  const NormalizedAuth({required this.config, this.secretVarName, this.warning});
  final AuthConfig config;
  final String? secretVarName;
  final String? warning;

  @override
  List<Object?> get props => [config, secretVarName, warning];
}

/// The product of an import: a single collection [root] node, the
/// [environments] to create, and any non-fatal [warnings] to surface.
class ImportResult extends Equatable {
  const ImportResult({
    required this.root,
    this.environments = const [],
    this.warnings = const [],
  });

  final CollectionNodeEntity root;
  final List<EnvironmentEntity> environments;
  final List<String> warnings;

  @override
  List<Object?> get props => [root, environments, warnings];
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/normalized_api_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/normalized_api.dart test/core/utils/openapi/normalized_api_test.dart
git commit -m "$(cat <<'EOF'
feat(import): normalized intermediate model + ImportResult

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `ref_resolver.dart` — internal `$ref` resolution

**Files:**
- Create: `lib/core/utils/openapi/ref_resolver.dart`
- Test: `test/core/utils/openapi/ref_resolver_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/ref_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/ref_resolver.dart';

void main() {
  final root = <String, dynamic>{
    'components': {
      'schemas': {
        'User': {
          'type': 'object',
          'properties': {
            'id': {'type': 'integer'},
            'manager': {r'$ref': '#/components/schemas/User'}, // cycle
          },
        },
      },
    },
    'definitions': {
      'Pet': {'type': 'object', 'properties': {'name': {'type': 'string'}}},
    },
  };

  test('resolves a #/components/schemas ref one level', () {
    final r = RefResolver(root);
    final user = r.resolve(<String, dynamic>{r'$ref': '#/components/schemas/User'});
    expect(user['type'], 'object');
    expect((user['properties'] as Map).containsKey('id'), isTrue);
  });

  test('resolves a Swagger #/definitions ref', () {
    final r = RefResolver(root);
    final pet = r.resolve(<String, dynamic>{r'$ref': '#/definitions/Pet'});
    expect((pet['properties'] as Map)['name'], isA<Map>());
  });

  test('deepResolve replaces nested refs and breaks cycles', () {
    final r = RefResolver(root);
    final user =
        r.deepResolve(<String, dynamic>{r'$ref': '#/components/schemas/User'})
            as Map<String, dynamic>;
    final manager =
        (user['properties'] as Map)['manager'] as Map<String, dynamic>;
    // Cycle short-circuited to an empty object, not infinite recursion.
    expect(manager, isEmpty);
  });

  test('returns the node unchanged when there is no ref', () {
    final r = RefResolver(root);
    final node = <String, dynamic>{'type': 'string'};
    expect(r.resolve(node), node);
  });

  test('external refs (other files/urls) are left as-is by resolve', () {
    final r = RefResolver(root);
    final node = <String, dynamic>{r'$ref': 'other.yaml#/Thing'};
    expect(r.resolve(node), node); // unresolved; caller may warn
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/ref_resolver_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/openapi/ref_resolver.dart

/// Resolves internal JSON-pointer `$ref`s (`#/...`) within a single spec
/// document. External refs (anything not starting with `#/`) are left intact.
class RefResolver {
  RefResolver(this._root);
  final Map<String, dynamic> _root;

  /// True if [node] is `{ $ref: '#/...' }` (an internal reference).
  bool isInternalRef(Object? node) =>
      node is Map && node[r'$ref'] is String &&
      (node[r'$ref'] as String).startsWith('#/');

  /// One-level resolve: if [node] is an internal `$ref`, return its target
  /// map; otherwise return [node] unchanged. Returns `{}` if the pointer is
  /// dangling.
  Map<String, dynamic> resolve(Map<String, dynamic> node) {
    if (!isInternalRef(node)) return node;
    final target = _follow(node[r'$ref'] as String);
    return target is Map ? Map<String, dynamic>.from(target) : <String, dynamic>{};
  }

  /// Recursively resolves all internal refs in [node], replacing each with a
  /// copy of its target. Cyclic refs are replaced with `{}` to terminate.
  Object? deepResolve(Object? node, [Set<String>? seen]) {
    final visited = seen ?? <String>{};
    if (node is Map) {
      final ref = node[r'$ref'];
      if (ref is String && ref.startsWith('#/')) {
        if (visited.contains(ref)) return <String, dynamic>{}; // cycle
        final target = _follow(ref);
        if (target is! Map) return <String, dynamic>{};
        return deepResolve(
          Map<String, dynamic>.from(target),
          {...visited, ref},
        );
      }
      return <String, dynamic>{
        for (final e in node.entries)
          e.key.toString(): deepResolve(e.value, visited),
      };
    }
    if (node is List) {
      return node.map((e) => deepResolve(e, visited)).toList();
    }
    return node;
  }

  Object? _follow(String ref) {
    // '#/components/schemas/User' -> ['components','schemas','User']
    final parts = ref
        .substring(2)
        .split('/')
        .map((p) => p.replaceAll('~1', '/').replaceAll('~0', '~'));
    Object? current = _root;
    for (final part in parts) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/ref_resolver_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/ref_resolver.dart test/core/utils/openapi/ref_resolver_test.dart
git commit -m "$(cat <<'EOF'
feat(import): internal $ref resolver with cycle guard

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `schema_sampler.dart` — JSON body stub from a schema

**Files:**
- Create: `lib/core/utils/openapi/schema_sampler.dart`
- Test: `test/core/utils/openapi/schema_sampler_test.dart`

Input is an already-`deepResolve`d schema map (no `$ref`s). Produces a Dart value (`Map`/`List`/scalar) for `jsonEncode`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/schema_sampler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/schema_sampler.dart';

void main() {
  test('uses example when present', () {
    expect(sampleSchema({'type': 'string', 'example': 'hi'}), 'hi');
  });

  test('uses default when present and no example', () {
    expect(sampleSchema({'type': 'integer', 'default': 7}), 7);
  });

  test('uses first enum value', () {
    expect(sampleSchema({'enum': ['a', 'b']}), 'a');
  });

  test('object produces a map of sampled properties', () {
    final out = sampleSchema({
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'age': {'type': 'integer'},
        'active': {'type': 'boolean'},
      },
    });
    expect(out, {'name': '', 'age': 0, 'active': false});
  });

  test('array produces a single-element list of the item sample', () {
    final out = sampleSchema({
      'type': 'array',
      'items': {'type': 'string', 'example': 'x'},
    });
    expect(out, ['x']);
  });

  test('allOf merges object properties', () {
    final out = sampleSchema({
      'allOf': [
        {'type': 'object', 'properties': {'a': {'type': 'string'}}},
        {'type': 'object', 'properties': {'b': {'type': 'integer'}}},
      ],
    });
    expect(out, {'a': '', 'b': 0});
  });

  test('untyped node with properties is treated as an object', () {
    final out = sampleSchema({
      'properties': {'k': {'type': 'string'}},
    });
    expect(out, {'k': ''});
  });

  test('depth cap stops runaway nesting and returns {}', () {
    // A self-similar object deeper than the cap collapses to {}.
    Map<String, dynamic> nest(int n) => n == 0
        ? {'type': 'string'}
        : {'type': 'object', 'properties': {'child': nest(n - 1)}};
    final out = sampleSchema(nest(50)) as Map<String, dynamic>;
    expect(out.containsKey('child'), isTrue); // does not throw / hang
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/schema_sampler_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/openapi/schema_sampler.dart

const int _maxDepth = 8;

/// Produces a representative Dart value (Map/List/scalar) for a resolved
/// JSON-Schema [schema], suitable for `jsonEncode`. Honors `example` →
/// `default` → first `enum`, then falls back to a type-based zero value.
Object? sampleSchema(Map<String, dynamic> schema) => _sample(schema, 0);

Object? _sample(Map<String, dynamic> schema, int depth) {
  if (depth > _maxDepth) return <String, dynamic>{};

  if (schema.containsKey('example')) return schema['example'];
  if (schema.containsKey('default')) return schema['default'];
  final enumValues = schema['enum'];
  if (enumValues is List && enumValues.isNotEmpty) return enumValues.first;

  if (schema['allOf'] is List) {
    final merged = <String, dynamic>{};
    for (final part in (schema['allOf'] as List).whereType<Map>()) {
      final sub = _sample(Map<String, dynamic>.from(part), depth);
      if (sub is Map<String, dynamic>) merged.addAll(sub);
    }
    return merged;
  }
  // oneOf/anyOf: sample the first branch.
  for (final key in const ['oneOf', 'anyOf']) {
    final branches = schema[key];
    if (branches is List && branches.isNotEmpty) {
      final first = branches.first;
      if (first is Map) {
        return _sample(Map<String, dynamic>.from(first), depth);
      }
    }
  }

  final type = schema['type'] as String?;
  if (type == 'object' || (type == null && schema['properties'] is Map)) {
    final props = schema['properties'];
    final out = <String, dynamic>{};
    if (props is Map) {
      for (final entry in props.entries) {
        final propSchema = entry.value;
        out[entry.key.toString()] = propSchema is Map
            ? _sample(Map<String, dynamic>.from(propSchema), depth + 1)
            : null;
      }
    }
    return out;
  }
  if (type == 'array') {
    final items = schema['items'];
    if (items is Map) {
      return [_sample(Map<String, dynamic>.from(items), depth + 1)];
    }
    return <dynamic>[];
  }
  switch (type) {
    case 'integer':
    case 'number':
      return 0;
    case 'boolean':
      return false;
    case 'string':
    default:
      return '';
  }
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/schema_sampler_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/schema_sampler.dart test/core/utils/openapi/schema_sampler_test.dart
git commit -m "$(cat <<'EOF'
feat(import): JSON body stub generator from schema

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `auth_mapper.dart` — security scheme → AuthConfig

**Files:**
- Create: `lib/core/utils/openapi/auth_mapper.dart`
- Test: `test/core/utils/openapi/auth_mapper_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/auth_mapper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/openapi/auth_mapper.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';

void main() {
  test('null scheme → none auth, no secret, no warning', () {
    final a = mapAuth(null);
    expect(a.config.type, AuthType.none);
    expect(a.secretVarName, isNull);
    expect(a.warning, isNull);
  });

  test('bearer → bearer auth with blank token + bearerToken secret', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(kind: SecuritySchemeKind.bearer),
    );
    expect(a.config.type, AuthType.bearer);
    expect(a.config.token, '');
    expect(a.secretVarName, 'bearerToken');
  });

  test('basic → basic auth + basicPassword secret', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(kind: SecuritySchemeKind.basic),
    );
    expect(a.config.type, AuthType.basic);
    expect(a.secretVarName, 'basicPassword');
  });

  test('apiKey header → apiKey auth with name + header location', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(
        kind: SecuritySchemeKind.apiKeyHeader,
        apiKeyName: 'X-Api-Key',
      ),
    );
    expect(a.config.type, AuthType.apiKey);
    expect(a.config.apiKeyName, 'X-Api-Key');
    expect(a.config.apiKeyLocation, ApiKeyLocation.header);
    expect(a.config.apiKeyValue, '');
    expect(a.secretVarName, 'apiKey');
  });

  test('apiKey query → apiKey auth with query location', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(
        kind: SecuritySchemeKind.apiKeyQuery,
        apiKeyName: 'token',
      ),
    );
    expect(a.config.apiKeyLocation, ApiKeyLocation.query);
  });

  test('oauth2 → none auth + warning', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(kind: SecuritySchemeKind.oauth2),
    );
    expect(a.config.type, AuthType.none);
    expect(a.warning, isNotNull);
    expect(a.warning, contains('OAuth2'));
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/auth_mapper_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/openapi/auth_mapper.dart
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';

/// Maps a normalized security scheme to a Getman [AuthConfig] (type/shape only,
/// secret values blank) plus an optional secret env-var name to seed and an
/// optional human warning. See plan "Design decisions locked in" #1.
NormalizedAuth mapAuth(NormalizedSecurityScheme? scheme) {
  if (scheme == null) {
    return const NormalizedAuth(config: AuthConfig());
  }
  switch (scheme.kind) {
    case SecuritySchemeKind.bearer:
      return const NormalizedAuth(
        config: AuthConfig(type: AuthType.bearer),
        secretVarName: 'bearerToken',
      );
    case SecuritySchemeKind.basic:
      return const NormalizedAuth(
        config: AuthConfig(type: AuthType.basic),
        secretVarName: 'basicPassword',
      );
    case SecuritySchemeKind.apiKeyHeader:
      return NormalizedAuth(
        config: AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: scheme.apiKeyName ?? '',
        ),
        secretVarName: 'apiKey',
      );
    case SecuritySchemeKind.apiKeyQuery:
      return NormalizedAuth(
        config: AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: scheme.apiKeyName ?? '',
          apiKeyLocation: ApiKeyLocation.query,
        ),
        secretVarName: 'apiKey',
      );
    case SecuritySchemeKind.oauth2:
      return const NormalizedAuth(
        config: AuthConfig(),
        warning: 'OAuth2 security is not yet wired — auth left as None. '
            'Set credentials manually once OAuth2 support lands.',
      );
    case SecuritySchemeKind.unsupported:
      return const NormalizedAuth(
        config: AuthConfig(),
        warning: 'Unsupported security scheme — auth left as None.',
      );
  }
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/auth_mapper_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/auth_mapper.dart test/core/utils/openapi/auth_mapper_test.dart
git commit -m "$(cat <<'EOF'
feat(import): security scheme to AuthConfig mapper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `openapi_v3_normalizer.dart` — OpenAPI 3.x → NormalizedApi

**Files:**
- Create: `lib/core/utils/openapi/openapi_v3_normalizer.dart`
- Test: `test/core/utils/openapi/openapi_v3_normalizer_test.dart`

This is the meatiest pure module. It walks `paths`, builds operations (params split into query/header, path params left in the path string, requestBody → NormalizedBody), resolves the per-operation/global security to a `NormalizedSecurityScheme`, and reads `servers`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/openapi_v3_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/openapi_v3_normalizer.dart';

Map<String, dynamic> get _spec => {
      'openapi': '3.0.0',
      'info': {'title': 'Demo API'},
      'servers': [
        {'url': 'https://api.example.com/v1', 'description': 'prod'},
        {
          'url': 'https://{host}/v1',
          'description': 'custom',
          'variables': {
            'host': {'default': 'staging.example.com'},
          },
        },
      ],
      'components': {
        'securitySchemes': {
          'bearerAuth': {'type': 'http', 'scheme': 'bearer'},
        },
        'schemas': {
          'NewUser': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
          },
        },
      },
      'security': [
        {'bearerAuth': <dynamic>[]},
      ],
      'paths': {
        '/users/{id}': {
          'get': {
            'summary': 'Get user',
            'tags': ['Users'],
            'parameters': [
              {'name': 'id', 'in': 'path', 'required': true,
               'schema': {'type': 'integer'}},
              {'name': 'verbose', 'in': 'query',
               'schema': {'type': 'boolean', 'example': true}},
              {'name': 'X-Trace', 'in': 'header',
               'schema': {'type': 'string'}},
            ],
          },
        },
        '/users': {
          'post': {
            'operationId': 'createUser',
            'tags': ['Users'],
            'requestBody': {
              'content': {
                'application/json': {
                  'schema': {r'$ref': '#/components/schemas/NewUser'},
                },
              },
            },
          },
        },
      },
    };

void main() {
  test('reads title and servers with variable defaults', () {
    final api = normalizeOpenApiV3(_spec);
    expect(api.title, 'Demo API');
    expect(api.servers, hasLength(2));
    expect(api.servers[0].url, 'https://api.example.com/v1');
    expect(api.servers[1].variables['host'], 'staging.example.com');
  });

  test('GET op: method/path/name/tag, query+header params, path untouched', () {
    final api = normalizeOpenApiV3(_spec);
    final get = api.operations.firstWhere((o) => o.method == 'GET');
    expect(get.path, '/users/{id}');
    expect(get.name, 'Get user');
    expect(get.tag, 'Users');
    expect(get.queryParams.single.name, 'verbose');
    expect(get.queryParams.single.value, 'true');
    expect(get.headerParams.single.name, 'X-Trace');
    expect(get.body, isNull);
    expect(get.security?.kind, SecuritySchemeKind.bearer); // inherits global
  });

  test('POST op: json body sampled from a \$ref schema', () {
    final api = normalizeOpenApiV3(_spec);
    final post = api.operations.firstWhere((o) => o.method == 'POST');
    expect(post.name, 'createUser');
    expect(post.body!.bodyType, BodyType.raw);
    expect(post.body!.contentType, 'application/json');
    expect(post.body!.raw, contains('"name"'));
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/openapi_v3_normalizer_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/openapi/openapi_v3_normalizer.dart
import 'dart:convert';

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/ref_resolver.dart';
import 'package:getman/core/utils/openapi/schema_sampler.dart';

const _httpMethods = ['get', 'post', 'put', 'patch', 'delete', 'head', 'options'];

/// Converts an OpenAPI 3.x spec map into a [NormalizedApi].
NormalizedApi normalizeOpenApiV3(Map<String, dynamic> spec) {
  final refs = RefResolver(spec);
  final title = (spec['info'] is Map
          ? (spec['info'] as Map)['title'] as String?
          : null) ??
      'Imported API';

  final servers = <NormalizedServer>[];
  final rawServers = spec['servers'];
  if (rawServers is List) {
    for (final s in rawServers.whereType<Map>()) {
      final vars = <String, String>{};
      final rawVars = s['variables'];
      if (rawVars is Map) {
        for (final e in rawVars.entries) {
          final def = e.value is Map ? (e.value as Map)['default'] : null;
          vars[e.key.toString()] = def?.toString() ?? '';
        }
      }
      servers.add(NormalizedServer(
        url: (s['url'] as String?) ?? '',
        description: s['description'] as String?,
        variables: vars,
      ));
    }
  }

  final schemes = _securitySchemes(spec, refs);
  final globalSecurity = _firstSchemeName(spec['security']);

  final operations = <NormalizedOperation>[];
  final paths = spec['paths'];
  if (paths is Map) {
    for (final pathEntry in paths.entries) {
      final path = pathEntry.key.toString();
      final pathItem = pathEntry.value;
      if (pathItem is! Map) continue;
      for (final method in _httpMethods) {
        final op = pathItem[method];
        if (op is! Map) continue;
        operations.add(_operation(
          method: method.toUpperCase(),
          path: path,
          op: Map<String, dynamic>.from(op),
          refs: refs,
          schemes: schemes,
          globalSecurity: globalSecurity,
        ));
      }
    }
  }

  return NormalizedApi(title: title, servers: servers, operations: operations);
}

NormalizedOperation _operation({
  required String method,
  required String path,
  required Map<String, dynamic> op,
  required RefResolver refs,
  required Map<String, NormalizedSecurityScheme> schemes,
  required String? globalSecurity,
}) {
  final warnings = <String>[];
  final tags = op['tags'];
  final tag = (tags is List && tags.isNotEmpty) ? tags.first.toString() : null;
  final name = (op['summary'] as String?) ??
      (op['operationId'] as String?) ??
      '$method $path';

  final query = <NormalizedParam>[];
  final headers = <NormalizedParam>[];
  final rawParams = op['parameters'];
  if (rawParams is List) {
    for (final p in rawParams.whereType<Map>()) {
      final resolved = refs.resolve(Map<String, dynamic>.from(p));
      final location = resolved['in'] as String?;
      final pName = resolved['name'] as String?;
      if (pName == null) continue;
      final value = _paramExample(resolved, refs);
      if (location == 'query') {
        query.add(NormalizedParam(name: pName, value: value));
      } else if (location == 'header') {
        headers.add(NormalizedParam(name: pName, value: value));
      }
      // 'path' params stay templated in the path; 'cookie' ignored.
    }
  }

  NormalizedBody? body;
  final requestBody = op['requestBody'];
  if (requestBody is Map) {
    final resolvedBody = refs.resolve(Map<String, dynamic>.from(requestBody));
    final content = resolvedBody['content'];
    if (content is Map) {
      body = _body(content, refs, warnings);
    }
  }

  // Operation-level security overrides global; [] means "no auth".
  NormalizedSecurityScheme? security;
  if (op.containsKey('security')) {
    final name = _firstSchemeName(op['security']);
    security = name == null ? null : schemes[name];
  } else if (globalSecurity != null) {
    security = schemes[globalSecurity];
  }

  return NormalizedOperation(
    method: method,
    path: path,
    name: name,
    tag: tag,
    queryParams: query,
    headerParams: headers,
    body: body,
    security: security,
    warnings: warnings,
  );
}

String _paramExample(Map<String, dynamic> param, RefResolver refs) {
  if (param['example'] != null) return param['example'].toString();
  final schema = param['schema'];
  if (schema is Map) {
    final resolved = refs.deepResolve(Map<String, dynamic>.from(schema));
    if (resolved is Map<String, dynamic>) {
      final sample = sampleSchema(resolved);
      if (sample is String) return sample;
      if (sample is num || sample is bool) return sample.toString();
    }
  }
  return '';
}

NormalizedBody? _body(Map content, RefResolver refs, List<String> warnings) {
  // Prefer JSON.
  String? chosenType;
  if (content.containsKey('application/json')) {
    chosenType = 'application/json';
  } else if (content.containsKey('application/x-www-form-urlencoded')) {
    chosenType = 'application/x-www-form-urlencoded';
  } else if (content.containsKey('multipart/form-data')) {
    chosenType = 'multipart/form-data';
  } else if (content.isNotEmpty) {
    chosenType = content.keys.first.toString();
  }
  if (chosenType == null) return null;

  final media = content[chosenType];
  final schema = media is Map && media['schema'] is Map
      ? refs.deepResolve(Map<String, dynamic>.from(media['schema'] as Map))
      : null;

  if (chosenType == 'application/x-www-form-urlencoded' ||
      chosenType == 'multipart/form-data') {
    final fields = _formFields(schema);
    return NormalizedBody(
      bodyType: chosenType == 'multipart/form-data'
          ? BodyType.multipart
          : BodyType.urlencoded,
      formFields: fields,
    );
  }

  // Raw JSON (or any other single content type treated as raw text).
  final sample = schema is Map<String, dynamic> ? sampleSchema(schema) : null;
  final raw = sample == null
      ? ''
      : const JsonEncoder.withIndent('  ').convert(sample);
  return NormalizedBody(
    bodyType: BodyType.raw,
    raw: raw,
    contentType: chosenType,
  );
}

List<MultipartFieldEntity> _formFields(Object? schema) {
  final out = <MultipartFieldEntity>[];
  if (schema is Map && schema['properties'] is Map) {
    for (final e in (schema['properties'] as Map).entries) {
      final prop = e.value;
      final isFile = prop is Map &&
          (prop['format'] == 'binary' || prop['format'] == 'byte');
      out.add(MultipartFieldEntity(name: e.key.toString(), isFile: isFile));
    }
  }
  return out;
}

Map<String, NormalizedSecurityScheme> _securitySchemes(
  Map<String, dynamic> spec,
  RefResolver refs,
) {
  final out = <String, NormalizedSecurityScheme>{};
  final components = spec['components'];
  final raw = components is Map ? components['securitySchemes'] : null;
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final scheme = refs.resolve(Map<String, dynamic>.from(e.value as Map));
    out[e.key.toString()] = _scheme(scheme);
  }
  return out;
}

NormalizedSecurityScheme _scheme(Map<String, dynamic> scheme) {
  final type = scheme['type'] as String?;
  switch (type) {
    case 'http':
      final s = (scheme['scheme'] as String?)?.toLowerCase();
      if (s == 'bearer') {
        return const NormalizedSecurityScheme(kind: SecuritySchemeKind.bearer);
      }
      if (s == 'basic') {
        return const NormalizedSecurityScheme(kind: SecuritySchemeKind.basic);
      }
      return const NormalizedSecurityScheme(
          kind: SecuritySchemeKind.unsupported);
    case 'apiKey':
      final location = scheme['in'] as String?;
      return NormalizedSecurityScheme(
        kind: location == 'query'
            ? SecuritySchemeKind.apiKeyQuery
            : SecuritySchemeKind.apiKeyHeader,
        apiKeyName: scheme['name'] as String?,
      );
    case 'oauth2':
    case 'openIdConnect':
      return const NormalizedSecurityScheme(kind: SecuritySchemeKind.oauth2);
    default:
      return const NormalizedSecurityScheme(
          kind: SecuritySchemeKind.unsupported);
  }
}

/// `[{schemeName: [...]}, ...]` → first scheme name, or null if empty/absent.
String? _firstSchemeName(Object? security) {
  if (security is List && security.isNotEmpty) {
    final first = security.first;
    if (first is Map && first.isNotEmpty) return first.keys.first.toString();
  }
  return null;
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/openapi_v3_normalizer_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/openapi_v3_normalizer.dart test/core/utils/openapi/openapi_v3_normalizer_test.dart
git commit -m "$(cat <<'EOF'
feat(import): OpenAPI 3.x normalizer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `swagger_v2_normalizer.dart` — Swagger 2.0 → NormalizedApi

**Files:**
- Create: `lib/core/utils/openapi/swagger_v2_normalizer.dart`
- Test: `test/core/utils/openapi/swagger_v2_normalizer_test.dart`

Swagger 2.0 differences: base URL from `schemes[0]://host + basePath` (one synthetic server); schemas under `definitions`; body via a `parameters` entry with `in: body` (a `schema`) and form fields via `in: formData`; `securityDefinitions` (apiKey/basic/oauth2 — no `http bearer` type).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/swagger_v2_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/swagger_v2_normalizer.dart';

Map<String, dynamic> get _spec => {
      'swagger': '2.0',
      'info': {'title': 'Legacy API'},
      'host': 'api.legacy.com',
      'basePath': '/v2',
      'schemes': ['https'],
      'securityDefinitions': {
        'apiKey': {'type': 'apiKey', 'name': 'X-Key', 'in': 'header'},
      },
      'security': [
        {'apiKey': <dynamic>[]},
      ],
      'definitions': {
        'Pet': {
          'type': 'object',
          'properties': {'name': {'type': 'string'}},
        },
      },
      'paths': {
        '/pets/{petId}': {
          'get': {
            'summary': 'Get pet',
            'tags': ['Pets'],
            'parameters': [
              {'name': 'petId', 'in': 'path', 'required': true,
               'type': 'integer'},
              {'name': 'detailed', 'in': 'query', 'type': 'boolean'},
            ],
          },
        },
        '/pets': {
          'post': {
            'operationId': 'createPet',
            'tags': ['Pets'],
            'parameters': [
              {'name': 'body', 'in': 'body',
               'schema': {r'$ref': '#/definitions/Pet'}},
            ],
          },
        },
      },
    };

void main() {
  test('synthesizes one server from schemes+host+basePath', () {
    final api = normalizeSwaggerV2(_spec);
    expect(api.title, 'Legacy API');
    expect(api.servers.single.url, 'https://api.legacy.com/v2');
  });

  test('GET op: tag, query param, path templated, apiKey security', () {
    final api = normalizeSwaggerV2(_spec);
    final get = api.operations.firstWhere((o) => o.method == 'GET');
    expect(get.path, '/pets/{petId}');
    expect(get.tag, 'Pets');
    expect(get.queryParams.single.name, 'detailed');
    expect(get.security?.kind, SecuritySchemeKind.apiKeyHeader);
    expect(get.security?.apiKeyName, 'X-Key');
  });

  test('POST op: body param sampled from a definitions \$ref', () {
    final api = normalizeSwaggerV2(_spec);
    final post = api.operations.firstWhere((o) => o.method == 'POST');
    expect(post.name, 'createPet');
    expect(post.body!.bodyType, BodyType.raw);
    expect(post.body!.contentType, 'application/json');
    expect(post.body!.raw, contains('"name"'));
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/swagger_v2_normalizer_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/openapi/swagger_v2_normalizer.dart
import 'dart:convert';

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/ref_resolver.dart';
import 'package:getman/core/utils/openapi/schema_sampler.dart';

const _httpMethods = ['get', 'post', 'put', 'patch', 'delete', 'head', 'options'];

/// Converts a Swagger 2.0 spec map into a [NormalizedApi].
NormalizedApi normalizeSwaggerV2(Map<String, dynamic> spec) {
  final refs = RefResolver(spec);
  final title = (spec['info'] is Map
          ? (spec['info'] as Map)['title'] as String?
          : null) ??
      'Imported API';

  final scheme = (spec['schemes'] is List &&
          (spec['schemes'] as List).isNotEmpty)
      ? (spec['schemes'] as List).first.toString()
      : 'https';
  final host = (spec['host'] as String?) ?? '';
  final basePath = (spec['basePath'] as String?) ?? '';
  final servers = host.isEmpty
      ? <NormalizedServer>[]
      : [NormalizedServer(url: '$scheme://$host$basePath')];

  final schemes = _securityDefinitions(spec);
  final globalSecurity = _firstSchemeName(spec['security']);

  final operations = <NormalizedOperation>[];
  final paths = spec['paths'];
  if (paths is Map) {
    for (final pathEntry in paths.entries) {
      final path = pathEntry.key.toString();
      final pathItem = pathEntry.value;
      if (pathItem is! Map) continue;
      for (final method in _httpMethods) {
        final op = pathItem[method];
        if (op is! Map) continue;
        operations.add(_operation(
          method: method.toUpperCase(),
          path: path,
          op: Map<String, dynamic>.from(op),
          refs: refs,
          schemes: schemes,
          globalSecurity: globalSecurity,
        ));
      }
    }
  }
  return NormalizedApi(title: title, servers: servers, operations: operations);
}

NormalizedOperation _operation({
  required String method,
  required String path,
  required Map<String, dynamic> op,
  required RefResolver refs,
  required Map<String, NormalizedSecurityScheme> schemes,
  required String? globalSecurity,
}) {
  final tags = op['tags'];
  final tag = (tags is List && tags.isNotEmpty) ? tags.first.toString() : null;
  final name = (op['summary'] as String?) ??
      (op['operationId'] as String?) ??
      '$method $path';

  final query = <NormalizedParam>[];
  final headers = <NormalizedParam>[];
  final formFields = <MultipartFieldEntity>[];
  NormalizedBody? body;

  final rawParams = op['parameters'];
  if (rawParams is List) {
    for (final p in rawParams.whereType<Map>()) {
      final param = refs.resolve(Map<String, dynamic>.from(p));
      final location = param['in'] as String?;
      final pName = param['name'] as String?;
      switch (location) {
        case 'query':
          if (pName != null) {
            query.add(NormalizedParam(name: pName, value: ''));
          }
        case 'header':
          if (pName != null) {
            headers.add(NormalizedParam(name: pName, value: ''));
          }
        case 'formData':
          if (pName != null) {
            formFields.add(MultipartFieldEntity(
              name: pName,
              isFile: param['type'] == 'file',
            ));
          }
        case 'body':
          final schema = param['schema'];
          if (schema is Map) {
            final resolved =
                refs.deepResolve(Map<String, dynamic>.from(schema));
            final sample =
                resolved is Map<String, dynamic> ? sampleSchema(resolved) : null;
            body = NormalizedBody(
              bodyType: BodyType.raw,
              contentType: 'application/json',
              raw: sample == null
                  ? ''
                  : const JsonEncoder.withIndent('  ').convert(sample),
            );
          }
        default:
          break; // 'path' stays templated
      }
    }
  }

  if (body == null && formFields.isNotEmpty) {
    final consumes = op['consumes'];
    final isMultipart = consumes is List &&
        consumes.any((c) => c.toString().contains('multipart'));
    body = NormalizedBody(
      bodyType: isMultipart ? BodyType.multipart : BodyType.urlencoded,
      formFields: formFields,
    );
  }

  NormalizedSecurityScheme? security;
  if (op.containsKey('security')) {
    final n = _firstSchemeName(op['security']);
    security = n == null ? null : schemes[n];
  } else if (globalSecurity != null) {
    security = schemes[globalSecurity];
  }

  return NormalizedOperation(
    method: method,
    path: path,
    name: name,
    tag: tag,
    queryParams: query,
    headerParams: headers,
    body: body,
    security: security,
  );
}

Map<String, NormalizedSecurityScheme> _securityDefinitions(
    Map<String, dynamic> spec) {
  final out = <String, NormalizedSecurityScheme>{};
  final raw = spec['securityDefinitions'];
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final def = e.value;
    if (def is! Map) continue;
    final type = def['type'] as String?;
    switch (type) {
      case 'basic':
        out[e.key.toString()] =
            const NormalizedSecurityScheme(kind: SecuritySchemeKind.basic);
      case 'apiKey':
        out[e.key.toString()] = NormalizedSecurityScheme(
          kind: def['in'] == 'query'
              ? SecuritySchemeKind.apiKeyQuery
              : SecuritySchemeKind.apiKeyHeader,
          apiKeyName: def['name'] as String?,
        );
      case 'oauth2':
        out[e.key.toString()] =
            const NormalizedSecurityScheme(kind: SecuritySchemeKind.oauth2);
      default:
        out[e.key.toString()] = const NormalizedSecurityScheme(
            kind: SecuritySchemeKind.unsupported);
    }
  }
  return out;
}

String? _firstSchemeName(Object? security) {
  if (security is List && security.isNotEmpty) {
    final first = security.first;
    if (first is Map && first.isNotEmpty) return first.keys.first.toString();
  }
  return null;
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/swagger_v2_normalizer_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/swagger_v2_normalizer.dart test/core/utils/openapi/swagger_v2_normalizer_test.dart
git commit -m "$(cat <<'EOF'
feat(import): Swagger 2.0 normalizer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `spec_normalizer.dart` — version sniff + dispatch

**Files:**
- Create: `lib/core/utils/openapi/spec_normalizer.dart`
- Test: `test/core/utils/openapi/spec_normalizer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/spec_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/spec_normalizer.dart';

void main() {
  test('routes an OpenAPI 3.x map', () {
    final api = normalizeSpec({
      'openapi': '3.0.1',
      'info': {'title': 'Three'},
      'paths': <String, dynamic>{},
    });
    expect(api.title, 'Three');
  });

  test('routes a Swagger 2.0 map', () {
    final api = normalizeSpec({
      'swagger': '2.0',
      'info': {'title': 'Two'},
      'paths': <String, dynamic>{},
    });
    expect(api.title, 'Two');
  });

  test('throws FormatException when neither key is present', () {
    expect(
      () => normalizeSpec({'info': {'title': 'X'}}),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/spec_normalizer_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/openapi/spec_normalizer.dart
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/openapi_v3_normalizer.dart';
import 'package:getman/core/utils/openapi/swagger_v2_normalizer.dart';

/// Detects the spec version and dispatches to the matching normalizer.
/// Throws [FormatException] if [spec] is neither OpenAPI 3.x nor Swagger 2.0.
NormalizedApi normalizeSpec(Map<String, dynamic> spec) {
  if (spec['openapi'] is String &&
      (spec['openapi'] as String).startsWith('3')) {
    return normalizeOpenApiV3(spec);
  }
  if (spec['swagger'] is String &&
      (spec['swagger'] as String).startsWith('2')) {
    return normalizeSwaggerV2(spec);
  }
  throw const FormatException(
    'Unrecognized spec — expected an "openapi: 3.x" or "swagger: 2.0" '
    'document.',
  );
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/spec_normalizer_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/spec_normalizer.dart test/core/utils/openapi/spec_normalizer_test.dart
git commit -m "$(cat <<'EOF'
feat(import): spec version sniff + normalizer dispatch

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `collection_builder.dart` — NormalizedApi → ImportResult

**Files:**
- Create: `lib/core/utils/openapi/collection_builder.dart`
- Test: `test/core/utils/openapi/collection_builder_test.dart`

Builds the collection tree (root = title; folders by `tag` else first path segment; leaves = request configs) + one environment per server (`baseUrl` concrete, secret vars seeded). Uses `UrlQueryUtils.replaceQuery` for query params — **confirm its signature first** by reading `lib/core/utils/url_query_utils.dart`; the Postman mapper calls `UrlQueryUtils.replaceQuery(url, List<QueryParamEntity>)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/collection_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/openapi/collection_builder.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';

NormalizedApi get _api => const NormalizedApi(
      title: 'Demo',
      servers: [
        NormalizedServer(url: 'https://api.example.com/v1', description: 'prod'),
        NormalizedServer(
          url: 'https://{host}/v1',
          description: 'custom',
          variables: {'host': 'staging.example.com'},
        ),
      ],
      operations: [
        NormalizedOperation(
          method: 'GET',
          path: '/users/{id}',
          name: 'Get user',
          tag: 'Users',
          queryParams: [NormalizedParam(name: 'verbose', value: 'true')],
          headerParams: [NormalizedParam(name: 'X-Trace', value: 't')],
          security: NormalizedSecurityScheme(kind: SecuritySchemeKind.bearer),
        ),
        NormalizedOperation(
          method: 'GET',
          path: '/ping',
          name: 'Ping', // untagged → grouped by first path segment 'ping'
        ),
      ],
    );

void main() {
  test('root is named after the title', () {
    final result = buildImport(_api);
    expect(result.root.name, 'Demo');
    expect(result.root.isFolder, isTrue);
  });

  test('one environment per server, baseUrl concrete (vars substituted)', () {
    final result = buildImport(_api);
    expect(result.environments, hasLength(2));
    expect(result.environments[0].variables['baseUrl'],
        'https://api.example.com/v1');
    expect(result.environments[1].variables['baseUrl'],
        'https://staging.example.com/v1');
  });

  test('bearer secret var seeded into every environment', () {
    final result = buildImport(_api);
    for (final env in result.environments) {
      expect(env.variables.containsKey('bearerToken'), isTrue);
      expect(env.secretKeys.contains('bearerToken'), isTrue);
    }
  });

  test('tagged op lands in a folder named after the tag', () {
    final result = buildImport(_api);
    final usersFolder =
        result.root.children.firstWhere((n) => n.name == 'Users');
    expect(usersFolder.isFolder, isTrue);
    expect(usersFolder.children.single.name, 'Get user');
  });

  test('untagged op grouped by first path segment', () {
    final result = buildImport(_api);
    expect(result.root.children.any((n) => n.name == 'ping'), isTrue);
  });

  test('leaf config: templated url, path-param tokenized, query + header', () {
    final result = buildImport(_api);
    final leaf = result.root.children
        .firstWhere((n) => n.name == 'Users')
        .children
        .single;
    final cfg = leaf.config!;
    expect(cfg.method, 'GET');
    expect(cfg.url, contains('{{baseUrl}}/users/{{id}}'));
    expect(cfg.url, contains('verbose=true'));
    expect(cfg.headers['X-Trace'], 't');
    expect(AuthConfig.fromMap(cfg.auth).type, AuthType.bearer);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/collection_builder_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement** (confirm `UrlQueryUtils.replaceQuery` first)

```dart
// lib/core/utils/openapi/collection_builder.dart
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/openapi/auth_mapper.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/url_query_utils.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Builds a collection tree + environments from a [NormalizedApi].
ImportResult buildImport(NormalizedApi api) {
  final warnings = <String>[];
  final secretVars = <String>{};

  // Group operations into folders (tag, else first path segment).
  final folders = <String, List<CollectionNodeEntity>>{};
  for (final op in api.operations) {
    warnings.addAll(op.warnings);
    final auth = mapAuth(op.security);
    if (auth.secretVarName != null) secretVars.add(auth.secretVarName!);
    if (auth.warning != null) warnings.add('${op.method} ${op.path}: ${auth.warning}');

    final leaf = CollectionNodeEntity(
      id: _uuid.v4(),
      name: op.name,
      isFolder: false,
      config: _config(op, auth),
    );
    final group = op.tag ?? _firstSegment(op.path);
    folders.putIfAbsent(group, () => []).add(leaf);
  }

  final folderNodes = [
    for (final entry in folders.entries)
      CollectionNodeEntity(
        id: _uuid.v4(),
        name: entry.key,
        children: entry.value,
      ),
  ];

  final root = CollectionNodeEntity(
    id: _uuid.v4(),
    name: api.title,
    children: folderNodes,
  );

  final environments = _environments(api.servers, secretVars);
  return ImportResult(
    root: root,
    environments: environments,
    warnings: warnings,
  );
}

HttpRequestConfigEntity _config(NormalizedOperation op, NormalizedAuth auth) {
  var url = '{{baseUrl}}${_templatePath(op.path)}';
  if (op.queryParams.isNotEmpty) {
    url = UrlQueryUtils.replaceQuery(
      url,
      [for (final q in op.queryParams) QueryParamEntity(key: q.name, value: q.value)],
    );
  }

  final headers = <String, String>{
    for (final h in op.headerParams) h.name: h.value,
  };
  final body = op.body;
  if (body != null && body.bodyType == BodyType.raw && body.contentType != null) {
    headers['Content-Type'] = body.contentType!;
  }

  return HttpRequestConfigEntity(
    id: _uuid.v4(),
    method: op.method,
    url: url,
    headers: headers,
    body: body?.raw ?? '',
    bodyType: body?.bodyType ?? BodyType.none,
    formFields: body?.formFields ?? const [],
    auth: auth.config.toMap(),
  );
}

/// `/users/{id}` → `/users/{{id}}`.
String _templatePath(String path) =>
    path.replaceAllMapped(RegExp(r'\{([^}/]+)\}'), (m) => '{{${m[1]}}}');

String _firstSegment(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? 'default' : parts.first;
}

List<EnvironmentEntity> _environments(
  List<NormalizedServer> servers,
  Set<String> secretVars,
) {
  if (servers.isEmpty) {
    // No servers declared: still create one env so {{baseUrl}} resolves.
    return [
      EnvironmentEntity(
        name: 'Imported',
        variables: {
          'baseUrl': '',
          for (final v in secretVars) v: '',
        },
        secretKeys: {...secretVars},
      ),
    ];
  }
  final usedNames = <String>{};
  return [
    for (final server in servers)
      EnvironmentEntity(
        name: _uniqueName(_serverName(server), usedNames),
        variables: {
          'baseUrl': _concreteBaseUrl(server),
          for (final v in secretVars) v: '',
        },
        secretKeys: {...secretVars},
      ),
  ];
}

/// Substitutes `{var}` server variables with their defaults; trims a trailing
/// slash. See plan "Design decisions locked in" #2.
String _concreteBaseUrl(NormalizedServer server) {
  var url = server.url;
  server.variables.forEach((name, value) {
    url = url.replaceAll('{$name}', value);
  });
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  return url;
}

String _serverName(NormalizedServer server) {
  if (server.description != null && server.description!.trim().isNotEmpty) {
    return server.description!.trim();
  }
  final host = Uri.tryParse(_concreteBaseUrl(server))?.host;
  return (host != null && host.isNotEmpty) ? host : 'server';
}

String _uniqueName(String base, Set<String> used) {
  if (used.add(base)) return base;
  var i = 2;
  while (!used.add('$base ($i)')) {
    i++;
  }
  return '$base ($i)';
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/collection_builder_test.dart`
Expected: PASS (6 tests). If the `url` assertion fails because `replaceQuery` percent-encodes or reorders, read `url_query_utils.dart` and adjust (fall back to manual `?k=v` join for plain values if needed).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/collection_builder.dart test/core/utils/openapi/collection_builder_test.dart
git commit -m "$(cat <<'EOF'
feat(import): build collection tree + environments from spec

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `import_selection.dart` — leaf ids + tree pruning

**Files:**
- Create: `lib/core/utils/openapi/import_selection.dart`
- Test: `test/core/utils/openapi/import_selection_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/openapi/import_selection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/openapi/import_selection.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

CollectionNodeEntity get _root => const CollectionNodeEntity(
      id: 'root',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'f1',
          name: 'Users',
          children: [
            CollectionNodeEntity(
                id: 'l1', name: 'a', isFolder: false,
                config: HttpRequestConfigEntity(id: 'c1')),
            CollectionNodeEntity(
                id: 'l2', name: 'b', isFolder: false,
                config: HttpRequestConfigEntity(id: 'c2')),
          ],
        ),
        CollectionNodeEntity(
          id: 'f2',
          name: 'Pets',
          children: [
            CollectionNodeEntity(
                id: 'l3', name: 'c', isFolder: false,
                config: HttpRequestConfigEntity(id: 'c3')),
          ],
        ),
      ],
    );

void main() {
  test('collectLeafIds returns every request leaf id', () {
    expect(collectLeafIds(_root), {'l1', 'l2', 'l3'});
  });

  test('applySelection keeps only selected leaves and drops empty folders', () {
    final full = ImportResult(root: _root);
    final pruned = applySelection(full, {'l1'});
    expect(pruned.root.children, hasLength(1)); // only Users
    final users = pruned.root.children.single;
    expect(users.name, 'Users');
    expect(users.children.single.id, 'l1'); // l2 dropped, Pets folder dropped
  });

  test('applySelection preserves environments and warnings', () {
    final full = ImportResult(
      root: _root,
      warnings: const ['w'],
    );
    final pruned = applySelection(full, {'l3'});
    expect(pruned.warnings, ['w']);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/core/utils/openapi/import_selection_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/openapi/import_selection.dart
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

/// Every request-leaf id in [node]'s subtree.
Set<String> collectLeafIds(CollectionNodeEntity node) {
  final ids = <String>{};
  void walk(CollectionNodeEntity n) {
    if (!n.isFolder) {
      ids.add(n.id);
      return;
    }
    for (final c in n.children) {
      walk(c);
    }
  }
  walk(node);
  return ids;
}

/// Prunes [full]'s tree to only the request leaves in [selectedLeafIds],
/// dropping folders left empty. Environments and warnings are preserved.
ImportResult applySelection(ImportResult full, Set<String> selectedLeafIds) {
  final pruned = _prune(full.root, selectedLeafIds);
  return ImportResult(
    root: pruned ?? full.root.copyWith(children: const []),
    environments: full.environments,
    warnings: full.warnings,
  );
}

CollectionNodeEntity? _prune(
    CollectionNodeEntity node, Set<String> selected) {
  if (!node.isFolder) {
    return selected.contains(node.id) ? node : null;
  }
  final kids = <CollectionNodeEntity>[];
  for (final c in node.children) {
    final p = _prune(c, selected);
    if (p != null) kids.add(p);
  }
  if (kids.isEmpty) return null;
  return node.copyWith(children: kids);
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/core/utils/openapi/import_selection_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/openapi/import_selection.dart test/core/utils/openapi/import_selection_test.dart
git commit -m "$(cat <<'EOF'
feat(import): leaf-id collection + tree pruning by selection

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: `SpecImportDialog` — multi-step dialog

**Files:**
- Create: `lib/features/collections/presentation/widgets/spec_import_dialog.dart`
- Test: `test/features/collections/presentation/widgets/spec_import_dialog_test.dart`

A `StatefulWidget` shown via `showResponsiveDialog`. State machine: **source** (segmented File / Paste / URL) → on parse success, **preview** (checkbox list + env summary + warnings + Import). `parse` runs `loadSpec` → `normalizeSpec` → `buildImport`. On Import, `applySelection` then `widget.onImport(result)` and pop. All sizing/colors via `context.app*`. Use the existing `MethodBadge` atom for method display (confirm its constructor when implementing).

> Architectural note: the dialog imports the pure utils + `NetworkService` (passed in), but **not** the blocs — the caller wires those (Task 12). This keeps it testable with a plain callback.

- [ ] **Step 1: Write the failing widget test** (paste path — no file picker / network)

```dart
// test/features/collections/presentation/widgets/spec_import_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/presentation/widgets/spec_import_dialog.dart';

const _spec = '''
{
  "openapi": "3.0.0",
  "info": {"title": "Demo"},
  "servers": [{"url": "https://api.example.com"}],
  "paths": {
    "/users": {"get": {"summary": "List", "tags": ["Users"]}},
    "/pets": {"get": {"summary": "Pets", "tags": ["Pets"]}}
  }
}
''';

Future<void> _open(
  WidgetTester tester,
  void Function(ImportResult) onImport,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => SpecImportDialog.show(
              context,
              networkService: null, // paste path doesn't touch the network
              onImport: onImport,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('paste → preview lists folders, import fires callback', (tester) async {
    ImportResult? captured;
    await _open(tester, (r) => captured = r);

    // Switch to the Paste tab and enter the spec.
    await tester.tap(find.text('PASTE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, _spec);
    await tester.tap(find.widgetWithText(TextButton, 'PARSE'));
    await tester.pumpAndSettle();

    // Preview shows both folders.
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Pets'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'IMPORT'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.root.name, 'Demo');
    expect(captured!.root.children, hasLength(2));
    expect(captured!.environments, hasLength(1));
  });

  testWidgets('deselecting a folder excludes it from the import', (tester) async {
    ImportResult? captured;
    await _open(tester, (r) => captured = r);
    await tester.tap(find.text('PASTE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, _spec);
    await tester.tap(find.widgetWithText(TextButton, 'PARSE'));
    await tester.pumpAndSettle();

    // Uncheck the "Pets" folder checkbox.
    final petsCheckbox = find.descendant(
      of: find.ancestor(
        of: find.text('Pets'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Checkbox),
    );
    await tester.tap(petsCheckbox.first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'IMPORT'));
    await tester.pumpAndSettle();

    expect(captured!.root.children, hasLength(1));
    expect(captured!.root.children.single.name, 'Users');
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `fvm flutter test test/features/collections/presentation/widgets/spec_import_dialog_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement the dialog**

Build `SpecImportDialog` with:
- `static Future<void> show(BuildContext context, {required NetworkService? networkService, required void Function(ImportResult) onImport})` → `showResponsiveDialog`.
- Internal `enum _Source { file, paste, url }` segmented control (use `BrandedTabBar` or simple themed buttons labeled `FILE` / `PASTE` / `URL`).
- A `CodeLineEditingController`-free plain `TextField` (multiline) for paste; a single-line `TextField` for URL + a `FETCH` button; a `PICK FILE` button for file (use `FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json','yaml','yml'], withData: true)` + `readPickedFile`).
- A `PARSE` button (paste) / auto-parse after fetch/file: runs `_parse(String text)`:
  ```dart
  try {
    final api = normalizeSpec(loadSpec(text));
    setState(() {
      _result = buildImport(api);
      _selected = collectLeafIds(_result!.root);
      _error = null;
    });
  } on FormatException catch (e) {
    setState(() => _error = e.message);
  }
  ```
- Preview: for each folder node in `_result!.root.children`, a `Row` with a tristate `Checkbox` (checked when all its leaves are selected) + folder name; indented leaf `Row`s each with a `Checkbox` + `MethodBadge(method: leaf.config!.method)` (confirm constructor) + leaf name. Toggling a folder adds/removes all its leaf ids in `_selected`.
- An env summary line: `'Creates ${_result!.environments.length} environment(s): ${_result!.environments.map((e) => e.name).join(', ')}'` via `context.appTypography`.
- Warnings (if any) rendered in `context.appPalette.statusWarning`.
- Actions: `CANCEL` (pop) and `IMPORT` (enabled when `_selected.isNotEmpty`) → `widget.onImport(applySelection(_result!, _selected)); Navigator.pop(context);`.
- All paddings/sizes/radii/colors via `context.appLayout`/`appShape`/`appPalette`/`appTypography`; wrap tappables in `context.appDecoration.wrapInteractive` where the codebase does. No `Colors.*` literals (custom_lint `avoid_hardcoded_brand_colors`).
- URL fetch handler (guard `networkService != null`):
  ```dart
  final resp = await networkService!.request(url: _urlController.text, method: 'GET');
  _parse(resp.body);
  ```
  Wrap in try/catch; on failure `setState(() => _error = ...)`.

Keep the file focused; if it grows past ~250 LOC, extract the preview list into a private `_ImportPreview` widget in the same file.

- [ ] **Step 4: Run it, verify it passes**

Run: `fvm flutter test test/features/collections/presentation/widgets/spec_import_dialog_test.dart`
Expected: PASS (2 tests). Adjust finders if the widget tree differs (e.g. the folder `Row`/`Checkbox` ancestry).

- [ ] **Step 5: Full gate + commit**

Run: `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0), `fvm dart format lib test`, `fvm flutter test` (green).

```bash
git add lib/features/collections/presentation/widgets/spec_import_dialog.dart test/features/collections/presentation/widgets/spec_import_dialog_test.dart
git commit -m "$(cat <<'EOF'
feat(import): OpenAPI/Swagger import dialog with selectable preview

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Wire the entry point in `collections_list.dart`

**Files:**
- Modify: `lib/features/collections/presentation/widgets/collections_list.dart` (the import `IconButton` ~line 204-213 and the `_importCollections` handler ~line 117-125)
- Test: extend `test/features/collections/presentation/widgets/collections_list_test.dart` if it exists; otherwise a focused new test that the menu opens the dialog.

- [ ] **Step 1: Replace the single import button with a menu**

Convert the `IconButton(tooltip: 'IMPORT FROM POSTMAN', onPressed: _importCollections)` into a `PopupMenuButton<String>` (icon `Icons.file_upload`, `tooltip: 'IMPORT'`) with two items: `'postman'` → "FROM POSTMAN" and `'openapi'` → "FROM OPENAPI / SWAGGER". Theme the menu text via `context.appTypography`. Keep `_importCollections` for the Postman item.

- [ ] **Step 2: Add the OpenAPI coordinator handler**

```dart
void _importSpec(BuildContext context) {
  final collectionsBloc = context.read<CollectionsBloc>();
  final environmentsBloc = context.read<EnvironmentsBloc>();
  final messenger = ScaffoldMessenger.of(context);
  SpecImportDialog.show(
    context,
    networkService: context.read<NetworkService>(),
    onImport: (result) {
      collectionsBloc.add(ImportCollections([result.root]));
      if (result.environments.isNotEmpty) {
        environmentsBloc.add(ImportEnvironments(result.environments));
      }
      showAppSnackBarVia(messenger, 'Imported "${result.root.name}".');
      for (final w in result.warnings.take(1)) {
        // Surface the first warning, if any, so OAuth2/unsupported is visible.
        showAppSnackBarVia(messenger, w);
      }
    },
  );
}
```

Add the imports: `spec_import_dialog.dart`, `normalized_api.dart` (for `ImportResult`), `environments` bloc + event, `network_service.dart`, `app_snack_bar.dart`. `NetworkService` and the blocs are already provided up-tree (`MultiRepositoryProvider` / `MultiBlocProvider`), so `context.read` is valid (no GetIt).

- [ ] **Step 3: Verify the full gate**

Run, all clean:
```
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test
fvm flutter test
```
Note: `EnvironmentsBloc` must be reachable from `collections_list.dart`'s context. Confirm `MultiBlocProvider` in `main.dart` provides it above the collections panel (per CLAUDE.md §4.1 it does). If the widget test for collections_list can't easily provide all blocs, keep the test minimal (verify the popup menu shows both items) and rely on the dialog's own tests for behavior.

- [ ] **Step 4: Commit**

```bash
git add lib/features/collections/presentation/widgets/collections_list.dart test/features/collections/presentation/widgets/
git commit -m "$(cat <<'EOF'
feat(import): wire OpenAPI/Swagger import into the collections menu

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: End-to-end round-trip test (JSON + YAML)

**Files:**
- Test: `test/core/utils/openapi/import_pipeline_test.dart`

A small integration test over the public pipeline (`loadSpec` → `normalizeSpec` → `buildImport`) for both a JSON OpenAPI 3.x spec and the equivalent YAML, asserting the same collection shape — guards regressions across module boundaries.

- [ ] **Step 1: Write the test**

```dart
// test/core/utils/openapi/import_pipeline_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/collection_builder.dart';
import 'package:getman/core/utils/openapi/spec_loader.dart';
import 'package:getman/core/utils/openapi/spec_normalizer.dart';

const _json = '''
{"openapi":"3.0.0","info":{"title":"RT"},
 "servers":[{"url":"https://x.test"}],
 "paths":{"/a":{"get":{"summary":"GetA","tags":["T"]}}}}
''';

const _yaml = '''
openapi: 3.0.0
info:
  title: RT
servers:
  - url: https://x.test
paths:
  /a:
    get:
      summary: GetA
      tags: [T]
''';

void main() {
  test('JSON and YAML produce the same collection shape', () {
    final fromJson = buildImport(normalizeSpec(loadSpec(_json)));
    final fromYaml = buildImport(normalizeSpec(loadSpec(_yaml)));

    expect(fromJson.root.name, 'RT');
    expect(fromYaml.root.name, 'RT');
    expect(fromJson.root.children.single.name, 'T');
    expect(fromYaml.root.children.single.name, 'T');
    expect(fromJson.environments.single.variables['baseUrl'], 'https://x.test');
    expect(fromYaml.environments.single.variables['baseUrl'], 'https://x.test');
  });
}
```

- [ ] **Step 2: Run it, verify it passes** (modules already exist)

Run: `fvm flutter test test/core/utils/openapi/import_pipeline_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/core/utils/openapi/import_pipeline_test.dart
git commit -m "$(cat <<'EOF'
test(import): end-to-end JSON/YAML pipeline round-trip

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Update the wiki

**Files:** the separate `Getman.wiki.git` repo (not this repo).

Per the CLAUDE.md "Keep the wiki in sync" mandate — this adds a user-facing capability.

- [ ] **Step 1: Clone the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

- [ ] **Step 2: Add an "Importing APIs" page** (`/tmp/getman-wiki/Importing-APIs.md`) covering: supported formats (OpenAPI 3.x, Swagger 2.0; JSON or YAML; HAR not yet), the three input methods (file / paste / URL), the selectable preview, that one environment is created per server with a `{{baseUrl}}` variable, that auth type is mapped but secrets are left blank with a labeled secret env var to fill, and the menu location (Collections panel → Import → From OpenAPI / Swagger). Use verbatim UI labels.

- [ ] **Step 3: Add a `_Sidebar.md` entry** linking the new page.

- [ ] **Step 4: Commit + push**

```bash
cd /tmp/getman-wiki && git add -A && git commit -m "docs: Importing APIs (OpenAPI/Swagger)" && git push origin master
```

---

## Self-review (completed during planning)

**Spec coverage:** every spec section maps to a task — formats/loader (T1), `$ref` (T3), body stubs (T4), auth (T5), 3.x (T6), 2.0 (T7), dispatch (T8), servers→envs + mapping rules (T9), selective preview prune (T10), dialog/source/preview (T11), entry point + bloc coordination (T12), JSON/YAML parity (T13), wiki (T14). HAR + OAuth2 are explicitly out of scope (spec §2).

**Type consistency:** `ImportResult`, `NormalizedApi`, `NormalizedOperation`, `NormalizedSecurityScheme`, `SecuritySchemeKind`, `NormalizedAuth`, `NormalizedBody`, `NormalizedParam`, `NormalizedServer` are defined once in Task 2 and referenced consistently. Function names stable: `loadSpec`, `normalizeSpec`, `normalizeOpenApiV3`, `normalizeSwaggerV2`, `buildImport`, `mapAuth`, `sampleSchema`, `collectLeafIds`, `applySelection`, `RefResolver.{resolve,deepResolve}`.

**Known implementation-time confirmations (flagged inline, not placeholders):** `UrlQueryUtils.replaceQuery` exact signature + URL-templating behavior (T9); `MethodBadge` constructor (T11); that `EnvironmentsBloc`/`NetworkService` are reachable from `collections_list.dart` context (T12). Each has a stated fallback.
