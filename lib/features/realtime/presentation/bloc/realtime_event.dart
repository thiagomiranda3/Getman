// RealtimeBloc events: connect (WebSocket or SSE, by RequestKind), send a
// message, disconnect. FrameReceived is internal — routed through the bloc so
// state only ever changes inside an event handler.

import 'package:equatable/equatable.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';

abstract class RealtimeEvent extends Equatable {
  const RealtimeEvent();
  @override
  List<Object?> get props => [];
}

class Connect extends RealtimeEvent {
  const Connect({
    required this.tabId,
    required this.kind,
    required this.url,
    this.headers = const {},
  });
  final String tabId;
  final RequestKind kind;
  final String url;
  final Map<String, String> headers;
  @override
  List<Object?> get props => [tabId, kind, url, headers];
}

class SendRealtimeMessage extends RealtimeEvent {
  const SendRealtimeMessage(this.tabId, this.text);
  final String tabId;
  final String text;
  @override
  List<Object?> get props => [tabId, text];
}

class Disconnect extends RealtimeEvent {
  const Disconnect(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

/// Request tabs were CLOSED (dispatched by `TabCloseTeardownListener`): tear
/// down any live connection for these ids and drop their session entries —
/// unlike [Disconnect], nothing remains to show a log for, and without this a
/// closed tab's WebSocket/SSE stream stayed open (and streaming into state)
/// until app exit.
class RealtimeTabsClosed extends RealtimeEvent {
  const RealtimeTabsClosed(this.tabIds);
  final Set<String> tabIds;
  @override
  List<Object?> get props => [tabIds];
}

/// Internal: a frame arrived on a connection's stream. Routed through the bloc
/// so state is only ever emitted from within an event handler.
class FrameReceived extends RealtimeEvent {
  const FrameReceived(this.tabId, this.frame);
  final String tabId;
  final RealtimeFrame frame;
  @override
  List<Object?> get props => [tabId, frame];
}
