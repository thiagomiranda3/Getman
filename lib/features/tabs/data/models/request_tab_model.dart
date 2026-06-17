import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/tabs/data/models/stored_response_model.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

part 'request_tab_model.g.dart';

@HiveType(typeId: 2)
class HttpRequestTabModel extends HiveObject {
  HttpRequestTabModel({
    required this.config,
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
    this.isSending = false,
    this.collectionNodeId,
    this.collectionName,
    String? tabId,
    this.responseHistory,
  }) : tabId = tabId ?? const Uuid().v4();

  factory HttpRequestTabModel.fromEntity(HttpRequestTabEntity entity) =>
      HttpRequestTabModel(
        config: HttpRequestConfig.fromEntity(entity.config),
        responseBody: entity.response?.body,
        responseHeaders: entity.response?.headers,
        statusCode: entity.response?.statusCode,
        durationMs: entity.response?.durationMs,
        isSending: entity.isSending,
        collectionNodeId: entity.collectionNodeId,
        collectionName: entity.collectionName,
        tabId: entity.tabId,
        responseHistory: entity.responseHistory
            .map(StoredResponseModel.fromEntity)
            .toList(),
      );
  @HiveField(0)
  HttpRequestConfig config;

  @HiveField(1)
  String? responseBody;

  @HiveField(2)
  Map<String, String>? responseHeaders;

  @HiveField(3)
  int? statusCode;

  @HiveField(4)
  int? durationMs;

  @HiveField(5)
  bool isSending;

  @HiveField(6)
  String? collectionNodeId;

  @HiveField(7)
  String? collectionName;

  @HiveField(8)
  String tabId;

  /// Time-travel history, newest-first. Null on tabs persisted before this
  /// field existed (treated as empty). The currently-displayed response is
  /// stored flat (fields 1–4); this list is the rest of the recent sends.
  @HiveField(9)
  List<StoredResponseModel>? responseHistory;

  HttpRequestTabEntity toEntity() => HttpRequestTabEntity(
    config: config.toEntity(),
    // The Hive layout keeps the four response columns flat (typeId 2 is
    // load-bearing); statusCode is the discriminator for "a response exists".
    response: statusCode == null
        ? null
        : HttpResponseEntity(
            statusCode: statusCode!,
            body: responseBody ?? '',
            headers: responseHeaders ?? const {},
            durationMs: durationMs ?? 0,
          ),
    isSending: isSending,
    collectionNodeId: collectionNodeId,
    collectionName: collectionName,
    tabId: tabId,
    responseHistory:
        responseHistory?.map((m) => m.toEntity()).toList() ?? const [],
  );
}
