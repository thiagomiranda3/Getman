// MCP bloc: see class doc below for the per-tab connection ownership and
// teardown discipline (mirrors RealtimeBloc).

import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';

/// Owns one live [McpConnection] per tab and its derived state. Mirrors
/// RealtimeBloc's teardown discipline: a connection is closed on disconnect, on
/// reconnect for the same tab, and on bloc close.
class McpBloc extends Bloc<McpEvent, McpState> {
  McpBloc({required this._service}) : super(const McpState()) {
    on<McpConnectRequested>(_onConnect);
    on<McpDisconnectRequested>(_onDisconnect);
    on<McpToolSelected>(_onToolSelected);
    on<McpToolCallRequested>(_onCallTool);
  }

  final McpService _service;
  final Map<String, McpConnection> _connections = {};

  Future<void> _onConnect(
    McpConnectRequested event,
    Emitter<McpState> emit,
  ) async {
    await _teardown(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        const McpTabSession(status: McpConnectionStatus.connecting),
      ),
    );
    try {
      final conn = await _service.connect(event.url, headers: event.headers);
      _connections[event.tabId] = conn;
      final tools = await conn.listTools();
      final serverLabel =
          '${conn.session.serverName} (${conn.session.protocolVersion})';
      emit(
        state.withSession(
          event.tabId,
          McpTabSession(
            status: McpConnectionStatus.connected,
            session: conn.session,
            tools: tools,
            log: [
              'Connected to $serverLabel',
              'Listed ${tools.length} tool(s)',
            ],
          ),
        ),
      );
    } on Object catch (e) {
      log('MCP connect failed: $e', name: 'McpBloc');
      await _teardown(event.tabId);
      emit(
        state.withSession(
          event.tabId,
          McpTabSession(
            status: McpConnectionStatus.error,
            errorMessage: e.toString(),
            log: ['Connect failed: $e'],
          ),
        ),
      );
    }
  }

  Future<void> _onDisconnect(
    McpDisconnectRequested event,
    Emitter<McpState> emit,
  ) async {
    await _teardown(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        const McpTabSession(),
      ),
    );
  }

  void _onToolSelected(McpToolSelected event, Emitter<McpState> emit) {
    final s = state.sessionFor(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        s.copyWith(selectedTool: event.toolName),
      ),
    );
  }

  Future<void> _onCallTool(
    McpToolCallRequested event,
    Emitter<McpState> emit,
  ) async {
    final conn = _connections[event.tabId];
    if (conn == null) return;
    final base = state.sessionFor(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        base.copyWith(
          calling: true,
          selectedTool: event.toolName,
          lastResult: base.lastResult,
        ),
      ),
    );
    try {
      final result = await conn.callTool(event.toolName, event.arguments);
      final after = state.sessionFor(event.tabId);
      emit(
        state.withSession(
          event.tabId,
          after.copyWith(
            calling: false,
            lastResult: result,
            log: [...after.log, 'Called ${event.toolName}'],
          ),
        ),
      );
    } on Object catch (e) {
      log('MCP tool call failed: $e', name: 'McpBloc');
      final after = state.sessionFor(event.tabId);
      emit(
        state.withSession(
          event.tabId,
          after.copyWith(
            calling: false,
            errorMessage: e.toString(),
            log: [...after.log, 'Call failed: $e'],
            lastResult: after.lastResult,
          ),
        ),
      );
    }
  }

  Future<void> _teardown(String tabId) async {
    await _connections.remove(tabId)?.close();
  }

  @override
  Future<void> close() async {
    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();
    return super.close();
  }
}
