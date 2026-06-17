import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/data/models/stored_response_model.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';

void main() {
  group('StoredResponseModel', () {
    test('round-trips a history entry through fromEntity/toEntity', () {
      const entry = ResponseHistoryEntry(
        id: 'e1',
        response: HttpResponseEntity(
          statusCode: 200,
          body: '{"ok":true}',
          headers: {'content-type': 'application/json'},
          durationMs: 42,
        ),
        capturedAt: 1700000000000,
      );

      final back = StoredResponseModel.fromEntity(entry).toEntity();

      expect(back, entry);
    });
  });
}
