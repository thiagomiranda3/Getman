import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';

/// Owns live WebSocket/SSE connections per tab and their message logs. Mirrors
/// the TabsBloc request-manager teardown discipline: every connection is closed
/// on disconnect, on a new connect for the same tab, and on bloc close.
class RealtimeBloc extends Bloc<RealtimeEvent, RealtimeState> {
  final RealtimeService service;

  static const int _maxFrames = 500;

  final Map<String, RealtimeConnection> _connections = {};
  final Map<String, StreamSubscription<RealtimeFrame>> _subs = {};

  RealtimeBloc({required this.service}) : super(const RealtimeState()) {
    on<Connect>(_onConnect);
    on<SendRealtimeMessage>(_onSend);
    on<Disconnect>(_onDisconnect);
    on<FrameReceived>(_onFrame);
  }

  Future<void> _onConnect(Connect event, Emitter<RealtimeState> emit) async {
    await _teardown(event.tabId);
    final conn = event.kind == RequestKind.sse
        ? service.connectSse(event.url, headers: event.headers)
        : service.connectWebSocket(event.url);
    _connections[event.tabId] = conn;
    _subs[event.tabId] = conn.frames.listen((f) => add(FrameReceived(event.tabId, f)));
    emit(state.withSession(event.tabId, const RealtimeSession(connected: true, frames: [])));
  }

  void _onSend(SendRealtimeMessage event, Emitter<RealtimeState> emit) {
    _connections[event.tabId]?.send(event.text);
  }

  Future<void> _onDisconnect(Disconnect event, Emitter<RealtimeState> emit) async {
    await _teardown(event.tabId);
    final session = state.sessionFor(event.tabId);
    emit(state.withSession(event.tabId, session.copyWith(connected: false)));
  }

  void _onFrame(FrameReceived event, Emitter<RealtimeState> emit) {
    final session = state.sessionFor(event.tabId);
    final frames = [...session.frames, event.frame];
    final capped =
        frames.length > _maxFrames ? frames.sublist(frames.length - _maxFrames) : frames;
    final connected = switch (event.frame.direction) {
      RealtimeDirection.open ||
      RealtimeDirection.incoming ||
      RealtimeDirection.outgoing =>
        true,
      RealtimeDirection.close || RealtimeDirection.error => false,
    };
    emit(state.withSession(event.tabId, RealtimeSession(connected: connected, frames: capped)));
  }

  Future<void> _teardown(String tabId) async {
    await _subs.remove(tabId)?.cancel();
    await _connections.remove(tabId)?.close();
  }

  @override
  Future<void> close() async {
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    for (final conn in _connections.values) {
      await conn.close();
    }
    _subs.clear();
    _connections.clear();
    return super.close();
  }
}
