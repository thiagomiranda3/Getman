import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';

/// Internal: a batch of frames buffered from a connection's stream within one
/// coalescing window, dispatched as a single event so a high-frequency stream
/// causes one state emission (and one list copy) per window instead of per
/// frame. Private to this file — never part of the public event API.
class _FramesBatchReceived extends RealtimeEvent {
  const _FramesBatchReceived(this.tabId, this.frames);
  final String tabId;
  final List<RealtimeFrame> frames;
  @override
  List<Object?> get props => [tabId, frames];
}

/// Owns live WebSocket/SSE connections per tab and their message logs. Mirrors
/// the TabsBloc request-manager teardown discipline: every connection is closed
/// on disconnect, on a new connect for the same tab, and on bloc close.
class RealtimeBloc extends Bloc<RealtimeEvent, RealtimeState> {
  RealtimeBloc({required RealtimeService service})
    : _service = service,
      super(const RealtimeState()) {
    on<Connect>(_onConnect);
    on<SendRealtimeMessage>(_onSend);
    on<Disconnect>(_onDisconnect);
    on<FrameReceived>(_onFrame);
    on<_FramesBatchReceived>(_onFramesBatch);
  }
  final RealtimeService _service;

  static const int _maxFrames = 500;

  /// Frames are coalesced over this window: an SSE/WebSocket firehose emits one
  /// state per window (~1 frame at 60 fps) rather than one per message.
  static const Duration _coalesceWindow = Duration(milliseconds: 16);

  final Map<String, RealtimeConnection> _connections = {};
  final Map<String, StreamSubscription<RealtimeFrame>> _subs = {};

  /// Per-tab frames awaiting their coalescing flush, and the timer that flushes
  /// them. Both are cleared on teardown so a closing connection can't emit.
  final Map<String, List<RealtimeFrame>> _pending = {};
  final Map<String, Timer> _flushTimers = {};

  Future<void> _onConnect(Connect event, Emitter<RealtimeState> emit) async {
    await _teardown(event.tabId);
    final conn = event.kind == RequestKind.sse
        ? _service.connectSse(event.url, headers: event.headers)
        : _service.connectWebSocket(event.url);
    _connections[event.tabId] = conn;
    _subs[event.tabId] = conn.frames.listen(
      (f) => _bufferFrame(event.tabId, f),
    );
    emit(
      state.withSession(event.tabId, const RealtimeSession(connected: true)),
    );
  }

  void _onSend(SendRealtimeMessage event, Emitter<RealtimeState> emit) {
    _connections[event.tabId]?.send(event.text);
  }

  Future<void> _onDisconnect(
    Disconnect event,
    Emitter<RealtimeState> emit,
  ) async {
    await _teardown(event.tabId);
    final session = state.sessionFor(event.tabId);
    emit(state.withSession(event.tabId, session.copyWith(connected: false)));
  }

  /// Buffers a stream frame and arms a single coalescing timer per tab. Frames
  /// arriving within [_coalesceWindow] flush together as one batch event.
  void _bufferFrame(String tabId, RealtimeFrame frame) {
    (_pending[tabId] ??= <RealtimeFrame>[]).add(frame);
    _flushTimers[tabId] ??= Timer(_coalesceWindow, () {
      _flushTimers.remove(tabId);
      final batch = _pending.remove(tabId);
      if (batch != null && batch.isNotEmpty) {
        add(_FramesBatchReceived(tabId, batch));
      }
    });
  }

  void _onFrame(FrameReceived event, Emitter<RealtimeState> emit) {
    _appendFrames(event.tabId, [event.frame], emit);
  }

  void _onFramesBatch(_FramesBatchReceived event, Emitter<RealtimeState> emit) {
    _appendFrames(event.tabId, event.frames, emit);
  }

  /// Appends [incoming] to the tab's log (one list copy), re-applies the
  /// [_maxFrames] cap, and derives `connected` from the last frame — matching
  /// the per-frame semantics applied sequentially.
  void _appendFrames(
    String tabId,
    List<RealtimeFrame> incoming,
    Emitter<RealtimeState> emit,
  ) {
    if (incoming.isEmpty) return;
    final session = state.sessionFor(tabId);
    final frames = [...session.frames, ...incoming];
    final capped = frames.length > _maxFrames
        ? frames.sublist(frames.length - _maxFrames)
        : frames;
    final connected = switch (incoming.last.direction) {
      RealtimeDirection.open ||
      RealtimeDirection.incoming ||
      RealtimeDirection.outgoing => true,
      RealtimeDirection.close || RealtimeDirection.error => false,
    };
    emit(
      state.withSession(
        tabId,
        RealtimeSession(connected: connected, frames: capped),
      ),
    );
  }

  Future<void> _teardown(String tabId) async {
    _flushTimers.remove(tabId)?.cancel();
    _pending.remove(tabId);
    await _subs.remove(tabId)?.cancel();
    await _connections.remove(tabId)?.close();
  }

  @override
  Future<void> close() async {
    for (final timer in _flushTimers.values) {
      timer.cancel();
    }
    _flushTimers.clear();
    _pending.clear();
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
