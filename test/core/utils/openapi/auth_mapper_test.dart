// test/core/utils/openapi/auth_mapper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/openapi/auth_mapper.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';

void main() {
  test('null scheme → none auth, no secret, no warning', () {
    final a = mapAuth(null);
    expect(a.config.type, AuthType.none);
    expect(a.secretVarName, isNull);
    expect(a.warning, isNull);
  });

  test('bearer → bearer auth with blank token + bearerToken secret', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(kind: SecuritySchemeKind.bearer),
    );
    expect(a.config.type, AuthType.bearer);
    expect(a.config.token, '');
    expect(a.secretVarName, 'bearerToken');
  });

  test('basic → basic auth + basicPassword secret', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(kind: SecuritySchemeKind.basic),
    );
    expect(a.config.type, AuthType.basic);
    expect(a.secretVarName, 'basicPassword');
  });

  test('apiKey header → apiKey auth with name + header location', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(
        kind: SecuritySchemeKind.apiKeyHeader,
        apiKeyName: 'X-Api-Key',
      ),
    );
    expect(a.config.type, AuthType.apiKey);
    expect(a.config.apiKeyName, 'X-Api-Key');
    expect(a.config.apiKeyLocation, ApiKeyLocation.header);
    expect(a.config.apiKeyValue, '');
    expect(a.secretVarName, 'apiKey');
  });

  test('apiKey query → apiKey auth with query location', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(
        kind: SecuritySchemeKind.apiKeyQuery,
        apiKeyName: 'token',
      ),
    );
    expect(a.config.apiKeyLocation, ApiKeyLocation.query);
  });

  test('oauth2 → none auth + warning', () {
    final a = mapAuth(
      const NormalizedSecurityScheme(kind: SecuritySchemeKind.oauth2),
    );
    expect(a.config.type, AuthType.none);
    expect(a.warning, isNotNull);
    expect(a.warning, contains('OAuth2'));
  });
}
