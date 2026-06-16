# OpenAPI / Swagger Importer — Design

> Status: approved (brainstorming) — 2026-06-15
> Author: Thiago Miranda + Claude
> Feature 1 of 5 in the "make people want to leave Postman" track. The other
> four (global fuzzy search, response diff, quick env switcher + var hover-peek,
> bulk header/param editing) are deferred to their own spec → plan cycles.

## 1. Motivation

Getman's wedge against Postman is that it is fast, local-only, private,
git-friendly, and free. The remaining adoption friction is "I'd have to rebuild
everything." The single highest-leverage *pull* feature is an importer that
turns an existing API specification into a ready-to-use collection in seconds.

This spec covers importing **OpenAPI 3.x and Swagger 2.0** specifications. It
leans into Getman's environment feature by auto-creating one environment per
declared server, so a freshly imported API is immediately switchable across
dev/staging/prod.

## 2. Scope

**In scope (v1):**
- OpenAPI 3.0 / 3.1 and Swagger 2.0.
- JSON **and** YAML input.
- Three input methods: pick a file, paste raw spec text, or fetch a remote spec
  by URL.
- A selectable preview: a checkbox tree of folders → requests plus a summary of
  the environments that will be created, so the user can deselect noise before
  committing.
- Output: one new collection root + one or more environments (domain entities
  the existing blocs already own).

**Out of scope (deferred):**
- HAR import (different mapping; its own later pass — the architecture leaves
  room via a shared intermediate model + builder).
- External `$ref` resolution (refs into other files or URLs). Internal refs are
  resolved; external refs are surfaced as per-item preview warnings and left
  unresolved.
- Full JSON-Schema validation of the spec.
- OAuth2 credential wiring. `oauth2` / `openIdConnect` security schemes are
  recognized but the auth is left `none` with a preview note until the deferred
  H3 (OAuth2) feature lands.

## 3. Architecture & layering

Mirrors the existing Postman-import structure (`core/utils/postman/` +
`core/utils/json_file_io.dart`). This is import/utility plumbing, so it follows
the Postman precedent of **no domain/data split** — its output is domain
*entities*, which the blocs already own.

New pure-Dart logic under `lib/core/utils/openapi/`:

- `spec_loader.dart` — take bytes/string, sniff JSON vs YAML, decode to a
  `Map<String, dynamic>`. (Requires a new `yaml` dependency — see §5.)
- `spec_normalizer.dart` — resolve internal `$ref`s and collapse both OpenAPI
  3.x and Swagger 2.0 into **one intermediate model** (`NormalizedApi`). This is
  the seam that lets a future HAR mapper target the same builder.
- `collection_builder.dart` — `NormalizedApi` → `CollectionNodeEntity` subtree +
  `List<EnvironmentEntity>`.

### Intermediate model (`NormalizedApi`)

A version-agnostic, pure-Dart shape so the builder never branches on spec
version:

- `title` (from `info.title`).
- `servers`: list of `{ url, description, variables: Map<String,String> }`.
- `operations`: list of `{ method, path, name, tags, description,
  queryParams, headerParams, pathParams, body, security }`.
- `securitySchemes`: map of scheme name → normalized scheme
  (`{ kind: bearer|basic|apiKeyHeader|apiKeyQuery|oauth2|unsupported, ... }`).

### Bloc coordination

An import produces both a collection root **and** environments, touching two
blocs. Following the established "widget coordinates two blocs" pattern
(`EnvironmentsDialog._deleteEnvironment`, `ChainingWriteBackListener`), the
import dialog dispatches:

- `AddEnvironment(env)` per created environment on `EnvironmentsBloc` (carrying
  the full entity so the generated id is known at the call site, per the
  existing `AddEnvironment` contract), then
- the collection-root mutation on `CollectionsBloc`.

No bloc→bloc coupling.

## 4. Parsing & normalization

- **Version sniff:** `openapi:` key → 3.x branch; `swagger: "2.0"` → 2.0 branch.
  The two shapes differ in: base URL (`servers[]` vs `host` + `basePath` +
  `schemes[]`), schema location (`components/schemas` vs `definitions`), and body
  (`requestBody` vs body/formData `parameters`). The normalizer hides all of
  this from the builder.
- **`$ref`:** resolve internal refs (`#/components/...` for 3.x,
  `#/definitions/...` for 2.0) during normalization, with cycle protection.
  External refs are left as-is and flagged.

## 5. Dependencies

- **Add `package:yaml`** (dart.dev-maintained). OpenAPI specs are predominantly
  YAML, so JSON-only would be a poor migration UX. This is the only new
  dependency; flagged explicitly per the surgical-dependency mandate.

## 6. Mapping rules

- **Servers → environments:** one environment per declared server, each with a
  `{{baseUrl}}` variable plus any OpenAPI server-variables as env vars. Every
  request URL is templated as `{{baseUrl}}/path`. For Swagger 2.0 the base URL
  is synthesized from `schemes[0] + host + basePath`. Environments are named
  after the server `description` (fallback: the host, then `"server N"`).
- **Folders:** group operations by their **first `tag`**; operations with no tag
  group by their **first path segment**. `info.title` names the collection root
  (fallback `"Imported API"`).
- **Request name:** `summary` → else `operationId` → else `"METHOD /path"`.
- **Path params:** `/users/{id}` → `/users/{{id}}` (Getman-native tokens — they
  render highlighted and editable). An unset `{{id}}` is sent verbatim per the
  resolver's "unknown variable = leave as-is" rule, i.e. visibly broken rather
  than silently wrong.
- **Query / header params:** mapped to request params / headers using the
  param's `example`/`default` if present, else empty.
- **Request body:** prefer `application/json` content → a raw JSON body, using
  the spec's `example`/`examples` when present, otherwise a **minimal stub
  generated from the schema** (recursively: `example` → `default` → first `enum`
  → type zero-value). `application/x-www-form-urlencoded` and
  `multipart/form-data` map to Getman's urlencoded / multipart body types +
  `formFields`. The `Content-Type` header is set to match.
- **Auth (`securitySchemes`):** map the *type/shape* only —
  `http bearer` → bearer, `http basic` → basic, `apiKey` (in header) → apikey.
  The secret **value** is left blank, but a matching **secret env var**
  placeholder (the M11 secret-vars feature) is created in each environment so the
  user fills it once per environment. `oauth2` / `openIdConnect` → auth left
  `none` + a preview note (wires up when H3 OAuth2 lands).
  - **Implementation-time check:** confirm that send-time environment
    substitution reaches auth credential fields. If it does, pre-fill the
    credential as a `{{secretVar}}` reference; if it does not, set only the auth
    *type* and leave the value blank for manual entry.

## 7. Import flow & UI

A `ResponsiveDialog`-based flow, themed entirely through `context.app*`
(no hardcoded sizes/colors/radii), in three steps:

1. **Source** — a segmented selector: File / Paste / URL. File uses the existing
   `file_picker` plumbing; URL fetches via `NetworkService`; Paste takes raw
   text. Parse errors surface inline (not a crash).
2. **Preview & select** — a checkbox tree of folders → requests (default: all
   checked) plus a summary line of environments to be created (e.g. "Creates 3
   environments: dev, staging, prod") and per-item warnings (e.g. an unresolved
   external `$ref`). Deselecting a folder deselects its children.
3. **Commit** — builds the subtree from the selected items only, dispatches to
   `EnvironmentsBloc` then `CollectionsBloc`, and confirms via
   `showAppSnackBar`.

**Entry point:** an "Import → OpenAPI / Swagger" affordance alongside the
existing Postman import. (Exact menu location confirmed during planning.)

## 8. Testing strategy

- **Normalizer unit tests:** an OpenAPI 3.x fixture and a Swagger 2.0 fixture →
  assert the produced `NormalizedApi`, then the produced `CollectionNodeEntity`
  tree + environments. Cover: internal `$ref` resolution (incl. a cycle),
  body-stub generation from a schema, the path-param `{id}` → `{{id}}` rewrite,
  and auth → secret-env mapping.
- **Loader tests:** the same logical spec as both JSON and YAML produces an
  identical `NormalizedApi`.
- **Widget test:** the preview dialog — toggle a folder off and assert only the
  selected items are dispatched on import.

All gates from `CLAUDE.md` §5 apply: `fvm flutter analyze`,
`fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`,
`fvm dart format`, and `fvm flutter test` all clean before "done".

## 9. Wiki

Per the "keep the wiki in sync" mandate, this adds a user-facing capability and
must be documented in the `Getman.wiki.git` repo (a new "Importing APIs" page or
an addition to the existing import page, plus a `_Sidebar.md` entry) as part of
the implementation work.

## 10. Open questions resolved during brainstorming

- Formats: OpenAPI 3.x + Swagger 2.0 (HAR deferred). ✔
- Input: file + paste + URL fetch. ✔
- Servers: auto-create one environment per server. ✔
- UX: preview + selective import. ✔
- `package:yaml` dependency: approved. ✔
- Folder grouping by first tag (fallback first path segment): approved. ✔
- Schema-based body stub generation: approved. ✔
