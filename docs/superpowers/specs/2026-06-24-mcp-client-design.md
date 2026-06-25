# MCP Client Support — Design

**Date:** 2026-06-24
**Status:** Approved (design); implementation pending
**Branch:** `feat/mcp-client`

## Summary

Add **MCP (Model Context Protocol) client** support to Getman, analogous to
Postman's "MCP request": Getman acts as an MCP host/client that connects to an
external MCP server, lists its **tools**, and invokes a tool with
user-supplied arguments, showing the result.

Scope is deliberately tight for v1:

- **Direction:** client only (consume external MCP servers). Exposing Getman
  collections *as* an MCP server is out of scope.
- **Transport:** HTTP only — **Streamable HTTP** (JSON-RPC 2.0 over POST, with
  `application/json` or `text/event-stream` responses). No stdio / local
  process spawning, so the feature is web-safe on every platform.
- **Capabilities:** **tools only** (initialize → list tools → call tool).
  Resources and prompts are deferred.

## Why this approach

Getman already models non-HTTP protocols as a `RequestKind` that swaps the
response panel (`http` / `webSocket` / `sse`). The `realtime` feature is a
"bloc-over-service" feature with **no full domain/data split**, driven by
`RealtimeBloc` over `RealtimeService`, surfaced by `ResponseArea` switching on
`tab.config.kind`. MCP slots into exactly this seam as a new
`RequestKind.mcp` — reusing the tab system, persistence, URL bar, env
resolution, and panel-switching with no new tab/workspace machinery.

A standalone "MCP workspace" screen was considered and rejected: it would
duplicate tab/panel/env-resolution plumbing and diverge from the established
WebSocket/SSE precedent for no real benefit.

## Architecture

### 1. Protocol & transport — `core/network/`

- Add `mcp(3)` to the `RequestKind` enum (`core/network/request_kind.dart`).
  It persists as the **existing** int discriminator (config Hive model field
  14, default `0 = http`). **No new Hive typeId, no migration** — existing
  records keep reading as `http`, and `RequestKind.fromWire` already falls back
  to `http` for unknown values.

- New `McpService` (`core/network/mcp_service.dart`) — pure `dio`, web-safe,
  with the `Dio` injectable for tests (mirrors `RealtimeService`). Speaks
  **JSON-RPC 2.0 over Streamable HTTP**:
  - `connect(url, headers)` → POST `initialize`; capture the returned
    `Mcp-Session-Id` and negotiated `MCP-Protocol-Version`; send the
    `notifications/initialized` notification; return an `McpSession`.
  - `listTools(session)` → POST `tools/list`.
  - `callTool(session, name, args)` → POST `tools/call`.
  - Handles **both** response content-types per the spec: `application/json`
    (single JSON-RPC response) and `text/event-stream` (SSE-framed response,
    reusing the existing `SseParser`). Subsequent requests carry the session id
    + protocol-version headers.
  - In-flight calls are cancellable (a cancel token on the active request).

- **Out of scope for v1:** the standalone GET SSE stream for server-initiated
  messages, resources, prompts, and subscriptions.

### 2. Domain entities (pure Dart + `equatable`, `copyWith` where mutated)

- `McpSession { sessionId, protocolVersion, serverName, serverVersion }`
- `McpTool { name, description, inputSchema }` — `inputSchema` is the raw JSON
  Schema `Map` (not modeled further in v1).
- `McpToolResult { isError, List<text content block> }` — v1 renders text
  content blocks; non-text blocks are shown as their raw JSON.

### 3. State — `McpBloc` (bloc-over-service, no domain/data split)

Follows `RealtimeBloc` exactly. State carries:

- connection status: `disconnected` / `connecting` / `connected` / `error`
- server info (from `McpSession`)
- `tools` (from `tools/list`)
- `selectedTool`
- `lastResult`
- `sessionLog` — the JSON-RPC traffic (request/response/notification) for
  debugging.

Events are scoped by `tabId` (matching `RealtimeBloc` and the identity-based
`TabsEvent` convention). `McpBloc` is registered app-wide in the `main.dart`
`MultiBlocProvider`, like `RealtimeBloc`.

### 4. UI

- `RequestKindMethodSelector` — add an **MCP** dropdown item alongside
  HTTP/WebSocket/SSE.
- For MCP kind, the **URL bar** holds the MCP **endpoint URL**. Auth reuses the
  existing **Headers tab** (e.g. `Authorization: Bearer …`) — no new auth UI.
  Method, PARAMS, and BODY are hidden (as they are for WebSocket/SSE).
- New `McpPanel` (`features/mcp/presentation/widgets/mcp_panel.dart`), shown by
  `ResponseArea` when `kind == mcp`:
  - a **Connect** bar (uses the tab's URL + headers),
  - a **tool list** (from `tools/list`),
  - a **selected-tool detail**: the input JSON Schema as **read-only
    reference** + a `JsonCodeEditor` (built via `createJsonCodeController()`)
    for the arguments object, + a **Call** button,
  - a **result view** + a collapsible **session log**.
- **Env resolution:** the endpoint URL, header values, and the JSON arguments
  all run through `ActiveEnvironmentHelper.variablesFor(...)` + the resolver, so
  `{{var}}` (and dynamic `{{$...}}`) work everywhere — matching how
  `SendRequest` resolves.

### 5. Boundaries

- MCP traffic does **not** write to HTTP history or response time-travel — it's
  a separate protocol, exactly like realtime. Tools, results, and the session
  log are **live-only** (not persisted). Only the endpoint URL + `kind` +
  headers persist, via the existing tab config Hive model.
- Theming: the `McpPanel` reads all sizes/colors/weights/shapes from the
  `context.app*` extensions — no hardcoded values, per the project mandate.

### 6. Feature layout

```
lib/features/mcp/
  domain/entities/    # McpSession, McpTool, McpToolResult (pure Dart)
  presentation/
    bloc/             # mcp_bloc.dart, mcp_event.dart, mcp_state.dart
    widgets/          # mcp_panel.dart
lib/core/network/
  mcp_service.dart    # JSON-RPC over Streamable HTTP (dio), web-safe
  request_kind.dart   # + mcp(3)
```

(Bloc-over-service by design — no `data/` layer, matching `realtime`.)

## Testing

- `McpService` unit tests with an **injected mock dio adapter**: the
  `initialize` handshake (session-id + protocol-version capture), `application/
  json` **and** `text/event-stream` response shapes, `tools/list` parsing, and
  `tools/call` success + `isError` result + JSON-RPC error responses.
- `McpBloc` `bloc_test`: connect → list → call happy path, plus connect-error
  and call-error paths.
- `McpPanel` widget smoke test + an overflow guard (per the project's
  per-panel test convention).

## Docs

- New wiki page "MCP requests" in `Getman.wiki.git` + a `_Sidebar.md` entry,
  kept verbatim-accurate to UI labels (per the "keep the wiki in sync"
  mandate).

## Deliberately deferred (post-v1)

- Resources and prompts.
- Server-initiated SSE notifications / subscriptions (the standalone GET
  stream).
- A generated argument **form** from JSON Schema (v1 uses a raw JSON args
  editor seeded by the schema reference).
- stdio / local-process transport (would need the same web-platform gating as
  the auto-updater).
- Exposing Getman collections *as* an MCP server.
