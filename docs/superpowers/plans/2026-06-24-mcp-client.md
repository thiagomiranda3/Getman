# MCP Client Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Model Context Protocol (MCP) *client* to Getman — a new request kind that connects to an external MCP server over Streamable HTTP, lists its tools, and invokes a tool with user-supplied JSON arguments, showing the result.

**Architecture:** MCP slots into the existing `RequestKind` seam (the same mechanism that drives WebSocket/SSE). A new `RequestKind.mcp` makes a tab speak MCP; `ResponseArea` swaps in an `McpPanel`; a connect button in the URL bar opens the connection. The protocol lives in a pure-`dio`, web-safe `McpService` returning an `McpConnection`; an `McpBloc` (bloc-over-service, no domain/data split — exactly like `RealtimeBloc`) owns one connection per tab. JSON-RPC 2.0 messages are POSTed and responses parsed from either `application/json` or `text/event-stream` (reusing `SseParser`).

**Tech Stack:** Flutter, `flutter_bloc`, `dio` (Streamable HTTP), `equatable`, `re_editor` (JSON args editor), `mocktail` + `bloc_test` (tests). Invoke Flutter as `fvm flutter ...`.

## Global Constraints

- Flutter SDK is pinned via `.fvmrc` — always invoke as `fvm flutter ...`, never plain `flutter`.
- Imports are `package:getman/...` everywhere (no relative imports; `directives_ordering` + `always_use_package_imports`).
- Domain layer is pure Dart + `equatable` only — zero imports from `data/` or Flutter UI.
- BLoCs must not import `package:flutter/foundation.dart`/material (bloc_lint `avoid_flutter_imports`); BLoC logging uses `dart:developer`'s `log(msg, name: 'McpBloc')`, never `debugPrint`/`print`.
- Widgets never call `sl<T>()`/`GetIt` (custom_lint `avoid_get_it_in_widgets`); reach services/blocs via `BlocProvider`/`RepositoryProvider`. GetIt is referenced only in `lib/core/di/` + `main.dart`.
- No hardcoded sizes/colors/radii/weights in widgets — read from `context.appLayout`/`appPalette`/`appShape`/`appTypography`/`appDecoration`. No `Colors.black/white/red` literals outside `lib/core/theme/` (custom_lint `avoid_hardcoded_brand_colors`).
- All states/events are `Equatable`; every entity is immutable.
- **Verification bar (all must be clean before "done"):** `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0 issues), `fvm dart run bloc_tools:bloc lint lib` (0 issues), `fvm dart format lib test` clean, and `fvm flutter test` 100% green. These are independent passes.
- No new Hive typeId / no migration: `RequestKind` persists as the existing int discriminator (config model field 14); a new enum value reads back via `RequestKind.fromWire`.

---

## File Structure

**Create:**
- `lib/features/mcp/domain/entities/mcp_session.dart` — `McpSession` value object + `fromInitializeResult`.
- `lib/features/mcp/domain/entities/mcp_tool.dart` — `McpTool` value object + `fromJson`.
- `lib/features/mcp/domain/entities/mcp_tool_result.dart` — `McpToolResult` value object + `fromJson`.
- `lib/core/network/mcp_service.dart` — `McpService`, `McpConnection`, `McpException`, protocol constants. Pure dio, web-safe.
- `lib/features/mcp/presentation/bloc/mcp_event.dart` — `McpEvent` hierarchy.
- `lib/features/mcp/presentation/bloc/mcp_state.dart` — `McpState` + `McpTabSession`.
- `lib/features/mcp/presentation/bloc/mcp_bloc.dart` — `McpBloc`.
- `lib/features/mcp/presentation/widgets/mcp_connect_button.dart` — URL-bar CONNECT/DISCONNECT button.
- `lib/features/mcp/presentation/widgets/mcp_panel.dart` — the post-connect UI (tool list, args editor, result, log).
- Tests mirroring each (paths in tasks).

**Modify:**
- `lib/core/network/request_kind.dart` — add `mcp(3)`.
- `lib/features/tabs/presentation/widgets/request_kind_method_selector.dart` — add an "MCP" dropdown item.
- `lib/features/tabs/presentation/widgets/url_bar.dart` — show `McpConnectButton` for MCP kind.
- `lib/features/tabs/presentation/widgets/response_area.dart` — render `McpPanel` for MCP kind.
- `lib/core/di/injection_container.dart` — register `McpService` + `McpBloc`.
- `lib/main.dart` — provide `McpBloc`.

---

### Task 1: Add `RequestKind.mcp`

**Files:**
- Modify: `lib/core/network/request_kind.dart`
- Test: `test/core/network/request_kind_test.dart`

**Interfaces:**
- Produces: `RequestKind.mcp` (wire `3`); `RequestKind.fromWire(3) == RequestKind.mcp`; unknown wires still fall back to `RequestKind.http`.

- [ ] **Step 1: Write the failing test**

Create `test/core/network/request_kind_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/request_kind.dart';

void main() {
  group('RequestKind', () {
    test('mcp has wire value 3', () {
      expect(RequestKind.mcp.wire, 3);
    });

    test('fromWire(3) resolves to mcp', () {
      expect(RequestKind.fromWire(3), RequestKind.mcp);
    });

    test('unknown wire falls back to http', () {
      expect(RequestKind.fromWire(99), RequestKind.http);
      expect(RequestKind.fromWire(null), RequestKind.http);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/network/request_kind_test.dart`
Expected: FAIL — `mcp` is not a member of `RequestKind`.

- [ ] **Step 3: Add the enum value**

In `lib/core/network/request_kind.dart`, extend the enum and the doc comment:

```dart
/// The protocol a request speaks. Orthogonal to the HTTP method — a WebSocket,
/// SSE, or MCP request has no method. Persisted as an int discriminator (Hive
/// field 14 on the config model, default 0 = http) so existing records read as
/// HTTP.
enum RequestKind {
  http(0),
  webSocket(1),
  sse(2),
  mcp(3)
  ;
```

(Leave `fromWire` unchanged — it already iterates `values`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/network/request_kind_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/network/request_kind.dart test/core/network/request_kind_test.dart
git commit -m "feat(mcp): add RequestKind.mcp protocol discriminator"
```

---

### Task 2: MCP domain entities

**Files:**
- Create: `lib/features/mcp/domain/entities/mcp_session.dart`
- Create: `lib/features/mcp/domain/entities/mcp_tool.dart`
- Create: `lib/features/mcp/domain/entities/mcp_tool_result.dart`
- Test: `test/features/mcp/domain/entities/mcp_entities_test.dart`

**Interfaces:**
- Produces:
  - `McpSession({required String sessionId, required String protocolVersion, required String serverName, required String serverVersion})`; `McpSession.fromInitializeResult(Map<String, dynamic> result, {String? sessionId})`.
  - `McpTool({required String name, required String description, required Map<String, dynamic> inputSchema})`; `McpTool.fromJson(Map<String, dynamic> json)`.
  - `McpToolResult({required bool isError, required List<String> textBlocks, required List<Map<String, dynamic>> rawBlocks})`; `McpToolResult.fromJson(Map<String, dynamic> result)`.

- [ ] **Step 1: Write the failing test**

Create `test/features/mcp/domain/entities/mcp_entities_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/mcp/domain/entities/mcp_session.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';

void main() {
  group('McpSession.fromInitializeResult', () {
    test('reads server info + protocol version, sessionId from header', () {
      final s = McpSession.fromInitializeResult(
        const {
          'protocolVersion': '2025-06-18',
          'serverInfo': {'name': 'demo', 'version': '1.2.3'},
        },
        sessionId: 'abc-123',
      );
      expect(s.sessionId, 'abc-123');
      expect(s.protocolVersion, '2025-06-18');
      expect(s.serverName, 'demo');
      expect(s.serverVersion, '1.2.3');
    });

    test('tolerates missing fields with safe defaults', () {
      final s = McpSession.fromInitializeResult(const {});
      expect(s.sessionId, '');
      expect(s.serverName, '');
      expect(s.protocolVersion, '');
    });
  });

  group('McpTool.fromJson', () {
    test('parses name, description, and raw input schema', () {
      final t = McpTool.fromJson(const {
        'name': 'add',
        'description': 'Adds numbers',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'a': {'type': 'number'},
          },
        },
      });
      expect(t.name, 'add');
      expect(t.description, 'Adds numbers');
      expect(t.inputSchema['type'], 'object');
    });

    test('defaults description to empty and schema to empty map', () {
      final t = McpTool.fromJson(const {'name': 'noop'});
      expect(t.description, '');
      expect(t.inputSchema, isEmpty);
    });
  });

  group('McpToolResult.fromJson', () {
    test('collects text blocks and isError flag', () {
      final r = McpToolResult.fromJson(const {
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'boom'},
          {'type': 'text', 'text': 'second'},
        ],
      });
      expect(r.isError, isTrue);
      expect(r.textBlocks, ['boom', 'second']);
    });

    test('keeps non-text blocks as raw maps and defaults isError to false', () {
      final r = McpToolResult.fromJson(const {
        'content': [
          {'type': 'image', 'data': 'xxx', 'mimeType': 'image/png'},
        ],
      });
      expect(r.isError, isFalse);
      expect(r.textBlocks, isEmpty);
      expect(r.rawBlocks.single['type'], 'image');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/mcp/domain/entities/mcp_entities_test.dart`
Expected: FAIL — entity files don't exist.

- [ ] **Step 3: Create the entities**

Create `lib/features/mcp/domain/entities/mcp_session.dart`:

```dart
import 'package:equatable/equatable.dart';

/// An established MCP session: the negotiated protocol version, the server's
/// self-reported identity, and the transport session id (from the
/// `Mcp-Session-Id` response header). Pure data — no transport concerns.
class McpSession extends Equatable {
  const McpSession({
    required this.sessionId,
    required this.protocolVersion,
    required this.serverName,
    required this.serverVersion,
  });

  /// Builds a session from an `initialize` JSON-RPC result, with the transport
  /// [sessionId] supplied separately (it rides on the HTTP response header, not
  /// the JSON-RPC body). Missing fields default to empty strings.
  factory McpSession.fromInitializeResult(
    Map<String, dynamic> result, {
    String? sessionId,
  }) {
    final info = (result['serverInfo'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return McpSession(
      sessionId: sessionId ?? '',
      protocolVersion: (result['protocolVersion'] as String?) ?? '',
      serverName: (info['name'] as String?) ?? '',
      serverVersion: (info['version'] as String?) ?? '',
    );
  }

  final String sessionId;
  final String protocolVersion;
  final String serverName;
  final String serverVersion;

  @override
  List<Object?> get props =>
      [sessionId, protocolVersion, serverName, serverVersion];
}
```

Create `lib/features/mcp/domain/entities/mcp_tool.dart`:

```dart
import 'package:equatable/equatable.dart';

/// A tool advertised by an MCP server via `tools/list`. [inputSchema] is the
/// tool's raw JSON Schema (kept verbatim; not modeled further in v1).
class McpTool extends Equatable {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) => McpTool(
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        inputSchema:
            (json['inputSchema'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{},
      );

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  @override
  List<Object?> get props => [name, description, inputSchema];
}
```

Create `lib/features/mcp/domain/entities/mcp_tool_result.dart`:

```dart
import 'package:equatable/equatable.dart';

/// The result of a `tools/call`. [textBlocks] are the `type: "text"` content
/// items (the common case); [rawBlocks] preserves every content item verbatim
/// so non-text blocks (images, resources) can still be shown as raw JSON.
class McpToolResult extends Equatable {
  const McpToolResult({
    required this.isError,
    required this.textBlocks,
    required this.rawBlocks,
  });

  factory McpToolResult.fromJson(Map<String, dynamic> result) {
    final content = (result['content'] as List?) ?? const [];
    final raw = content
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final text = raw
        .where((m) => m['type'] == 'text')
        .map((m) => (m['text'] as String?) ?? '')
        .toList();
    return McpToolResult(
      isError: (result['isError'] as bool?) ?? false,
      textBlocks: text,
      rawBlocks: raw,
    );
  }

  final bool isError;
  final List<String> textBlocks;
  final List<Map<String, dynamic>> rawBlocks;

  @override
  List<Object?> get props => [isError, textBlocks, rawBlocks];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/mcp/domain/entities/mcp_entities_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/mcp/domain/entities test/features/mcp/domain
git commit -m "feat(mcp): add MCP session/tool/result domain entities"
```

---

### Task 3: `McpService` — JSON-RPC over Streamable HTTP

**Files:**
- Create: `lib/core/network/mcp_service.dart`
- Test: `test/core/network/mcp_service_test.dart`

**Interfaces:**
- Consumes: `McpSession`, `McpTool`, `McpToolResult` (Task 2).
- Produces:
  - `class McpService { McpService({Dio? dio}); Future<McpConnection> connect(String url, {Map<String, String> headers = const {}}); }`
  - `abstract class McpConnection { McpSession get session; Future<List<McpTool>> listTools(); Future<McpToolResult> callTool(String name, Map<String, dynamic> arguments, {CancelToken? cancelToken}); Future<void> close(); }`
  - `class McpException implements Exception { McpException(this.message, {this.code}); final String message; final int? code; }`
  - `const String kMcpProtocolVersion = '2025-06-18';`

**Background — Streamable HTTP transport (what the code below implements):**
- One endpoint URL. Every JSON-RPC message is a `POST` with `Content-Type: application/json` and `Accept: application/json, text/event-stream`.
- `initialize` request → result carries `protocolVersion` + `serverInfo`; the HTTP response carries an `Mcp-Session-Id` header. After it, POST a `notifications/initialized` notification (no `id`, server replies `202` with empty body).
- Subsequent requests echo `Mcp-Session-Id` and `MCP-Protocol-Version` headers.
- A response may come back as a single `application/json` object **or** as `text/event-stream` (the JSON-RPC message arrives inside SSE `data:` frames). Both are read by draining the byte stream and decoding.

- [ ] **Step 1: Write the failing test**

Create `test/core/network/mcp_service_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

ResponseBody _jsonBody(Map<String, dynamic> json, {int status = 200}) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
  return ResponseBody(
    Stream<Uint8List>.value(bytes),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

ResponseBody _sseBody(Map<String, dynamic> json, {int status = 200}) {
  final frame = 'event: message\ndata: ${jsonEncode(json)}\n\n';
  final bytes = Uint8List.fromList(utf8.encode(frame));
  return ResponseBody(
    Stream<Uint8List>.value(bytes),
    status,
    headers: {
      Headers.contentTypeHeader: ['text/event-stream'],
    },
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  late _MockDio dio;
  late McpService service;

  setUp(() {
    dio = _MockDio();
    service = McpService(dio: dio);
  });

  // Queues a sequence of POST responses; the Nth POST returns responses[N].
  void stubPosts(List<Response<ResponseBody>> responses) {
    var i = 0;
    when(
      () => dio.post<ResponseBody>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => responses[i++]);
  }

  Response<ResponseBody> resp(ResponseBody body, {Map<String, List<String>>? headers}) =>
      Response<ResponseBody>(
        data: body,
        statusCode: body.statusCode,
        headers: Headers.fromMap(headers ?? {}),
        requestOptions: RequestOptions(path: '/'),
      );

  test('connect performs the initialize handshake and captures session id',
      () async {
    stubPosts([
      resp(
        _jsonBody({
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'protocolVersion': '2025-06-18',
            'serverInfo': {'name': 'demo', 'version': '9.9'},
          },
        }),
        headers: {
          'mcp-session-id': ['sess-1'],
        },
      ),
      resp(_jsonBody({'jsonrpc': '2.0'}), headers: {}), // initialized notif (202-ish)
    ]);

    final conn = await service.connect('https://mcp.dev/');
    expect(conn.session.sessionId, 'sess-1');
    expect(conn.session.serverName, 'demo');
    // initialize POST + initialized notification POST = 2 calls.
    verify(
      () => dio.post<ResponseBody>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(2);
  });

  test('listTools parses tools from an application/json response', () async {
    stubPosts([
      resp(_jsonBody({
        'jsonrpc': '2.0',
        'id': 2,
        'result': {
          'tools': [
            {'name': 'add', 'description': 'Add', 'inputSchema': {'type': 'object'}},
          ],
        },
      })),
    ]);

    final conn = _ConnectedFixture.build(service, dio);
    final tools = await conn.listTools();
    expect(tools.single.name, 'add');
  });

  test('callTool parses a result delivered over text/event-stream', () async {
    stubPosts([
      resp(_sseBody({
        'jsonrpc': '2.0',
        'id': 3,
        'result': {
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
          'isError': false,
        },
      })),
    ]);

    final conn = _ConnectedFixture.build(service, dio);
    final result = await conn.callTool('echo', const {'msg': 'hi'});
    expect(result.textBlocks, ['hello']);
    expect(result.isError, isFalse);
  });

  test('a JSON-RPC error response throws McpException', () async {
    stubPosts([
      resp(_jsonBody({
        'jsonrpc': '2.0',
        'id': 2,
        'error': {'code': -32601, 'message': 'Method not found'},
      })),
    ]);

    final conn = _ConnectedFixture.build(service, dio);
    await expectLater(
      conn.listTools(),
      throwsA(
        isA<McpException>()
            .having((e) => e.code, 'code', -32601)
            .having((e) => e.message, 'message', contains('Method not found')),
      ),
    );
  });
}

/// Builds a connection without re-stubbing the initialize handshake: connect()
/// is exercised in its own test, so here we drive listTools/callTool directly
/// by stubbing the initialize POST first, then the operation POST.
class _ConnectedFixture {
  static McpConnection build(McpService service, _MockDio dio) {
    throw UnimplementedError();
  }
}
```

> Note: `_ConnectedFixture` is a placeholder so the file compiles for the
> first failing run. Replace it in Step 3b once `McpConnection` exists.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/network/mcp_service_test.dart`
Expected: FAIL — `mcp_service.dart` doesn't exist.

- [ ] **Step 3: Create the service**

Create `lib/core/network/mcp_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:getman/core/network/sse_parser.dart';
import 'package:getman/features/mcp/domain/entities/mcp_session.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';

/// MCP protocol version Getman negotiates in `initialize`.
const String kMcpProtocolVersion = '2025-06-18';

/// Client identity sent in `initialize.params.clientInfo`.
const String _kClientName = 'Getman';
const String _kClientVersion = '1.0';

/// A JSON-RPC error returned by an MCP server, or a transport-level failure.
class McpException implements Exception {
  McpException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() =>
      'McpException(${code == null ? '' : '$code: '}$message)';
}

/// A live MCP session over Streamable HTTP. One per connected tab.
abstract class McpConnection {
  McpSession get session;
  Future<List<McpTool>> listTools();
  Future<McpToolResult> callTool(
    String name,
    Map<String, dynamic> arguments, {
    CancelToken? cancelToken,
  });
  Future<void> close();
}

/// Opens MCP connections over Streamable HTTP (JSON-RPC 2.0). Pure `dio`, so it
/// is web-safe (no `dart:io`). The [Dio] is injectable for tests.
class McpService {
  McpService({Dio? dio}) : _dio = dio ?? _buildDio();
  final Dio _dio;

  static Dio _buildDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          // MCP servers may answer with a JSON-RPC error at HTTP 200, or with
          // 4xx/5xx — read every status so we can surface the body either way.
          validateStatus: (_) => true,
          responseType: ResponseType.stream,
        ),
      );

  /// Performs the `initialize` handshake, captures the `Mcp-Session-Id`
  /// header, sends the `notifications/initialized` notification, and returns a
  /// ready connection.
  Future<McpConnection> connect(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final conn = _HttpMcpConnection(_dio, url, headers);
    await conn._initialize();
    return conn;
  }
}

class _HttpMcpConnection implements McpConnection {
  _HttpMcpConnection(this._dio, this._url, this._headers);
  final Dio _dio;
  final String _url;
  final Map<String, String> _headers;

  McpSession _session = const McpSession(
    sessionId: '',
    protocolVersion: '',
    serverName: '',
    serverVersion: '',
  );
  int _nextId = 0;

  @override
  McpSession get session => _session;

  Future<void> _initialize() async {
    final (result, respHeaders) = await _request('initialize', {
      'protocolVersion': kMcpProtocolVersion,
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': _kClientName, 'version': _kClientVersion},
    });
    _session = McpSession.fromInitializeResult(
      result,
      sessionId: respHeaders.value('mcp-session-id'),
    );
    await _notify('notifications/initialized', const {});
  }

  @override
  Future<List<McpTool>> listTools() async {
    final (result, _) = await _request('tools/list', const {});
    final tools = (result['tools'] as List?) ?? const [];
    return tools
        .whereType<Map>()
        .map((t) => McpTool.fromJson(t.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<McpToolResult> callTool(
    String name,
    Map<String, dynamic> arguments, {
    CancelToken? cancelToken,
  }) async {
    final (result, _) = await _request(
      'tools/call',
      {'name': name, 'arguments': arguments},
      cancelToken: cancelToken,
    );
    return McpToolResult.fromJson(result);
  }

  @override
  Future<void> close() async {
    // v1: nothing to release (each call is a discrete POST). Session
    // termination via HTTP DELETE is deferred.
  }

  Map<String, dynamic> _envelope(String method, Map<String, dynamic> params) =>
      {'jsonrpc': '2.0', 'id': ++_nextId, 'method': method, 'params': params};

  Options _options() => Options(
        responseType: ResponseType.stream,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          if (_session.sessionId.isNotEmpty)
            'Mcp-Session-Id': _session.sessionId,
          if (_session.protocolVersion.isNotEmpty)
            'MCP-Protocol-Version': _session.protocolVersion,
        },
      );

  /// Sends a JSON-RPC request and returns `(result, responseHeaders)`. Throws
  /// [McpException] on a JSON-RPC `error` or a missing/invalid result.
  Future<(Map<String, dynamic>, Headers)> _request(
    String method,
    Map<String, dynamic> params, {
    CancelToken? cancelToken,
  }) async {
    final envelope = _envelope(method, params);
    final response = await _dio.post<ResponseBody>(
      _url,
      data: jsonEncode(envelope),
      options: _options(),
      cancelToken: cancelToken,
    );
    final message = await _readMessage(response, envelope['id'] as int);
    if (message == null) {
      throw McpException('Empty response from server for $method');
    }
    final error = message['error'];
    if (error is Map) {
      throw McpException(
        (error['message'] as String?) ?? 'Unknown error',
        code: error['code'] as int?,
      );
    }
    final result = (message['result'] as Map?)?.cast<String, dynamic>();
    if (result == null) {
      throw McpException('Malformed JSON-RPC response for $method');
    }
    return (result, response.headers);
  }

  /// Fire-and-forget JSON-RPC notification (no id, no response body expected).
  Future<void> _notify(String method, Map<String, dynamic> params) async {
    final response = await _dio.post<ResponseBody>(
      _url,
      data: jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
      options: _options(),
      cancelToken: null,
    );
    // Drain so the connection is released; the body is ignored (202 Accepted).
    await _drain(response.data);
  }

  /// Reads a JSON-RPC message from either an `application/json` body or a
  /// `text/event-stream` body, returning the message whose `id` matches
  /// [expectedId] (or the first message that has no id match for json).
  Future<Map<String, dynamic>?> _readMessage(
    Response<ResponseBody> response,
    int expectedId,
  ) async {
    final body = response.data;
    if (body == null) return null;
    final text = await _drain(body);
    final contentType =
        response.headers.value(Headers.contentTypeHeader) ?? '';

    if (contentType.contains('text/event-stream')) {
      final parser = SseParser();
      final events = [...parser.addChunk(text), ...parser.flush()];
      for (final raw in events) {
        final decoded = _tryDecode(raw);
        if (decoded != null && decoded['id'] == expectedId) return decoded;
      }
      // Fall back to the last decodable event if no id matched.
      for (final raw in events.reversed) {
        final decoded = _tryDecode(raw);
        if (decoded != null) return decoded;
      }
      return null;
    }

    return _tryDecode(text);
  }

  Map<String, dynamic>? _tryDecode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Drains a streamed [ResponseBody] to a UTF-8 string.
  Future<String> _drain(ResponseBody? body) async {
    if (body == null) return '';
    final bytes = <int>[];
    await for (final Uint8List chunk in body.stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
```

- [ ] **Step 3b: Replace the test's `_ConnectedFixture` with a real helper**

The connection is only reachable through `connect()`, which runs the
initialize handshake first. Update the test to build a connected fixture by
stubbing initialize then the operation. Replace the `_ConnectedFixture` class
**and** update the three tests that use it (`listTools`, `callTool`, error) to
queue the initialize responses ahead of the operation response. Concretely,
replace the class with a helper that returns a `Future<McpConnection>`:

```dart
// Replaces `_ConnectedFixture`. Queues: initialize result, initialized notif
// ack, then the caller-supplied operation responses.
Future<McpConnection> _connected(
  McpService service,
  void Function(List<Response<ResponseBody>>) stub,
  List<Response<ResponseBody>> Function(Response<ResponseBody> Function(ResponseBody, {Map<String, List<String>>? headers}) resp, ResponseBody Function(Map<String, dynamic>, {int status}) jsonBody) ops,
) async {
  throw UnimplementedError();
}
```

This signature is awkward; instead, prefer restructuring each of the three
tests to call `stubPosts([...])` with the initialize + notif responses
**prepended** to the operation response, then `final conn = await service.connect('https://mcp.dev/');` before the operation. For example, the `listTools` test body becomes:

```dart
test('listTools parses tools from an application/json response', () async {
  stubPosts([
    // initialize
    resp(
      _jsonBody({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'protocolVersion': '2025-06-18',
          'serverInfo': {'name': 'demo', 'version': '1'},
        },
      }),
      headers: {'mcp-session-id': ['s1']},
    ),
    // initialized notification ack
    resp(_jsonBody({'jsonrpc': '2.0'})),
    // tools/list
    resp(_jsonBody({
      'jsonrpc': '2.0',
      'id': 2,
      'result': {
        'tools': [
          {'name': 'add', 'description': 'Add', 'inputSchema': {'type': 'object'}},
        ],
      },
    })),
  ]);

  final conn = await service.connect('https://mcp.dev/');
  final tools = await conn.listTools();
  expect(tools.single.name, 'add');
});
```

Apply the same prepend-initialize pattern to the `callTool` (SSE) and error
tests, then delete the `_ConnectedFixture` class. (The standalone `connect`
test already stands alone — leave it.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/core/network/mcp_service_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/network/mcp_service.dart test/core/network/mcp_service_test.dart
git commit -m "feat(mcp): McpService — JSON-RPC over Streamable HTTP (json + SSE)"
```

---

### Task 4: `McpBloc` + events + state

**Files:**
- Create: `lib/features/mcp/presentation/bloc/mcp_event.dart`
- Create: `lib/features/mcp/presentation/bloc/mcp_state.dart`
- Create: `lib/features/mcp/presentation/bloc/mcp_bloc.dart`
- Test: `test/features/mcp/presentation/bloc/mcp_bloc_test.dart`

**Interfaces:**
- Consumes: `McpService`, `McpConnection`, `McpException` (Task 3); `McpTool`, `McpToolResult` (Task 2).
- Produces:
  - Events: `McpConnectRequested({required String tabId, required String url, Map<String, String> headers})`, `McpDisconnectRequested(String tabId)`, `McpToolSelected({required String tabId, required String toolName})`, `McpToolCallRequested({required String tabId, required String toolName, required Map<String, dynamic> arguments})`.
  - State: `McpState({Map<String, McpTabSession> sessions})` with `McpTabSession sessionFor(String tabId)`.
  - `McpConnectionStatus { disconnected, connecting, connected, error }`.
  - `McpTabSession({McpConnectionStatus status, McpSession? session, List<McpTool> tools, String? selectedTool, McpToolResult? lastResult, bool calling, String? errorMessage, List<String> log})` with `copyWith`.

- [ ] **Step 1: Write the failing test**

Create `test/features/mcp/presentation/bloc/mcp_bloc_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/features/mcp/domain/entities/mcp_session.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements McpService {}

class _MockConnection extends Mock implements McpConnection {}

void main() {
  late _MockService service;
  late _MockConnection conn;

  const tool = McpTool(name: 'add', description: 'Add', inputSchema: {});
  const session = McpSession(
    sessionId: 's1',
    protocolVersion: '2025-06-18',
    serverName: 'demo',
    serverVersion: '1',
  );

  setUp(() {
    service = _MockService();
    conn = _MockConnection();
    when(() => conn.session).thenReturn(session);
    when(() => conn.listTools()).thenAnswer((_) async => [tool]);
    when(() => conn.close()).thenAnswer((_) async {});
  });

  blocTest<McpBloc, McpState>(
    'connect → connected with tools',
    build: () {
      when(() => service.connect(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => conn);
      return McpBloc(service: service);
    },
    act: (b) => b.add(
      const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'),
    ),
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(s.status, McpConnectionStatus.connected);
      expect(s.tools.single.name, 'add');
      expect(s.session?.serverName, 'demo');
    },
  );

  blocTest<McpBloc, McpState>(
    'connect failure → error status with message',
    build: () {
      when(() => service.connect(any(), headers: any(named: 'headers')))
          .thenThrow(McpException('nope', code: -1));
      return McpBloc(service: service);
    },
    act: (b) => b.add(
      const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'),
    ),
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(s.status, McpConnectionStatus.error);
      expect(s.errorMessage, contains('nope'));
    },
  );

  blocTest<McpBloc, McpState>(
    'call tool → lastResult populated',
    build: () {
      when(() => service.connect(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => conn);
      when(
        () => conn.callTool(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer(
        (_) async => const McpToolResult(
          isError: false,
          textBlocks: ['42'],
          rawBlocks: [],
        ),
      );
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(
        const McpToolCallRequested(
          tabId: 't1',
          toolName: 'add',
          arguments: {'a': 1, 'b': 2},
        ),
      );
    },
    verify: (b) {
      expect(b.state.sessionFor('t1').lastResult?.textBlocks, ['42']);
    },
  );

  blocTest<McpBloc, McpState>(
    'disconnect closes the connection and resets status',
    build: () {
      when(() => service.connect(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => conn);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(const McpDisconnectRequested('t1'));
    },
    verify: (b) {
      expect(b.state.sessionFor('t1').status, McpConnectionStatus.disconnected);
      verify(() => conn.close()).called(1);
    },
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/mcp/presentation/bloc/mcp_bloc_test.dart`
Expected: FAIL — bloc/event/state files don't exist.

- [ ] **Step 3: Create event, state, and bloc**

Create `lib/features/mcp/presentation/bloc/mcp_event.dart`:

```dart
import 'package:equatable/equatable.dart';

abstract class McpEvent extends Equatable {
  const McpEvent();
  @override
  List<Object?> get props => [];
}

class McpConnectRequested extends McpEvent {
  const McpConnectRequested({
    required this.tabId,
    required this.url,
    this.headers = const {},
  });
  final String tabId;
  final String url;
  final Map<String, String> headers;
  @override
  List<Object?> get props => [tabId, url, headers];
}

class McpDisconnectRequested extends McpEvent {
  const McpDisconnectRequested(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

class McpToolSelected extends McpEvent {
  const McpToolSelected({required this.tabId, required this.toolName});
  final String tabId;
  final String toolName;
  @override
  List<Object?> get props => [tabId, toolName];
}

class McpToolCallRequested extends McpEvent {
  const McpToolCallRequested({
    required this.tabId,
    required this.toolName,
    required this.arguments,
  });
  final String tabId;
  final String toolName;
  final Map<String, dynamic> arguments;
  @override
  List<Object?> get props => [tabId, toolName, arguments];
}
```

Create `lib/features/mcp/presentation/bloc/mcp_state.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:getman/features/mcp/domain/entities/mcp_session.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';

enum McpConnectionStatus { disconnected, connecting, connected, error }

/// The MCP state for one tab: connection status, server session, advertised
/// tools, the selected tool, the last call result, and a debug log of traffic.
class McpTabSession extends Equatable {
  const McpTabSession({
    this.status = McpConnectionStatus.disconnected,
    this.session,
    this.tools = const [],
    this.selectedTool,
    this.lastResult,
    this.calling = false,
    this.errorMessage,
    this.log = const [],
  });

  final McpConnectionStatus status;
  final McpSession? session;
  final List<McpTool> tools;
  final String? selectedTool;
  final McpToolResult? lastResult;
  final bool calling;
  final String? errorMessage;
  final List<String> log;

  McpTabSession copyWith({
    McpConnectionStatus? status,
    McpSession? session,
    List<McpTool>? tools,
    String? selectedTool,
    McpToolResult? lastResult,
    bool? calling,
    String? errorMessage,
    List<String>? log,
  }) =>
      McpTabSession(
        status: status ?? this.status,
        session: session ?? this.session,
        tools: tools ?? this.tools,
        selectedTool: selectedTool ?? this.selectedTool,
        lastResult: lastResult ?? this.lastResult,
        calling: calling ?? this.calling,
        errorMessage: errorMessage,
        log: log ?? this.log,
      );

  @override
  List<Object?> get props => [
        status,
        session,
        tools,
        selectedTool,
        lastResult,
        calling,
        errorMessage,
        log,
      ];
}

class McpState extends Equatable {
  const McpState({this.sessions = const {}});
  final Map<String, McpTabSession> sessions;

  McpTabSession sessionFor(String tabId) =>
      sessions[tabId] ?? const McpTabSession();

  McpState withSession(String tabId, McpTabSession session) =>
      McpState(sessions: {...sessions, tabId: session});

  @override
  List<Object?> get props => [sessions];
}
```

> Note: `copyWith` sets `errorMessage` directly (not `?? this.errorMessage`) so
> a successful step can clear a prior error by passing `errorMessage: null`.

Create `lib/features/mcp/presentation/bloc/mcp_bloc.dart`:

```dart
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';

/// Owns one live [McpConnection] per tab and its derived state. Mirrors
/// RealtimeBloc's teardown discipline: a connection is closed on disconnect, on
/// reconnect for the same tab, and on bloc close.
class McpBloc extends Bloc<McpEvent, McpState> {
  McpBloc({required McpService service})
      : _service = service,
        super(const McpState()) {
    on<McpConnectRequested>(_onConnect);
    on<McpDisconnectRequested>(_onDisconnect);
    on<McpToolSelected>(_onToolSelected);
    on<McpToolCallRequested>(_onCallTool);
  }

  final McpService _service;
  final Map<String, McpConnection> _connections = {};

  Future<void> _onConnect(
    McpConnectRequested event,
    Emitter<McpState> emit,
  ) async {
    await _teardown(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        const McpTabSession(status: McpConnectionStatus.connecting),
      ),
    );
    try {
      final conn = await _service.connect(event.url, headers: event.headers);
      _connections[event.tabId] = conn;
      final tools = await conn.listTools();
      emit(
        state.withSession(
          event.tabId,
          McpTabSession(
            status: McpConnectionStatus.connected,
            session: conn.session,
            tools: tools,
            log: [
              'Connected to ${conn.session.serverName} '
                  '(${conn.session.protocolVersion})',
              'Listed ${tools.length} tool(s)',
            ],
          ),
        ),
      );
    } on Object catch (e) {
      log('MCP connect failed: $e', name: 'McpBloc');
      await _teardown(event.tabId);
      emit(
        state.withSession(
          event.tabId,
          McpTabSession(
            status: McpConnectionStatus.error,
            errorMessage: e.toString(),
            log: ['Connect failed: $e'],
          ),
        ),
      );
    }
  }

  Future<void> _onDisconnect(
    McpDisconnectRequested event,
    Emitter<McpState> emit,
  ) async {
    await _teardown(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        const McpTabSession(),
      ),
    );
  }

  void _onToolSelected(McpToolSelected event, Emitter<McpState> emit) {
    final s = state.sessionFor(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        s.copyWith(selectedTool: event.toolName, lastResult: null),
      ),
    );
  }

  Future<void> _onCallTool(
    McpToolCallRequested event,
    Emitter<McpState> emit,
  ) async {
    final conn = _connections[event.tabId];
    if (conn == null) return;
    final base = state.sessionFor(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        base.copyWith(calling: true, selectedTool: event.toolName),
      ),
    );
    try {
      final result = await conn.callTool(event.toolName, event.arguments);
      final after = state.sessionFor(event.tabId);
      emit(
        state.withSession(
          event.tabId,
          after.copyWith(
            calling: false,
            lastResult: result,
            log: [...after.log, 'Called ${event.toolName}'],
          ),
        ),
      );
    } on Object catch (e) {
      log('MCP tool call failed: $e', name: 'McpBloc');
      final after = state.sessionFor(event.tabId);
      emit(
        state.withSession(
          event.tabId,
          after.copyWith(
            calling: false,
            errorMessage: e.toString(),
            log: [...after.log, 'Call failed: $e'],
          ),
        ),
      );
    }
  }

  Future<void> _teardown(String tabId) async {
    await _connections.remove(tabId)?.close();
  }

  @override
  Future<void> close() async {
    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();
    return super.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/mcp/presentation/bloc/mcp_bloc_test.dart`
Expected: PASS (all four `blocTest`s).

- [ ] **Step 5: Run bloc_lint on the new bloc**

Run: `fvm dart run bloc_tools:bloc lint lib`
Expected: no issues (confirms no Flutter import / naming violations).

- [ ] **Step 6: Commit**

```bash
git add lib/features/mcp/presentation/bloc test/features/mcp/presentation
git commit -m "feat(mcp): McpBloc owning one MCP connection + tool state per tab"
```

---

### Task 5: Register `McpService` + `McpBloc` in DI and provide the bloc

**Files:**
- Modify: `lib/core/di/injection_container.dart:242-244` (the Realtime block)
- Modify: `lib/main.dart` (imports + the `MultiBlocProvider` `providers` list near line 216)
- Test: `test/features/mcp/di_registration_test.dart`

**Interfaces:**
- Consumes: `McpService` (Task 3), `McpBloc` (Task 4), the existing `sl` GetIt instance.
- Produces: `sl<McpService>()` and `sl<McpBloc>()` resolve; `McpBloc` is provided above `MaterialApp`.

- [ ] **Step 1: Write the failing test**

Create `test/features/mcp/di_registration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';

void main() {
  test('McpService and McpBloc are registered after init', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await di.init();
    expect(di.sl.isRegistered<McpService>(), isTrue);
    expect(di.sl<McpBloc>(), isA<McpBloc>());
  });
}
```

> If `di.init()` requires Hive temp dirs and other suites already do this setup,
> follow the pattern in an existing DI/integration test (e.g. search
> `test/` for `di.init(`); reuse its `setUp`/`setUpAll` (Hive `path_provider`
> mock) verbatim if present. If no such test exists, this test may need the
> same `hive_test`/temp-dir bootstrapping — match the project's convention.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/mcp/di_registration_test.dart`
Expected: FAIL — `McpService`/`McpBloc` not registered.

- [ ] **Step 3: Register in DI**

In `lib/core/di/injection_container.dart`, add imports (respecting
`directives_ordering` — alphabetical within the `package:getman` group):

```dart
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
```

Then, immediately after the Realtime registrations (currently lines 242-244):

```dart
    // Features - MCP (Model Context Protocol client over Streamable HTTP)
    ..registerLazySingleton(McpService.new)
    ..registerLazySingleton(() => McpBloc(service: sl()))
```

- [ ] **Step 4: Provide the bloc in `main.dart`**

In `lib/main.dart`, add the import (alphabetical in the `package:getman` group):

```dart
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
```

Then in the `MultiBlocProvider` `providers` list, directly after the
`BlocProvider(create: (_) => di.sl<RealtimeBloc>())` line (near line 216):

```dart
          BlocProvider(create: (_) => di.sl<McpBloc>()),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `fvm flutter test test/features/mcp/di_registration_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/di/injection_container.dart lib/main.dart test/features/mcp/di_registration_test.dart
git commit -m "feat(mcp): register McpService + McpBloc in DI and provide app-wide"
```

---

### Task 6: URL-bar wiring — MCP dropdown item + CONNECT button

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/request_kind_method_selector.dart`
- Create: `lib/features/mcp/presentation/widgets/mcp_connect_button.dart`
- Modify: `lib/features/tabs/presentation/widgets/url_bar.dart` (the send/connect button branch near line 432)
- Test: `test/features/mcp/presentation/widgets/mcp_connect_button_test.dart`

**Interfaces:**
- Consumes: `McpBloc`, `McpConnectRequested`, `McpDisconnectRequested`, `McpState`/`McpConnectionStatus` (Tasks 4); `EnvironmentResolver.resolve`/`resolveMap`; `TabsBloc` for reading the live config; `context.appLayout`/`appTypography`/`appDecoration`.
- Produces: `McpConnectButton({required String tabId, required HttpRequestConfigEntity config, required bool isNarrow, required Map<String, String> activeVars})`.

- [ ] **Step 1: Add the MCP dropdown item**

In `request_kind_method_selector.dart`, add to the `DropdownButton<RequestKind>`
`items` list, after the SSE item:

```dart
                DropdownMenuItem(value: RequestKind.mcp, child: Text('MCP')),
```

(No test needed for this one-line list addition; it is covered by the connect-button test compiling against the new kind and by analyze.)

- [ ] **Step 2: Write the failing connect-button test**

Create `test/features/mcp/presentation/widgets/mcp_connect_button_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/mcp/presentation/widgets/mcp_connect_button.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockMcpBloc extends MockBloc<McpEvent, McpState> implements McpBloc {}

class _MockTabsBloc extends MockBloc<dynamic, TabsState> implements TabsBloc {}

void main() {
  late _MockMcpBloc mcp;
  late _MockTabsBloc tabs;

  const config = HttpRequestConfigEntity(
    id: 'c1',
    url: 'https://mcp.dev/',
    kind: RequestKind.mcp,
  );
  const tab = HttpRequestTabEntity(tabId: 't1', name: 'T', config: config);

  setUp(() {
    mcp = _MockMcpBloc();
    tabs = _MockTabsBloc();
    when(() => tabs.state).thenReturn(
      const TabsState(
        panels: [
          PanelEntity(id: 'p1', name: 'Panel 1', tabs: [tab], activeTabId: 't1'),
        ],
        activePanelId: 'p1',
      ),
    );
  });

  Widget harness(McpState mcpState) {
    when(() => mcp.state).thenReturn(mcpState);
    return MaterialApp(
      theme: resolveTheme('classic')(Brightness.light, false),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<McpBloc>.value(value: mcp),
            BlocProvider<TabsBloc>.value(value: tabs),
          ],
          child: const McpConnectButton(
            tabId: 't1',
            config: config,
            isNarrow: false,
            activeVars: {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows CONNECT when disconnected and dispatches connect',
      (tester) async {
    await tester.pumpWidget(harness(const McpState()));
    expect(find.text('CONNECT'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcp_connect_button')));
    await tester.pump();
    verify(
      () => mcp.add(
        any(that: isA<McpConnectRequested>()),
      ),
    ).called(1);
  });

  testWidgets('shows DISCONNECT when connected', (tester) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(status: McpConnectionStatus.connected),
          },
        ),
      ),
    );
    expect(find.text('DISCONNECT'), findsOneWidget);
  });
}
```

> If the `TabsState`/`PanelEntity` constructor argument names differ, adjust to
> match `lib/features/tabs/presentation/bloc/tabs_state.dart` and
> `lib/features/tabs/domain/entities/panel_entity.dart` — read those for the
> exact required params.

- [ ] **Step 3: Run test to verify it fails**

Run: `fvm flutter test test/features/mcp/presentation/widgets/mcp_connect_button_test.dart`
Expected: FAIL — `mcp_connect_button.dart` doesn't exist.

- [ ] **Step 4: Create the connect button**

Create `lib/features/mcp/presentation/widgets/mcp_connect_button.dart` (closely
mirrors `RealtimeButton`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';

/// CONNECT / DISCONNECT button for MCP requests, driven by the MCP connection
/// status for this tab. Resolves `{{var}}` in the endpoint URL + headers at
/// press time (the URL bar does not rebuild on URL edits, so read the live
/// config from TabsBloc).
class McpConnectButton extends StatelessWidget {
  const McpConnectButton({
    required this.tabId,
    required this.config,
    required this.isNarrow,
    required this.activeVars,
    super.key,
  });
  final String tabId;
  final HttpRequestConfigEntity config;
  final bool isNarrow;
  final Map<String, String> activeVars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return BlocBuilder<McpBloc, McpState>(
      buildWhen: (p, n) =>
          p.sessionFor(tabId).status != n.sessionFor(tabId).status,
      builder: (context, mcp) {
        final status = mcp.sessionFor(tabId).status;
        final connected = status == McpConnectionStatus.connected;
        final connecting = status == McpConnectionStatus.connecting;
        return context.appDecoration.wrapInteractive(
          child: ElevatedButton(
            key: const ValueKey('mcp_connect_button'),
            onPressed: connecting
                ? null
                : () {
                    final bloc = context.read<McpBloc>();
                    if (connected) {
                      bloc.add(McpDisconnectRequested(tabId));
                      return;
                    }
                    final current = context
                            .read<TabsBloc>()
                            .state
                            .tabs
                            .byId(tabId)
                            ?.config ??
                        config;
                    bloc.add(
                      McpConnectRequested(
                        tabId: tabId,
                        url: EnvironmentResolver.resolve(
                          current.url,
                          activeVars,
                        ),
                        headers: EnvironmentResolver.resolveMap(
                          current.headers,
                          activeVars,
                        ),
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: connected ? theme.colorScheme.error : null,
              foregroundColor: connected ? theme.colorScheme.onError : null,
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 12 : layout.buttonPaddingHorizontal,
                vertical: isNarrow ? 10 : layout.buttonPaddingVertical,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              connected
                  ? (isNarrow ? 'STOP' : 'DISCONNECT')
                  : (connecting ? '...' : 'CONNECT'),
              style: TextStyle(
                fontSize: layout.fontSizeTitle,
                fontWeight: context.appTypography.displayWeight,
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Wire it into the URL bar**

In `lib/features/tabs/presentation/widgets/url_bar.dart`, locate the
send/connect branch (currently `if (tab.config.kind == RequestKind.http) ... else RealtimeButton(...)` near lines 345/432). Change the `else` into a kind switch so MCP gets its own button. Add the import:

```dart
import 'package:getman/features/mcp/presentation/widgets/mcp_connect_button.dart';
```

Replace the trailing `else RealtimeButton(...)` with:

```dart
                          else if (tab.config.kind == RequestKind.mcp)
                            McpConnectButton(
                              tabId: tab.tabId,
                              config: tab.config,
                              isNarrow: isNarrow,
                              activeVars: _activeVariables(context),
                            )
                          else
                            RealtimeButton(
                              tabId: tab.tabId,
                              config: tab.config,
                              isNarrow: isNarrow,
                              activeVars: _activeVariables(context),
                            ),
```

- [ ] **Step 6: Run tests + analyze**

Run: `fvm flutter test test/features/mcp/presentation/widgets/mcp_connect_button_test.dart`
Expected: PASS.
Run: `fvm flutter analyze lib/features/tabs/presentation/widgets/url_bar.dart lib/features/mcp`
Expected: 0 issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/tabs/presentation/widgets/request_kind_method_selector.dart lib/features/tabs/presentation/widgets/url_bar.dart lib/features/mcp/presentation/widgets/mcp_connect_button.dart test/features/mcp/presentation/widgets/mcp_connect_button_test.dart
git commit -m "feat(mcp): MCP kind in selector + CONNECT button in URL bar"
```

---

### Task 7: `McpPanel` + `ResponseArea` switch

**Files:**
- Create: `lib/features/mcp/presentation/widgets/mcp_panel.dart`
- Modify: `lib/features/tabs/presentation/widgets/response_area.dart`
- Test: `test/features/mcp/presentation/widgets/mcp_panel_test.dart`

**Interfaces:**
- Consumes: `McpBloc`/`McpState`/`McpConnectionStatus`/`McpTabSession` (Task 4); `McpTool`/`McpToolResult` (Task 2); `McpToolSelected`/`McpToolCallRequested` (Task 4); `createJsonCodeController` + `JsonCodeEditor` (`lib/features/tabs/presentation/widgets/json_code_editor.dart`); `context.appLayout`/`appPalette`/`appTypography`/`appShape`.
- Produces: `McpPanel({required String tabId})`.

**Behavior:** When `status != connected`, show a centered hint ("Not connected — press CONNECT" / error message / spinner for connecting). When connected: a tool list (tappable rows dispatching `McpToolSelected`); for the selected tool, a read-only schema reference (`JsonCodeEditor(readOnly: true)`) + an editable JSON args editor + a "CALL" button dispatching `McpToolCallRequested` with the parsed args (invalid JSON shows an inline error and does not dispatch); the last result (text blocks, or raw JSON for non-text); and a collapsible session log.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/mcp/presentation/widgets/mcp_panel_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/mcp/presentation/widgets/mcp_panel.dart';
import 'package:mocktail/mocktail.dart';

class _MockMcpBloc extends MockBloc<McpEvent, McpState> implements McpBloc {}

void main() {
  late _MockMcpBloc mcp;

  setUp(() => mcp = _MockMcpBloc());

  Widget harness(McpState state) {
    when(() => mcp.state).thenReturn(state);
    return MaterialApp(
      theme: resolveTheme('classic')(Brightness.light, false),
      home: Scaffold(
        body: BlocProvider<McpBloc>.value(
          value: mcp,
          child: const SizedBox(
            width: 800,
            height: 600,
            child: McpPanel(tabId: 't1'),
          ),
        ),
      ),
    );
  }

  testWidgets('disconnected shows a hint', (tester) async {
    await tester.pumpWidget(harness(const McpState()));
    expect(find.textContaining('CONNECT'), findsWidgets);
  });

  testWidgets('connected lists tools and renders without overflow',
      (tester) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(
              status: McpConnectionStatus.connected,
              tools: [
                McpTool(name: 'add', description: 'Add', inputSchema: {}),
                McpTool(name: 'echo', description: 'Echo', inputSchema: {}),
              ],
              selectedTool: 'add',
              lastResult: McpToolResult(
                isError: false,
                textBlocks: ['result text'],
                rawBlocks: [],
              ),
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('add'), findsWidgets);
    expect(find.text('echo'), findsWidgets);
    expect(find.textContaining('result text'), findsWidgets);
    expect(tester.takeException(), isNull); // no RenderFlex overflow
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/mcp/presentation/widgets/mcp_panel_test.dart`
Expected: FAIL — `mcp_panel.dart` doesn't exist.

- [ ] **Step 3: Create the panel**

Create `lib/features/mcp/presentation/widgets/mcp_panel.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';

/// Post-connect MCP UI for one tab: tool list, the selected tool's schema +
/// JSON arguments editor + CALL, the last result, and a session log. Connecting
/// itself is driven by the URL-bar CONNECT button.
class McpPanel extends StatefulWidget {
  const McpPanel({required this.tabId, super.key});
  final String tabId;

  @override
  State<McpPanel> createState() => _McpPanelState();
}

class _McpPanelState extends State<McpPanel> {
  final CodeLineEditingController _args = createJsonCodeController();
  String? _argsErrorFor;
  String? _editingTool;

  @override
  void dispose() {
    _args.dispose();
    super.dispose();
  }

  void _syncArgsForTool(String? tool) {
    if (tool == _editingTool) return;
    _editingTool = tool;
    _args.text = '{}';
    _argsErrorFor = null;
  }

  void _call(BuildContext context, String tool) {
    final raw = _args.text.trim().isEmpty ? '{}' : _args.text;
    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) parsed = decoded;
    } on FormatException {
      parsed = null;
    }
    if (parsed == null) {
      setState(() => _argsErrorFor = 'Arguments must be a JSON object');
      return;
    }
    setState(() => _argsErrorFor = null);
    context.read<McpBloc>().add(
          McpToolCallRequested(
            tabId: widget.tabId,
            toolName: tool,
            arguments: parsed,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final typo = context.appTypography;
    final theme = Theme.of(context);

    return BlocBuilder<McpBloc, McpState>(
      buildWhen: (p, n) => p.sessionFor(widget.tabId) != n.sessionFor(widget.tabId),
      builder: (context, state) {
        final s = state.sessionFor(widget.tabId);

        if (s.status != McpConnectionStatus.connected) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(layout.spacingLarge),
              child: Text(
                switch (s.status) {
                  McpConnectionStatus.connecting => 'Connecting…',
                  McpConnectionStatus.error =>
                    s.errorMessage ?? 'Connection error',
                  _ => 'Not connected — press CONNECT to list tools',
                },
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: s.status == McpConnectionStatus.error
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface,
                  fontWeight: typo.bodyWeight,
                ),
              ),
            ),
          );
        }

        _syncArgsForTool(s.selectedTool);
        final selected = s.tools
            .where((t) => t.name == s.selectedTool)
            .cast<McpTool?>()
            .firstOrNull;

        return Padding(
          padding: EdgeInsets.all(layout.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tools (${s.tools.length})',
                style: TextStyle(fontWeight: typo.titleWeight),
              ),
              SizedBox(height: layout.spacingSmall),
              // Tool chips.
              Wrap(
                spacing: layout.spacingSmall,
                runSpacing: layout.spacingSmall,
                children: s.tools
                    .map(
                      (t) => ChoiceChip(
                        label: Text(t.name),
                        selected: t.name == s.selectedTool,
                        onSelected: (_) => context.read<McpBloc>().add(
                              McpToolSelected(
                                tabId: widget.tabId,
                                toolName: t.name,
                              ),
                            ),
                      ),
                    )
                    .toList(),
              ),
              SizedBox(height: layout.spacingMedium),
              if (selected != null)
                Expanded(
                  child: _ToolDetail(
                    tool: selected,
                    argsController: _args,
                    argsError: _argsErrorFor,
                    calling: s.calling,
                    resultText: _resultText(s),
                    onCall: () => _call(context, selected.name),
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: Text(
                      'Select a tool',
                      style: TextStyle(color: palette.codeBackground),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _resultText(McpTabSession s) {
    final r = s.lastResult;
    if (r == null) return '';
    if (r.textBlocks.isNotEmpty) return r.textBlocks.join('\n');
    if (r.rawBlocks.isNotEmpty) {
      return const JsonEncoder.withIndent('  ').convert(r.rawBlocks);
    }
    return r.isError ? '(error, no content)' : '(no content)';
  }
}

class _ToolDetail extends StatelessWidget {
  const _ToolDetail({
    required this.tool,
    required this.argsController,
    required this.argsError,
    required this.calling,
    required this.resultText,
    required this.onCall,
  });
  final McpTool tool;
  final CodeLineEditingController argsController;
  final String? argsError;
  final bool calling;
  final String resultText;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typo = context.appTypography;
    final theme = Theme.of(context);
    final schemaText = tool.inputSchema.isEmpty
        ? '(no input schema)'
        : const JsonEncoder.withIndent('  ').convert(tool.inputSchema);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tool.description.isNotEmpty) ...[
            Text(tool.description, style: TextStyle(fontWeight: typo.bodyWeight)),
            SizedBox(height: layout.spacingSmall),
          ],
          Text('Input schema', style: TextStyle(fontWeight: typo.titleWeight)),
          SizedBox(height: layout.spacingSmall),
          SizedBox(
            height: 160,
            child: JsonCodeEditor(
              controller: createJsonCodeController()..text = schemaText,
              readOnly: true,
              autofocus: false,
            ),
          ),
          SizedBox(height: layout.spacingMedium),
          Text('Arguments (JSON)',
              style: TextStyle(fontWeight: typo.titleWeight)),
          SizedBox(height: layout.spacingSmall),
          SizedBox(
            height: 160,
            child: JsonCodeEditor(
              controller: argsController,
              autofocus: false,
            ),
          ),
          if (argsError != null) ...[
            SizedBox(height: layout.spacingSmall),
            Text(argsError!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          SizedBox(height: layout.spacingMedium),
          Align(
            alignment: Alignment.centerLeft,
            child: context.appDecoration.wrapInteractive(
              child: ElevatedButton(
                key: const ValueKey('mcp_call_button'),
                onPressed: calling ? null : onCall,
                child: Text(
                  calling ? 'CALLING…' : 'CALL',
                  style: TextStyle(fontWeight: typo.displayWeight),
                ),
              ),
            ),
          ),
          if (resultText.isNotEmpty) ...[
            SizedBox(height: layout.spacingMedium),
            Text('Result', style: TextStyle(fontWeight: typo.titleWeight)),
            SizedBox(height: layout.spacingSmall),
            SelectableText(resultText),
          ],
        ],
      ),
    );
  }
}
```

> `firstOrNull` comes from `package:collection`, already a dependency. If
> analyze flags the import as missing, add `import 'package:collection/collection.dart';`.
> Verify `layout.spacingLarge`/`spacingMedium`/`spacingSmall` exist on
> `AppLayout`; if the field names differ, use the actual ones (read
> `lib/core/theme/extensions/` — search `AppLayout` for the spacing fields). Do
> not hardcode pixel values.

- [ ] **Step 4: Switch `ResponseArea` to the panel for MCP**

In `lib/features/tabs/presentation/widgets/response_area.dart`, add the import:

```dart
import 'package:getman/features/mcp/presentation/widgets/mcp_panel.dart';
```

Update the builder so MCP renders `McpPanel`, WS/SSE render `RealtimePanel`:

```dart
        final kind = state.tabs.byId(tabId)?.config.kind ?? RequestKind.http;
        if (kind == RequestKind.http) {
          return ResponseSection(
            tabId: tabId,
            responseController: responseController,
            showMetadata: showMetadata,
          );
        }
        if (kind == RequestKind.mcp) {
          return McpPanel(tabId: tabId);
        }
        return RealtimePanel(tabId: tabId);
```

- [ ] **Step 5: Run tests + analyze**

Run: `fvm flutter test test/features/mcp/presentation/widgets/mcp_panel_test.dart`
Expected: PASS (including the no-overflow assertion).
Run: `fvm flutter analyze lib/features/mcp lib/features/tabs/presentation/widgets/response_area.dart`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/mcp/presentation/widgets/mcp_panel.dart lib/features/tabs/presentation/widgets/response_area.dart test/features/mcp/presentation/widgets/mcp_panel_test.dart
git commit -m "feat(mcp): McpPanel (tools, args editor, result) wired into ResponseArea"
```

---

### Task 8: Full verification + wiki documentation

**Files:**
- No app code; runs the full verification bar and updates the external wiki repo.

- [ ] **Step 1: Run the entire verification bar**

Run each and confirm the stated expectation:

```bash
fvm flutter analyze
```
Expected: "No issues found!"

```bash
fvm dart run custom_lint
```
Expected: "No issues found!"

```bash
fvm dart run bloc_tools:bloc lint lib
```
Expected: no issues.

```bash
fvm dart format lib test
```
Expected: formats with no diffs needed (or commit the formatting).

```bash
fvm flutter test
```
Expected: all tests pass (the prior suite count + the new MCP tests).

- [ ] **Step 2: Fix anything that fails, then re-run until all five are clean**

If any pass reports issues, fix them and re-run that pass plus `fvm flutter test`. Do not proceed until all five are clean.

- [ ] **Step 3: Update the wiki**

Clone and edit the separate wiki repo (per the "keep the wiki in sync" mandate):

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

Create `/tmp/getman-wiki/MCP-Requests.md` documenting (verbatim UI labels):
- What MCP support is (a client that connects to MCP servers over HTTP).
- How to use it: set the request kind dropdown to **MCP**, enter the server **endpoint URL**, add an `Authorization` header in the **HEADERS** tab if needed, press **CONNECT**.
- Selecting a tool, editing the **Arguments (JSON)** field (supports `{{var}}`), pressing **CALL**, reading the **Result**.
- Current limits: HTTP transport only (no stdio), **tools only** (resources/prompts not yet supported), no server-initiated notifications.

Add a line to `/tmp/getman-wiki/_Sidebar.md` linking the new page, alongside the other feature pages.

```bash
cd /tmp/getman-wiki
git add MCP-Requests.md _Sidebar.md
git commit -m "docs: MCP requests page"
git push origin master
```

- [ ] **Step 4: Final commit (if formatting changed any files)**

```bash
git add -A
git commit -m "chore(mcp): format + final verification" || echo "nothing to commit"
```

---

## Self-Review

**Spec coverage:**
- New `RequestKind.mcp`, no Hive migration → Task 1. ✓
- Streamable HTTP JSON-RPC service, json + SSE responses, initialize handshake, session-id/protocol-version headers, tools/list, tools/call, error→exception, cancellable call → Task 3. ✓
- Domain entities (`McpSession`/`McpTool`/`McpToolResult`) → Task 2. ✓
- `McpBloc` bloc-over-service, per-tab sessions, status/tools/selected/result/log → Task 4. ✓
- DI + app-wide provider → Task 5. ✓
- Selector item + URL-bar CONNECT button reusing env resolution + live-config read → Task 6. ✓
- `McpPanel` (tool list, schema reference, raw JSON args editor with `{{}}`-capable controller + validation, result, log) + `ResponseArea` switch → Task 7. ✓
- Headers tab reused for auth: no code needed (editor area is not kind-gated; HEADERS already shows) — documented in Task 8 wiki step. ✓
- MCP traffic excluded from HTTP history/time-travel: satisfied by construction (MCP never dispatches `SendRequest`; it uses `McpBloc`, not `TabsBloc` send path). No task needed. ✓
- Verification bar + wiki → Task 8. ✓
- Deferred (resources, prompts, server-initiated SSE, generated form, stdio, DELETE session-terminate): explicitly not implemented; noted in code comments + wiki. ✓

**Placeholder scan:** The only intentional placeholder is the test-only `_ConnectedFixture` in Task 3 Step 1, which Step 3b explicitly removes; flagged inline. No `TBD`/`TODO`/"handle edge cases" in shipped code.

**Type consistency:** `McpConnection.callTool(name, arguments, {cancelToken})`, `listTools()`, `connect(url, {headers})`, `McpTabSession.copyWith(...)`, `McpState.withSession/sessionFor`, `McpConnectionStatus` enum values, and event constructor signatures are used identically across Tasks 3–7. `createJsonCodeController()` / `JsonCodeEditor(controller:, readOnly:, autofocus:)` match the real signatures read from `json_code_editor.dart`.
