// McpBloc state: per-tab MCP session map. See McpTabSession class doc below
// for what one tab's session carries. copyWith uses an internal sentinel
// (like request_tab_entity.dart) so callers can explicitly clear
// lastResult/errorMessage back to null vs. leaving them unchanged — the old
// always-replace semantics silently wiped the displayed result on every
// McpToolSelected.

import 'package:equatable/equatable.dart';
import 'package:getman/features/mcp/domain/entities/mcp_session.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';

// Sentinel used by copyWith to distinguish "not provided" from "explicitly
// null".
const Object _unset = Object();

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

  /// [lastResult] and [errorMessage] use the `_unset` sentinel: omit to keep
  /// the current value, pass `null` to clear explicitly. All other fields are
  /// plain keep-if-null.
  McpTabSession copyWith({
    McpConnectionStatus? status,
    McpSession? session,
    List<McpTool>? tools,
    String? selectedTool,
    Object? lastResult = _unset,
    bool? calling,
    Object? errorMessage = _unset,
    List<String>? log,
  }) => McpTabSession(
    status: status ?? this.status,
    session: session ?? this.session,
    tools: tools ?? this.tools,
    selectedTool: selectedTool ?? this.selectedTool,
    lastResult: identical(lastResult, _unset)
        ? this.lastResult
        : lastResult as McpToolResult?,
    calling: calling ?? this.calling,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
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

  /// Drops [tabId]'s session entirely (tab closed — nothing left to show).
  McpState without(String tabId) {
    final next = Map<String, McpTabSession>.of(sessions)..remove(tabId);
    return McpState(sessions: next);
  }

  @override
  List<Object?> get props => [sessions];
}
