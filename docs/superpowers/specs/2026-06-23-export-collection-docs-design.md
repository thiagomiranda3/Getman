# DW3 — Export collection as API docs (OpenAPI 3.x + Markdown)

**Status:** Design approved (2026-06-23) — ready for implementation planning.
**Branch:** `feat/export-collection-docs` (off `origin/master`, main repo).
**Backlog item:** DW3 — "Generate OpenAPI / Markdown docs *from* a collection"
(the reverse of the existing OpenAPI import).

## Goal

Let a user export any collection node (folder or single request) as developer
API documentation, in three formats chosen at export time:

- **OpenAPI 3.0.3 JSON** — machine-readable contract; re-imports cleanly through
  the existing importer; feeds Swagger UI / codegen.
- **OpenAPI 3.0.3 YAML** — same content, the conventional diff-friendly spec form.
- **Markdown** — human-readable API reference.

Postman paywalls collection-to-docs generation; this is an on-strategy,
local-only differentiator. It also lays groundwork for DW4 (OpenAPI drift
detection).

## Locked decisions (from brainstorming)

1. **Output:** BOTH Markdown and OpenAPI 3.x — one tree traversal feeds both.
2. **Schema depth (OpenAPI):** infer a JSON Schema from request bodies + saved
   example responses **and** embed the original payload as an `example`.
3. **OpenAPI file format:** JSON and YAML.
4. **Servers/variables:** prompt the user to pick an environment at export
   (including "None", default = active env). An env base-URL var becomes an
   OpenAPI `server`; `{{var}}` in paths become `{var}` path/server variables.
5. **UI:** ONE menu entry "EXPORT AS API DOCS…" opening a dialog (format radio +
   environment dropdown), in both the desktop node menu and the mobile sheet.

## Architecture

Pure-Dart generators (no Flutter import), mirroring how Postman export and
OpenAPI import are structured. One traversal builds a single intermediate model
(`ApiDoc`) that feeds both serializers.

```
CollectionNodeEntity (+ chosen EnvironmentEntity?)
        │  CollectionToApiDoc.build()
        ▼
     ApiDoc  ← export-specific IR (lib/core/utils/apidoc/)
        ├── OpenApiSerializer       → 3.0.3 map → JSON string | YAML string
        └── MarkdownDocSerializer   → Markdown string
        ▼
  saveTextFileWithFeedback(...)  ← generalized json_file_io
```

### Why a new `ApiDoc` IR (not import's `NormalizedApi`)

`NormalizedApi` (`lib/core/utils/openapi/normalized_api.dart`) is import-oriented
and lossy for our purposes: no operation descriptions, no per-status responses,
no schemas. Round-trip fidelity is guaranteed at the **OpenAPI-JSON level** via a
test (export → `loadSpec` → normalizer → collection ≈ original), not at the IR
level, so reusing `NormalizedApi` buys nothing and constrains us. A dedicated IR
also cleanly serves both OpenAPI and Markdown from a single traversal.

## Components

Each is independently testable with a single clear responsibility.

### `ApiDoc` model — `lib/core/utils/apidoc/api_doc.dart`
Pure value objects (Equatable, no Flutter):

- `ApiDoc { String title; String version; List<ApiServer> servers;
  List<ApiOperation> operations; List<String> warnings }`
- `ApiServer { String url; String? description; Map<String, ApiServerVar> variables }`
- `ApiServerVar { String defaultValue; String? description }`
- `ApiOperation { String method; String path; String summary; String? description;
  String? tag; List<ApiParam> queryParams; List<ApiParam> headerParams;
  List<ApiParam> pathParams; ApiBody? requestBody; List<ApiResponse> responses;
  ApiSecurity? security }`
- `ApiParam { String name; String? example; bool required; JsonSchema? schema }`
- `ApiBody { String contentType; JsonSchema? schema; Object? example }`
- `ApiResponse { int statusCode; String description; ApiBody? body }`
- `ApiSecurity { ApiSecurityKind kind; String? apiKeyName; ApiKeyLocation? location }`
  (kind ∈ none/bearer/basic/apiKey)

### `JsonSchema` + `JsonSchemaInferrer` — `lib/core/utils/apidoc/json_schema.dart`
- `JsonSchema` mirrors the subset of JSON Schema OpenAPI 3.0 uses: `type`,
  `properties`, `items`, `required`, `format`, `example?`.
- `JsonSchemaInferrer.infer(Object? json) → JsonSchema` — the reverse of the
  import-side `schema_sampler.dart`:
  - object → `type: object`, recurse into `properties`, `required` = observed keys.
  - array → `type: array`, `items` = merged schema of elements (union by best
    effort; empty array → `items` omitted / `type: object`).
  - string/bool → corresponding type; number → `number`; int → `integer`; null →
    `nullable`/omitted type.
- Used for request bodies and example response bodies. Non-JSON inputs skip
  inference (handled in `CollectionToApiDoc`).

### `CollectionToApiDoc` — `lib/core/utils/apidoc/collection_to_api_doc.dart`
`build(CollectionNodeEntity root, {EnvironmentEntity? env}) → ApiDoc`.

Traversal rules:
- **Folders** → `tag` (group) for the operations beneath them; nested folders
  flatten to a tag path (e.g. `users / admin`). The root node's name → `ApiDoc.title`.
  Collections have no version concept, so `ApiDoc.version` defaults to `"1.0.0"`
  (→ OpenAPI `info.version`, which is required).
- **Leaves** (`isFolder == false`, `config != null`) → one `ApiOperation`.
- **URL → server + path + query:**
  - Resolve `{{var}}` against `env` only to *identify* the base-URL portion; the
    base becomes (or matches) an `ApiServer`. Remaining `{{var}}` tokens in the
    path convert to OpenAPI `{var}` path variables (added to `pathParams` with
    defaults from `env`).
  - Query string parsed via `UrlQueryUtils` → `queryParams`.
  - Distinct base URLs across operations are de-duplicated into `servers`.
- **Headers** → `headerParams` (skip `Content-Type`/`Accept`/auth headers that
  are represented elsewhere).
- **Request body** by `bodyType`:
  - `raw` (JSON) → `application/json`, infer schema + example.
  - `urlencoded` → `application/x-www-form-urlencoded`, object schema of form fields.
  - `multipart` → `multipart/form-data`, object schema of form fields.
  - `binary` → `application/octet-stream`, `type: string, format: binary`.
  - `graphql` → `application/json` with `{query, variables}` example + schema.
  - `none` → no requestBody.
- **Responses** from `node.examples` (each example's `config.statusCode` +
  `responseBody` → an `ApiResponse`, schema inferred + example embedded), plus the
  leaf's last live response (`config.statusCode`/`responseBody`) if present and not
  already covered. No data → a single `200` "Successful response" stub.
- **Auth** via the inverse of `auth_mapper.dart`: `AuthConfig.type` →
  `ApiSecurity` (bearer → HTTP bearer; basic → HTTP basic; apiKey → apiKey in
  header/query using `apiKeyName`/location; none/inherit → none).
- **Secrets:** values for keys in `env.secretKeys` are masked (never emitted as
  example/server values).
- **Warnings** accumulate on `ApiDoc.warnings` (unresolvable base URL, OAuth/
  unsupported auth, method+path collisions, non-JSON raw bodies that couldn't be
  schema-inferred).

### `OpenApiSerializer` — `lib/core/utils/apidoc/openapi_serializer.dart`
`toJson(ApiDoc) → String` and `toYaml(ApiDoc) → String`.
- Builds an OpenAPI **3.0.3** map: `openapi`, `info{title,version}`, `servers`,
  `paths` (keyed by path then method; merges operations sharing a path),
  `components.securitySchemes` + per-operation `security`.
- Each `ApiBody` emits `content[contentType].schema` + `.example`.
- JSON via `JsonEncoder.withIndent('  ')`; YAML via `yaml_writer` (see Dependencies).

### `MarkdownDocSerializer` — `lib/core/utils/apidoc/markdown_doc_serializer.dart`
`toMarkdown(ApiDoc) → String`. Structure:
- `# <title>` + optional description; a servers list.
- Grouped by tag (folder); each operation:
  - `## METHOD /path`
  - description (from node `description`),
  - Path / Query / Header parameter tables (name, required, example),
  - Auth note,
  - fenced example request body,
  - Responses: per status code, description + fenced example body.

### `ExportApiDocsDialog` — `lib/features/collections/presentation/widgets/export_api_docs_dialog.dart`
- Built on `ResponsiveDialog`; uses theme extensions (no hardcoded sizes/colors).
- A format selector (OpenAPI JSON / OpenAPI YAML / Markdown) and an environment
  dropdown sourced from `EnvironmentsBloc` (plus a "No Environment" option),
  defaulting to the active env id from `SettingsBloc`.
- On confirm: builds the `ApiDoc`, serializes per chosen format, calls
  `saveTextFileWithFeedback` with the right extension + a slugged filename
  (`<slug>.openapi.json` / `.openapi.yaml` / `<slug>.md`), and shows any
  `ApiDoc.warnings` via `showAppSnackBar`.

## UI wiring

Add one entry **"EXPORT AS API DOCS…"** beside the existing Postman export in:
- `lib/features/collections/presentation/widgets/collection_node_menu.dart`
  (desktop popup — new `onSelected` case + `PopupMenuItem`).
- `lib/features/collections/presentation/widgets/node_action_sheet.dart`
  (mobile sheet — new `_Action`).

Both open `ExportApiDocsDialog` for the node (copying the existing `_exportNode`
pattern, but the dialog handles format/env + save itself).

## File IO

Generalize `lib/core/utils/json_file_io.dart`:
- Add `saveTextFileWithFeedback({required String content, required String fileName,
  required String dialogTitle, List<String> allowedExtensions})` — the existing
  picker + write + snackbar logic, content-type agnostic.
- Keep `saveJsonFileWithFeedback` as a thin delegate (back-compat for current
  callers).

## Dependencies

YAML output needs a serializer — the `yaml` package only parses. Plan: add
`yaml_writer` (pure-Dart, maintained). If we prefer zero new dependencies, the
fallback is a minimal hand-rolled emitter for the OpenAPI map subset (strings,
numbers, bools, nested maps/lists) — decided at planning time. JSON + Markdown
need no new dependencies.

## Error handling

- Empty folder (no leaves) → valid spec with empty `paths` + a warning.
- Unresolvable base URL → fall back to a concrete `scheme://host` parsed from the
  URL, else a `/` server, with a warning.
- method+path collision → merge under one path item; warn.
- Non-JSON raw body → emit as `text/plain` example without schema; warn.
- All errors are non-fatal: export always produces a file; problems surface as
  warnings, never as a thrown failure to the user.

## Testing

Unit (pure Dart, fast):
- `JsonSchemaInferrer` — object/array/nested/primitive/empty-array/mixed-array.
- `CollectionToApiDoc` — folder→tag grouping, URL split with/without env, auth
  mapping, body types, responses from examples + live response, secret masking,
  warning accumulation.
- `OpenApiSerializer` — golden JSON + YAML for a representative tree.
- `MarkdownDocSerializer` — golden Markdown.
- **Round-trip** — `OpenApiSerializer.toJson` → `loadSpec` → normalizer →
  `buildImport` ≈ original tree (method/path/auth/body parity).

Widget:
- `ExportApiDocsDialog` — format + env selection present; confirm triggers a save
  with the expected filename/extension; warnings shown.

Full gate before "done": `fvm flutter analyze`, `fvm dart run custom_lint`,
`fvm dart run bloc_tools:bloc lint lib`, `fvm dart format`, `fvm flutter test`
all clean/green.

## Wiki

Update the import/export wiki page (mandate §7) to document the new
"EXPORT AS API DOCS…" action, the three formats, and the environment prompt.

## Out of scope (this iteration)

- OpenAPI 3.1 / Swagger 2.0 output (3.0.3 only).
- OAuth2 security scheme emission (no OAuth2 in the app yet — see H3).
- DW4 drift detection (separate item; this spec only makes the export it builds on).
- `$ref`/`components.schemas` extraction (schemas inlined per operation for now).
