import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import '../../../../core/domain/entities/request_config_entity.dart';

part 'request_config_model.g.dart';

@HiveType(typeId: 1)
class HttpRequestConfig extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1, defaultValue: 'GET')
  String method;

  @HiveField(2, defaultValue: '')
  String url;

  @HiveField(3)
  Map<String, String> headers;

  @HiveField(4)
  Map<String, String> params;

  @HiveField(5, defaultValue: '')
  String body;

  @HiveField(6)
  Map<String, String> auth;

  @HiveField(7)
  String? responseBody;

  @HiveField(8)
  Map<String, String>? responseHeaders;

  @HiveField(9)
  int? statusCode;

  @HiveField(10)
  int? durationMs;

  HttpRequestConfig({
    String? id,
    this.method = 'GET',
    this.url = '',
    Map<String, String>? headers,
    Map<String, String>? params,
    this.body = '',
    Map<String, String>? auth,
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
  })  : id = id ?? const Uuid().v4(),
        headers = headers ??
            {
              'Content-Type': 'application/json',
              'Accept': '*/*',
            },
        params = params ?? {},
        auth = auth ?? {};

  HttpRequestConfig copyWith({
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
    return HttpRequestConfig(
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'url': url,
    'headers': headers,
    'params': params,
    'body': body,
    'auth': auth,
    'responseBody': responseBody,
    'responseHeaders': responseHeaders,
    'statusCode': statusCode,
    'durationMs': durationMs,
  };

  factory HttpRequestConfig.fromJson(Map<String, dynamic> json) => HttpRequestConfig(
    id: json['id'],
    method: json['method'] ?? 'GET',
    url: json['url'] ?? '',
    headers: Map<String, String>.from(json['headers'] ?? {}),
    params: Map<String, String>.from(json['params'] ?? {}),
    body: json['body'] ?? '',
    auth: Map<String, String>.from(json['auth'] ?? {}),
    responseBody: json['responseBody'],
    responseHeaders: json['responseHeaders'] != null 
        ? Map<String, String>.from(json['responseHeaders']) 
        : null,
    statusCode: json['statusCode'],
    durationMs: json['durationMs'],
  );

  factory HttpRequestConfig.fromEntity(HttpRequestConfigEntity entity) => HttpRequestConfig(
    id: entity.id,
    method: entity.method,
    url: entity.url,
    headers: entity.headers,
    params: entity.params,
    body: entity.body,
    auth: entity.auth,
    responseBody: entity.responseBody,
    responseHeaders: entity.responseHeaders,
    statusCode: entity.statusCode,
    durationMs: entity.durationMs,
  );

  HttpRequestConfigEntity toEntity() => HttpRequestConfigEntity(
    id: id,
    method: method,
    url: url,
    headers: headers,
    params: params,
    body: body,
    auth: auth,
    responseBody: responseBody,
    responseHeaders: responseHeaders,
    statusCode: statusCode,
    durationMs: durationMs,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HttpRequestConfig) return false;

    const mapEquality = MapEquality<String, String>();
    return other.method == method &&
        other.url == url &&
        mapEquality.equals(other.headers, headers) &&
        mapEquality.equals(other.params, params) &&
        other.body == body &&
        mapEquality.equals(other.auth, auth) &&
        other.responseBody == responseBody &&
        mapEquality.equals(other.responseHeaders, responseHeaders) &&
        other.statusCode == statusCode &&
        other.durationMs == durationMs;
  }

  @override
  int get hashCode {
    const mapEquality = MapEquality<String, String>();
    return method.hashCode ^
        url.hashCode ^
        mapEquality.hash(headers) ^
        mapEquality.hash(params) ^
        body.hashCode ^
        mapEquality.hash(auth) ^
        responseBody.hashCode ^
        mapEquality.hash(responseHeaders ?? {}) ^
        statusCode.hashCode ^
        durationMs.hashCode;
  }
}
