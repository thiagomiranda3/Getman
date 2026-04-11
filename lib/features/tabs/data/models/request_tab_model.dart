import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
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

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'responseBody': responseBody,
    'responseHeaders': responseHeaders,
    'statusCode': statusCode,
    'durationMs': durationMs,
    'collectionNodeId': collectionNodeId,
    'collectionName': collectionName,
    'tabId': tabId,
  };

  factory HttpRequestTabModel.fromJson(Map<String, dynamic> json) => HttpRequestTabModel(
    config: HttpRequestConfig.fromJson(json['config']),
    responseBody: json['responseBody'],
    responseHeaders: json['responseHeaders'] != null 
        ? Map<String, String>.from(json['responseHeaders']) 
        : null,
    statusCode: json['statusCode'],
    durationMs: json['durationMs'],
    collectionNodeId: json['collectionNodeId'],
    collectionName: json['collectionName'],
    tabId: json['tabId'],
  );

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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HttpRequestTabModel) return false;

    return other.tabId == tabId &&
        other.config == config &&
        other.responseBody == responseBody &&
        const MapEquality<String, String>().equals(other.responseHeaders, responseHeaders) &&
        other.statusCode == statusCode &&
        other.durationMs == durationMs &&
        other.isSending == isSending &&
        other.collectionNodeId == collectionNodeId &&
        other.collectionName == collectionName;
  }

  @override
  int get hashCode {
    return tabId.hashCode ^
        config.hashCode ^
        responseBody.hashCode ^
        const MapEquality<String, String>().hash(responseHeaders ?? {}) ^
        statusCode.hashCode ^
        durationMs.hashCode ^
        isSending.hashCode ^
        collectionNodeId.hashCode ^
        collectionName.hashCode;
  }
}
