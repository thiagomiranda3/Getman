import 'package:equatable/equatable.dart';
import 'package:getman/core/network/realtime_frame.dart';

/// The realtime session for one tab: connection status + message/event log.
class RealtimeSession extends Equatable {
  const RealtimeSession({this.connected = false, this.frames = const []});
  final bool connected;
  final List<RealtimeFrame> frames;

  RealtimeSession copyWith({bool? connected, List<RealtimeFrame>? frames}) =>
      RealtimeSession(
        connected: connected ?? this.connected,
        frames: frames ?? this.frames,
      );

  @override
  List<Object?> get props => [connected, frames];
}

class RealtimeState extends Equatable {
  const RealtimeState({this.sessions = const {}});

  /// Sessions keyed by tabId.
  final Map<String, RealtimeSession> sessions;

  RealtimeSession sessionFor(String tabId) =>
      sessions[tabId] ?? const RealtimeSession();

  RealtimeState withSession(String tabId, RealtimeSession session) =>
      RealtimeState(sessions: {...sessions, tabId: session});

  RealtimeState without(String tabId) {
    final next = Map<String, RealtimeSession>.of(sessions)..remove(tabId);
    return RealtimeState(sessions: next);
  }

  @override
  List<Object?> get props => [sessions];
}
