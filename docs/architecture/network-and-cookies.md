# Network & cookies — Dio client, redirects, mTLS, realtime, the cookie jar

> Deep-dive for the network layer (the Dio client, the manual redirect loop, mTLS, adapter rebuilds), the realtime transports (WebSocket + SSE), and the cookie jar. Loaded on demand — see the routing table in CLAUDE.md. For "where is X" lookups use docs/CODEMAP.md.

Networking is `dio` (cancel tokens wrapped by `NetworkCancelHandle`). The live client is `NetworkService` (`lib/core/network/network_service.dart`).

## Manual redirect loop

`SettingsEntity.maxRedirects` (default `5`) is stored on `BaseOptions.maxRedirects` but **enforced by `NetworkService`'s manual redirect loop**, not by Dio's own follow-redirects. Each hop is sent with `followRedirects: false` so the cookie interceptor runs per hop:

- A login 302's `Set-Cookie` is captured and re-matched on the next hop.
- 303 / POST-301/302 become bodyless GETs; 307/308 keep method + body.
- Credential headers are stripped when a redirect crosses hosts — the full
  dart:io `nonRedirectHeaders` set (`authorization`, `www-authenticate`,
  `cookie`, `cookie2`), so a hand-typed `Cookie:` row never follows a
  redirect to a different host. Jar cookies re-match per hop regardless.

## Adapter rebuilds, timeouts, mTLS

`applyConfig` (on `NetworkService`, `RealtimeService`, AND `McpService` — all three are pushed by `NetworkSettingsListener` and wired with the same adapter + cookie interceptor in DI) rebuilds the HTTP adapter **only when an adapter-relevant field changed** (`NetworkConfig.sameAdapterConfig`) and closes the replaced adapter. Timeout/redirect edits mutate `BaseOptions` in place — on all three services, BEFORE the adapter early-return (the SSE Dio keeps `receiveTimeout` unlimited: it is a long-lived stream).

WebSocket connects send the tab's enabled headers with the handshake on
dart:io platforms (`web_socket_connector_io.dart` → `IOWebSocketChannel`)
**and honor the last-applied `NetworkConfig`** — verify-SSL off, proxy, mTLS,
connect timeout — via a `customClient` HttpClient built by
`buildConfiguredHttpClient` (`dio_adapter_config_io.dart`), so a wss://
endpoint behaves like its https:// counterpart. `RealtimeService` seeds that
config from the Dio `buildSseDio` built (DI constructs the Dio; the settings
listener only fires on changes) and refreshes it on every `applyConfig`.
The web stub ignores headers and config (browser API limitation). Closing a request tab
tears down its live WebSocket/SSE/MCP session via
`TabCloseTeardownListener` (home feature) → `RealtimeTabsClosed` /
`McpTabsClosed` — without it a closed tab's socket stayed open (and
streaming into bloc state) until app exit.

mTLS is the client-certificate trio `clientCertPath` / `clientKeyPath` / `clientCertPassphrase` on `SettingsEntity`/`NetworkConfig`. Cert config is **plain-string data** — never a `dart:io` `SecurityContext`, which is built only inside `dio_adapter_config_io.dart` (guarded with a try/catch fallback; the web stub ignores it). A cert that fails to load (moved file, wrong passphrase) falls back to a cert-less client but is **never silent**: the load is eager (at configure time, not first request), it records the top-level `lastCertificateError` (re-exported through `dio_adapter_config.dart`; always null on web), and `configureHttpAdapter`/`buildConfiguredHttpClient` accept an optional `onCertificateError` callback — UI wiring for the signal is still open. Proxy config lives on `NetworkConfig` and is applied the same way.

All network settings reach the live Dio via `NetworkSettingsListener.listenWhen` (`lib/features/settings/presentation/widgets/network_settings_listener.dart`), which calls `NetworkService.applyConfig` **and** `RealtimeService.applyConfig` on settings changes.

## Realtime — WebSocket + SSE

WebSocket rides on `web_socket_channel`; SSE rides on a `dio` response stream via `SseParser`. Both are driven by `RealtimeBloc` over `RealtimeService` (`lib/core/network/realtime_service.dart`). This is bloc-over-service by design — no full domain/data split.

- `RealtimeService` takes an optional `webSocketFactory` (defaults to `connectWebSocketChannel`, signature `(Uri, headers, NetworkConfig)`) so WS teardown and config plumbing are unit-testable with a fake channel.
- The SSE Dio is built via `RealtimeService.buildSseDio(NetworkConfig, [cookieInterceptor])` — same verify-SSL / proxy / mTLS adapter, connect timeout, and cookie jar as the main client (receive timeout stays unlimited — long-lived stream).
- SSE surfaces non-2xx connects as an `HTTP <code>` error frame (it never silently streams an error body).
- Binary WS frames log as a `[binary frame · N bytes]` placeholder.
- WS connects honor verify-SSL / proxy / mTLS / connect timeout on dart:io via `IOWebSocketChannel.connect(customClient:, connectTimeout:)` — see the adapter section above.

`RealtimeBloc` holds one connection + frame log per tab; `realtime_panel.dart` is the live WS/SSE view (the composer is WS-only).

## Cookies — the jar

A Hive-backed cookie jar: `CookieStore` (abstract) / `InMemoryCookieStore` (runtime impl: matching, expiry, ordering) + `CookieInterceptor` on the live Dio. Durable backing is `features/cookies/data/hive_cookie_persistence.dart` (the `cookies` box, `StoredCookieModel` typeId 6, keyed by `domain|path|name` with one put/delete per cookie). `StoredCookieModel.hostOnly` (`HiveField(7)`, default `false`) is the RFC 6265 host-only flag — an absent Domain attribute means exact-host match.

`CookieStore` exposes `all()` + `remove(cookie)` for the manager UI (`cookies/presentation/widgets/cookie_manager_dialog.dart`, reached via Settings → COOKIES → **MANAGE**, guarded by `ConfirmDialog` for the destructive actions); otherwise the feature is infra-only (no domain/data split).

### Round-trip

1. `cookie_interceptor.dart` — attaches the `Cookie` header on request, captures `Set-Cookie` on response (once per hop, thanks to the manual redirect loop above).
2. `cookie_store.dart` / `in_memory_cookie_store.dart` — the abstract jar + runtime impl.
3. `hive_cookie_persistence.dart` — flushes each mutation to the `cookies` box.
4. `cookie_manager_dialog.dart` — the manager view over `CookieStore.all()` / `remove()`.
