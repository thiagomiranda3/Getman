import 'package:equatable/equatable.dart';

abstract class McpEvent extends Equatable {
  const McpEvent();
  @override
  List<Object?> get props => [];
}

class McpConnectRequested extends McpEvent {
  const McpConnectRequested({
    required this.tabId,
    required this.url,
    this.headers = const {},
  });
  final String tabId;
  final String url;
  final Map<String, String> headers;
  @override
  List<Object?> get props => [tabId, url, headers];
}

class McpDisconnectRequested extends McpEvent {
  const McpDisconnectRequested(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

class McpToolSelected extends McpEvent {
  const McpToolSelected({required this.tabId, required this.toolName});
  final String tabId;
  final String toolName;
  @override
  List<Object?> get props => [tabId, toolName];
}

class McpToolCallRequested extends McpEvent {
  const McpToolCallRequested({
    required this.tabId,
    required this.toolName,
    required this.arguments,
  });
  final String tabId;
  final String toolName;
  final Map<String, dynamic> arguments;
  @override
  List<Object?> get props => [tabId, toolName, arguments];
}
