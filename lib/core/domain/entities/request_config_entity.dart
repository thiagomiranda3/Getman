import 'package:equatable/equatable.dart';

class HttpRequestConfigEntity extends Equatable {
  final String id;
  final String method;
  final String url;
  final Map<String, String> headers;
  final Map<String, String> params;
  final String body;
  final Map<String, String> auth;
  final String? responseBody;
  final Map<String, String>? responseHeaders;
  final int? statusCode;
  final int? durationMs;

  const HttpRequestConfigEntity({
    required this.id,
    this.method = 'GET',
    this.url = '',
    this.headers = const {
      'Content-Type': 'application/json',
      'Accept': '*/*',
    },
    this.params = const {},
    this.body = '',
    this.auth = const {},
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
  });

  HttpRequestConfigEntity copyWith({
    String? method,
    String? url,
    Map<String, String>? headers,
    Map<String, String>? params,
    String? body,
    Map<String, String>? auth,
    String? responseBody,
    Map<String, String>? responseHeaders,
    int? statusCode,
    int? durationMs,
  }) {
    return HttpRequestConfigEntity(
      id: id,
      method: method ?? this.method,
      url: url ?? this.url,
      headers: headers ?? Map.from(this.headers),
      params: params ?? Map.from(this.params),
      body: body ?? this.body,
      auth: auth ?? Map.from(this.auth),
      responseBody: responseBody ?? this.responseBody,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      statusCode: statusCode ?? this.statusCode,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  @override
  List<Object?> get props => [
    id,
    method,
    url,
    headers,
    params,
    body,
    auth,
    responseBody,
    responseHeaders,
    statusCode,
    durationMs,
  ];
}
