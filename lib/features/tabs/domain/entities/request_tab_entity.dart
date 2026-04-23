import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/domain/entities/request_config_entity.dart';

// Sentinel used by copyWith to distinguish "not provided" from "explicitly null".
const Object _unset = Object();

extension HttpRequestTabLookup on Iterable<HttpRequestTabEntity> {
  /// Shorthand for `firstWhereOrNull((t) => t.tabId == id)`.
  /// All tab addressing is by `tabId`, not list position (see CLAUDE.md §4.2).
  HttpRequestTabEntity? byId(String id) => firstWhereOrNull((t) => t.tabId == id);
}

class HttpRequestTabEntity extends Equatable {
  final HttpRequestConfigEntity config;
  final String? responseBody;
  final Map<String, String>? responseHeaders;
  final int? statusCode;
  final int? durationMs;
  final bool isSending;
  final String? collectionNodeId;
  final String? collectionName;
  final String tabId;

  const HttpRequestTabEntity({
    required this.config,
    required this.tabId,
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
    this.isSending = false,
    this.collectionNodeId,
    this.collectionName,
  });

  HttpRequestTabEntity copyWith({
    HttpRequestConfigEntity? config,
    Object? responseBody = _unset,
    Object? responseHeaders = _unset,
    Object? statusCode = _unset,
    Object? durationMs = _unset,
    bool? isSending,
    Object? collectionNodeId = _unset,
    Object? collectionName = _unset,
    String? tabId,
  }) {
    return HttpRequestTabEntity(
      config: config ?? this.config,
      responseBody: identical(responseBody, _unset) ? this.responseBody : responseBody as String?,
      responseHeaders: identical(responseHeaders, _unset)
          ? this.responseHeaders
          : responseHeaders as Map<String, String>?,
      statusCode: identical(statusCode, _unset) ? this.statusCode : statusCode as int?,
      durationMs: identical(durationMs, _unset) ? this.durationMs : durationMs as int?,
      isSending: isSending ?? this.isSending,
      collectionNodeId: identical(collectionNodeId, _unset)
          ? this.collectionNodeId
          : collectionNodeId as String?,
      collectionName: identical(collectionName, _unset)
          ? this.collectionName
          : collectionName as String?,
      tabId: tabId ?? this.tabId,
    );
  }

  @override
  List<Object?> get props => [
    config,
    responseBody,
    responseHeaders,
    statusCode,
    durationMs,
    isSending,
    collectionNodeId,
    collectionName,
    tabId,
  ];
}
