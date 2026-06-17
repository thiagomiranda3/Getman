import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';
import 'package:hive_ce/hive.dart';

part 'stored_response_model.g.dart';

/// Hive model for one captured response in a tab's time-travel history.
/// typeId 11 (first free after 0–10). Nested as a list inside the tab model
/// (typeId 2, field 9), so it travels with the tab.
@HiveType(typeId: 11)
class StoredResponseModel extends HiveObject {
  StoredResponseModel({
    required this.id,
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.durationMs,
    required this.capturedAt,
  });

  factory StoredResponseModel.fromEntity(ResponseHistoryEntry entry) =>
      StoredResponseModel(
        id: entry.id,
        statusCode: entry.response.statusCode,
        body: entry.response.body,
        headers: entry.response.headers,
        durationMs: entry.response.durationMs,
        capturedAt: entry.capturedAt,
      );

  @HiveField(0)
  String id;

  @HiveField(1)
  int statusCode;

  @HiveField(2)
  String body;

  @HiveField(3)
  Map<String, String> headers;

  @HiveField(4)
  int durationMs;

  @HiveField(5)
  int capturedAt;

  ResponseHistoryEntry toEntity() => ResponseHistoryEntry(
    id: id,
    response: HttpResponseEntity(
      statusCode: statusCode,
      body: body,
      headers: headers,
      durationMs: durationMs,
    ),
    capturedAt: capturedAt,
  );
}
