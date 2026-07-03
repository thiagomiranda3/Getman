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

/// A response body with verbatim [text] and an explicit content-type — used for
/// empty/garbage payloads that must surface as an [McpException] rather than
/// parse into a JSON-RPC message.
ResponseBody _rawBody(String text, String contentType, {int status = 200}) {
  final bytes = Uint8List.fromList(utf8.encode(text));
  return ResponseBody(
    Stream<Uint8List>.value(bytes),
    status,
    headers: {
      Headers.contentTypeHeader: [contentType],
    },
  );
}

/// The `initialize` JSON-RPC result shape, reused by the multi-POST stubs.
Map<String, dynamic> _initResult() => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': {
    'protocolVersion': '2025-06-18',
    'serverInfo': {'name': 'demo', 'version': '1'},
  },
};

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

  Response<ResponseBody> resp(
    ResponseBody body, {
    Map<String, List<String>>? headers,
  }) => Response<ResponseBody>(
    data: body,
    statusCode: body.statusCode,
    headers: Headers.fromMap(headers ?? {}),
    requestOptions: RequestOptions(path: '/'),
  );

  test(
    'connect performs the initialize handshake and captures session id',
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
        // initialized notif (202-ish)
        resp(_jsonBody({'jsonrpc': '2.0'}), headers: {}),
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
    },
  );

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
        headers: {
          'mcp-session-id': ['s1'],
        },
      ),
      // initialized notification ack
      resp(_jsonBody({'jsonrpc': '2.0'})),
      // tools/list
      resp(
        _jsonBody({
          'jsonrpc': '2.0',
          'id': 2,
          'result': {
            'tools': [
              {
                'name': 'add',
                'description': 'Add',
                'inputSchema': {'type': 'object'},
              },
            ],
          },
        }),
      ),
    ]);

    final conn = await service.connect('https://mcp.dev/');
    final tools = await conn.listTools();
    expect(tools.single.name, 'add');
  });

  test('callTool parses a result delivered over text/event-stream', () async {
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
        headers: {
          'mcp-session-id': ['s1'],
        },
      ),
      // initialized notification ack
      resp(_jsonBody({'jsonrpc': '2.0'})),
      // tools/call (SSE)
      resp(
        _sseBody({
          'jsonrpc': '2.0',
          'id': 2,
          'result': {
            'content': [
              {'type': 'text', 'text': 'hello'},
            ],
            'isError': false,
          },
        }),
      ),
    ]);

    final conn = await service.connect('https://mcp.dev/');
    final result = await conn.callTool('echo', const {'msg': 'hi'});
    expect(result.textBlocks, ['hello']);
    expect(result.isError, isFalse);
  });

  test('a JSON-RPC error response throws McpException', () async {
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
        headers: {
          'mcp-session-id': ['s1'],
        },
      ),
      // initialized notification ack
      resp(_jsonBody({'jsonrpc': '2.0'})),
      // error response
      resp(
        _jsonBody({
          'jsonrpc': '2.0',
          'id': 2,
          'error': {'code': -32601, 'message': 'Method not found'},
        }),
      ),
    ]);

    final conn = await service.connect('https://mcp.dev/');
    await expectLater(
      conn.listTools(),
      throwsA(
        isA<McpException>()
            .having((e) => e.code, 'code', -32601)
            .having((e) => e.message, 'message', contains('Method not found')),
      ),
    );
  });

  test(
    'custom connect headers + session/protocol headers ride later requests',
    () async {
      stubPosts([
        resp(
          _jsonBody(_initResult()),
          headers: {
            'mcp-session-id': ['sess-7'],
          },
        ),
        // initialized notification ack
        resp(_jsonBody({'jsonrpc': '2.0'})),
        // tools/list
        resp(
          _jsonBody({
            'jsonrpc': '2.0',
            'id': 2,
            'result': {'tools': <dynamic>[]},
          }),
        ),
      ]);

      final conn = await service.connect(
        'https://mcp.dev/',
        headers: const {'X-Api-Key': 'secret'},
      );
      await conn.listTools();

      final captured = verify(
        () => dio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: captureAny(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).captured;
      // initialize POST (1st): the caller's custom header is present, but no
      // session id has been negotiated yet.
      final initHeaders = (captured.first as Options).headers!;
      expect(initHeaders['X-Api-Key'], 'secret');
      expect(initHeaders.containsKey('Mcp-Session-Id'), isFalse);
      // tools/list POST (3rd): session id + negotiated protocol version ride
      // alongside the still-present custom header.
      final listHeaders = (captured[2] as Options).headers!;
      expect(listHeaders['Mcp-Session-Id'], 'sess-7');
      expect(listHeaders['MCP-Protocol-Version'], '2025-06-18');
      expect(listHeaders['X-Api-Key'], 'secret');
    },
  );

  test('an empty response body surfaces as an McpException', () async {
    stubPosts([resp(_rawBody('', 'application/json'))]);
    await expectLater(
      service.connect('https://mcp.dev/'),
      throwsA(
        isA<McpException>().having(
          (e) => e.message,
          'message',
          contains('Empty/unparseable'),
        ),
      ),
    );
  });

  test('a response with neither result nor error is malformed', () async {
    // A syntactically valid JSON-RPC envelope that carries no `result` and no
    // `error` must not be silently treated as success.
    stubPosts([
      resp(_jsonBody({'jsonrpc': '2.0', 'id': 1})),
    ]);
    await expectLater(
      service.connect('https://mcp.dev/'),
      throwsA(
        isA<McpException>().having(
          (e) => e.message,
          'message',
          contains('Malformed JSON-RPC'),
        ),
      ),
    );
  });

  test(
    'callTool falls back to the last SSE event when no id matches',
    () async {
      stubPosts([
        resp(
          _jsonBody(_initResult()),
          headers: {
            'mcp-session-id': ['s1'],
          },
        ),
        resp(_jsonBody({'jsonrpc': '2.0'})),
        // tools/call SSE whose id (99) does NOT match the request id — the
        // service must still surface the result via its last-event fallback.
        resp(
          _sseBody({
            'jsonrpc': '2.0',
            'id': 99,
            'result': {
              'content': [
                {'type': 'text', 'text': 'fallback'},
              ],
              'isError': false,
            },
          }),
        ),
      ]);

      final conn = await service.connect('https://mcp.dev/');
      final result = await conn.callTool('echo', const {});
      expect(result.textBlocks, ['fallback']);
    },
  );

  test(
    'callTool surfaces an isError result and forwards the cancel token',
    () async {
      final token = CancelToken();
      stubPosts([
        resp(
          _jsonBody(_initResult()),
          headers: {
            'mcp-session-id': ['s1'],
          },
        ),
        resp(_jsonBody({'jsonrpc': '2.0'})),
        resp(
          _jsonBody({
            'jsonrpc': '2.0',
            'id': 2,
            'result': {
              'content': [
                {'type': 'text', 'text': 'bad input'},
              ],
              'isError': true,
            },
          }),
        ),
      ]);

      final conn = await service.connect('https://mcp.dev/');
      final result = await conn.callTool('boom', const {}, cancelToken: token);
      expect(result.isError, isTrue);
      expect(result.textBlocks, ['bad input']);
      // The caller's cancel token reaches the underlying POST so an in-flight
      // call can be aborted.
      verify(
        () => dio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
          cancelToken: token,
        ),
      ).called(1);
    },
  );
}
