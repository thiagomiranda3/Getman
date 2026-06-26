import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A hermetic localhost **MCP server** (JSON-RPC 2.0 over Streamable HTTP) for
/// the MCP E2E flow.
///
/// Binds an ephemeral loopback port and answers the three calls the app makes:
/// the `initialize` handshake (issuing an `Mcp-Session-Id`), `tools/list`, and
/// `tools/call` (which echoes the call arguments back as a `text` content
/// block). Point an MCP request's URL at [url] and the real `McpService` dio
/// path in the app connects to this server — offline, fast, deterministic.
///
/// ```dart
/// final server = await MockMcpServer.start();
/// addTearDown(server.close);
/// // ... drive the app to connect to server.url, list + call a tool ...
/// expect(server.receivedMethods, contains('tools/call'));
/// ```
class MockMcpServer {
  MockMcpServer._(this._server, this._tools) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<Map<String, dynamic>> _tools;

  /// Every JSON-RPC `method` the server received, in arrival order — so a flow
  /// can assert the handshake/list/call actually reached the wire.
  final List<String> receivedMethods = [];

  /// The MCP endpoint URL (e.g. `http://127.0.0.1:53412/mcp`).
  String get url => 'http://${_server.address.address}:${_server.port}/mcp';

  /// Starts a server advertising [tools] (defaults to a single `echo` tool).
  static Future<MockMcpServer> start({
    List<Map<String, dynamic>>? tools,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return MockMcpServer._(
      server,
      tools ??
          [
            {
              'name': 'echo',
              'description': 'Echoes the arguments back',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'msg': {'type': 'string'},
                },
              },
            },
          ],
    );
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    Map<String, dynamic> rpc;
    try {
      rpc = (jsonDecode(body) as Map).cast<String, dynamic>();
    } on Object {
      rpc = const {};
    }
    final method = (rpc['method'] as String?) ?? '';
    receivedMethods.add(method);
    final id = rpc['id'];

    request.response.headers.contentType = ContentType.json;

    try {
      switch (method) {
        case 'initialize':
          request.response.headers.set('Mcp-Session-Id', 'e2e-session');
          _writeResult(request, id, {
            'protocolVersion': '2025-06-18',
            'serverInfo': {'name': 'E2E MCP', 'version': '1.0'},
            'capabilities': <String, dynamic>{'tools': <String, dynamic>{}},
          });
        case 'notifications/initialized':
          // A notification — no id, no response payload expected.
          request.response.statusCode = HttpStatus.accepted;
        case 'tools/list':
          _writeResult(request, id, {'tools': _tools});
        case 'tools/call':
          final params = (rpc['params'] as Map?)?.cast<String, dynamic>() ?? {};
          final args =
              (params['arguments'] as Map?)?.cast<String, dynamic>() ?? {};
          _writeResult(request, id, {
            'content': [
              {'type': 'text', 'text': 'echo: ${jsonEncode(args)}'},
            ],
            'isError': false,
          });
        default:
          _writeError(request, id, 'Method not found: $method');
      }
    } on Object {
      // The client may have gone away mid-response; ignore write failures.
    } finally {
      try {
        await request.response.close();
      } on Object {
        // Connection already closed by the client — ignore.
      }
    }
  }

  void _writeResult(
    HttpRequest request,
    Object? id,
    Map<String, dynamic> result,
  ) {
    request.response.write(
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
    );
  }

  void _writeError(HttpRequest request, Object? id, String message) {
    request.response.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32601, 'message': message},
      }),
    );
  }

  /// Shuts the server down. Always call in `addTearDown`.
  Future<void> close() => _server.close(force: true);
}
