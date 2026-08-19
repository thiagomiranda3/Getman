// McpService: opens MCP (Model Context Protocol) client connections over
// Streamable HTTP (JSON-RPC 2.0), pure `dio` so it stays web-safe. Runs the
// `initialize` handshake (capturing the `Mcp-Session-Id` response header),
// then exposes listTools/callTool over the resulting McpConnection.
// Responses may arrive as a plain JSON body or a `text/event-stream` body.
// SSE bodies are parsed incrementally (SseParser) and complete as soon as
// the id-matching reply (one carrying `result`/`error`) arrives — the MCP
// spec says a server SHOULD (not MUST) close the POST's SSE stream, so
// waiting for EOF would hang against servers that hold it open.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:getman/core/network/dio_adapter_config.dart';
import 'package:getman/core/network/network_config.dart';
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
  String toString() => 'McpException(${code == null ? '' : '$code: '}$message)';
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
  McpService({Dio? dio}) : _dio = dio ?? buildMcpDio(NetworkConfig.defaults);
  final Dio _dio;

  /// Adapter-relevant config of the last [applyConfig] that rebuilt the
  /// adapter; null until the first swap.
  NetworkConfig? _adapterConfig;

  // Wired like RealtimeService.buildSseDio: the same verify-SSL/proxy/mTLS
  // adapter and (optional) cookie jar interceptor, so a self-signed dev MCP
  // server or session-cookie auth that works for plain requests and SSE also
  // works for MCP — a bare Dio here silently ignored every network setting.
  static Dio buildMcpDio(
    NetworkConfig config, [
    Interceptor? cookieInterceptor,
  ]) {
    final dio = Dio(
      BaseOptions(
        // Direct mapping like NetworkService.buildDio — 0 means disabled via
        // dio's own `> Duration.zero` gate.
        connectTimeout: Duration(milliseconds: config.connectTimeoutMs),
        sendTimeout: Duration(milliseconds: config.sendTimeoutMs),
        receiveTimeout: Duration(milliseconds: config.receiveTimeoutMs),
        // MCP servers may answer with a JSON-RPC error at HTTP 200, or with
        // 4xx/5xx — read every status so we can surface the body either way.
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
      ),
    );
    configureHttpAdapter(
      dio,
      verifySsl: config.verifySsl,
      proxyUrl: config.proxyUrl,
      clientCertPath: config.clientCertPath,
      clientKeyPath: config.clientKeyPath,
      clientCertPassphrase: config.clientCertPassphrase,
    );
    if (cookieInterceptor != null) dio.interceptors.add(cookieInterceptor);
    return dio;
  }

  /// Re-applies [config] to the live client without rebuilding it — mirrors
  /// NetworkService/RealtimeService.applyConfig: timeouts mutate
  /// [BaseOptions] in place BEFORE the adapter early-return, so a
  /// timeout-only edit still lands; only an adapter-relevant change
  /// (SSL/proxy/client cert) swaps the adapter. Interceptors (e.g. the
  /// cookie jar) survive.
  void applyConfig(NetworkConfig config) {
    _dio.options
      ..connectTimeout = Duration(milliseconds: config.connectTimeoutMs)
      ..sendTimeout = Duration(milliseconds: config.sendTimeoutMs)
      ..receiveTimeout = Duration(milliseconds: config.receiveTimeoutMs);
    if (_adapterConfig != null && _adapterConfig!.sameAdapterConfig(config)) {
      return;
    }
    _adapterConfig = config;
    final old = _dio.httpClientAdapter;
    configureHttpAdapter(
      _dio,
      verifySsl: config.verifySsl,
      proxyUrl: config.proxyUrl,
      clientCertPath: config.clientCertPath,
      clientKeyPath: config.clientKeyPath,
      clientCertPassphrase: config.clientCertPassphrase,
    );
    // Web stub leaves the adapter untouched (no-op); only close on a real swap.
    if (!identical(_dio.httpClientAdapter, old)) old.close();
  }

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
        .whereType<Map<String, dynamic>>()
        .map(McpTool.fromJson)
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
      if (_session.sessionId.isNotEmpty) 'Mcp-Session-Id': _session.sessionId,
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
      final ct =
          response.headers.map[Headers.contentTypeHeader]?.join(',') ??
          response.data?.headers[Headers.contentTypeHeader]?.join(',') ??
          '';
      throw McpException(
        'Empty/unparseable response for $method '
        '(HTTP ${response.statusCode}, content-type "$ct")',
      );
    }
    final error = message['error'];
    if (error is Map<String, dynamic>) {
      // Non-conformant servers send e.g. `'code': 'TOOL_NOT_FOUND'` or a
      // non-String message — surface the server's text instead of throwing
      // a Dart TypeError at the user.
      final code = error['code'];
      throw McpException(
        error['message']?.toString() ?? 'Unknown error',
        code: code is num ? code.toInt() : null,
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
    );
    // Drain so the connection is released; the body is ignored (202 Accepted).
    await _drain(response.data);
  }

  /// Reads the JSON-RPC reply to [expectedId] from either an
  /// `application/json` body or a `text/event-stream` body. SSE bodies are
  /// parsed incrementally and complete as soon as the reply arrives — see
  /// [_readSseReply]. Plain JSON bodies are drained to EOF (they close).
  Future<Map<String, dynamic>?> _readMessage(
    Response<ResponseBody> response,
    int expectedId,
  ) async {
    final body = response.data;
    if (body == null) return null;
    // In real Dio (streaming), Content-Type appears in both Response.headers
    // and ResponseBody.headers. In tests, only one side may be set.
    final headerValues =
        response.headers.map[Headers.contentTypeHeader] ??
        body.headers[Headers.contentTypeHeader] ??
        const <String>[];
    final contentType = headerValues.isNotEmpty ? headerValues.first : '';

    if (contentType.contains('text/event-stream')) {
      return _readSseReply(body, expectedId);
    }

    final decoded = _tryDecode(await _drain(body));
    return _replyIn(decoded, expectedId) ?? _fallbackMessage(decoded);
  }

  /// Incrementally parses a `text/event-stream` [body], completing as soon
  /// as an event decodes to the reply for [expectedId], then cancelling the
  /// body subscription. The MCP spec says the server SHOULD close the
  /// POST's SSE stream after the reply — not MUST — so draining to EOF
  /// hangs forever against servers that hold it open (keep-alive comments
  /// defeat the inter-chunk receiveTimeout, too). Non-matching events are
  /// notifications/server-initiated requests: they are skipped, with the
  /// last decodable message kept as a bounded fallback used only if the
  /// stream ends without a proper id-matched reply.
  Future<Map<String, dynamic>?> _readSseReply(
    ResponseBody body,
    int expectedId,
  ) {
    final completer = Completer<Map<String, dynamic>?>();
    final parser = SseParser();
    Map<String, dynamic>? lastMessage;
    late final StreamSubscription<String> subscription;

    void deliver(Map<String, dynamic>? message) {
      if (completer.isCompleted) return;
      completer.complete(message);
      unawaited(subscription.cancel());
    }

    void scan(List<String> events) {
      for (final raw in events) {
        if (completer.isCompleted) return;
        final decoded = _tryDecode(raw);
        final reply = _replyIn(decoded, expectedId);
        if (reply != null) {
          deliver(reply);
          return;
        }
        lastMessage = _fallbackMessage(decoded) ?? lastMessage;
      }
    }

    subscription = utf8.decoder
        .bind(body.stream)
        .listen(
          (chunk) => scan(parser.addChunk(chunk)),
          onDone: () {
            scan(parser.flush());
            deliver(lastMessage);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
          cancelOnError: true,
        );
    return completer.future;
  }

  /// True when [message] is the JSON-RPC reply to [expectedId]: id-equal
  /// (compared as strings, so a server echoing the id as `'1'` still
  /// matches `1`) AND carrying `result` or `error`. A server-initiated
  /// request (e.g. `ping`) may collide on id but has neither — it must not
  /// be mistaken for the reply.
  bool _isReplyTo(Map<String, dynamic> message, int expectedId) =>
      message['id']?.toString() == expectedId.toString() &&
      (message.containsKey('result') || message.containsKey('error'));

  /// Picks the reply to [expectedId] out of [decoded]: the Map itself when
  /// it satisfies [_isReplyTo], or — for a top-level batch List — its first
  /// reply element.
  Map<String, dynamic>? _replyIn(Object? decoded, int expectedId) {
    if (decoded is Map<String, dynamic>) {
      return _isReplyTo(decoded, expectedId) ? decoded : null;
    }
    if (decoded is List<dynamic>) {
      for (final element in decoded) {
        if (element is Map<String, dynamic> &&
            _isReplyTo(element, expectedId)) {
          return element;
        }
      }
    }
    return null;
  }

  /// Last-resort message when nothing id-matched: the Map itself, or the
  /// last Map element of a batch List. Lets `_request` surface a Malformed
  /// error (or a non-conformant server's un-id'd reply) instead of
  /// "empty response".
  Map<String, dynamic>? _fallbackMessage(Object? decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is List<dynamic>) {
      for (final element in decoded.reversed) {
        if (element is Map<String, dynamic>) return element;
      }
    }
    return null;
  }

  /// Decodes [raw] as JSON, returning a Map or a top-level batch List
  /// (anything else is not a JSON-RPC payload), or null on empty/garbage.
  Object? _tryDecode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> || decoded is List<dynamic>
          ? decoded
          : null;
    } on FormatException {
      return null;
    }
  }

  /// Drains a streamed [ResponseBody] to a UTF-8 string.
  Future<String> _drain(ResponseBody? body) async {
    if (body == null) return '';
    final bytes = <int>[];
    await body.stream.forEach(bytes.addAll);
    return utf8.decode(bytes, allowMalformed: true);
  }
}
