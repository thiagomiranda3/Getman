import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
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

  // Equality deliberately considers only the request signature — method, url,
  // and body — ignoring `id` and response fields. This is the contract history
  // dedup relies on: identical requests with different generated UUIDs (or
  // differing captured responses) collapse to a single entry. See CLAUDE.md §6.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HttpRequestConfig &&
        other.method == method &&
        other.url == url &&
        other.body == body;
  }

  @override
  int get hashCode => Object.hash(method, url, body);
}
