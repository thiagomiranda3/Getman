import 'package:equatable/equatable.dart';

import '../../utils/url_query_utils.dart';
import 'query_param_entity.dart';

// Sentinel used by copyWith to distinguish "not provided" from "explicitly null".
const Object _unset = Object();

class HttpRequestConfigEntity extends Equatable {
  final String id;
  final String method;
  final String url;
  final Map<String, String> headers;
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
    this.body = '',
    this.auth = const {},
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
  });

  /// Derived view of the query params embedded in [url]. URL is the single
  /// source of truth — params are never stored separately. Duplicates are
  /// preserved in order.
  List<QueryParamEntity> get params => UrlQueryUtils.parseQuery(url);

  /// Rebuilds the entity. If [url] is supplied it wins. Otherwise, if [params]
  /// is supplied, the current URL's query portion is rewritten to match.
  HttpRequestConfigEntity copyWith({
    String? method,
    String? url,
    Map<String, String>? headers,
    List<QueryParamEntity>? params,
    String? body,
    Map<String, String>? auth,
    Object? responseBody = _unset,
    Object? responseHeaders = _unset,
    Object? statusCode = _unset,
    Object? durationMs = _unset,
  }) {
    final resolvedUrl = url ??
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
      responseBody: identical(responseBody, _unset) ? this.responseBody : responseBody as String?,
      responseHeaders: identical(responseHeaders, _unset)
          ? this.responseHeaders
          : responseHeaders as Map<String, String>?,
      statusCode: identical(statusCode, _unset) ? this.statusCode : statusCode as int?,
      durationMs: identical(durationMs, _unset) ? this.durationMs : durationMs as int?,
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
    responseBody,
    responseHeaders,
    statusCode,
    durationMs,
  ];
}
