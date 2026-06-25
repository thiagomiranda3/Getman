import 'dart:async';
import 'dart:convert';

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
    if (error is Map<String, dynamic>) {
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
    // In real Dio (streaming), Content-Type appears in both Response.headers
    // and ResponseBody.headers. In tests, only one side may be set.
    final headerValues =
        response.headers.map[Headers.contentTypeHeader] ??
        body.headers[Headers.contentTypeHeader] ??
        const <String>[];
    final contentType =
        headerValues.isNotEmpty ? headerValues.first : '';

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
    await body.stream.forEach(bytes.addAll);
    return utf8.decode(bytes, allowMalformed: true);
  }
}
