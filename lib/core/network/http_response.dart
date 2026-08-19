// HttpResponseEntity: the response half of a request/response pair
// (statusCode/body/headers/durationMs), plus optional in-memory-only
// bodyBytes for non-textual (media/binary) responses — never persisted to
// Hive, so it is null on a restored tab or an older history entry.

import 'dart:typed_data';

import 'package:equatable/equatable.dart';

// bodyBytes participates in equality via bodyBytes?.length in props; a full
// multi-MB byte compare every rebuild is intentionally avoided.
// ignore: equatable_props_complete
class HttpResponseEntity extends Equatable {
  const HttpResponseEntity({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.durationMs,
    this.bodyBytes,
  });
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final int durationMs;

  /// Raw bytes for a non-textual (media/binary) response. Held **in memory
  /// only** — never persisted to Hive — so it is null on a restored tab or an
  /// older time-travel history entry. Null for textual responses.
  final Uint8List? bodyBytes;

  /// Returns a copy with [body] replaced, keeping status/headers/duration —
  /// used when an over-limit text body is swapped for a placeholder before
  /// persisting. By default media [bodyBytes] ride along (the persistence
  /// callers rely on that; bytes are dropped at the model layer anyway).
  /// Pass `keepBytes: false` to null them out — the in-session history
  /// downgrade uses it so a superseded media entry releases its (up to
  /// 50 MiB) buffer instead of pinning it in RAM for the whole session.
  HttpResponseEntity copyWithBody(String body, {bool keepBytes = true}) =>
      HttpResponseEntity(
        statusCode: statusCode,
        body: body,
        headers: headers,
        durationMs: durationMs,
        bodyBytes: keepBytes ? bodyBytes : null,
      );

  // bodyBytes itself is excluded from props — a list compare on multi-MB
  // buffers every rebuild is unacceptable. Its length is a cheap discriminator.
  @override
  List<Object?> get props => [
    statusCode,
    body,
    headers,
    durationMs,
    bodyBytes?.length,
  ];
}
