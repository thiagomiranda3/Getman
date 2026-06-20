import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/utils/url_query_utils.dart';

// Sentinel used by copyWith to distinguish "not provided" from "explicitly
// null".
const Object _unset = Object();

class HttpRequestConfigEntity extends Equatable {
  const HttpRequestConfigEntity({
    required this.id,
    this.method = 'GET',
    this.url = '',
    this.headers = const {
      'Content-Type': 'application/json',
      'Accept': '*/*',
    },
    this.body = '',
    this.auth = const {},
    this.bodyType = BodyType.raw,
    this.formFields = const [],
    this.bodyFilePath,
    this.graphqlVariables = '',
    this.kind = RequestKind.http,
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
  });
  final String id;
  final String method;
  final String url;
  final Map<String, String> headers;
  final String body;
  final Map<String, String> auth;

  /// How [body] / [formFields] / [bodyFilePath] are serialized at send time.
  final BodyType bodyType;

  /// Rows for `urlencoded` / `multipart` bodies. Empty for other body types.
  final List<MultipartFieldEntity> formFields;

  /// Filesystem path for a `binary` body (desktop/mobile only).
  final String? bodyFilePath;

  /// Variables JSON text for a `graphql` body. Empty for other body types.
  /// The query itself reuses [body].
  final String graphqlVariables;

  /// The protocol this request speaks (HTTP / WebSocket / SSE).
  final RequestKind kind;

  final String? responseBody;
  final Map<String, String>? responseHeaders;
  final int? statusCode;
  final int? durationMs;

  /// Derived view of the query params embedded in [url]. URL is the single
  /// source of truth — params are never stored separately. Duplicates are
  /// preserved in order.
  List<QueryParamEntity> get params => UrlQueryUtils.parseQuery(url);

  /// Type-safe view over the raw [auth] map. An empty map reads as
  /// [AuthType.none], so legacy records round-trip without migration.
  AuthConfig get authConfig => AuthConfig.fromMap(auth);

  /// Rebuilds the entity. If [url] is supplied it wins. Otherwise, if [params]
  /// is supplied, the current URL's query portion is rewritten to match.
  HttpRequestConfigEntity copyWith({
    String? method,
    String? url,
    Map<String, String>? headers,
    List<QueryParamEntity>? params,
    String? body,
    Map<String, String>? auth,
    BodyType? bodyType,
    List<MultipartFieldEntity>? formFields,
    Object? bodyFilePath = _unset,
    String? graphqlVariables,
    RequestKind? kind,
    Object? responseBody = _unset,
    Object? responseHeaders = _unset,
    Object? statusCode = _unset,
    Object? durationMs = _unset,
  }) {
    final resolvedUrl =
        url ??
        (params != null
            ? UrlQueryUtils.replaceQuery(this.url, params)
            : this.url);
    return HttpRequestConfigEntity(
      id: id,
      method: method ?? this.method,
      url: resolvedUrl,
      headers: headers ?? Map.from(this.headers),
      body: body ?? this.body,
      auth: auth ?? Map.from(this.auth),
      bodyType: bodyType ?? this.bodyType,
      formFields: formFields ?? this.formFields,
      bodyFilePath: identical(bodyFilePath, _unset)
          ? this.bodyFilePath
          : bodyFilePath as String?,
      graphqlVariables: graphqlVariables ?? this.graphqlVariables,
      kind: kind ?? this.kind,
      responseBody: identical(responseBody, _unset)
          ? this.responseBody
          : responseBody as String?,
      responseHeaders: identical(responseHeaders, _unset)
          ? this.responseHeaders
          : responseHeaders as Map<String, String>?,
      statusCode: identical(statusCode, _unset)
          ? this.statusCode
          : statusCode as int?,
      durationMs: identical(durationMs, _unset)
          ? this.durationMs
          : durationMs as int?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    method,
    url,
    headers,
    body,
    auth,
    bodyType,
    formFields,
    bodyFilePath,
    graphqlVariables,
    kind,
    responseBody,
    responseHeaders,
    statusCode,
    durationMs,
  ];
}
