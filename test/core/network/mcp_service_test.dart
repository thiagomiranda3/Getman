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
}
