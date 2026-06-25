import 'package:equatable/equatable.dart';
import 'package:getman/features/mcp/domain/entities/mcp_session.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';

enum McpConnectionStatus { disconnected, connecting, connected, error }

/// The MCP state for one tab: connection status, server session, advertised
/// tools, the selected tool, the last call result, and a debug log of traffic.
class McpTabSession extends Equatable {
  const McpTabSession({
    this.status = McpConnectionStatus.disconnected,
    this.session,
    this.tools = const [],
    this.selectedTool,
    this.lastResult,
    this.calling = false,
    this.errorMessage,
    this.log = const [],
  });

  final McpConnectionStatus status;
  final McpSession? session;
  final List<McpTool> tools;
  final String? selectedTool;
  final McpToolResult? lastResult;
  final bool calling;
  final String? errorMessage;
  final List<String> log;

  McpTabSession copyWith({
    McpConnectionStatus? status,
    McpSession? session,
    List<McpTool>? tools,
    String? selectedTool,
    McpToolResult? lastResult,
    bool? calling,
    String? errorMessage,
    List<String>? log,
  }) => McpTabSession(
    status: status ?? this.status,
    session: session ?? this.session,
    tools: tools ?? this.tools,
    selectedTool: selectedTool ?? this.selectedTool,
    lastResult: lastResult,
    calling: calling ?? this.calling,
    errorMessage: errorMessage,
    log: log ?? this.log,
  );

  @override
  List<Object?> get props => [
    status,
    session,
    tools,
    selectedTool,
    lastResult,
    calling,
    errorMessage,
    log,
  ];
}

class McpState extends Equatable {
  const McpState({this.sessions = const {}});
  final Map<String, McpTabSession> sessions;

  McpTabSession sessionFor(String tabId) =>
      sessions[tabId] ?? const McpTabSession();

  McpState withSession(String tabId, McpTabSession session) =>
      McpState(sessions: {...sessions, tabId: session});

  @override
  List<Object?> get props => [sessions];
}
