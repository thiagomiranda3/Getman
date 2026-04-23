import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../../../features/history/data/models/request_config_model.dart';
import '../../domain/entities/request_tab_entity.dart';

part 'request_tab_model.g.dart';

@HiveType(typeId: 2)
class HttpRequestTabModel extends HiveObject {
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
  }) : tabId = tabId ?? const Uuid().v4();

  HttpRequestTabModel copyWith({
    HttpRequestConfig? config,
    String? responseBody,
    Map<String, String>? responseHeaders,
    int? statusCode,
    int? durationMs,
    bool? isSending,
    String? collectionNodeId,
    String? collectionName,
    String? tabId,
  }) {
    return HttpRequestTabModel(
      config: config ?? this.config,
      responseBody: responseBody ?? this.responseBody,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      statusCode: statusCode ?? this.statusCode,
      durationMs: durationMs ?? this.durationMs,
      isSending: isSending ?? this.isSending,
      collectionNodeId: collectionNodeId ?? this.collectionNodeId,
      collectionName: collectionName ?? this.collectionName,
      tabId: tabId ?? this.tabId,
    );
  }

  factory HttpRequestTabModel.fromEntity(HttpRequestTabEntity entity) => HttpRequestTabModel(
    config: HttpRequestConfig.fromEntity(entity.config),
    responseBody: entity.responseBody,
    responseHeaders: entity.responseHeaders,
    statusCode: entity.statusCode,
    durationMs: entity.durationMs,
    isSending: entity.isSending,
    collectionNodeId: entity.collectionNodeId,
    collectionName: entity.collectionName,
    tabId: entity.tabId,
  );

  HttpRequestTabEntity toEntity() => HttpRequestTabEntity(
    config: config.toEntity(),
    responseBody: responseBody,
    responseHeaders: responseHeaders,
    statusCode: statusCode,
    durationMs: durationMs,
    isSending: isSending,
    collectionNodeId: collectionNodeId,
    collectionName: collectionName,
    tabId: tabId,
  );
}
