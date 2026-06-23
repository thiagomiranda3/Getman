// test/core/utils/apidoc/openapi_serializer_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';
import 'package:getman/core/utils/apidoc/openapi_serializer.dart';

ApiDoc _sample() => const ApiDoc(
  title: 'Petstore',
  servers: [ApiServer(url: 'https://api.test.com')],
  operations: [
    ApiOperation(
      method: 'GET',
      path: '/users/{id}',
      summary: 'Get user',
      tag: 'Users',
      pathParams: [ApiParam(name: 'id', isRequired: true, example: '7')],
      queryParams: [ApiParam(name: 'verbose', example: 'true')],
      security: AuthConfig(type: AuthType.bearer, token: 'x'),
      responses: [
        ApiResponse(
          statusCode: 200,
          description: 'OK',
          body: ApiBody(
            contentType: 'application/json',
            schema: JsonSchema(type: 'object'),
            example: {'id': 7},
          ),
        ),
      ],
    ),
  ],
);

Map<String, dynamic> _paths(Map<String, dynamic> map) =>
    map['paths'] as Map<String, dynamic>;

Map<String, dynamic> _pathItem(
  Map<String, dynamic> map,
  String path,
) => _paths(map)[path] as Map<String, dynamic>;

Map<String, dynamic> _op(
  Map<String, dynamic> map,
  String path,
  String method,
) => _pathItem(map, path)[method] as Map<String, dynamic>;

void main() {
  test('emits a 3.0.3 document with info, servers, paths', () {
    final map = OpenApiSerializer.toMap(_sample());
    expect(map['openapi'], '3.0.3');
    expect(map['info'], {'title': 'Petstore', 'version': '1.0.0'});
    expect((map['servers'] as List<dynamic>).first, {
      'url': 'https://api.test.com',
    });
    final op = _op(map, '/users/{id}', 'get');
    expect(op['summary'], 'Get user');
    expect(op['tags'], ['Users']);
  });

  test('path param is required, query param is not', () {
    final map = OpenApiSerializer.toMap(_sample());
    final params =
        _op(map, '/users/{id}', 'get')['parameters'] as List<dynamic>;
    final pathParam =
        params.firstWhere(
              (dynamic p) => (p as Map<String, dynamic>)['in'] == 'path',
            )
            as Map<String, dynamic>;
    final queryParam =
        params.firstWhere(
              (dynamic p) => (p as Map<String, dynamic>)['in'] == 'query',
            )
            as Map<String, dynamic>;
    expect(pathParam['required'], true);
    expect(queryParam['required'], false);
  });

  test('bearer security scheme is declared and referenced', () {
    final map = OpenApiSerializer.toMap(_sample());
    final schemes =
        (map['components'] as Map<String, dynamic>)['securitySchemes']
            as Map<String, dynamic>;
    expect(schemes['bearerAuth'], {'type': 'http', 'scheme': 'bearer'});
    final security =
        _op(map, '/users/{id}', 'get')['security'] as List<dynamic>;
    expect(security, [
      {'bearerAuth': <dynamic>[]},
    ]);
  });

  test('never emits the bearer token value anywhere', () {
    final json = OpenApiSerializer.toJson(_sample());
    expect(json.contains('"x"'), isFalse);
  });

  test('toJson is valid JSON; toYaml starts with openapi', () {
    final doc = _sample();
    expect(() => jsonDecode(OpenApiSerializer.toJson(doc)), returnsNormally);
    expect(OpenApiSerializer.toYaml(doc).startsWith('openapi:'), isTrue);
  });
}
