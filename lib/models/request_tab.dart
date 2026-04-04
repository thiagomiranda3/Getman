import 'package:hive/hive.dart';
import 'request_config.dart';

part 'request_tab.g.dart';

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

  HttpRequestTabModel({
    required this.config,
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
    this.isSending = false,
    this.collectionNodeId,
    this.collectionName,
  });

  HttpRequestTabModel copyWith({
    HttpRequestConfig? config,
    String? responseBody,
    Map<String, String>? responseHeaders,
    int? statusCode,
    int? durationMs,
    bool? isSending,
    String? collectionNodeId,
    String? collectionName,
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
  );
}
