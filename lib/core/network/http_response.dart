import 'package:equatable/equatable.dart';

class HttpResponseEntity extends Equatable {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final int durationMs;

  const HttpResponseEntity({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.durationMs,
  });

  @override
  List<Object?> get props => [statusCode, body, headers, durationMs];
}
