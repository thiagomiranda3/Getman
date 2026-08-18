import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/core/network/network_config.dart';
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

/// An SSE response body backed by [controller] — the test controls when (and
/// whether) chunks arrive and whether the stream ever closes, so it can model
/// a server that holds the POST's SSE stream open after the reply.
ResponseBody _openSseBody(StreamController<Uint8List> controller) =>
    ResponseBody(
      controller.stream,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );

/// A single UTF-8 encoded SSE `data:` frame carrying [json].
Uint8List _sseFrame(Map<String, dynamic> json) =>
    Uint8List.fromList(utf8.encode('data: ${jsonEncode(json)}\n\n'));

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

  test(
    'callTool completes as soon as the SSE reply arrives even though the '
    'server never closes the stream, and cancels the body subscription',
    () async {
      final controller = StreamController<Uint8List>();
      var cancelled = false;
      controller.onCancel = () {
        cancelled = true;
      };
      stubPosts([
        resp(
          _jsonBody(_initResult()),
          headers: {
            'mcp-session-id': ['s1'],
          },
        ),
        resp(_jsonBody({'jsonrpc': '2.0'})),
        resp(_openSseBody(controller)),
      ]);

      final conn = await service.connect('https://mcp.dev/');
      final pending = conn.callTool('echo', const {'msg': 'hi'});
      // A keep-alive comment first (real servers send these between events),
      // then the reply — and the stream stays open after it. Draining to EOF
      // would hang here forever.
      controller
        ..add(Uint8List.fromList(utf8.encode(': keep-alive\n\n')))
        ..add(
          _sseFrame({
            'jsonrpc': '2.0',
            'id': 2,
            'result': {
              'content': [
                {'type': 'text', 'text': 'hello'},
              ],
            },
          }),
        );

      final result = await pending.timeout(const Duration(seconds: 5));
      expect(result.textBlocks, ['hello']);
      // The reply is in hand — the still-open body stream must be released.
      await pumpEventQueue();
      expect(cancelled, isTrue);
      await controller.close();
    },
  );

  test(
    'connect completes when initialize arrives over an SSE stream that '
    'stays open',
    () async {
      final controller = StreamController<Uint8List>();
      stubPosts([
        resp(
          _openSseBody(controller),
          headers: {
            'mcp-session-id': ['sse-sess'],
          },
        ),
        // initialized notification ack
        resp(_jsonBody({'jsonrpc': '2.0'})),
      ]);

      final pending = service.connect('https://mcp.dev/');
      controller.add(_sseFrame(_initResult()));

      final conn = await pending.timeout(const Duration(seconds: 5));
      expect(conn.session.sessionId, 'sse-sess');
      expect(conn.session.serverName, 'demo');
      await controller.close();
    },
  );

  test(
    'a server-initiated request with a colliding id is skipped and the real '
    'reply that follows wins',
    () async {
      // Same id as the tools/call request, but no result/error: a
      // server-initiated `ping` REQUEST, not the reply. Mistaking it for the
      // reply produced a bogus "Malformed" error before the real reply.
      final ping = {'jsonrpc': '2.0', 'id': 2, 'method': 'ping'};
      final reply = {
        'jsonrpc': '2.0',
        'id': 2,
        'result': {
          'content': [
            {'type': 'text', 'text': 'real'},
          ],
        },
      };
      stubPosts([
        resp(
          _jsonBody(_initResult()),
          headers: {
            'mcp-session-id': ['s1'],
          },
        ),
        resp(_jsonBody({'jsonrpc': '2.0'})),
        resp(
          _rawBody(
            'data: ${jsonEncode(ping)}\n\ndata: ${jsonEncode(reply)}\n\n',
            'text/event-stream',
          ),
        ),
      ]);

      final conn = await service.connect('https://mcp.dev/');
      final result = await conn.callTool('echo', const {});
      expect(result.textBlocks, ['real']);
      expect(result.isError, isFalse);
    },
  );

  test('a reply whose id is echoed as a String still matches', () async {
    final controller = StreamController<Uint8List>();
    stubPosts([
      resp(
        _jsonBody(_initResult()),
        headers: {
          'mcp-session-id': ['s1'],
        },
      ),
      resp(_jsonBody({'jsonrpc': '2.0'})),
      resp(_openSseBody(controller)),
    ]);

    final conn = await service.connect('https://mcp.dev/');
    final pending = conn.callTool('echo', const {});
    controller.add(
      _sseFrame({
        'jsonrpc': '2.0',
        // Echoed as a String — must still match the int request id 2.
        'id': '2',
        'result': {
          'content': [
            {'type': 'text', 'text': 'string-id'},
          ],
        },
      }),
    );

    // The stream never closes, so only a true id match (not the stream-end
    // fallback) can complete this future.
    final result = await pending.timeout(const Duration(seconds: 5));
    expect(result.textBlocks, ['string-id']);
    await controller.close();
  });

  test(
    'a top-level batch array body is unwrapped and scanned for the reply',
    () async {
      stubPosts([
        resp(
          _jsonBody(_initResult()),
          headers: {
            'mcp-session-id': ['s1'],
          },
        ),
        resp(_jsonBody({'jsonrpc': '2.0'})),
        resp(
          _rawBody(
            jsonEncode([
              {'jsonrpc': '2.0', 'method': 'notifications/progress'},
              {
                'jsonrpc': '2.0',
                'id': 2,
                'result': {
                  'tools': [
                    {'name': 'batched'},
                  ],
                },
              },
            ]),
            'application/json',
          ),
        ),
      ]);

      final conn = await service.connect('https://mcp.dev/');
      final tools = await conn.listTools();
      expect(tools.single.name, 'batched');
    },
  );

  test(
    'a non-conformant error (string code / numeric message) surfaces the '
    "server's text instead of a Dart TypeError",
    () async {
      stubPosts([
        resp(
          _jsonBody(_initResult()),
          headers: {
            'mcp-session-id': ['s1'],
          },
        ),
        resp(_jsonBody({'jsonrpc': '2.0'})),
        // String code: must not throw a cast error; the message survives.
        resp(
          _jsonBody({
            'jsonrpc': '2.0',
            'id': 2,
            'error': {'code': 'TOOL_NOT_FOUND', 'message': 'no such tool'},
          }),
        ),
        // Double code + numeric message: code truncates, message stringifies.
        resp(
          _jsonBody({
            'jsonrpc': '2.0',
            'id': 3,
            'error': {'code': -32601.0, 'message': 404},
          }),
        ),
      ]);

      final conn = await service.connect('https://mcp.dev/');
      await expectLater(
        conn.listTools(),
        throwsA(
          isA<McpException>()
              .having((e) => e.code, 'code', isNull)
              .having((e) => e.message, 'message', contains('no such tool')),
        ),
      );
      await expectLater(
        conn.listTools(),
        throwsA(
          isA<McpException>()
              .having((e) => e.code, 'code', -32601)
              .having((e) => e.message, 'message', '404'),
        ),
      );
    },
  );

  group('MCP Dio wiring (network settings)', () {
    test('buildMcpDio honors the configured connect/send/receive '
        'timeouts', () {
      final built = McpService.buildMcpDio(
        const NetworkConfig(
          connectTimeoutMs: 5000,
          sendTimeoutMs: 6000,
          receiveTimeoutMs: 7000,
        ),
      );

      expect(built.options.connectTimeout, const Duration(seconds: 5));
      expect(built.options.sendTimeout, const Duration(seconds: 6));
      expect(built.options.receiveTimeout, const Duration(seconds: 7));
    });

    test('buildMcpDio maps 0 straight through (dio treats a non-positive '
        'timeout as disabled)', () {
      final built = McpService.buildMcpDio(
        const NetworkConfig(
          connectTimeoutMs: 0,
          sendTimeoutMs: 0,
          receiveTimeoutMs: 0,
        ),
      );

      expect(built.options.connectTimeout, Duration.zero);
      expect(built.options.sendTimeout, Duration.zero);
      expect(built.options.receiveTimeout, Duration.zero);
    });

    test(
      'applyConfig updates all three timeouts in place on a timeout-only '
      'change (no adapter swap)',
      () {
        final built = McpService.buildMcpDio(NetworkConfig.defaults);
        final mcpService = McpService(dio: built)
          ..applyConfig(NetworkConfig.defaults);
        final adapter = built.httpClientAdapter;

        mcpService.applyConfig(
          const NetworkConfig(
            connectTimeoutMs: 1111,
            sendTimeoutMs: 2222,
            receiveTimeoutMs: 3333,
          ),
        );

        expect(
          built.options.connectTimeout,
          const Duration(milliseconds: 1111),
        );
        expect(built.options.sendTimeout, const Duration(milliseconds: 2222));
        expect(
          built.options.receiveTimeout,
          const Duration(milliseconds: 3333),
        );
        // A timeout-only change must not drop the adapter's socket pool.
        expect(built.httpClientAdapter, same(adapter));
      },
    );
  });
}
