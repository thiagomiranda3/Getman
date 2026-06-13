import 'package:equatable/equatable.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';

abstract class RealtimeEvent extends Equatable {
  const RealtimeEvent();
  @override
  List<Object?> get props => [];
}

class Connect extends RealtimeEvent {
  final String tabId;
  final RequestKind kind;
  final String url;
  final Map<String, String> headers;
  const Connect({
    required this.tabId,
    required this.kind,
    required this.url,
    this.headers = const {},
  });
  @override
  List<Object?> get props => [tabId, kind, url, headers];
}

class SendRealtimeMessage extends RealtimeEvent {
  final String tabId;
  final String text;
  const SendRealtimeMessage(this.tabId, this.text);
  @override
  List<Object?> get props => [tabId, text];
}

class Disconnect extends RealtimeEvent {
  final String tabId;
  const Disconnect(this.tabId);
  @override
  List<Object?> get props => [tabId];
}

/// Internal: a frame arrived on a connection's stream. Routed through the bloc
/// so state is only ever emitted from within an event handler.
class FrameReceived extends RealtimeEvent {
  final String tabId;
  final RealtimeFrame frame;
  const FrameReceived(this.tabId, this.frame);
  @override
  List<Object?> get props => [tabId, frame];
}
