import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';

// Sentinel used by copyWith to distinguish "not provided" from "explicitly null".
const Object _unset = Object();

extension HttpRequestTabLookup on Iterable<HttpRequestTabEntity> {
  /// Shorthand for `firstWhereOrNull((t) => t.tabId == id)`.
  /// All tab addressing is by `tabId`, not list position (see CLAUDE.md §4.2).
  HttpRequestTabEntity? byId(String id) => firstWhereOrNull((t) => t.tabId == id);
}

extension HttpRequestTabDisplay on HttpRequestTabEntity {
  /// Title shown in the tab strip, switcher sheet, and phone tab chip.
  String get displayTitle =>
      collectionName ?? (config.url.isEmpty ? 'NEW REQUEST' : config.url);
}

class HttpRequestTabEntity extends Equatable {
  final HttpRequestConfigEntity config;

  /// Last response received on this tab, or null when nothing has been sent
  /// (or the last send was cancelled before completing).
  final HttpResponseEntity? response;
  final bool isSending;
  final String? collectionNodeId;
  final String? collectionName;
  final String tabId;

  const HttpRequestTabEntity({
    required this.config,
    required this.tabId,
    this.response,
    this.isSending = false,
    this.collectionNodeId,
    this.collectionName,
  });

  HttpRequestTabEntity copyWith({
    HttpRequestConfigEntity? config,
    Object? response = _unset,
    bool? isSending,
    Object? collectionNodeId = _unset,
    Object? collectionName = _unset,
    String? tabId,
  }) {
    return HttpRequestTabEntity(
      config: config ?? this.config,
      response: identical(response, _unset) ? this.response : response as HttpResponseEntity?,
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
    response,
    isSending,
    collectionNodeId,
    collectionName,
    tabId,
  ];
}
