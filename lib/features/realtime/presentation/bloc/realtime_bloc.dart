// Realtime (WebSocket/SSE) bloc-over-service — no domain/data split by design
// (see CLAUDE.md's realtime feature note). Owns one live RealtimeConnection
// per tab; frames from each connection's stream are buffered and flushed as a
// single _FramesBatchReceived event per 16ms coalescing window so a
// high-frequency stream causes ~1 state emission per frame at 60fps instead of
// one per message. Connections are closed on disconnect, on reconnect for the
// same tab, and on bloc close (mirrors TabsBloc's request-manager teardown).
// A per-tab epoch counter (bumped by every teardown) makes in-flight connects
// and queued frame batches from a superseded generation bail instead of
// overwriting the live connection or resurrecting a dead session.

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
  const _FramesBatchReceived(this.tabId, this.frames, this.epoch);
  final String tabId;
  final List<RealtimeFrame> frames;

  /// The tab's epoch when this batch was flushed. `_onFramesBatch` drops the
  /// batch when a teardown bumped the epoch before it was processed — a stale
  /// batch would flip `connected` back on with no live connection (composer
  /// re-enabled, sends silently discarded) or inject dead frames into a
  /// fresh session.
  final int epoch;
  @override
  List<Object?> get props => [tabId, frames, epoch];
}

/// Owns live WebSocket/SSE connections per tab and their message logs. Mirrors
/// the TabsBloc request-manager teardown discipline: every connection is closed
/// on disconnect, on a new connect for the same tab, and on bloc close.
class RealtimeBloc extends Bloc<RealtimeEvent, RealtimeState> {
  RealtimeBloc({required this._service}) : super(const RealtimeState()) {
    on<Connect>(_onConnect);
    on<SendRealtimeMessage>(_onSend);
    on<Disconnect>(_onDisconnect);
    on<RealtimeTabsClosed>(_onTabsClosed);
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

  /// Per-tab teardown generation. Every [_teardown] bumps it (synchronously,
  /// before its awaits); an in-flight handler that captured an older value
  /// bails after its awaits instead of writing over newer state. This is what
  /// stops a slow first CONNECT from overwriting a second CONNECT's live
  /// connection in the maps (leaking its socket + subscription into the same
  /// log) and what lets [_onFramesBatch] drop batches queued before a
  /// teardown.
  final Map<String, int> _epochs = {};

  int _epochOf(String tabId) => _epochs[tabId] ?? 0;

  Future<void> _onConnect(Connect event, Emitter<RealtimeState> emit) async {
    // _teardown bumps the tab's epoch in its synchronous prologue; capture
    // the post-bump value BEFORE awaiting, so anything that interleaves with
    // the (potentially slow, real-network) close of the previous socket —
    // a second Connect, a Disconnect, RealtimeTabsClosed — bumps past us and
    // the staleness check below makes this handler bail instead of
    // overwriting the newer connection.
    final teardown = _teardown(event.tabId);
    final epoch = _epochOf(event.tabId);
    await teardown;
    if (isClosed || _epochOf(event.tabId) != epoch) return;
    final RealtimeConnection conn;
    try {
      conn = event.kind == RequestKind.sse
          ? _service.connectSse(event.url, headers: event.headers)
          : _service.connectWebSocket(
              _normalizeWsUrl(event.url),
              headers: event.headers,
            );
    } on Object catch (e) {
      // With any enabled header (the desktop path), a non-ws scheme — e.g. an
      // unresolved `{{base}}/ws` leaving an empty scheme — makes
      // IOWebSocketChannel.connect throw SYNCHRONOUSLY (dart:io's
      // WebSocket.connect validates outside its async body). Without this
      // catch the throw escaped to the zone and CONNECT visibly did nothing.
      // Surface it the way _appendFrames treats an error-direction frame:
      // an error entry in the log, session not connected.
      emit(
        state.withSession(
          event.tabId,
          RealtimeSession(frames: [RealtimeFrame.error(e.toString())]),
        ),
      );
      return;
    }
    _connections[event.tabId] = conn;
    _subs[event.tabId] = conn.frames.listen(
      (f) => _bufferFrame(event.tabId, f),
    );
    emit(
      state.withSession(event.tabId, const RealtimeSession(connected: true)),
    );
  }

  /// Normalizes an `http(s)` scheme to `ws(s)` for WebSocket connects —
  /// Postman does the same, and dart:io's `WebSocket.connect` throws on any
  /// non-ws scheme. Anything else (already `ws://`, or unparseable) passes
  /// through for the connector to reject via [_onConnect]'s try/catch.
  static String _normalizeWsUrl(String url) {
    final trimmed = url.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://')) return 'ws://${trimmed.substring(7)}';
    if (lower.startsWith('https://')) return 'wss://${trimmed.substring(8)}';
    return trimmed;
  }

  void _onSend(SendRealtimeMessage event, Emitter<RealtimeState> emit) {
    _connections[event.tabId]?.send(event.text);
  }

  Future<void> _onDisconnect(
    Disconnect event,
    Emitter<RealtimeState> emit,
  ) async {
    // FLUSH (not discard) frames still waiting in the coalescing buffer: the
    // teardown below clears _pending and bumps the epoch (so any queued batch
    // is dropped as stale), and without this the last ≤16ms of traffic before
    // the user hit DISCONNECT would vanish from the log.
    _flushTimers.remove(event.tabId)?.cancel();
    final pending = _pending.remove(event.tabId) ?? const <RealtimeFrame>[];
    final teardown = _teardown(event.tabId);
    final epoch = _epochOf(event.tabId);
    await teardown;
    // A reconnect/tab close that interleaved with the (real-network) close()
    // await owns the session now — emitting the disconnect reset here would
    // clobber its fresh session.
    if (isClosed || _epochOf(event.tabId) != epoch) return;
    // Read the session AFTER the teardown awaits — live state, not a
    // pre-teardown snapshot.
    final session = state.sessionFor(event.tabId);
    final frames = [...session.frames, ...pending];
    emit(
      state.withSession(
        event.tabId,
        RealtimeSession(frames: _capped(frames)),
      ),
    );
  }

  /// Closed tabs: tear down their live connections AND drop their session
  /// entries — a session for a tab that no longer exists is unreachable state
  /// that only grows (`without` had no caller before this: closing a tab left
  /// its socket open until app exit).
  Future<void> _onTabsClosed(
    RealtimeTabsClosed event,
    Emitter<RealtimeState> emit,
  ) async {
    for (final tabId in event.tabIds) {
      await _teardown(tabId);
      // The tab is gone for good — drop its epoch entry too. Safe: any stale
      // in-flight connect/batch captured a post-bump value (>= 1), which can
      // never compare equal to the 0 an absent entry reads as.
      _epochs.remove(tabId);
    }
    // Fold over the LIVE state only after every teardown await: a snapshot
    // taken before the awaits would clobber anything another handler emitted
    // while the teardowns were in flight (e.g. a frame batch appended for a
    // different tab).
    var next = state;
    for (final tabId in event.tabIds) {
      next = next.without(tabId);
    }
    if (next != state) emit(next);
  }

  /// Buffers a stream frame and arms a single coalescing timer per tab. Frames
  /// arriving within [_coalesceWindow] flush together as one batch event.
  void _bufferFrame(String tabId, RealtimeFrame frame) {
    if (isClosed) return;
    (_pending[tabId] ??= <RealtimeFrame>[]).add(frame);
    _flushTimers[tabId] ??= Timer(_coalesceWindow, () {
      _flushTimers.remove(tabId);
      final batch = _pending.remove(tabId);
      // A frame arriving during close()'s awaits can arm this timer after
      // close() already cancelled the old ones — add() on a closed bloc
      // throws StateError, so bail once closed.
      if (isClosed) return;
      if (batch != null && batch.isNotEmpty) {
        // Stamped with the tab's CURRENT epoch: if a teardown lands before
        // this event is processed, the epoch moves on and _onFramesBatch
        // drops the batch instead of resurrecting a dead session.
        add(_FramesBatchReceived(tabId, batch, _epochOf(tabId)));
      }
    });
  }

  void _onFrame(FrameReceived event, Emitter<RealtimeState> emit) {
    _appendFrames(event.tabId, [event.frame], emit);
  }

  void _onFramesBatch(_FramesBatchReceived event, Emitter<RealtimeState> emit) {
    // A batch flushed before a teardown can still be in the event queue when
    // Disconnect/Connect/RealtimeTabsClosed processes — appending it then
    // would flip `connected` true with no live connection, or inject dead
    // frames into a fresh session. Stale epoch ⇒ drop.
    if (event.epoch != _epochOf(event.tabId)) return;
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
    final capped = _capped([...session.frames, ...incoming]);
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

  /// Re-applies the [_maxFrames] cap, keeping the newest frames.
  static List<RealtimeFrame> _capped(List<RealtimeFrame> frames) =>
      frames.length > _maxFrames
      ? frames.sublist(frames.length - _maxFrames)
      : frames;

  /// Closes and forgets [tabId]'s connection. Bumps the tab's epoch FIRST and
  /// synchronously (an async body runs to its first await): callers capture
  /// the post-bump value before awaiting, and every in-flight connect/batch
  /// holding an older epoch bails instead of writing over newer state (the
  /// double-CONNECT overwrite, the stale frame-batch resurrection).
  Future<void> _teardown(String tabId) async {
    _epochs[tabId] = _epochOf(tabId) + 1;
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
