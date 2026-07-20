# Environments & chaining — variables, resolution, assertions, extraction

> Deep-dive for environments (`{{var}}` variable sets + resolution) and chaining (no-code post-response assertions + variable extraction). Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md.

## Environments

Flat list of `EnvironmentEntity(id, name, variables: Map<String, String>)` — no folders/tree. Stored in the `environments` Hive box as `EnvironmentModel` (typeId 4). The list is **sorted case-insensitively by name** — in the data source on read AND in the bloc on add/update/import — because box keys are UUIDs (post key-migration), so Hive's key order is meaningless; the sort keeps restart order identical to in-session order.

The currently-active environment id is **not** owned by `EnvironmentsBloc`; it lives on `SettingsEntity.activeEnvironmentId` (per-user preference, persisted with settings). `null` means "No Environment" — a synthetic always-available option in the selector UI.

### Variable syntax

`{{name}}` — the resolver in `lib/core/utils/environment_resolver.dart` accepts any non-empty, non-brace name (trimmed): `\$?[^{}]+?` with optional whitespace inside the braces (`{{ name }}`, `{{api key}}`, `{{token@prod}}` are all valid — the env editor, Postman import, and autocomplete all allow such names, so the grammar must resolve whatever they produce). Unknown variable names are **left verbatim**, not blanked — silent empty substitution is worse than a visibly broken URL.

### Dynamic variables

A leading `$` marks a built-in resolved at send time without an environment — `{{$guid}}`/`{{$randomUUID}}`, `{{$timestamp}}` (unix seconds), `{{$isoTimestamp}}` (UTC ISO-8601), `{{$randomInt}}` (0–1000). Each occurrence resolves independently; an env var of the same name still wins. `EnvironmentResolver.isDynamic(name)` is the source of truth (the URL highlighter colors dynamic vars as resolved).

### Substitution scope

`TabsRepositoryImpl.sendRequest` resolves against URL, query-param values, header values, and body (not header/param *keys*) before dispatching via `networkService.request`. **History records the templated (unresolved) config** — the user should be able to re-send a history entry under a different environment, matching Postman/Insomnia. Never resolve env vars in `SendRequestUseCase._record`.

### Resolution plumbing

The `SendRequest` event carries `tabId` plus `Map<String, String> envVars`. Dispatchers that need real substitution — the SEND button in `UrlBar`, the `SendRequestIntent` shortcut in `MainScreen` — compute it via `ActiveEnvironmentHelper.variablesFor(environments, activeEnvironmentId)` read from `EnvironmentsBloc` + `SettingsBloc`. Omitting `envVars` sends `{{var}}` placeholders to the network verbatim.

### URL highlighting

`VariableHighlightController` (in `lib/core/ui/widgets/`, a `TextEditingController` subclass) overrides `buildTextSpan` to color each `{{var}}` token. Colors are theme-dependent so the constructor takes none — the owning widget pushes variable + color updates via `updateVariables` / `updateColors` in `didChangeDependencies`; both methods `notifyListeners()` only when the underlying value actually changed (via `MapEquality` / `==`) so we don't thrash rebuilds. Until colors arrive, tokens render unhighlighted. Palette: `AppPalette.variableResolved` / `variableUnresolved` (never hardcode green/red literals).

### Secret variables

`EnvironmentEntity.secretKeys` (a `Set<String>` of variable names; `EnvironmentModel` stores it as a `List<String>` at `HiveField(3)`). `KeyValueListEditor` takes an optional `secretKeys` + `onSecretKeysChanged` — when non-null, each row shows a lock toggle and secret rows obscure their value with a reveal toggle. Params/headers pass neither, so their behavior is unchanged. The env editor prunes stale secret flags on rename/delete (intersect with the live keys). Postman export masks secret values (empty value, `type: 'secret'`); **send-time resolution is unaffected** (secrets resolve like any other variable).

### Add / delete gotchas

- **`AddEnvironment` carries the full `EnvironmentEntity`,** not a name: bloc state updates are asynchronous, so an id generated inside the handler would be unknowable at the call site (the dialog needs it to select the new row).
- **Deleting the active environment** is handled at the widget layer in `EnvironmentsDialog._deleteEnvironment`: if the just-deleted id matches `SettingsEntity.activeEnvironmentId`, dispatch `UpdateActiveEnvironmentId(null)` on `SettingsBloc` after the delete. BLoC-to-BLoC coupling is intentionally avoided — the coordinator is the widget with both blocs in scope.

## Chaining — post-response assertions + extraction

No-code post-response **assertions** + variable **extraction**. Pure engines live in `chaining/domain/logic/`: `assertion_engine.dart`, `extraction_engine.dart`, `rules_runner.dart`. Rules are stored per request-config id (`RequestRulesModel`, typeId 9, box `requestRules`) and run after a send.

Flow:

1. A response arrives in `TabsBloc` — it loads rules via `GetRequestRulesUseCase`.
2. `rules_runner.dart` decodes the body once and runs `assertion_engine.dart` + `extraction_engine.dart`.
3. Captured values are written back to the active environment by `ChainingWriteBackListener` (a widget-layer coordinator, never bloc→bloc).
4. `EnvironmentsBloc.MergeEnvironmentVariables` persists the captures.

The response TREE mode's **Extract to `{{var}}`** action closes the loop from the other direction: it dispatches `AddExtractionRule(configId, rule)` to the global `RulesBloc`.
