import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/assertion_result.dart';
import 'package:getman/core/domain/entities/extraction_result.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';

// Sentinel used by copyWith to distinguish "not provided" from "explicitly
// null".
const Object _unset = Object();

extension HttpRequestTabLookup on Iterable<HttpRequestTabEntity> {
  /// Shorthand for `firstWhereOrNull((t) => t.tabId == id)`.
  /// All tab addressing is by `tabId`, not list position (see CLAUDE.md §4.2).
  HttpRequestTabEntity? byId(String id) =>
      firstWhereOrNull((t) => t.tabId == id);
}

extension HttpRequestTabDisplay on HttpRequestTabEntity {
  /// Title shown in the tab strip, switcher sheet, and phone tab chip.
  String get displayTitle =>
      collectionName ?? (config.url.isEmpty ? 'NEW REQUEST' : config.url);
}

class HttpRequestTabEntity extends Equatable {
  const HttpRequestTabEntity({
    required this.config,
    required this.tabId,
    this.response,
    this.isSending = false,
    this.collectionNodeId,
    this.collectionName,
    this.extractionResults = const [],
    this.assertionResults = const [],
    this.responseHistory = const [],
  });
  final HttpRequestConfigEntity config;

  /// Currently displayed response on this tab, or null when nothing has been
  /// sent (or the last send was cancelled before completing). Defaults to the
  /// newest send; time-travel (`ViewResponseHistoryEntry`) swaps it to an older
  /// [responseHistory] entry without mutating the history.
  final HttpResponseEntity? response;
  final bool isSending;
  final String? collectionNodeId;
  final String? collectionName;
  final String tabId;

  /// Transient results from the last send's extraction rules / assertions.
  /// Not persisted (recomputed on each send); excluded from the Hive model.
  final List<ExtractionResult> extractionResults;
  final List<AssertionResult> assertionResults;

  /// Recent responses for time-travel, newest-first. Capped to the user's
  /// `responseHistoryLimit`. The head mirrors [response] after a fresh send.
  final List<ResponseHistoryEntry> responseHistory;

  HttpRequestTabEntity copyWith({
    HttpRequestConfigEntity? config,
    Object? response = _unset,
    bool? isSending,
    Object? collectionNodeId = _unset,
    Object? collectionName = _unset,
    String? tabId,
    List<ExtractionResult>? extractionResults,
    List<AssertionResult>? assertionResults,
    List<ResponseHistoryEntry>? responseHistory,
  }) {
    return HttpRequestTabEntity(
      config: config ?? this.config,
      response: identical(response, _unset)
          ? this.response
          : response as HttpResponseEntity?,
      isSending: isSending ?? this.isSending,
      collectionNodeId: identical(collectionNodeId, _unset)
          ? this.collectionNodeId
          : collectionNodeId as String?,
      collectionName: identical(collectionName, _unset)
          ? this.collectionName
          : collectionName as String?,
      tabId: tabId ?? this.tabId,
      extractionResults: extractionResults ?? this.extractionResults,
      assertionResults: assertionResults ?? this.assertionResults,
      responseHistory: responseHistory ?? this.responseHistory,
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
    extractionResults,
    assertionResults,
    responseHistory,
  ];
}
