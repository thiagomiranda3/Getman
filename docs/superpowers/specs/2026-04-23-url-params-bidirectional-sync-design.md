# URL ↔ Params Bi-Directional Sync — Design

**Date:** 2026-04-23
**Status:** Approved, ready for implementation plan
**Area:** `tabs` feature (request editor), `HttpRequestConfigEntity`, `curl` + Postman mappers

---

## 1. Problem

Today the request editor has two places of truth for query parameters:

- `HttpRequestConfigEntity.url` — a path-only URL string
- `HttpRequestConfigEntity.params` — a `Map<String, String>` displayed in the PARAMS tab

These never reflect each other. If the user types `?a=1` into the URL bar, the Params panel doesn't update. If they add a row in the Params panel, the URL bar doesn't update. Postman users expect both to stay in sync — it is the Postman mental model.

## 2. Goal

Make the URL bar and the Params panel display the same data, always, with no sync logic in the bloc. Support duplicate keys (`?a=1&a=2`) so the design matches Postman's row-based model.

## 3. Non-goals

- Disabled/enabled checkbox per row (Postman feature — not requested).
- Moving Headers to a list-of-pairs representation — out of scope; Headers stays `Map<String, String>`.
- Auth tab changes — unchanged.
- An "edit raw URL vs. structured URL" toggle — out of scope.

## 4. Chosen approach

**Option A: URL is the single source of truth.** The URL string stores the full query (`?a=1&b=2#frag`) inline. `params` becomes a **computed view** derived from `url`. No two-way reducer; sync emerges from single-source-of-truth.

**Duplicate keys are preserved** via a list-of-pairs representation. The entity's `params` getter returns `List<QueryParamEntity>`, ordered, duplicates allowed.

### Why this approach

- Matches Postman's actual mental model (URL is the URL; Params panel is a structured editor over its query portion).
- Removes the possibility of drift between two fields — there is only one field.
- Migration is trivial: one conversion inside `HttpRequestConfig.toEntity()`, lazy and idempotent.
- History dedup (already keyed on `method + url + body`) gains query-aware dedup for free.

### Rejected alternatives

- **Keep both fields, sync them bi-directionally via the bloc.** Two sources of truth, drift risk, duplicate state in Hive, harder to reason about when `params` is authoritative vs `url`.
- **Map-based params with last-write-wins on duplicates.** Loses fidelity when a request legitimately has `?a=1&a=2` (a real use case in some APIs). User explicitly chose duplicate-preserving behavior.

## 5. Architecture

### 5.1 `QueryParamEntity` (new)

`lib/core/domain/entities/query_param_entity.dart`

```dart
class QueryParamEntity extends Equatable {
  final String key;
  final String value;
  const QueryParamEntity({required this.key, required this.value});
  @override
  List<Object?> get props => [key, value];
}
```

Pure Dart, no Hive, no Flutter.

### 5.2 `HttpRequestConfigEntity` changes

`lib/core/domain/entities/request_config_entity.dart`

- Remove the stored `params` field.
- Add a computed getter: `List<QueryParamEntity> get params => UrlQueryUtils.parseQuery(url);`
- `copyWith({List<QueryParamEntity>? params, String? url, ...})`:
  - If `url` supplied → use as-is.
  - Else if `params` supplied → `UrlQueryUtils.replaceQuery(this.url, params)`.
  - Else → `this.url`.
- `props` drops `params` (it is fully determined by `url`).
- Default constructor signature drops the `params` named parameter.

**Callers migrated in this change:**
- `CurlUtils.parse` — no longer passes `params` (URL already carries query). No code change required in curl_utils — it already only populates `url`.
- `PostmanCollectionMapper._requestToConfig` — merges `url.query` into `url.raw` before constructing the entity (see §5.5).
- `request_config_section.dart` — Params panel (see §5.4).
- `tabs_repository_impl.dart` — send path (see §5.3).

### 5.3 `UrlQueryUtils` (new)

`lib/core/utils/url_query_utils.dart` — pure Dart, no Flutter, tested in isolation.

```dart
class UrlParts {
  final String base;            // everything before the first '?'
  final List<QueryParamEntity> params;
  final String? fragment;       // everything after '#', or null
}

class UrlQueryUtils {
  static UrlParts parse(String url);
  static List<QueryParamEntity> parseQuery(String url);
  static String replaceQuery(String url, List<QueryParamEntity> params);
  static String build({required String base, List<QueryParamEntity> params = const [], String? fragment});
}
```

**Parsing rules:**
- Split on the **first** `?`. Everything before is `base`.
- From there, split on the **first** `#`. Everything between `?` and `#` is the query. Everything after `#` is `fragment`.
- Query is `&`-separated pairs.
- Each pair: split on the **first** `=`. If no `=` → value is empty string (`?flag` → `flag=''`).
- **Skip empty keys** (`?&a=1` → `[('a','1')]`).
- **Percent-decode** key and value.
- **Preserve `{{var}}` tokens verbatim.** Token regex: `\{\{[A-Za-z0-9_\-\.\s]+\}\}` (matches `environment_resolver.dart`). The decoder walks the string and skips decoding inside balanced `{{…}}` tokens.

**Build rules:**
- Percent-encode each key and value, preserving `{{var}}` tokens (encode the surrounding characters but not the token itself).
- Skip pairs whose key is empty.
- Join pairs with `&`, prefix with `?` if non-empty.
- Append `#fragment` if present.

**Round-trip invariant:** `build(parse(url)) == url` for any URL whose query has been produced by `build` (canonical form). Non-canonical inputs (e.g., `?a=1&&b=2`, redundant encoding) normalize on round-trip.

### 5.4 Send path

`lib/features/tabs/data/repositories/tabs_repository_impl.dart`

Replace the current `sendRequest` body with:

```dart
final parts = UrlQueryUtils.parse(config.url);
final resolvedBase = EnvironmentResolver.resolve(parts.base, envVars);

final queryMap = <String, List<String>>{};
for (final p in parts.params) {
  queryMap.putIfAbsent(p.key, () => []).add(EnvironmentResolver.resolve(p.value, envVars));
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
```

- `Map<String, List<String>>` preserves duplicate keys — Dio serializes list values as repeated params (`a=1&a=2`).
- Fragment is dropped before hitting the network (servers never receive fragments — standard HTTP behavior).
- Env-resolution scope is preserved per `CLAUDE.md` §4.10: URL base, query values, header values, body. **Keys unchanged.**
- `NetworkService.request` already accepts `Map<String, dynamic>?` for `queryParameters`; `Map<String, List<String>>` fits. Verify Dio's query serialization produces `a=1&a=2` for list values (default behavior; if the `ListFormat` defaults to CSV, configure `ListFormat.multi` on the Dio BaseOptions).

### 5.5 Hive model + lazy migration

`lib/features/history/data/models/request_config_model.dart`

- Keep `@HiveField(4) Map<String, String> params` declared. Do **not** remove, renumber, or re-type — `CLAUDE.md` §3 prohibits this.
- `HttpRequestConfig.fromEntity(entity)`: always writes `params: {}`. Entity no longer has a stored `params` field to source from.
- `HttpRequestConfig.toEntity()`:
  ```dart
  if (params.isNotEmpty) {
    final legacy = params.entries.map((e) => QueryParamEntity(key: e.key, value: e.value)).toList();
    final migratedUrl = UrlQueryUtils.replaceQuery(url, legacy);
    return HttpRequestConfigEntity(id: id, method: method, url: migratedUrl, ...);
  }
  return HttpRequestConfigEntity(id: id, method: method, url: url, ...);
  ```
- Migration is lazy and idempotent. On next save, `fromEntity` writes `params: {}`, and subsequent loads skip the migration branch.
- **No `build_runner` regen needed** — no `@HiveType`/`@HiveField` additions or type changes.
- **No explicit boot-time migration pass needed** — round-trips clean up organically.

### 5.6 Params panel UI

`lib/features/tabs/presentation/widgets/request_config_section.dart`

- Split `_KeyValueEditor` into **`_QueryParamsEditor`** (new, `List<QueryParamEntity>`-based) and **`_HeadersEditor`** (renamed existing, `Map<String, String>`-based).
- Shared row UI `_KeyValueRow` stays.
- `_QueryParamsEditor`:
  - `items: List<QueryParamEntity>`, `onChanged: (List<QueryParamEntity>)`.
  - Maintains two parallel `List<TextEditingController>` for keys and values (same shape as today).
  - Keeps the **echo-suppression** pattern: `_lastEmitted: List<QueryParamEntity>?`, compared with `const ListEquality<QueryParamEntity>().equals(...)` in `didUpdateWidget`. The purpose (preserve focus and half-typed state during bloc echoes) is unchanged.
  - `_asList()` produces `List<QueryParamEntity>` from the controllers (skipping rows with empty keys, same as today's map version).
- `RequestConfigSection`'s `buildWhen` compares `config.url` (captures base + query in one string). Drops the now-dead `headerMapEquality.equals(p.config.params, n.config.params)` check.
- The Params tab's `onChanged` handler dispatches:
  ```dart
  context.read<TabsBloc>().add(UpdateTab(
    current.copyWith(config: current.config.copyWith(params: list)),
  ));
  ```
  which via the new `copyWith` rewrites `url`'s query portion.

### 5.7 URL bar

`lib/features/tabs/presentation/widgets/url_bar.dart` — **zero code change.**

- Typing `?a=1&b=2` in the URL bar dispatches `UpdateTab` with the new URL string. `RequestConfigSection`'s `BlocBuilder` rebuilds, the Params panel re-renders from the derived `config.params` getter, and rows appear. Bi-directional sync is automatic.
- `VariableHighlightController` already highlights `{{var}}` anywhere in the URL including the query string. No change.
- cURL paste flow unchanged — `CurlUtils.parse` returns a config whose `url` carries the full query.

### 5.8 Curl utils

`lib/core/utils/curl_utils.dart` — **zero code change.**

- `generate` writes `config.url` verbatim, which now includes the query. Correct.
- `parse` populates `config.url` with whatever URL string it finds (already includes any `?…` the user pasted). Correct.

### 5.9 Postman mapper

`lib/core/utils/postman/postman_collection_mapper.dart`

- **Export (`_configToRequest`):**
  - `url.raw = config.url` (unchanged; now includes query).
  - `url.query = UrlQueryUtils.parseQuery(config.url).map((p) => {'key': p.key, 'value': p.value}).toList()`. Preserves round-trip with Postman's structured UI.
- **Import (`_requestToConfig`):**
  - Parse `url.raw` as the base URL (may include query already).
  - Parse `url.query` into a `List<QueryParamEntity>` (respecting `disabled: true` skips, matching today's behavior).
  - If `url.query` is present and non-empty, merge into URL via `UrlQueryUtils.replaceQuery`. If the raw URL already had a query, the structured `url.query` takes precedence (Postman's behavior).
  - Construct entity with the merged URL.
- Remove the separate `_parseQuery` → `Map<String, String>` path; rebuild as a merger that produces a full URL string.

## 6. Migration and compatibility

- **Persisted Hive data** (history, collections, tabs) remains readable. Old records with non-empty legacy `params` get their query merged into `url` on first load through `HttpRequestConfig.toEntity()`, then written back empty on next save.
- **No typeId changes.** No `build_runner` invocation required by this change.
- **Dedup side effect:** history dedup now distinguishes `?a=1` from `?a=2`. This is an intentional UX improvement, not a breaking change — it's a strict refinement of the previous `method+url+body` rule.

## 7. Testing

### New unit tests

**`test/core/utils/url_query_utils_test.dart`**
- Parse: simple (`?a=1`), duplicates (`?a=1&a=2`), fragment (`?a=1#frag`), empty value (`?flag=`), no-value (`?flag`), empty key skipped (`?&a=1`), percent-encoded (`?a=hello%20world` → value `'hello world'`), special chars in values (`?q=foo%26bar` → value `'foo&bar'`).
- `{{var}}` preservation on parse: `?id={{userId}}` → `[('id', '{{userId}}')]`.
- `{{var}}` preservation on build: `[('id', '{{userId}}')]` → `?id={{userId}}` (not percent-encoded).
- Round-trip: `build(parse(canonicalUrl)) == canonicalUrl` for a canonical input.
- Base without query: `parse('https://host/path')` → base stays intact, params empty.
- URL with only fragment: `parse('https://host#frag')` → base `'https://host'`, fragment `'frag'`.

**`test/features/history/data/models/request_config_model_test.dart`**
- Legacy migration: Hive model with `url: 'https://x/y'`, `params: {'a': '1', 'b': '2'}` → entity with `url: 'https://x/y?a=1&b=2'` and empty `params` after re-serialization.

### Updated tests

**`test/core/utils/postman/postman_collection_mapper_test.dart`**
- Export round-trip with duplicate keys.
- Import round-trip where `url.raw` contains a query AND `url.query` is also present — structured `url.query` wins.
- Disabled `url.query` entries still excluded.

### Optional widget test

- Typing `?a=1` into the URL bar causes the Params panel to show a single row `a=1`.
- Adding a row in the Params panel updates the URL bar text to `?key=value`.

Skip if the fixture setup is disproportionate to the value.

## 8. Verification gate

Per `CLAUDE.md` §5:

- `fvm flutter analyze` → `No issues found!`
- `fvm flutter test` → all green

## 9. Rollout checklist

1. `QueryParamEntity` added.
2. `UrlQueryUtils` added, unit tests green.
3. `HttpRequestConfigEntity` reshaped (computed `params`, removed stored field, `copyWith` rewritten).
4. `HttpRequestConfig.toEntity()` migration + `fromEntity` writes empty `params`.
5. `tabs_repository_impl.sendRequest` rewired to parse URL and resolve query.
6. `request_config_section.dart` split into `_QueryParamsEditor` + `_HeadersEditor`; `buildWhen` updated.
7. Postman mapper export/import updated, tests green.
8. Full analyze + test pass.

---

**End of spec.**
