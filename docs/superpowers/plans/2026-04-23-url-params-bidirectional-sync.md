# URL ↔ Params Bi-Directional Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the URL bar and the Params panel show the same query-parameter data at all times by moving to URL-as-source-of-truth. Support duplicate query keys (`?a=1&a=2`) via an ordered list-of-pairs.

**Architecture:** The URL is the single source of truth. `config.params` becomes a computed `List<QueryParamEntity>` derived from `config.url`. A new `UrlQueryUtils` module handles parse/build of the query portion, preserving `{{var}}` tokens. The legacy `params` stored field on the Hive model (`HttpRequestConfig`, typeId 1, `@HiveField(4)`) stays declared for backward compatibility but is always written empty going forward; legacy non-empty maps get merged into `url` on first read via `toEntity()`.

**Tech Stack:** Flutter (via `fvm`), Equatable, Dio (network), Hive (persistence), flutter_bloc, collection (`ListEquality`, `MapEquality`). Dart version pinned via `.fvmrc` — always run `fvm flutter …`, never plain `flutter`.

**Spec:** `docs/superpowers/specs/2026-04-23-url-params-bidirectional-sync-design.md`

**Commit style:** The repo uses terse, lowercase commit subjects (see `git log`). Match that style. Every commit uses the standard `Co-Authored-By` trailer.

---

## File map

**Created:**
- `lib/core/domain/entities/query_param_entity.dart` — value object, pure Dart + Equatable
- `lib/core/utils/url_query_utils.dart` — parse/build of URL query portion
- `test/core/utils/url_query_utils_test.dart` — unit tests
- `test/core/domain/entities/request_config_entity_test.dart` — entity getter + copyWith tests
- `test/features/history/data/models/request_config_model_test.dart` — Hive model legacy-migration test

**Modified:**
- `lib/core/domain/entities/request_config_entity.dart` — drop stored `params`, add computed getter, rework `copyWith`
- `lib/features/history/data/models/request_config_model.dart` — `fromEntity` writes empty map; `toEntity` migrates legacy map into `url`
- `lib/features/tabs/data/repositories/tabs_repository_impl.dart` — split URL into base + queryMap before calling Dio
- `lib/core/network/network_service.dart` — configure `ListFormat.multi` on `Dio.BaseOptions`
- `lib/core/utils/postman/postman_collection_mapper.dart` — export uses `UrlQueryUtils.parseQuery`; import merges `url.query` into `url.raw`
- `lib/features/tabs/presentation/widgets/request_config_section.dart` — split `_KeyValueEditor` into `_QueryParamsEditor` + `_HeadersEditor`
- `test/core/utils/postman/postman_collection_mapper_test.dart` — update fixtures to pass query in URL; expectations use list-of-pairs

**Untouched:**
- `lib/core/utils/curl_utils.dart` — already populates `url` only; URL now naturally carries query
- `lib/features/tabs/presentation/widgets/url_bar.dart` — bi-directional sync emerges from single-source-of-truth
- `lib/core/ui/widgets/variable_highlight_controller.dart` — already highlights `{{var}}` anywhere in URL
- Hive `@HiveType` / `@HiveField` declarations on `HttpRequestConfig` — not renumbered, not re-typed; `build_runner` not run

---

## Verification gate (from `CLAUDE.md` §5)

Every commit lands in a green state:
- `fvm flutter analyze` → `No issues found!`
- `fvm flutter test` → all green

---

## Task 1: Introduce `QueryParamEntity`

**Files:**
- Create: `lib/core/domain/entities/query_param_entity.dart`

- [ ] **Step 1: Create the entity**

Write `lib/core/domain/entities/query_param_entity.dart`:

```dart
import 'package:equatable/equatable.dart';

/// Ordered key/value pair for a single URL query parameter. Duplicates of the
/// same key are allowed — preserves Postman's row-based representation of
/// `?a=1&a=2`.
class QueryParamEntity extends Equatable {
  final String key;
  final String value;

  const QueryParamEntity({required this.key, required this.value});

  @override
  List<Object?> get props => [key, value];
}
```

- [ ] **Step 2: Analyze**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run existing tests**

Run: `fvm flutter test`
Expected: all green (no tests touched this file yet).

- [ ] **Step 4: Commit**

```bash
git add lib/core/domain/entities/query_param_entity.dart
git commit -m "$(cat <<'EOF'
query param entity

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `UrlQueryUtils` (TDD)

**Files:**
- Create: `test/core/utils/url_query_utils_test.dart`
- Create: `lib/core/utils/url_query_utils.dart`

- [ ] **Step 1: Write the failing tests**

Write `test/core/utils/url_query_utils_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/utils/url_query_utils.dart';

void main() {
  group('UrlQueryUtils.parse', () {
    test('splits base, empty query, no fragment', () {
      final parts = UrlQueryUtils.parse('https://example.com/path');
      expect(parts.base, 'https://example.com/path');
      expect(parts.params, isEmpty);
      expect(parts.fragment, isNull);
    });

    test('single key/value', () {
      final parts = UrlQueryUtils.parse('https://x/a?a=1');
      expect(parts.base, 'https://x/a');
      expect(parts.params, [const QueryParamEntity(key: 'a', value: '1')]);
    });

    test('preserves duplicate keys in order', () {
      final parts = UrlQueryUtils.parse('https://x/a?a=1&a=2');
      expect(parts.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'a', value: '2'),
      ]);
    });

    test('extracts fragment after query', () {
      final parts = UrlQueryUtils.parse('https://x/a?a=1#frag');
      expect(parts.base, 'https://x/a');
      expect(parts.params, [const QueryParamEntity(key: 'a', value: '1')]);
      expect(parts.fragment, 'frag');
    });

    test('extracts fragment when no query', () {
      final parts = UrlQueryUtils.parse('https://x/a#frag');
      expect(parts.base, 'https://x/a');
      expect(parts.params, isEmpty);
      expect(parts.fragment, 'frag');
    });

    test('missing equals sign yields empty value', () {
      final parts = UrlQueryUtils.parse('https://x/a?flag');
      expect(parts.params, [const QueryParamEntity(key: 'flag', value: '')]);
    });

    test('trailing equals yields empty value', () {
      final parts = UrlQueryUtils.parse('https://x/a?flag=');
      expect(parts.params, [const QueryParamEntity(key: 'flag', value: '')]);
    });

    test('empty keys are skipped', () {
      final parts = UrlQueryUtils.parse('https://x/a?&a=1&=2&b=3');
      expect(parts.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '3'),
      ]);
    });

    test('percent-decodes values', () {
      final parts = UrlQueryUtils.parse('https://x/a?q=hello%20world');
      expect(parts.params, [const QueryParamEntity(key: 'q', value: 'hello world')]);
    });

    test('percent-decodes special characters in values', () {
      final parts = UrlQueryUtils.parse('https://x/a?q=foo%26bar%3Dbaz');
      expect(parts.params, [const QueryParamEntity(key: 'q', value: 'foo&bar=baz')]);
    });

    test('preserves {{var}} tokens verbatim on parse', () {
      final parts = UrlQueryUtils.parse('https://x/a?id={{userId}}');
      expect(parts.params, [const QueryParamEntity(key: 'id', value: '{{userId}}')]);
    });

    test('only splits on the first ? and first # after it', () {
      final parts = UrlQueryUtils.parse('https://x/a?a=1&b=?=2#frag#tail');
      expect(parts.base, 'https://x/a');
      expect(parts.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '?=2'),
      ]);
      expect(parts.fragment, 'frag#tail');
    });
  });

  group('UrlQueryUtils.parseQuery', () {
    test('returns params list directly', () {
      final list = UrlQueryUtils.parseQuery('https://x/a?a=1&b=2');
      expect(list, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });
  });

  group('UrlQueryUtils.build', () {
    test('reassembles base with no query', () {
      final url = UrlQueryUtils.build(base: 'https://x/a');
      expect(url, 'https://x/a');
    });

    test('emits ordered query', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [
          QueryParamEntity(key: 'a', value: '1'),
          QueryParamEntity(key: 'b', value: '2'),
        ],
      );
      expect(url, 'https://x/a?a=1&b=2');
    });

    test('preserves duplicate keys in order', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [
          QueryParamEntity(key: 'a', value: '1'),
          QueryParamEntity(key: 'a', value: '2'),
        ],
      );
      expect(url, 'https://x/a?a=1&a=2');
    });

    test('appends fragment', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [QueryParamEntity(key: 'a', value: '1')],
        fragment: 'frag',
      );
      expect(url, 'https://x/a?a=1#frag');
    });

    test('skips rows with empty keys', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [
          QueryParamEntity(key: '', value: '1'),
          QueryParamEntity(key: 'b', value: '2'),
        ],
      );
      expect(url, 'https://x/a?b=2');
    });

    test('percent-encodes values', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [QueryParamEntity(key: 'q', value: 'hello world')],
      );
      expect(url, 'https://x/a?q=hello%20world');
    });

    test('percent-encodes ampersand and equals in values', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [QueryParamEntity(key: 'q', value: 'foo&bar=baz')],
      );
      expect(url, 'https://x/a?q=foo%26bar%3Dbaz');
    });

    test('preserves {{var}} tokens literally on build', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [QueryParamEntity(key: 'id', value: '{{userId}}')],
      );
      expect(url, 'https://x/a?id={{userId}}');
    });
  });

  group('UrlQueryUtils.replaceQuery', () {
    test('replaces existing query with new params, preserves fragment', () {
      final url = UrlQueryUtils.replaceQuery(
        'https://x/a?old=1#frag',
        const [QueryParamEntity(key: 'new', value: '2')],
      );
      expect(url, 'https://x/a?new=2#frag');
    });

    test('clears query when params is empty', () {
      final url = UrlQueryUtils.replaceQuery(
        'https://x/a?old=1',
        const [],
      );
      expect(url, 'https://x/a');
    });

    test('adds query to a URL that had none', () {
      final url = UrlQueryUtils.replaceQuery(
        'https://x/a',
        const [QueryParamEntity(key: 'a', value: '1')],
      );
      expect(url, 'https://x/a?a=1');
    });
  });

  group('round-trip', () {
    test('build(parse(url)) is idempotent on canonical input', () {
      const url = 'https://x/a?a=1&b=hello%20world&a=2#frag';
      final parts = UrlQueryUtils.parse(url);
      final rebuilt = UrlQueryUtils.build(
        base: parts.base,
        params: parts.params,
        fragment: parts.fragment,
      );
      expect(rebuilt, url);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/core/utils/url_query_utils_test.dart`
Expected: FAIL — `url_query_utils.dart` does not exist.

- [ ] **Step 3: Implement the module**

Write `lib/core/utils/url_query_utils.dart`:

```dart
import '../domain/entities/query_param_entity.dart';

/// Parsed components of a URL string. `base` is everything before the first
/// `?`; `params` is the parsed query; `fragment` is everything after `#`
/// (null if no fragment).
class UrlParts {
  final String base;
  final List<QueryParamEntity> params;
  final String? fragment;

  const UrlParts({
    required this.base,
    required this.params,
    required this.fragment,
  });
}

/// Parses and builds the query portion of a URL string.
///
/// Preserves `{{var}}` environment-variable tokens verbatim (no percent
/// encoding, no decoding of their contents). Token syntax matches
/// `environment_resolver.dart`: `[A-Za-z0-9_\-\.\s]+` inside balanced braces.
///
/// Duplicate keys are preserved in order. Empty keys are dropped on build.
class UrlQueryUtils {
  UrlQueryUtils._();

  // Matches one {{var}} token. Kept permissive (accepts whitespace inside
  // braces) to mirror EnvironmentResolver.
  static final RegExp _varToken = RegExp(r'\{\{[A-Za-z0-9_\-\.\s]+\}\}');

  static UrlParts parse(String url) {
    final qIndex = url.indexOf('?');
    if (qIndex == -1) {
      final hIndex = url.indexOf('#');
      if (hIndex == -1) {
        return UrlParts(base: url, params: const [], fragment: null);
      }
      return UrlParts(
        base: url.substring(0, hIndex),
        params: const [],
        fragment: url.substring(hIndex + 1),
      );
    }

    final base = url.substring(0, qIndex);
    final afterQ = url.substring(qIndex + 1);
    final hIndex = afterQ.indexOf('#');
    final queryStr = hIndex == -1 ? afterQ : afterQ.substring(0, hIndex);
    final fragment = hIndex == -1 ? null : afterQ.substring(hIndex + 1);

    final params = <QueryParamEntity>[];
    if (queryStr.isNotEmpty) {
      for (final pair in queryStr.split('&')) {
        if (pair.isEmpty) continue;
        final eqIndex = pair.indexOf('=');
        final rawKey = eqIndex == -1 ? pair : pair.substring(0, eqIndex);
        final rawVal = eqIndex == -1 ? '' : pair.substring(eqIndex + 1);
        final key = _decode(rawKey);
        if (key.isEmpty) continue;
        params.add(QueryParamEntity(key: key, value: _decode(rawVal)));
      }
    }

    return UrlParts(base: base, params: params, fragment: fragment);
  }

  static List<QueryParamEntity> parseQuery(String url) => parse(url).params;

  static String replaceQuery(String url, List<QueryParamEntity> params) {
    final parts = parse(url);
    return build(base: parts.base, params: params, fragment: parts.fragment);
  }

  static String build({
    required String base,
    List<QueryParamEntity> params = const [],
    String? fragment,
  }) {
    final buf = StringBuffer(base);
    final rendered = <String>[];
    for (final p in params) {
      if (p.key.isEmpty) continue;
      rendered.add('${_encode(p.key)}=${_encode(p.value)}');
    }
    if (rendered.isNotEmpty) {
      buf.write('?');
      buf.write(rendered.join('&'));
    }
    if (fragment != null) {
      buf.write('#');
      buf.write(fragment);
    }
    return buf.toString();
  }

  // --- encoding / decoding, preserving {{var}} tokens ---

  static String _encode(String input) {
    if (input.isEmpty) return '';
    final buf = StringBuffer();
    int i = 0;
    for (final m in _varToken.allMatches(input)) {
      if (m.start > i) {
        buf.write(Uri.encodeQueryComponent(input.substring(i, m.start)));
      }
      buf.write(m.group(0));
      i = m.end;
    }
    if (i < input.length) {
      buf.write(Uri.encodeQueryComponent(input.substring(i)));
    }
    return buf.toString();
  }

  static String _decode(String input) {
    if (input.isEmpty) return '';
    final buf = StringBuffer();
    int i = 0;
    for (final m in _varToken.allMatches(input)) {
      if (m.start > i) {
        buf.write(_safeDecode(input.substring(i, m.start)));
      }
      buf.write(m.group(0));
      i = m.end;
    }
    if (i < input.length) {
      buf.write(_safeDecode(input.substring(i)));
    }
    return buf.toString();
  }

  static String _safeDecode(String input) {
    try {
      return Uri.decodeQueryComponent(input);
    } catch (_) {
      return input;
    }
  }
}
```

Note: `Uri.encodeQueryComponent` uses form-encoding (spaces → `+`) in Dart. Test cases expect `%20` — switch to `Uri.encodeComponent` if the tests demand it. Run tests next; fix if red.

- [ ] **Step 4: Run tests to verify green**

Run: `fvm flutter test test/core/utils/url_query_utils_test.dart`
Expected: ALL PASS. If `hello world` decoded to `hello+world` instead of `hello world`, replace `Uri.encodeQueryComponent` with `Uri.encodeComponent` (which uses `%20` for spaces) and `Uri.decodeQueryComponent` with `Uri.decodeComponent`. Re-run.

- [ ] **Step 5: Full analyze + test sweep**

Run: `fvm flutter analyze`
Expected: `No issues found!`

Run: `fvm flutter test`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/core/utils/url_query_utils.dart test/core/utils/url_query_utils_test.dart
git commit -m "$(cat <<'EOF'
url query utils

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: URL as params source of truth (cascade)

This task is atomic — every file changes together because the entity's `params` type flips from `Map<String, String>` to a computed `List<QueryParamEntity>`. The task is intentionally larger than the rest so the tree stays compilable between commits.

**Files:**
- Modify: `lib/core/domain/entities/request_config_entity.dart`
- Modify: `lib/features/history/data/models/request_config_model.dart`
- Modify: `lib/features/tabs/data/repositories/tabs_repository_impl.dart`
- Modify: `lib/core/network/network_service.dart`
- Modify: `lib/core/utils/postman/postman_collection_mapper.dart`
- Modify: `lib/features/tabs/presentation/widgets/request_config_section.dart`
- Modify: `test/core/utils/postman/postman_collection_mapper_test.dart`

- [ ] **Step 1: Rewrite `HttpRequestConfigEntity`**

Replace the full contents of `lib/core/domain/entities/request_config_entity.dart`:

```dart
import 'package:equatable/equatable.dart';

import '../../utils/url_query_utils.dart';
import 'query_param_entity.dart';

// Sentinel used by copyWith to distinguish "not provided" from "explicitly null".
const Object _unset = Object();

class HttpRequestConfigEntity extends Equatable {
  final String id;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String body;
  final Map<String, String> auth;
  final String? responseBody;
  final Map<String, String>? responseHeaders;
  final int? statusCode;
  final int? durationMs;

  const HttpRequestConfigEntity({
    required this.id,
    this.method = 'GET',
    this.url = '',
    this.headers = const {
      'Content-Type': 'application/json',
      'Accept': '*/*',
    },
    this.body = '',
    this.auth = const {},
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
  });

  /// Derived view: the query params embedded in [url]. URL is the single
  /// source of truth — never stored separately on the entity. Duplicate keys
  /// are preserved in order.
  List<QueryParamEntity> get params => UrlQueryUtils.parseQuery(url);

  /// Rebuilds the entity. If [url] is supplied it wins. Otherwise, if [params]
  /// is supplied, the current URL's query portion is rewritten to match.
  HttpRequestConfigEntity copyWith({
    String? method,
    String? url,
    Map<String, String>? headers,
    List<QueryParamEntity>? params,
    String? body,
    Map<String, String>? auth,
    Object? responseBody = _unset,
    Object? responseHeaders = _unset,
    Object? statusCode = _unset,
    Object? durationMs = _unset,
  }) {
    final resolvedUrl = url ??
        (params != null ? UrlQueryUtils.replaceQuery(this.url, params) : this.url);
    return HttpRequestConfigEntity(
      id: id,
      method: method ?? this.method,
      url: resolvedUrl,
      headers: headers ?? Map.from(this.headers),
      body: body ?? this.body,
      auth: auth ?? Map.from(this.auth),
      responseBody: identical(responseBody, _unset) ? this.responseBody : responseBody as String?,
      responseHeaders: identical(responseHeaders, _unset)
          ? this.responseHeaders
          : responseHeaders as Map<String, String>?,
      statusCode: identical(statusCode, _unset) ? this.statusCode : statusCode as int?,
      durationMs: identical(durationMs, _unset) ? this.durationMs : durationMs as int?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    method,
    url,
    headers,
    body,
    auth,
    responseBody,
    responseHeaders,
    statusCode,
    durationMs,
  ];
}
```

Key changes:
- No stored `params` field; removed from constructor, `copyWith` signature changed type, `props` no longer lists `params` (fully determined by `url`).
- `copyWith(params: ...)` rewrites `url`. `copyWith(url: ...)` wins over `copyWith(params: ...)` if both supplied.

- [ ] **Step 2: Update `HttpRequestConfig` Hive model**

Rewrite `lib/features/history/data/models/request_config_model.dart`:

```dart
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/domain/entities/query_param_entity.dart';
import '../../../../core/domain/entities/request_config_entity.dart';
import '../../../../core/utils/url_query_utils.dart';

part 'request_config_model.g.dart';

@HiveType(typeId: 1)
class HttpRequestConfig extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1, defaultValue: 'GET')
  String method;

  @HiveField(2, defaultValue: '')
  String url;

  @HiveField(3)
  Map<String, String> headers;

  // Legacy field retained for backward compat with pre-migration Hive data.
  // New records always write an empty map here; queries live inside [url].
  // See toEntity() for the one-time lazy migration.
  @HiveField(4)
  Map<String, String> params;

  @HiveField(5, defaultValue: '')
  String body;

  @HiveField(6)
  Map<String, String> auth;

  @HiveField(7)
  String? responseBody;

  @HiveField(8)
  Map<String, String>? responseHeaders;

  @HiveField(9)
  int? statusCode;

  @HiveField(10)
  int? durationMs;

  HttpRequestConfig({
    String? id,
    this.method = 'GET',
    this.url = '',
    Map<String, String>? headers,
    Map<String, String>? params,
    this.body = '',
    Map<String, String>? auth,
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
  })  : id = id ?? const Uuid().v4(),
        headers = headers ??
            {
              'Content-Type': 'application/json',
              'Accept': '*/*',
            },
        params = params ?? {},
        auth = auth ?? {};

  factory HttpRequestConfig.fromEntity(HttpRequestConfigEntity entity) => HttpRequestConfig(
    id: entity.id,
    method: entity.method,
    url: entity.url,
    headers: entity.headers,
    // URL carries the query now; stored params stays empty going forward.
    params: const {},
    body: entity.body,
    auth: entity.auth,
    responseBody: entity.responseBody,
    responseHeaders: entity.responseHeaders,
    statusCode: entity.statusCode,
    durationMs: entity.durationMs,
  );

  HttpRequestConfigEntity toEntity() {
    // Lazy migration: if a legacy record stored params in the separate map,
    // merge them into the URL's query string. Next save will write params
    // back as empty — this runs at most once per record.
    var entityUrl = url;
    if (params.isNotEmpty) {
      final legacy = params.entries
          .map((e) => QueryParamEntity(key: e.key, value: e.value))
          .toList(growable: false);
      entityUrl = UrlQueryUtils.replaceQuery(url, legacy);
    }
    return HttpRequestConfigEntity(
      id: id,
      method: method,
      url: entityUrl,
      headers: headers,
      body: body,
      auth: auth,
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      statusCode: statusCode,
      durationMs: durationMs,
    );
  }

  // Equality deliberately considers only the request signature — method, url,
  // and body — ignoring `id` and response fields. URL now carries the query
  // portion, so dedup naturally distinguishes ?a=1 from ?a=2. See CLAUDE.md §6.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HttpRequestConfig &&
        other.method == method &&
        other.url == url &&
        other.body == body;
  }

  @override
  int get hashCode => Object.hash(method, url, body);
}
```

Note: no `@HiveType` or `@HiveField` declarations changed. `build_runner` does **not** need to run. The generated `request_config_model.g.dart` stays valid.

- [ ] **Step 3: Rewire `sendRequest`**

Replace `lib/features/tabs/data/repositories/tabs_repository_impl.dart`:

```dart
import '../../../../core/domain/entities/request_config_entity.dart';
import '../../../../core/error/guard.dart';
import '../../../../core/network/http_response.dart';
import '../../../../core/network/network_service.dart';
import '../../../../core/utils/environment_resolver.dart';
import '../../../../core/utils/url_query_utils.dart';
import '../../domain/entities/request_tab_entity.dart';
import '../../domain/repositories/tabs_repository.dart';
import '../datasources/tabs_local_data_source.dart';
import '../models/request_tab_model.dart';

class TabsRepositoryImpl implements TabsRepository {
  final TabsLocalDataSource localDataSource;
  final NetworkService networkService;

  TabsRepositoryImpl({
    required this.localDataSource,
    required this.networkService,
  });

  @override
  Future<List<HttpRequestTabEntity>> getTabs() => guardPersistence(() async {
    final models = await localDataSource.getTabs();
    return models.map((m) => m.toEntity()).toList();
  });

  @override
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs) => guardPersistence(() async {
    final models = tabs.map((e) => HttpRequestTabModel.fromEntity(e)).toList();
    await localDataSource.saveTabs(models);
  });

  @override
  Future<HttpResponseEntity> sendRequest(
    HttpRequestConfigEntity config, {
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
  }) {
    final parts = UrlQueryUtils.parse(config.url);
    final resolvedBase = EnvironmentResolver.resolve(parts.base, envVars);

    // Duplicate keys ride through as list values — Dio (with ListFormat.multi)
    // serializes `[1, 2]` as `?key=1&key=2`.
    final queryMap = <String, List<String>>{};
    for (final p in parts.params) {
      queryMap
          .putIfAbsent(p.key, () => <String>[])
          .add(EnvironmentResolver.resolve(p.value, envVars));
    }

    final resolvedBody = config.body.isNotEmpty
        ? EnvironmentResolver.resolve(config.body, envVars)
        : null;

    return networkService.request(
      url: resolvedBase,
      method: config.method,
      queryParameters: queryMap,
      data: resolvedBody,
      headers: EnvironmentResolver.resolveMap(config.headers, envVars),
      cancelHandle: cancelHandle,
    );
  }
}
```

Fragment (`parts.fragment`) is intentionally dropped — servers never see URL fragments.

- [ ] **Step 4: Configure Dio `ListFormat.multi`**

Modify `lib/core/network/network_service.dart` — in `buildDio()`, add `listFormat: ListFormat.multi` to `BaseOptions`:

```dart
static Dio buildDio() {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (_) => true,
    listFormat: ListFormat.multi,
  ));
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      requestHeader: false,
      responseHeader: false,
      request: true,
      error: true,
    ));
  }
  return dio;
}
```

This ensures duplicate keys serialize as `?a=1&a=2` rather than the default CSV form (`?a=1,2`).

- [ ] **Step 5: Update Postman mapper (export + import)**

Modify `lib/core/utils/postman/postman_collection_mapper.dart`:

1. Add imports at the top:

```dart
import '../url_query_utils.dart';
```

2. Replace `_configToRequest` with:

```dart
static Map<String, dynamic> _configToRequest(HttpRequestConfigEntity? config) {
  if (config == null) {
    return {
      'method': 'GET',
      'header': <Map<String, dynamic>>[],
      'url': {'raw': ''},
    };
  }
  final headers = config.headers.entries
      .map((e) => {'key': e.key, 'value': e.value, 'type': 'text'})
      .toList();
  final urlObj = <String, dynamic>{'raw': config.url};
  // Emit the structured `query` array so Postman's UI renders rows.
  // Derived from the URL's query portion — duplicates preserved.
  final query = UrlQueryUtils.parseQuery(config.url);
  if (query.isNotEmpty) {
    urlObj['query'] = query
        .map((p) => {'key': p.key, 'value': p.value})
        .toList();
  }
  final result = <String, dynamic>{
    'method': config.method,
    'header': headers,
    'url': urlObj,
  };
  if (config.body.isNotEmpty) {
    final isJson = config.headers.entries.any((e) =>
        e.key.toLowerCase() == 'content-type' &&
        e.value.toLowerCase().contains('json'));
    result['body'] = {
      'mode': 'raw',
      'raw': config.body,
      if (isJson)
        'options': {
          'raw': {'language': 'json'},
        },
    };
  }
  return result;
}
```

3. Replace `_requestToConfig` with:

```dart
static HttpRequestConfigEntity _requestToConfig(Map<String, dynamic> request) {
  final method = (request['method'] as String?)?.toUpperCase() ?? 'GET';
  final rawUrl = _parseUrl(request['url']);
  final structuredQuery = _parseQueryList(request['url']);
  // If Postman gave us a structured query block, it takes precedence — merge
  // it into the raw URL's query portion. Otherwise keep raw as-is.
  final mergedUrl = structuredQuery == null
      ? rawUrl
      : UrlQueryUtils.replaceQuery(rawUrl, structuredQuery);
  final headers = _parseHeaders(request['header']);
  final body = _parseBody(request['body']);
  return HttpRequestConfigEntity(
    id: _uuid.v4(),
    method: method,
    url: mergedUrl,
    headers: headers,
    body: body,
  );
}
```

4. Replace `_parseQuery` with `_parseQueryList`:

```dart
/// Returns null when the Postman payload did not include a structured
/// `url.query` array at all (caller should keep the raw URL's query intact).
/// Returns an empty list when `url.query` was present but empty or fully
/// disabled (caller should clear the raw URL's query).
static List<QueryParamEntity>? _parseQueryList(dynamic url) {
  if (url is! Map) return null;
  final query = url['query'];
  if (query is! List) return null;
  final result = <QueryParamEntity>[];
  for (final entry in query.whereType<Map>()) {
    if (entry['disabled'] == true) continue;
    final key = entry['key'];
    final value = entry['value'];
    if (key is! String || key.isEmpty) continue;
    result.add(QueryParamEntity(
      key: key,
      value: value is String ? value : (value?.toString() ?? ''),
    ));
  }
  return result;
}
```

Add the import:

```dart
import '../../domain/entities/query_param_entity.dart';
```

- [ ] **Step 6: Split the Params editor widget**

Rewrite `lib/features/tabs/presentation/widgets/request_config_section.dart`. The public shell (`RequestConfigSection`) stays, but internally `_KeyValueEditor` splits into `_QueryParamsEditor` (List) and `_HeadersEditor` (Map). Shared row UI (`_KeyValueRow`) stays.

Full file:

```dart
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';

const ListEquality<QueryParamEntity> _queryParamListEquality =
    ListEquality<QueryParamEntity>();

class RequestConfigSection extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController bodyController;
  const RequestConfigSection({super.key, required this.tabId, required this.bodyController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        if (p == null || n == null) return true;
        // URL carries the query — a single equality check captures any params
        // change that would affect the PARAMS tab.
        return p.config.url != n.config.url ||
            !headerMapEquality.equals(p.config.headers, n.config.headers);
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        return DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                dividerColor: Colors.transparent,
                isScrollable: true,
                indicator: BoxDecoration(
                  color: theme.primaryColor,
                  border: Border(
                    top: BorderSide(color: theme.dividerColor, width: layout.borderThick),
                    left: BorderSide(color: theme.dividerColor, width: layout.borderThick),
                    right: BorderSide(color: theme.dividerColor, width: layout.borderThick),
                  ),
                ),
                labelColor: theme.colorScheme.onPrimary,
                unselectedLabelColor: theme.colorScheme.onSurface,
                labelStyle: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.displayWeight),
                tabs: const [
                  Tab(text: 'PARAMS'),
                  Tab(text: 'HEADERS'),
                  Tab(text: 'BODY'),
                ],
              ),
              Expanded(
                child: Container(
                  decoration: context.appDecoration.panelBox(context, offset: 0),
                  child: TabBarView(
                    children: [
                      _QueryParamsEditor(
                        items: tab.config.params,
                        onChanged: (list) {
                          final current = context.read<TabsBloc>().state.tabs.byId(tabId);
                          if (current == null) return;
                          context.read<TabsBloc>().add(UpdateTab(
                            current.copyWith(config: current.config.copyWith(params: list)),
                          ));
                        },
                      ),
                      _HeadersEditor(
                        items: tab.config.headers,
                        onChanged: (map) {
                          final current = context.read<TabsBloc>().state.tabs.byId(tabId);
                          if (current == null) return;
                          context.read<TabsBloc>().add(UpdateTab(
                            current.copyWith(config: current.config.copyWith(headers: map)),
                          ));
                        },
                      ),
                      _buildBodyEditor(context, theme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBodyEditor(BuildContext context, ThemeData theme) {
    final layout = context.appLayout;

    return Stack(
      children: [
        JsonCodeEditor(controller: bodyController),
        Positioned(
          top: 8,
          right: 8,
          child: context.appDecoration.wrapInteractive(
            child: IconButton(
              icon: Icon(Icons.auto_fix_high, color: theme.colorScheme.secondary, size: layout.isCompact ? 20 : 24),
              tooltip: 'Beautify JSON',
              onPressed: () async {
                final prettified = await JsonUtils.prettify(bodyController.text);
                bodyController.text = prettified;
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Editor for ordered `List<QueryParamEntity>`. Duplicates allowed, order
/// preserved. Mirrors the echo-suppression pattern of `_HeadersEditor`.
class _QueryParamsEditor extends StatefulWidget {
  final List<QueryParamEntity> items;
  final Function(List<QueryParamEntity>) onChanged;

  const _QueryParamsEditor({required this.items, required this.onChanged});

  @override
  State<_QueryParamsEditor> createState() => _QueryParamsEditorState();
}

class _QueryParamsEditorState extends State<_QueryParamsEditor> {
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;
  List<QueryParamEntity>? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.items);
  }

  void _initControllers(List<QueryParamEntity> items) {
    _keyControllers = [];
    _valControllers = [];

    for (final p in items) {
      _keyControllers.add(TextEditingController(text: p.key));
      _valControllers.add(TextEditingController(text: p.value));
    }
    _keyControllers.add(TextEditingController());
    _valControllers.add(TextEditingController());
  }

  @override
  void didUpdateWidget(_QueryParamsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastEmitted != null &&
        _queryParamListEquality.equals(widget.items, _lastEmitted)) {
      return;
    }
    if (_queryParamListEquality.equals(widget.items, oldWidget.items)) {
      return;
    }
    _disposeControllers();
    _initControllers(widget.items);
    _lastEmitted = null;
  }

  void _disposeControllers() {
    for (final c in _keyControllers) {
      c.dispose();
    }
    for (final c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  List<QueryParamEntity> _asList() {
    final list = <QueryParamEntity>[];
    for (int i = 0; i < _keyControllers.length; i++) {
      final key = _keyControllers[i].text;
      final val = _valControllers[i].text;
      if (key.isNotEmpty) {
        list.add(QueryParamEntity(key: key, value: val));
      }
    }
    return list;
  }

  void _emit() {
    final list = _asList();
    _lastEmitted = list;
    widget.onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return ListView.builder(
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return _KeyValueRow(
          key: ValueKey(_keyControllers[index]),
          keyController: _keyControllers[index],
          valController: _valControllers[index],
          layout: layout,
          isLast: index == _keyControllers.length - 1,
          onKeyChanged: (val) {
            if (index == _keyControllers.length - 1 && val.isNotEmpty) {
              setState(() {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
              });
            }
            _emit();
          },
          onValChanged: (val) => _emit(),
          onDelete: () {
            setState(() {
              _keyControllers[index].dispose();
              _valControllers[index].dispose();
              _keyControllers.removeAt(index);
              _valControllers.removeAt(index);
              if (_keyControllers.isEmpty) {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
              }
              _emit();
            });
          },
        );
      },
    );
  }
}

/// Editor for headers, still keyed as `Map<String, String>`. Duplicates are
/// not a real concern for headers in this UI — last-write-wins is fine.
class _HeadersEditor extends StatefulWidget {
  final Map<String, String> items;
  final Function(Map<String, String>) onChanged;

  const _HeadersEditor({required this.items, required this.onChanged});

  @override
  State<_HeadersEditor> createState() => _HeadersEditorState();
}

class _HeadersEditorState extends State<_HeadersEditor> {
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;
  Map<String, String>? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.items);
  }

  void _initControllers(Map<String, String> items) {
    _keyControllers = [];
    _valControllers = [];

    for (final entry in items.entries) {
      _keyControllers.add(TextEditingController(text: entry.key));
      _valControllers.add(TextEditingController(text: entry.value));
    }
    _keyControllers.add(TextEditingController());
    _valControllers.add(TextEditingController());
  }

  @override
  void didUpdateWidget(_HeadersEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastEmitted != null && headerMapEquality.equals(widget.items, _lastEmitted)) {
      return;
    }
    if (headerMapEquality.equals(widget.items, oldWidget.items)) {
      return;
    }
    _disposeControllers();
    _initControllers(widget.items);
    _lastEmitted = null;
  }

  void _disposeControllers() {
    for (final c in _keyControllers) {
      c.dispose();
    }
    for (final c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Map<String, String> _asMap() {
    final map = <String, String>{};
    for (int i = 0; i < _keyControllers.length; i++) {
      final key = _keyControllers[i].text;
      final val = _valControllers[i].text;
      if (key.isNotEmpty) {
        map[key] = val;
      }
    }
    return map;
  }

  void _emit() {
    final map = _asMap();
    _lastEmitted = map;
    widget.onChanged(map);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return ListView.builder(
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return _KeyValueRow(
          key: ValueKey(_keyControllers[index]),
          keyController: _keyControllers[index],
          valController: _valControllers[index],
          layout: layout,
          isLast: index == _keyControllers.length - 1,
          onKeyChanged: (val) {
            if (index == _keyControllers.length - 1 && val.isNotEmpty) {
              setState(() {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
              });
            }
            _emit();
          },
          onValChanged: (val) => _emit(),
          onDelete: () {
            setState(() {
              _keyControllers[index].dispose();
              _valControllers[index].dispose();
              _keyControllers.removeAt(index);
              _valControllers.removeAt(index);
              if (_keyControllers.isEmpty) {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
              }
              _emit();
            });
          },
        );
      },
    );
  }
}

class _KeyValueRow extends StatefulWidget {
  final TextEditingController keyController;
  final TextEditingController valController;
  final AppLayout layout;
  final bool isLast;
  final Function(String) onKeyChanged;
  final Function(String) onValChanged;
  final VoidCallback onDelete;

  const _KeyValueRow({
    super.key,
    required this.keyController,
    required this.valController,
    required this.layout,
    required this.isLast,
    required this.onKeyChanged,
    required this.onValChanged,
    required this.onDelete,
  });

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: widget.layout.isCompact ? 8.0 : 12.0),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _isHovered ? theme.hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          border: Border.all(color: _isHovered ? theme.dividerColor.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                decoration: InputDecoration(
                  hintText: 'KEY',
                  isDense: true,
                  contentPadding: EdgeInsets.all(widget.layout.isCompact ? 8 : 12),
                ),
                controller: widget.keyController,
                onChanged: widget.onKeyChanged,
              ),
            ),
            SizedBox(width: widget.layout.isCompact ? 8 : 12),
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                decoration: InputDecoration(
                  hintText: 'VALUE',
                  isDense: true,
                  contentPadding: EdgeInsets.all(widget.layout.isCompact ? 8 : 12),
                ),
                controller: widget.valController,
                onChanged: widget.onValChanged,
              ),
            ),
            SizedBox(width: widget.layout.isCompact ? 4 : 8),
            context.appDecoration.wrapInteractive(
              child: IconButton(
                icon: Icon(Icons.delete_outline, size: widget.layout.isCompact ? 20 : 24, color: Theme.of(context).colorScheme.error),
                onPressed: widget.onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Update Postman mapper tests to pass query via URL**

In `test/core/utils/postman/postman_collection_mapper_test.dart`, update the fixtures and expectations:

Line 28, the `maps folders and request leaves` test — change the leaf fixture to put the query inside the URL instead of the `params` map:

```dart
const child = CollectionNodeEntity(
  id: 'leaf',
  name: 'Get Users',
  isFolder: false,
  config: HttpRequestConfigEntity(
    id: 'cfg',
    method: 'GET',
    url: 'https://api.example.com/users?page=1',
    headers: {'X-Token': 'abc', 'Accept': 'application/json'},
    body: '',
  ),
);
```

Update its expectation so `url.raw` carries the query and `url.query` is derived:

```dart
expect(request['url']['raw'], 'https://api.example.com/users?page=1');
final query = request['url']['query'] as List;
expect(query.first, {'key': 'page', 'value': '1'});
```

Line 130, the `parses a basic v2.1 collection` test — change `leaf.config!.params['x']` to assert on the derived getter:

```dart
expect(
  leaf.config!.params,
  [const QueryParamEntity(key: 'x', value: '1')],
);
```

Add the import at the top of the test file:

```dart
import 'package:getman/core/domain/entities/query_param_entity.dart';
```

Line 174, the `skips disabled headers and query entries` test — change:

```dart
expect(config.params, {'k1': 'v1'});
```

to:

```dart
expect(
  config.params,
  [const QueryParamEntity(key: 'k1', value: 'v1')],
);
```

And verify the merged URL behaviour:

```dart
expect(config.url, 'https://x.y?k1=v1');
```

Line 209 and 241, the `round-trip` test — update both fixture and assertion:

Change the original leaf to:

```dart
config: HttpRequestConfigEntity(
  id: 'cfg',
  method: 'POST',
  url: 'https://api.example.com/things?dry=true',
  headers: {'Content-Type': 'application/json', 'X-Key': 'k'},
  body: '{"a":1}',
),
```

And change the expectation:

```dart
expect(leaf.config!.url, 'https://api.example.com/things?dry=true');
expect(
  leaf.config!.params,
  [const QueryParamEntity(key: 'dry', value: 'true')],
);
```

Add one more test in the `fromJson` group to prove `url.query` wins over a conflicting `url.raw` query — append after the `skips disabled…` test:

```dart
test('structured url.query takes precedence over url.raw query', () {
  const source = '''
{
  "info": {"name": "S", "schema": "v2.1.0"},
  "item": [
    {
      "name": "R",
      "request": {
        "method": "GET",
        "url": {
          "raw": "https://x.y?old=1",
          "query": [{"key": "new", "value": "2"}]
        }
      }
    }
  ]
}
''';
  final config = PostmanCollectionMapper.fromJson(source).children.first.config!;
  expect(config.url, 'https://x.y?new=2');
  expect(
    config.params,
    [const QueryParamEntity(key: 'new', value: '2')],
  );
});
```

Add one more test in the `toJson` group to prove duplicate keys survive export — append after `maps folders and request leaves`:

```dart
test('preserves duplicate query keys on export', () {
  const leaf = CollectionNodeEntity(
    id: 'leaf',
    name: 'Dup',
    isFolder: false,
    config: HttpRequestConfigEntity(
      id: 'cfg',
      url: 'https://x.y?a=1&a=2',
    ),
  );
  final decoded = jsonDecode(PostmanCollectionMapper.toJson(leaf)) as Map<String, dynamic>;
  final item = (decoded['item'] as List).first as Map<String, dynamic>;
  final query = item['request']['url']['query'] as List;
  expect(query, [
    {'key': 'a', 'value': '1'},
    {'key': 'a', 'value': '2'},
  ]);
});
```

- [ ] **Step 8: Analyze**

Run: `fvm flutter analyze`
Expected: `No issues found!`

If errors appear, they'll be in the form of "The named parameter 'params' isn't defined for the type 'HttpRequestConfigEntity'" in files you didn't see — surface via analyze output and fix. Known call sites are the ones enumerated in this task; any extra is a bug in this plan — fix and note.

- [ ] **Step 9: Run all tests**

Run: `fvm flutter test`
Expected: ALL PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/core/domain/entities/request_config_entity.dart \
        lib/features/history/data/models/request_config_model.dart \
        lib/features/tabs/data/repositories/tabs_repository_impl.dart \
        lib/core/network/network_service.dart \
        lib/core/utils/postman/postman_collection_mapper.dart \
        lib/features/tabs/presentation/widgets/request_config_section.dart \
        test/core/utils/postman/postman_collection_mapper_test.dart
git commit -m "$(cat <<'EOF'
url as params source of truth

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Entity unit tests

**Files:**
- Create: `test/core/domain/entities/request_config_entity_test.dart`

- [ ] **Step 1: Write the tests**

Write `test/core/domain/entities/request_config_entity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';

void main() {
  group('HttpRequestConfigEntity.params getter', () {
    test('returns empty list when URL has no query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a');
      expect(config.params, isEmpty);
    });

    test('derives list from URL query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?a=1&b=2');
      expect(config.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });

    test('preserves duplicate keys', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?a=1&a=2');
      expect(config.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'a', value: '2'),
      ]);
    });
  });

  group('HttpRequestConfigEntity.copyWith', () {
    test('copyWith(url: ...) rewrites the URL directly', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a');
      final next = config.copyWith(url: 'https://example.com/b?c=1');
      expect(next.url, 'https://example.com/b?c=1');
      expect(next.params, [const QueryParamEntity(key: 'c', value: '1')]);
    });

    test('copyWith(params: [...]) rewrites the URL query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?old=1');
      final next = config.copyWith(params: const [
        QueryParamEntity(key: 'a', value: '1'),
        QueryParamEntity(key: 'b', value: '2'),
      ]);
      expect(next.url, 'https://example.com/a?a=1&b=2');
      expect(next.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });

    test('copyWith(params: []) clears the query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?old=1');
      final next = config.copyWith(params: const []);
      expect(next.url, 'https://example.com/a');
      expect(next.params, isEmpty);
    });

    test('copyWith(url:, params:) — url wins', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a');
      final next = config.copyWith(
        url: 'https://example.com/b?kept=1',
        params: const [QueryParamEntity(key: 'ignored', value: 'x')],
      );
      expect(next.url, 'https://example.com/b?kept=1');
      expect(next.params, [const QueryParamEntity(key: 'kept', value: '1')]);
    });

    test('copyWith preserves fragment when rewriting query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?old=1#frag');
      final next = config.copyWith(params: const [
        QueryParamEntity(key: 'new', value: '2'),
      ]);
      expect(next.url, 'https://example.com/a?new=2#frag');
    });
  });
}
```

- [ ] **Step 2: Run the tests**

Run: `fvm flutter test test/core/domain/entities/request_config_entity_test.dart`
Expected: ALL PASS (functionality already exists from Task 3; these tests just lock it in).

- [ ] **Step 3: Commit**

```bash
git add test/core/domain/entities/request_config_entity_test.dart
git commit -m "$(cat <<'EOF'
request config entity tests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Hive model legacy-params migration test

**Files:**
- Create: `test/features/history/data/models/request_config_model_test.dart`

- [ ] **Step 1: Write the test**

Write `test/features/history/data/models/request_config_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';

void main() {
  group('HttpRequestConfig.toEntity() legacy-params migration', () {
    test('merges legacy params map into URL when non-empty', () {
      final model = HttpRequestConfig(
        id: 'id',
        method: 'GET',
        url: 'https://x.y/path',
        params: {'a': '1', 'b': '2'},
      );
      final entity = model.toEntity();
      expect(entity.url, 'https://x.y/path?a=1&b=2');
      expect(entity.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });

    test('replaces existing URL query with legacy params when both present', () {
      // Pre-migration data should not have both, but be lenient: legacy map
      // wins to restore user intent (they had explicit params rows before).
      final model = HttpRequestConfig(
        id: 'id',
        url: 'https://x.y/path?stale=1',
        params: {'fresh': '2'},
      );
      final entity = model.toEntity();
      expect(entity.url, 'https://x.y/path?fresh=2');
    });

    test('passes URL through when legacy params is empty', () {
      final model = HttpRequestConfig(
        id: 'id',
        url: 'https://x.y/path?already=here',
        params: const {},
      );
      final entity = model.toEntity();
      expect(entity.url, 'https://x.y/path?already=here');
    });

    test('fromEntity writes an empty legacy params map', () {
      const entity = HttpRequestConfigEntity(
        id: 'id',
        url: 'https://x.y/path?a=1',
      );
      final model = HttpRequestConfig.fromEntity(entity);
      expect(model.params, isEmpty);
      expect(model.url, 'https://x.y/path?a=1');
    });
  });
}
```

The `HttpRequestConfigEntity` import is pulled in transitively by `request_config_model.dart` — if the analyzer complains, add:

```dart
import 'package:getman/core/domain/entities/request_config_entity.dart';
```

- [ ] **Step 2: Run the tests**

Run: `fvm flutter test test/features/history/data/models/request_config_model_test.dart`
Expected: ALL PASS.

- [ ] **Step 3: Commit**

```bash
git add test/features/history/data/models/request_config_model_test.dart
git commit -m "$(cat <<'EOF'
request config legacy params migration test

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Final verification

No commit — verification only.

- [ ] **Step 1: Full analyze**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full test run**

Run: `fvm flutter test`
Expected: all green across every test file.

- [ ] **Step 3: Manual smoke on macOS**

Run: `fvm flutter run -d macos`

Verify each of these by hand:

1. **URL → Params (happy path):** In a fresh tab, type `https://httpbin.org/get?a=1&b=2` into the URL bar. Open the PARAMS tab. Two rows appear: `a=1`, `b=2`.
2. **Params → URL (happy path):** In the PARAMS tab, add a row `c=3`. URL bar updates to `https://httpbin.org/get?a=1&b=2&c=3`.
3. **Duplicate keys:** Type `https://httpbin.org/get?a=1&a=2` into the URL bar. The PARAMS tab shows two separate rows both keyed `a`, values `1` and `2`, in order.
4. **Duplicate on edit:** Edit one of the two `a` rows in PARAMS to `a=9`. URL bar updates to reflect the new value in place; the other `a` row stays as `1`.
5. **Delete a row:** Delete one of the `a` rows in PARAMS. URL bar updates with only the remaining param.
6. **Send hits the right URL:** Hit SEND on `https://httpbin.org/get?a=1&a=2`. Response body echoes `"args": {"a": ["1", "2"]}` (httpbin reflects repeated params as an array). If it shows `"a": "1,2"` instead, `ListFormat.multi` didn't land — revisit Task 3 Step 4.
7. **Environment variable in URL:** Create an environment with `{"base": "https://httpbin.org"}`, set it active. Type `{{base}}/get?q=hello` in URL. Highlight is green on `{{base}}`. SEND hits the resolved URL.
8. **Collection restore:** Create a new tab, SAVE it to a collection, change the URL, click the saved tab from the sidebar. URL restores exactly (including any query).
9. **History re-send under a different env:** Send a request with `{{base}}/get?q=1`. Open the history entry — URL shows the templated `{{base}}/get?q=1` (not the resolved form). Click to open in a new tab. Switch environments. Send — new env's base resolves.

Any mismatch → fix before claiming done.

---

## Self-review checklist

Covered in sequence against the spec:

- [x] §4 (Chosen approach — URL source of truth, list of pairs) → Task 3 entity reshape
- [x] §5.1 `QueryParamEntity` → Task 1
- [x] §5.2 Entity changes (computed `params`, `copyWith` wins) → Task 3 Step 1 + Task 4 tests
- [x] §5.3 `UrlQueryUtils` module → Task 2
- [x] §5.4 Send path (split, `Map<String, List<String>>`, fragment dropped) → Task 3 Step 3
- [x] §5.4 `ListFormat.multi` — `listFormat: ListFormat.multi` on Dio `BaseOptions` → Task 3 Step 4
- [x] §5.5 Hive model fromEntity/toEntity + lazy migration → Task 3 Step 2 + Task 5
- [x] §5.6 Params panel split (`_QueryParamsEditor` + `_HeadersEditor`) → Task 3 Step 6
- [x] §5.7 URL bar unchanged → explicit no-op in file map
- [x] §5.8 Curl unchanged → explicit no-op in file map
- [x] §5.9 Postman mapper export + import → Task 3 Step 5
- [x] §6 Migration behaviour (lazy, no boot-time pass, no `build_runner`) → Task 3 Step 2 + Task 5
- [x] §7 Tests (`url_query_utils_test`, `request_config_model_test`, updated Postman mapper test, duplicate-keys export, `url.query` wins) → Tasks 2, 3.7, 5
- [x] §8 Verification gate (analyze + test) → runs at end of every task + Task 6

Out-of-scope items in §3 (disabled-per-row checkbox, headers refactor, auth tab) remain explicitly untouched.

---

**End of plan.**
