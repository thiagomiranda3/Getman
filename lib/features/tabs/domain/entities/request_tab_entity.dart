// Domain entity for one request tab: request config, the currently displayed
// response (null = nothing sent, or the last send was cancelled), isSending,
// time-travel responseHistory, and viewedHistoryEntryId (which history entry
// the response was time-travelled to; null = viewing the latest — view state,
// never persisted). copyWith uses an internal sentinel so callers can
// explicitly clear response/collectionNodeId/collectionName/
// viewedHistoryEntryId back to null (vs. leaving them unchanged).
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';

// Sentinel used by copyWith to distinguish "not provided" from "explicitly
// null".
const Object _unset = Object();

extension HttpRequestTabLookup on Iterable<HttpRequestTabEntity> {
  /// Shorthand for `firstWhereOrNull((t) => t.tabId == id)`.
  /// All tab addressing is by `tabId`, not list position (see
  /// docs/architecture/tabs-and-panels.md).
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
    this.executionId,
    this.scriptExecutionPhase = ScriptExecutionPhase.idle,
    this.scriptExecutionResult,
    this.scriptSecretValues = const {},
    this.isSending = false,
    this.collectionNodeId,
    this.collectionName,
    this.responseHistory = const [],
    this.viewedHistoryEntryId,
  });
  final HttpRequestConfigEntity config;

  /// Currently displayed response on this tab, or null when nothing has been
  /// sent (or the last send was cancelled before completing). Defaults to the
  /// newest send; time-travel (`ViewResponseHistoryEntry`) swaps it to an older
  /// [responseHistory] entry without mutating the history.
  final HttpResponseEntity? response;
  final bool isSending;
  final String? executionId;
  final ScriptExecutionPhase scriptExecutionPhase;
  final ExecuteRequestResult? scriptExecutionResult;
  final Set<String> scriptSecretValues;
  final String? collectionNodeId;
  final String? collectionName;
  final String tabId;

  /// Recent responses for time-travel, newest-first. Capped to the user's
  /// `responseHistoryLimit`. The head mirrors [response] after a fresh send.
  final List<ResponseHistoryEntry> responseHistory;

  /// Id of the [responseHistory] entry currently displayed via time-travel;
  /// null = viewing the latest response. Identity (not response value) is
  /// what the timeline highlights and what keeps a time-travel emission from
  /// being suppressed when two history entries hold value-equal responses.
  /// Pure view state — deliberately NOT persisted (the Hive model maps its
  /// fields explicitly and omits it, so a restored tab opens on the latest
  /// response).
  final String? viewedHistoryEntryId;

  HttpRequestTabEntity copyWith({
    HttpRequestConfigEntity? config,
    Object? response = _unset,
    bool? isSending,
    Object? executionId = _unset,
    ScriptExecutionPhase? scriptExecutionPhase,
    Object? scriptExecutionResult = _unset,
    Set<String>? scriptSecretValues,
    Object? collectionNodeId = _unset,
    Object? collectionName = _unset,
    String? tabId,
    List<ResponseHistoryEntry>? responseHistory,
    Object? viewedHistoryEntryId = _unset,
  }) {
    return HttpRequestTabEntity(
      config: config ?? this.config,
      response: identical(response, _unset)
          ? this.response
          : response as HttpResponseEntity?,
      isSending: isSending ?? this.isSending,
      executionId: identical(executionId, _unset)
          ? this.executionId
          : executionId as String?,
      scriptExecutionPhase: scriptExecutionPhase ?? this.scriptExecutionPhase,
      scriptSecretValues: scriptSecretValues ?? this.scriptSecretValues,
      scriptExecutionResult: identical(scriptExecutionResult, _unset)
          ? this.scriptExecutionResult
          : scriptExecutionResult as ExecuteRequestResult?,
      collectionNodeId: identical(collectionNodeId, _unset)
          ? this.collectionNodeId
          : collectionNodeId as String?,
      collectionName: identical(collectionName, _unset)
          ? this.collectionName
          : collectionName as String?,
      tabId: tabId ?? this.tabId,
      responseHistory: responseHistory ?? this.responseHistory,
      viewedHistoryEntryId: identical(viewedHistoryEntryId, _unset)
          ? this.viewedHistoryEntryId
          : viewedHistoryEntryId as String?,
    );
  }

  @override
  List<Object?> get props => [
    config,
    response,
    isSending,
    executionId,
    scriptExecutionPhase,
    scriptExecutionResult,
    scriptSecretValues,
    collectionNodeId,
    collectionName,
    tabId,
    responseHistory,
    viewedHistoryEntryId,
  ];
}
