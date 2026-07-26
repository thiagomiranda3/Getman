// test/core/utils/openapi/normalized_api_test.dart
//
// Value-equality behavior for every normalized-API value type. Builders
// return fresh (non-identical) instances so `==`/`hashCode` exercise the
// Equatable props path instead of short-circuiting on canonicalized consts.
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

NormalizedServer buildServer({String url = 'https://{host}/v1'}) =>
    NormalizedServer(
      url: url,
      description: 'prod',
      variables: const {'host': 'a.dev'},
    );

NormalizedParam buildParam({String name = 'verbose'}) =>
    NormalizedParam(name: name, value: 'true');

NormalizedBody buildBody({BodyType bodyType = BodyType.raw}) => NormalizedBody(
  bodyType: bodyType,
  raw: '{"a":1}',
  contentType: 'application/json',
  formFields: const [MultipartFieldEntity(name: 'f', value: 'v')],
);

NormalizedSecurityScheme buildScheme({
  SecuritySchemeKind kind = SecuritySchemeKind.apiKeyHeader,
}) => NormalizedSecurityScheme(kind: kind, apiKeyName: 'X-Key');

NormalizedOperation buildOperation({
  String method = 'GET',
  List<String> warnings = const ['w1'],
}) => NormalizedOperation(
  method: method,
  path: '/users/{id}',
  name: 'Get user',
  tag: 'Users',
  queryParams: [buildParam()],
  headerParams: [buildParam(name: 'X-Trace')],
  body: buildBody(),
  security: buildScheme(),
  server: buildServer(),
  warnings: warnings,
);

NormalizedApi buildApi({String title = 'Demo'}) => NormalizedApi(
  title: title,
  servers: [buildServer()],
  operations: [buildOperation()],
);

NormalizedAuth buildAuth({String? warning}) => NormalizedAuth(
  config: const AuthConfig(type: AuthType.bearer),
  secretVarName: 'bearerToken',
  warning: warning,
);

ImportResult buildResult({String rootName = 'Root'}) => ImportResult(
  root: CollectionNodeEntity(id: 'root-1', name: rootName),
  environments: [
    EnvironmentEntity(
      id: 'env-1',
      name: 'Prod',
      variables: const {'baseUrl': 'https://a.dev'},
      secretKeys: const {'bearerToken'},
    ),
  ],
  warnings: const ['w'],
);

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

  group('value equality on fresh instances (props, not identity)', () {
    test('NormalizedApi', () {
      expect(buildApi(), buildApi());
      expect(buildApi().hashCode, buildApi().hashCode);
      expect(buildApi(), isNot(equals(buildApi(title: 'Other'))));
    });

    test('NormalizedServer', () {
      expect(buildServer(), buildServer());
      expect(buildServer().hashCode, buildServer().hashCode);
      expect(buildServer(), isNot(equals(buildServer(url: 'https://b/v2'))));
    });

    test('NormalizedParam', () {
      expect(buildParam(), buildParam());
      expect(buildParam().hashCode, buildParam().hashCode);
      expect(buildParam(), isNot(equals(buildParam(name: 'other'))));
    });

    test('NormalizedBody', () {
      expect(buildBody(), buildBody());
      expect(buildBody().hashCode, buildBody().hashCode);
      expect(
        buildBody(),
        isNot(equals(buildBody(bodyType: BodyType.urlencoded))),
      );
    });

    test('NormalizedSecurityScheme', () {
      expect(buildScheme(), buildScheme());
      expect(buildScheme().hashCode, buildScheme().hashCode);
      expect(
        buildScheme(),
        isNot(equals(buildScheme(kind: SecuritySchemeKind.oauth2))),
      );
    });

    test('NormalizedOperation with all optional fields populated', () {
      expect(buildOperation(), buildOperation());
      expect(buildOperation().hashCode, buildOperation().hashCode);
      expect(buildOperation(), isNot(equals(buildOperation(method: 'POST'))));
    });

    test('NormalizedOperation warnings participate in equality', () {
      expect(
        buildOperation(),
        isNot(equals(buildOperation(warnings: const ['other warning']))),
      );
    });

    test('NormalizedAuth', () {
      expect(buildAuth(), buildAuth());
      expect(buildAuth().hashCode, buildAuth().hashCode);
      expect(buildAuth(), isNot(equals(buildAuth(warning: 'unsupported'))));
    });

    test('ImportResult', () {
      expect(buildResult(), buildResult());
      expect(buildResult().hashCode, buildResult().hashCode);
      expect(buildResult(), isNot(equals(buildResult(rootName: 'Other'))));
    });
  });
}
