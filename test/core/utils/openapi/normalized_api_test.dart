// test/core/utils/openapi/normalized_api_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';

void main() {
  test('value equality holds for NormalizedOperation', () {
    const a = NormalizedOperation(method: 'GET', path: '/u', name: 'list');
    const b = NormalizedOperation(method: 'GET', path: '/u', name: 'list');
    expect(a, b);
  });

  test('NormalizedSecurityScheme carries kind + apiKeyName', () {
    const s = NormalizedSecurityScheme(
      kind: SecuritySchemeKind.apiKeyHeader,
      apiKeyName: 'X-Key',
    );
    expect(s.kind, SecuritySchemeKind.apiKeyHeader);
    expect(s.apiKeyName, 'X-Key');
  });
}
