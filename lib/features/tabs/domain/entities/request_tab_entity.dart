import 'package:equatable/equatable.dart';
import '../../../../core/domain/entities/request_config_entity.dart';

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
    String? responseBody,
    Map<String, String>? responseHeaders,
    int? statusCode,
    int? durationMs,
    bool? isSending,
    String? collectionNodeId,
    String? collectionName,
    String? tabId,
  }) {
    return HttpRequestTabEntity(
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
