import 'package:equatable/equatable.dart';

class HttpResponseEntity extends Equatable {
  const HttpResponseEntity({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.durationMs,
  });
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final int durationMs;

  /// Returns a copy with [body] replaced, keeping status/headers/duration —
  /// used when an over-limit response body is swapped for a placeholder before
  /// persisting.
  HttpResponseEntity copyWithBody(String body) => HttpResponseEntity(
    statusCode: statusCode,
    body: body,
    headers: headers,
    durationMs: durationMs,
  );

  @override
  List<Object?> get props => [statusCode, body, headers, durationMs];
}
