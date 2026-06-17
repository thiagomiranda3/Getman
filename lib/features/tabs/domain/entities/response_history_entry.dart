import 'package:equatable/equatable.dart';
import 'package:getman/core/network/http_response.dart';

/// One captured response in a tab's time-travel history.
///
/// [id] addresses the entry (e.g. for `ViewResponseHistoryEntry`); [capturedAt]
/// is epoch millis, used for display ordering. Entries are stored newest-first
/// in `HttpRequestTabEntity.responseHistory`. The in-session entry keeps the
/// full body; only the on-disk copy is capped (see persistence_limits.dart).
class ResponseHistoryEntry extends Equatable {
  const ResponseHistoryEntry({
    required this.id,
    required this.response,
    required this.capturedAt,
  });

  final String id;
  final HttpResponseEntity response;
  final int capturedAt;

  ResponseHistoryEntry copyWith({
    String? id,
    HttpResponseEntity? response,
    int? capturedAt,
  }) => ResponseHistoryEntry(
    id: id ?? this.id,
    response: response ?? this.response,
    capturedAt: capturedAt ?? this.capturedAt,
  );

  @override
  List<Object?> get props => [id, response, capturedAt];
}
