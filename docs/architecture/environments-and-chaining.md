# Environments — variables, resolution and script commits

> Deep-dive for environments (`{{var}}` variable sets + resolution) and confirmed JavaScript variable patches. Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md.

## Environments

Flat list of `EnvironmentEntity(id, name, variables: Map<String, String>)` — no folders/tree. Stored in the `environments` Hive box as `EnvironmentModel` (typeId 4). The list is **sorted case-insensitively by name** — in the data source on read AND in the bloc on add/update/import — because box keys are UUIDs (post key-migration), so Hive's key order is meaningless; the sort keeps restart order identical to in-session order.

The currently-active environment id is **not** owned by `EnvironmentsBloc`; it lives on `SettingsEntity.activeEnvironmentId` (per-user preference, persisted with settings). `null` means "No Environment" — a synthetic always-available option in the selector UI.

### Variable syntax

`{{name}}` — the resolver in `lib/core/utils/environment_resolver.dart` accepts any non-empty, non-brace name (trimmed): `\$?[^{}]+?` with optional whitespace inside the braces (`{{ name }}`, `{{api key}}`, `{{token@prod}}` are all valid — the env editor, Postman import, and autocomplete all allow such names, so the grammar must resolve whatever they produce). `UrlQueryUtils._varToken` mirrors this grammar exactly — a narrower class there percent-mangles wide tokens on every params-row edit. Unknown variable names are **left verbatim**, not blanked — silent empty substitution is worse than a visibly broken URL.

Resolution is **recursive to a fixpoint** (Postman-compatible, depth-capped at 10 to survive reference cycles): a substituted value may itself contain `{{var}}` — `baseUrl = https://{{host}}/api` is a common imported-environment shape. A nested UNKNOWN name still ships verbatim.

### Dynamic variables

A leading `$` marks a built-in resolved at send time without an environment — `{{$guid}}`/`{{$randomUUID}}`, `{{$timestamp}}` (unix seconds), `{{$isoTimestamp}}` (UTC ISO-8601), `{{$randomInt}}` (0–1000). Each occurrence resolves independently; an env var of the same name still wins. `EnvironmentResolver.isDynamic(name)` is the source of truth (the URL highlighter colors dynamic vars as resolved).

### Substitution scope

`TabsRepositoryImpl.sendRequest` resolves against URL, query-param keys AND values, header values, and body (header *keys* only stay unresolved — the warning chip flags those) before dispatching via `networkService.request`. Param keys resolve so send matches code-gen (which resolves the whole URL) and the urlencoded/multipart form-field names. **History records the templated (unresolved) config** — the user should be able to re-send a history entry under a different environment, matching Postman/Insomnia. Never resolve env vars in `SendRequestUseCase._record`.

### Resolution plumbing

The `SendRequest` event carries `tabId` plus `Map<String, String> envVars`. Dispatchers that need real substitution — the SEND button in `UrlBar`, the `SendRequestIntent` shortcut in `MainScreen` — compute it via `ActiveEnvironmentHelper.variablesFor(environments, activeEnvironmentId)` read from `EnvironmentsBloc` + `SettingsBloc`. Omitting `envVars` sends `{{var}}` placeholders to the network verbatim.

### Request-body template assistance

`BodyCodeEditor` offers the same layered variable names and dynamic variables
at the caret when typing `{{`, or explicitly with Option+Space on macOS /
Ctrl+Space elsewhere. `TabVariableContextBuilder` supplies collection ancestry
and the active environment; environment values override inherited collection
values. Completion inserts the `{{name}}` token, leaving resolution to send
time. Secret previews are masked. Learning JSON field names stores only those
names and counts, never variable values or request body values.

JSON body diagnostics validate **template syntax**, independently of variable
lookup. Both `{"name":"{{user}}"}` and `{"count":{{count}}}` are accepted as
templates even when the variables are currently undefined. The validator masks
complete unquoted placeholders with a padded JSON `null` sentinel, preserving
UTF-16 source offsets for error navigation; quoted strings retain ordinary JSON
escape validation. An unquoted placeholder cannot stand in for a property name
or arbitrary JSON punctuation. The advisory does not resolve values, test their
types, or guarantee valid JSON after substitution. Undefined variables remain
the unresolved-variable chip's concern, and neither advisory blocks sending.

### URL highlighting

`VariableHighlightController` (in `lib/core/ui/widgets/`, a `TextEditingController` subclass) overrides `buildTextSpan` to color each `{{var}}` token. Colors are theme-dependent so the constructor takes none — the owning widget pushes variable + color updates via `updateVariables` / `updateColors` in `didChangeDependencies`; both methods `notifyListeners()` only when the underlying value actually changed (via `MapEquality` / `==`) so we don't thrash rebuilds. Until colors arrive, tokens render unhighlighted. Palette: `AppPalette.variableResolved` / `variableUnresolved` (never hardcode green/red literals).

### Unresolved-variable warning chip (E3)

`UnresolvedVarsChip` (left of SEND in `UrlBar`) is purely advisory — it never blocks sending. `UnresolvedVariableCollector.collect` is **wire-accurate**: it scans only what send transmits (URL, ENABLED header values, raw/graphql body, form fields for urlencoded/multipart, auth — parked params and disabled header rows never ship, so they're skipped), and any `{{var}}` in an enabled header KEY is flagged even when defined (send never resolves header keys, so it ships as a literal header name). Tokens that resolve to nothing are checked against the same `LayeredVariableContext` (env layered over inherited collection variables, via `TabVariableContextBuilder`) every other variable-aware field uses — no separate resolution path. The scan is memoized in the widget's `State` on the `(config, LayeredVariableContext)` pair so a keystroke that changes neither input doesn't re-run the regex. Clicking the chip lists up to `UnresolvedVarsChip.maxListedNames` (10) names plus an "Open environment editor…" action that reopens `EnvironmentsDialog`.

### Secret variables

`EnvironmentEntity.secretKeys` (a `Set<String>` of variable names; `EnvironmentModel` stores it as a `List<String>` at `HiveField(3)`). `KeyValueListEditor` takes an optional `secretKeys` + `onSecretKeysChanged` — when non-null, each row shows a lock toggle and secret rows obscure their value with a reveal toggle. Params/headers pass neither, so their behavior is unchanged. The env editor prunes stale secret flags on rename/delete (intersect with the live keys). Postman export masks secret values (empty value, `type: 'secret'`); **send-time resolution is unaffected** (secrets resolve like any other variable). The C5 bug-report bundle (`BugReportComposer`, docs/architecture/tabs-and-panels.md) applies the same masking to both env and collection-scoped secret keys before resolving `{{var}}` into the copied markdown.

### Confirmed script variable patches and external edits

`EnvironmentsRepository.applyVariablePatch(environmentId, ScriptPatch)` merges
sets and unsets against the current stored environment in the repository's
single mutation queue. Put, editor update, import, replace, delete and script
patches share that queue. Admission order determines the winner for the same
key; independent keys survive. A missing or deleted target raises
`PersistenceFailure` and is never recreated. The returned Future completes only
after the storage write; failures propagate to the script orchestrator, while
later writes can still proceed. Sets preserve existing secret flags, new keys
are public, and unsets prune flags.

Editor updates carry the prior entity via `UpdateEnvironment.previous` and
`updateEnvironment(previous:)`. Only fields changed from that snapshot merge
into the live record, so a rename or ordinary variable edit cannot overwrite
an unrelated capture. Imports admit incoming records without replaying a stale
whole-list UI snapshot; explicit `saveEnvironments` retains replace semantics.

`watchEnvironments()` starts with the sorted current list, follows Hive changes,
and suppresses equal snapshots. `WatchEnvironmentsUseCase` feeds the optional
`EnvironmentsBloc` watcher; the BLoC cancels its subscription on close. The
editor reconciles external snapshots with local edits awaiting their echo,
including variable order and secret toggles; clean name fields refresh on an
external rename, while unfinished local name edits remain intact.

### Add / delete gotchas

- **`AddEnvironment` carries the full `EnvironmentEntity`,** not a name: bloc state updates are asynchronous, so an id generated inside the handler would be unknowable at the call site (the dialog needs it to select the new row).
- **Deleting the active environment** is handled at the widget layer in `EnvironmentsDialog._deleteEnvironment`: if the just-deleted id matches `SettingsEntity.activeEnvironmentId`, dispatch `UpdateActiveEnvironmentId(null)` on `SettingsBloc` after the delete. BLoC-to-BLoC coupling is intentionally avoided — the coordinator is the widget with both blocs in scope.

## Script captures

Scripts replace the former Rules feature. `gm.environment.set/unset` proposes
patches to the environment captured at SEND. ExecuteRequestUseCase confirms them
only after a successful stage, using the serialized repository described below.
There is no cross-BLoC write-back listener. See [scripting.md](scripting.md).
