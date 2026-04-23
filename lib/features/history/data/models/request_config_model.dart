import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/domain/entities/query_param_entity.dart';
import '../../../../core/domain/entities/request_config_entity.dart';
import '../../../../core/utils/url_query_utils.dart';

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

  // Legacy field retained for backward compat with pre-migration Hive data.
  // New records always write an empty map here; queries live inside [url].
  // See toEntity() for the one-time lazy migration.
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
    // URL carries the query now; stored params stays empty going forward.
    params: const {},
    body: entity.body,
    auth: entity.auth,
    responseBody: entity.responseBody,
    responseHeaders: entity.responseHeaders,
    statusCode: entity.statusCode,
    durationMs: entity.durationMs,
  );

  HttpRequestConfigEntity toEntity() {
    // Lazy migration: if a legacy record stored params in the separate map,
    // merge them into the URL's query string. Next save writes params back
    // as empty — this runs at most once per record.
    var entityUrl = url;
    if (params.isNotEmpty) {
      final legacy = params.entries
          .map((e) => QueryParamEntity(key: e.key, value: e.value))
          .toList(growable: false);
      entityUrl = UrlQueryUtils.replaceQuery(url, legacy);
    }
    return HttpRequestConfigEntity(
      id: id,
      method: method,
      url: entityUrl,
      headers: headers,
      body: body,
      auth: auth,
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      statusCode: statusCode,
      durationMs: durationMs,
    );
  }

  // Equality deliberately considers only the request signature — method, url,
  // and body — ignoring `id` and response fields. URL now carries the query
  // portion, so dedup distinguishes ?a=1 from ?a=2. See CLAUDE.md §6.
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
