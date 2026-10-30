// Immutable ScriptResponse value exchanged by script execution components.
import 'package:equatable/equatable.dart';

class ScriptResponse extends Equatable {
  ScriptResponse({
    required this.status,
    this.durationMs = 0,
    this.text = '',
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);
  final int status;
  final int durationMs;
  final String text;
  final Map<String, String> headers;

  ScriptResponse copyWith({
    int? status,
    int? durationMs,
    String? text,
    Map<String, String>? headers,
  }) => ScriptResponse(
    status: status ?? this.status,
    durationMs: durationMs ?? this.durationMs,
    text: text ?? this.text,
    headers: headers ?? this.headers,
  );
  @override
  List<Object?> get props => [status, durationMs, text, headers];
}
