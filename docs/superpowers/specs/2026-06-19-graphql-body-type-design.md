# GraphQL body type (M8) — Design

> Status: approved 2026-06-19. Adds a `graphql` request body type to Getman.
> Backlog item **M8** in `docs/BACKLOG.md`.

## Goal

Let a request carry a GraphQL payload: a **query** and an optional **variables**
JSON object, sent over HTTP as `{"query": ..., "variables": ...}` with
`Content-Type: application/json`. Edited through a dual-pane body editor.

## 1. Data model (storage)

- Add `graphql('graphql')` to the `BodyType` enum
  (`lib/core/domain/entities/body_type.dart`).
- **Reuse the existing `body` field for the GraphQL query.** It is the primary
  content, so the existing `_bodyController` ↔ `config.body` bidirectional sync
  in `request_view.dart` is reused unchanged.
- **Add one new field `graphqlVariables` (String, default `''`)** to:
  - `HttpRequestConfigEntity` (`lib/core/domain/entities/request_config_entity.dart`)
    — constructor field, `copyWith`, `props`.
  - `HttpRequestConfig` Hive model
    (`lib/features/history/data/models/request_config_model.dart`, typeId 1):
    **`@HiveField(15, defaultValue: '')`** (next free field), plus `fromEntity`
    / `toEntity`.
  - Run `dart run build_runner build --delete-conflicting-outputs` to regenerate
    the adapter, then re-run analyze + tests.
- Rationale for a separate field rather than packing query+variables into one
  JSON envelope inside `body`: the editor needs two independent live text
  controllers; packing would force JSON-escaping the query on every keystroke and
  break on half-typed variables. Legacy records read back `graphqlVariables` as
  `''` → no migration required.

## 2. Send path (serialization)

- `BodyTypeUtils.applyContentType` (`lib/core/utils/body_type_utils.dart`) gains
  a `graphql` case → forces `Content-Type: application/json`, skip-if-custom
  (same shape as the binary rule).
- `RequestSerializer.buildBody`
  (`lib/features/tabs/data/request_serializer.dart`) gains a `graphql` case:
  - Resolve `{{vars}}` in both the query (`config.body`) and the variables text
    (`config.graphqlVariables`) via `EnvironmentResolver`.
  - Build and return `{'query': <resolvedQuery>, 'variables': <vars>}` as a
    `Map<String, dynamic>` (Dio JSON-encodes Maps).
  - `vars`: blank variables → `{}`. Non-blank → `jsonDecode(resolvedVariables)`.
- **Invalid variables** (non-blank text that does not `jsonDecode`): throw a new
  pure-Dart `GraphqlVariablesException` (mirrors `FileBodyException` in
  `lib/core/error/exceptions.dart`). The repository maps it to a synthetic
  status-0 error response carrying a clear message
  (`GraphQL variables are not valid JSON: <detail>`) — surfaced in the response
  panel, never silent. Mirror the existing `FileBodyException` mapping path.

## 3. Editor UI (dual pane)

- `_BodyTypeSelector._labels` gains `BodyType.graphql: 'GRAPHQL'`
  (`lib/features/tabs/presentation/widgets/request_editor_tabs.dart`).
- `BodyTabView._editorFor` returns a new `_GraphqlBodyEditor` for
  `BodyType.graphql`.
- Layout: a vertical split — **QUERY** pane on top (reuses the existing
  `_bodyController` bound to `config.body`), **VARIABLES** pane below (a new
  dedicated JSON code controller + beautify affordance, since variables are
  JSON). Each pane gets a small header label. The same widget feeds both the
  split-pane (`RequestConfigSection`) and unified-phone (`UnifiedRequestPanel`)
  layouts.
- The variables controller is created/owned in `request_view.dart` beside
  `_bodyController`, synced bidirectionally to `config.graphqlVariables` — an
  exact mirror of the existing `_onBodyChanged` listener (controller → bloc) and
  the `BlocConsumer` listener (bloc → controller). It is threaded down through
  `RequestConfigSection` / `UnifiedRequestPanel` → `BodyTabView` →
  `_GraphqlBodyEditor`.
- GraphQL query syntax highlighting is out of scope; the query pane uses the
  existing controller (JSON-oriented highlighting falls back to base color on
  non-JSON lines, which is acceptable).

## 4. Integration surfaces

- **Code generation** (`lib/core/utils/code_gen_service.dart`) — compiler-forced
  across all 6 targets (cURL, fetch, axios, requests, net/http, OkHttp). GraphQL
  is emitted as the `{query,variables}` JSON envelope string with
  `application/json`. Normalize the envelope once (in the `_Effective` body
  computation) so each target reuses its existing raw-JSON-body formatter.
- **Postman export** (`lib/core/utils/postman/postman_collection_mapper.dart`
  `_configToRequest` switch — compiler-forced) **and import** (`_parseBody`,
  cheap and symmetric): round-trip Postman's `graphql` body mode —
  `{ "mode": "graphql", "graphql": { "query": <str>, "variables": <str> } }`
  (Postman stores variables as a string).
- **Workspace git-mirror serializer**
  (`lib/core/utils/workspace/workspace_collection_serializer.dart`): add
  `graphqlVariables` to the emitted JSON and read it back, so the new field
  survives the mirror.
- **cURL import** and **OpenAPI import**: out of scope. A GraphQL `curl --data`
  command already imports cleanly as a raw JSON body.
- **History dedup** unchanged (`method + url + body`): two requests differing
  only in variables dedupe together, consistent with the existing rule and the
  `HttpRequestConfig.==` signature.

## 5. Tests + docs

Tests:
- Serializer: GraphQL build produces the correct envelope Map + forces
  `application/json`; blank variables → `{}`; invalid variables → throws
  `GraphqlVariablesException`.
- Entity ↔ model round-trip: `graphqlVariables` persists through
  `fromEntity`/`toEntity`.
- Postman: export→import round-trip for a GraphQL request preserves query +
  variables + body type.
- Code-gen: one target (cURL) emits the GraphQL JSON envelope.
- Widget: selecting GRAPHQL renders the dual pane; editing the variables pane
  dispatches `UpdateTab` with the new `graphqlVariables`.

Docs:
- Update the GitHub wiki Body types page to document the GraphQL body type
  (per the keep-the-wiki-in-sync mandate in CLAUDE.md §7).

## Verification bar (per CLAUDE.md §5)

`fvm flutter analyze` (0 issues), `fvm dart run custom_lint`,
`fvm dart run bloc_tools:bloc lint lib`, `fvm dart format` clean, and
`fvm flutter test` 100% green. For the Hive-model change, verify with a real
compile (`fvm flutter test`), not just analyze.
