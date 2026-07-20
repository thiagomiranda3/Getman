# MCP — Model Context Protocol client

> Deep-dive for the MCP feature (a Model Context Protocol client: connect to an MCP server, list its tools, call them). Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md.

## What it does

MCP is a fourth **request kind** alongside HTTP / WebSocket / SSE (`RequestKind.mcp`, wire value 3, in `lib/core/network/request_kind.dart`). An MCP request connects to a server over **Streamable HTTP** (JSON-RPC 2.0), runs the `initialize` handshake, lists the server's advertised tools, and calls them with a JSON arguments object. It mirrors the realtime feature's shape: bloc-over-service, one live connection per tab, no full domain/data split.

## Transport (`lib/core/network/mcp_service.dart`)

`McpService` opens connections over Streamable HTTP using **pure `dio`** so it stays web-safe (no `dart:io`; the `Dio` is injectable for tests). `McpConnection` (abstract) exposes `session` / `listTools()` / `callTool()` / `close()`; `_HttpMcpConnection` is the impl.

- **Handshake:** `connect()` performs `initialize` (negotiating `kMcpProtocolVersion = '2025-06-18'` and sending `clientInfo` `Getman/1.0`), captures the `Mcp-Session-Id` response header into the `McpSession`, then sends the `notifications/initialized` notification.
- **Requests:** each call is a discrete JSON-RPC POST (`initialize` / `tools/list` / `tools/call`) carrying the session id + protocol-version headers. The response may arrive as a plain `application/json` body **or** a `text/event-stream` body (parsed via `SseParser`); either way the message whose `id` matches the request is picked out.
- **Errors:** `validateStatus` is always true (an MCP server may answer a JSON-RPC error at HTTP 200 or with 4xx/5xx), and a JSON-RPC `error` or an empty/unparseable body becomes an `McpException` (with the optional numeric code).
- **`close()` is a v1 no-op** — each call is a discrete POST, so there's nothing to release; HTTP-DELETE session termination is deferred.

## Entities (`lib/features/mcp/domain/`)

- `entities/mcp_session.dart` — `McpSession`: the transport `sessionId` (from the header, supplied separately from the JSON-RPC body), negotiated `protocolVersion`, and the server's self-reported `serverName` / `serverVersion`. `fromInitializeResult` builds it; missing fields default to empty strings.
- `entities/mcp_tool.dart` — `McpTool`: `name` / `description` / `inputSchema` (the raw JSON Schema, kept verbatim; not modeled further in v1).
- `entities/mcp_tool_result.dart` — `McpToolResult`: `isError`, `textBlocks` (the `type: "text"` content items, the common case), and `rawBlocks` (every content item verbatim, so non-text blocks — images, resources — can still be shown as raw JSON).
- `mcp_argument_resolver.dart` — `resolveMcpArgValue` recursively resolves `{{var}}` / `{{$dynamic}}` tokens inside the tool-call arguments JSON, walking `Map`/`List` structurally and substituting **only String leaves** (keeps the document structurally valid even when a value contains quotes/braces). Delegates each leaf to `EnvironmentResolver.resolve`. Used by `McpPanel` at CALL time.

## Bloc (`lib/features/mcp/presentation/bloc/`)

`McpBloc` owns one `McpConnection` per tab (`Map<String, McpConnection>`) plus the derived per-tab state. It mirrors `RealtimeBloc`'s teardown discipline: a connection is closed on disconnect, on reconnect for the same tab, and on bloc `close()`.

- **Events** (`mcp_event.dart`): `McpConnectRequested(tabId, url, headers)`, `McpDisconnectRequested(tabId)`, `McpToolSelected(tabId, toolName)`, `McpToolCallRequested(tabId, toolName, arguments)`.
- **State** (`mcp_state.dart`): `McpState` holds a per-tab `McpTabSession` map. A session carries `status` (`McpConnectionStatus`: disconnected / connecting / connected / error), the `McpSession`, the advertised `tools`, the `selectedTool`, the last `McpToolResult`, a `calling` flag, an `errorMessage`, and a debug `log` of traffic. On connect the bloc lists tools and logs the server label; failures are logged via `dart:developer`'s `log(name: 'McpBloc')` and surfaced in `status: error`.

## Widgets (`lib/features/mcp/presentation/widgets/`)

- `mcp_connect_button.dart` — the CONNECT / DISCONNECT button for an MCP request tab, driven by the tab's connection status. It resolves `{{var}}` in the endpoint URL + headers **at press time**, reading the live config from `TabsBloc` (the URL bar doesn't rebuild on URL edits, so a snapshot would be stale).
- `mcp_panel.dart` — the post-connect UI: tool picker, JSON arguments editor (with `{{var}}` autocomplete), CALL button, result view, and the session log. Tool/result text mutations are always scheduled via `addPostFrameCallback` (never inline in `build()`) so controller updates that `notifyListeners` never fire mid-build.

## Wiring

Bloc-over-service by design. `injection_container.dart` registers `McpService` and `McpBloc` as lazy singletons; `McpBloc` is provided in the root `MultiBlocProvider`. The connect button and panel render in the request area (`url_bar.dart` + `response_area.dart`), gated on `RequestKind.mcp`.
