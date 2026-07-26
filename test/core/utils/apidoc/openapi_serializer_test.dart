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

  group('security scheme variants', () {
    ApiDoc docWithAuth(AuthConfig auth) => ApiDoc(
      title: 'T',
      operations: [
        ApiOperation(method: 'GET', path: '/x', summary: 'S', security: auth),
      ],
    );

    test('basic auth registers basicAuth and references it', () {
      final map = OpenApiSerializer.toMap(
        docWithAuth(const AuthConfig(type: AuthType.basic, username: 'u')),
      );
      final schemes =
          (map['components'] as Map<String, dynamic>)['securitySchemes']
              as Map<String, dynamic>;
      expect(schemes['basicAuth'], {'type': 'http', 'scheme': 'basic'});
      expect(_op(map, '/x', 'get')['security'], [
        {'basicAuth': <dynamic>[]},
      ]);
    });

    test('api key auth in a header declares in: header with the name', () {
      final map = OpenApiSerializer.toMap(
        docWithAuth(
          const AuthConfig(
            type: AuthType.apiKey,
            apiKeyName: 'X-Key',
            apiKeyValue: 'secret',
          ),
        ),
      );
      final schemes =
          (map['components'] as Map<String, dynamic>)['securitySchemes']
              as Map<String, dynamic>;
      expect(schemes['apiKeyAuth'], {
        'type': 'apiKey',
        'in': 'header',
        'name': 'X-Key',
      });
      expect(_op(map, '/x', 'get')['security'], [
        {'apiKeyAuth': <dynamic>[]},
      ]);
      expect(
        OpenApiSerializer.toJson(
          docWithAuth(
            const AuthConfig(
              type: AuthType.apiKey,
              apiKeyName: 'X-Key',
              apiKeyValue: 'secret',
            ),
          ),
        ),
        isNot(contains('secret')),
        reason: 'auth shape only — never the key value',
      );
    });

    test('api key auth in the query declares in: query', () {
      final map = OpenApiSerializer.toMap(
        docWithAuth(
          const AuthConfig(
            type: AuthType.apiKey,
            apiKeyName: 'k',
            apiKeyLocation: ApiKeyLocation.query,
          ),
        ),
      );
      final schemes =
          (map['components'] as Map<String, dynamic>)['securitySchemes']
              as Map<String, dynamic>;
      expect(schemes['apiKeyAuth'], {
        'type': 'apiKey',
        'in': 'query',
        'name': 'k',
      });
    });

    test('none and inherit emit no security key and no components', () {
      for (final auth in const [
        AuthConfig.none,
        AuthConfig(type: AuthType.inherit),
      ]) {
        final map = OpenApiSerializer.toMap(docWithAuth(auth));
        expect(_op(map, '/x', 'get').containsKey('security'), isFalse);
        expect(map.containsKey('components'), isFalse);
      }
    });
  });

  group('paths assembly', () {
    test(
      'ops on the same path merge into one path item; a duplicate '
      'method keeps the first op',
      () {
        const doc = ApiDoc(
          title: 'T',
          operations: [
            ApiOperation(method: 'GET', path: '/u', summary: 'first'),
            ApiOperation(method: 'GET', path: '/u', summary: 'second'),
            ApiOperation(method: 'POST', path: '/u', summary: 'create'),
          ],
        );
        final map = OpenApiSerializer.toMap(doc);
        final pathItem = _pathItem(map, '/u');
        expect(pathItem.keys, unorderedEquals(['get', 'post']));
        expect(_op(map, '/u', 'get')['summary'], 'first');
        expect(_op(map, '/u', 'post')['summary'], 'create');
      },
    );
  });

  test('request body emits content with schema and example', () {
    const doc = ApiDoc(
      title: 'T',
      operations: [
        ApiOperation(
          method: 'POST',
          path: '/u',
          summary: 'Create',
          description: 'Creates a user.',
          requestBody: ApiBody(
            contentType: 'application/json',
            schema: JsonSchema(type: 'object'),
            example: {'name': 'n'},
          ),
        ),
      ],
    );
    final map = OpenApiSerializer.toMap(doc);
    final op = _op(map, '/u', 'post');
    expect(op['description'], 'Creates a user.');
    final content =
        (op['requestBody'] as Map<String, dynamic>)['content']
            as Map<String, dynamic>;
    final json = content['application/json'] as Map<String, dynamic>;
    expect(json['schema'], {
      'type': 'object',
      'properties': <String, Object>{},
    });
    expect(json['example'], {'name': 'n'});
  });

  test('server variables emit their defaults', () {
    const doc = ApiDoc(
      title: 'T',
      servers: [
        ApiServer(url: 'https://{host}/v1', variables: {'host': 'a.dev'}),
      ],
    );
    final map = OpenApiSerializer.toMap(doc);
    expect((map['servers'] as List<dynamic>).single, {
      'url': 'https://{host}/v1',
      'variables': {
        'host': {'default': 'a.dev'},
      },
    });
  });

  test('an empty response description falls back to "Response"', () {
    const doc = ApiDoc(
      title: 'T',
      operations: [
        ApiOperation(
          method: 'GET',
          path: '/x',
          summary: 'S',
          responses: [ApiResponse(statusCode: 204)],
        ),
      ],
    );
    final map = OpenApiSerializer.toMap(doc);
    final responses =
        _op(map, '/x', 'get')['responses'] as Map<String, dynamic>;
    expect(responses['204'], {'description': 'Response'});
  });
}
