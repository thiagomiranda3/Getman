// MCP bloc: see class doc below for the per-tab connection ownership and
// teardown discipline (mirrors RealtimeBloc).

import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';

/// Owns one live [McpConnection] per tab and its derived state. Mirrors
/// RealtimeBloc's teardown discipline: a connection is closed on disconnect, on
/// reconnect for the same tab, and on bloc close. A per-tab epoch counter
/// (bumped by every teardown) makes in-flight connects and tool calls from a
/// superseded generation bail instead of emitting a ghost session for a tab
/// that was already torn down.
class McpBloc extends Bloc<McpEvent, McpState> {
  McpBloc({required this._service}) : super(const McpState()) {
    on<McpConnectRequested>(_onConnect);
    on<McpDisconnectRequested>(_onDisconnect);
    on<McpTabsClosed>(_onTabsClosed);
    on<McpToolSelected>(_onToolSelected);
    on<McpToolCallRequested>(_onCallTool);
  }

  final McpService _service;
  final Map<String, McpConnection> _connections = {};

  /// Per-tab teardown generation. Every [_teardown] bumps it (synchronously,
  /// before its awaits); an in-flight connect or tool call that captured an
  /// older value bails after its awaits instead of emitting a ghost session
  /// for a tab that [McpTabsClosed]/disconnect/reconnect already tore down.
  final Map<String, int> _epochs = {};

  int _epochOf(String tabId) => _epochs[tabId] ?? 0;

  Future<void> _onConnect(
    McpConnectRequested event,
    Emitter<McpState> emit,
  ) async {
    // _teardown bumps the tab's epoch in its synchronous prologue; capture
    // the post-bump value BEFORE awaiting, so any interleaved teardown
    // (second connect, disconnect, tab close) bumps past us and the
    // staleness checks below catch it.
    final teardown = _teardown(event.tabId);
    final epoch = _epochOf(event.tabId);
    await teardown;
    if (isClosed || _epochOf(event.tabId) != epoch) return;
    emit(
      state.withSession(
        event.tabId,
        const McpTabSession(status: McpConnectionStatus.connecting),
      ),
    );
    try {
      final conn = await _service.connect(event.url, headers: event.headers);
      if (isClosed || _epochOf(event.tabId) != epoch) {
        // Superseded while the handshake was in flight — the bloc closed, or
        // the TAB closed/disconnected/reconnected (the old isClosed-only
        // guard covered just the first case and let a ghost session be
        // emitted after McpTabsClosed tore the tab down). The connection was
        // never stored, so close it here or it leaks.
        await conn.close();
        return;
      }
      _connections[event.tabId] = conn;
      final tools = await conn.listTools();
      if (isClosed || _epochOf(event.tabId) != epoch) {
        // The conn WAS stored before listTools, so whichever teardown bumped
        // the epoch (or bloc close) already removed and closed it — just
        // don't emit for the dead generation.
        return;
      }
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
      if (isClosed || _epochOf(event.tabId) != epoch) return;
      // listTools may have failed AFTER the conn was stored — tear it down.
      // Our own teardown bumps the epoch, so re-capture the post-bump value
      // for the final staleness check (a connect interleaving with this
      // cleanup must not have its fresh session clobbered by our error).
      final cleanup = _teardown(event.tabId);
      final cleanupEpoch = _epochOf(event.tabId);
      await cleanup;
      if (isClosed || _epochOf(event.tabId) != cleanupEpoch) return;
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
    final teardown = _teardown(event.tabId);
    final epoch = _epochOf(event.tabId);
    await teardown;
    // A reconnect/tab close that interleaved with the close() await owns the
    // session now — emitting the reset here would clobber it.
    if (isClosed || _epochOf(event.tabId) != epoch) return;
    emit(
      state.withSession(
        event.tabId,
        const McpTabSession(),
      ),
    );
  }

  /// Closed tabs: tear down their connections AND drop their session entries
  /// — a session for a tab that no longer exists is unreachable state.
  Future<void> _onTabsClosed(
    McpTabsClosed event,
    Emitter<McpState> emit,
  ) async {
    for (final tabId in event.tabIds) {
      await _teardown(tabId);
      // The tab is gone for good — drop its epoch entry too. Safe: any stale
      // in-flight connect/call captured a post-bump value (>= 1), which can
      // never compare equal to the 0 an absent entry reads as.
      _epochs.remove(tabId);
    }
    // Fold over the LIVE state only after every teardown await: a snapshot
    // taken before the awaits would clobber anything another handler emitted
    // while the teardowns were in flight (e.g. a tool call completing for a
    // different tab).
    var next = state;
    for (final tabId in event.tabIds) {
      next = next.without(tabId);
    }
    if (next != state) emit(next);
  }

  void _onToolSelected(McpToolSelected event, Emitter<McpState> emit) {
    final s = state.sessionFor(event.tabId);
    // Re-tapping the already-selected tool chip must NOT wipe the displayed
    // result (the old always-replace copyWith cleared it on every select). A
    // CHANGE of tool does clear lastResult + errorMessage: both describe the
    // previously selected tool's call, and keeping them under a different
    // tool's argument form would misattribute the output.
    final toolChanged = s.selectedTool != event.toolName;
    emit(
      state.withSession(
        event.tabId,
        toolChanged
            ? s.copyWith(
                selectedTool: event.toolName,
                lastResult: null,
                errorMessage: null,
              )
            : s.copyWith(selectedTool: event.toolName),
      ),
    );
  }

  Future<void> _onCallTool(
    McpToolCallRequested event,
    Emitter<McpState> emit,
  ) async {
    final conn = _connections[event.tabId];
    if (conn == null) return;
    // Every teardown (disconnect, tab close, reconnect) bumps the epoch, so
    // a result landing after any of them compares stale — this subsumes the
    // old identical(_connections[tabId], conn) guard; isClosed covers the
    // bloc-close path (close() drains the map without bumping).
    final epoch = _epochOf(event.tabId);
    final base = state.sessionFor(event.tabId);
    emit(
      state.withSession(
        event.tabId,
        // errorMessage: null — a fresh call clears the previous call's error
        // explicitly (sentinel copyWith keeps it otherwise); lastResult stays
        // visible until the new result replaces it.
        base.copyWith(
          calling: true,
          selectedTool: event.toolName,
          errorMessage: null,
        ),
      ),
    );
    try {
      final result = await conn.callTool(event.toolName, event.arguments);
      // The tab may have closed/disconnected/reconnected while the call was
      // in flight — emitting then would resurrect a session for a dead tab
      // (or clobber a deliberate disconnect reset).
      if (isClosed || _epochOf(event.tabId) != epoch) return;
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
      // Same staleness guard as the success path: a torn-down connection's
      // failure must not resurrect or overwrite the tab's session.
      if (isClosed || _epochOf(event.tabId) != epoch) return;
      final after = state.sessionFor(event.tabId);
      emit(
        state.withSession(
          event.tabId,
          after.copyWith(
            calling: false,
            errorMessage: e.toString(),
            log: [...after.log, 'Call failed: $e'],
          ),
        ),
      );
    }
  }

  /// Closes and forgets [tabId]'s connection. Bumps the tab's epoch FIRST and
  /// synchronously (an async body runs to its first await): callers capture
  /// the post-bump value before awaiting, and every in-flight connect/call
  /// holding an older epoch bails instead of emitting for a dead generation.
  Future<void> _teardown(String tabId) async {
    _epochs[tabId] = _epochOf(tabId) + 1;
    await _connections.remove(tabId)?.close();
  }

  @override
  Future<void> close() async {
    // Snapshot + clear BEFORE awaiting: an in-flight _onConnect can resume
    // during the awaits and mutate the map mid-iteration
    // (ConcurrentModificationError) if we iterate _connections directly.
    final conns = [..._connections.values];
    _connections.clear();
    for (final conn in conns) {
      await conn.close();
    }
    return super.close();
  }
}
