import 'package:equatable/equatable.dart';

enum RealtimeDirection { open, incoming, outgoing, close, error }

/// One entry in a realtime (WebSocket/SSE) session log: a lifecycle event or a
/// message in either direction, with a timestamp for display.
class RealtimeFrame extends Equatable {
  const RealtimeFrame({
    required this.direction,
    required this.text,
    required this.timestampMs,
  });

  factory RealtimeFrame.open([String text = 'Connected']) => RealtimeFrame(
    direction: RealtimeDirection.open,
    text: text,
    timestampMs: _now(),
  );
  factory RealtimeFrame.incoming(String text) => RealtimeFrame(
    direction: RealtimeDirection.incoming,
    text: text,
    timestampMs: _now(),
  );
  factory RealtimeFrame.outgoing(String text) => RealtimeFrame(
    direction: RealtimeDirection.outgoing,
    text: text,
    timestampMs: _now(),
  );
  factory RealtimeFrame.close([String text = 'Disconnected']) => RealtimeFrame(
    direction: RealtimeDirection.close,
    text: text,
    timestampMs: _now(),
  );
  factory RealtimeFrame.error(String text) => RealtimeFrame(
    direction: RealtimeDirection.error,
    text: text,
    timestampMs: _now(),
  );
  final RealtimeDirection direction;
  final String text;
  final int timestampMs;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  List<Object?> get props => [direction, text, timestampMs];
}
