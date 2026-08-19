// test/core/utils/openapi/swagger_v2_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/swagger_v2_normalizer.dart';

Map<String, dynamic> get _spec => {
  'swagger': '2.0',
  'info': {'title': 'Legacy API'},
  'host': 'api.legacy.com',
  'basePath': '/v2',
  'schemes': ['https'],
  'securityDefinitions': {
    'apiKey': {'type': 'apiKey', 'name': 'X-Key', 'in': 'header'},
  },
  'security': [
    {'apiKey': <dynamic>[]},
  ],
  'definitions': {
    'Pet': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
      },
    },
  },
  'paths': {
    '/pets/{petId}': {
      'get': {
        'summary': 'Get pet',
        'tags': ['Pets'],
        'parameters': [
          {
            'name': 'petId',
            'in': 'path',
            'required': true,
            'type': 'integer',
          },
          {'name': 'detailed', 'in': 'query', 'type': 'boolean'},
        ],
      },
    },
    '/pets': {
      'post': {
        'operationId': 'createPet',
        'tags': ['Pets'],
        'parameters': [
          {
            'name': 'body',
            'in': 'body',
            'schema': {r'$ref': '#/definitions/Pet'},
          },
        ],
      },
    },
  },
};

void main() {
  test('synthesizes one server from schemes+host+basePath', () {
    final api = normalizeSwaggerV2(_spec);
    expect(api.title, 'Legacy API');
    expect(api.servers.single.url, 'https://api.legacy.com/v2');
  });

  test('GET op: tag, query param, path templated, apiKey security', () {
    final api = normalizeSwaggerV2(_spec);
    final get = api.operations.firstWhere((o) => o.method == 'GET');
    expect(get.path, '/pets/{petId}');
    expect(get.tag, 'Pets');
    expect(get.queryParams.single.name, 'detailed');
    expect(get.security?.kind, SecuritySchemeKind.apiKeyHeader);
    expect(get.security?.apiKeyName, 'X-Key');
  });

  test(r'POST op: body param sampled from a definitions $ref', () {
    final api = normalizeSwaggerV2(_spec);
    final post = api.operations.firstWhere((o) => o.method == 'POST');
    expect(post.name, 'createPet');
    expect(post.body!.bodyType, BodyType.raw);
    expect(post.body!.contentType, 'application/json');
    expect(post.body!.raw, contains('"name"'));
  });

  test('non-body params extract default / enum / x-example values', () {
    final api = normalizeSwaggerV2({
      'swagger': '2.0',
      'info': {'title': 'P'},
      'host': 'h',
      'basePath': '/',
      'schemes': ['https'],
      'paths': {
        '/x': {
          'get': {
            'summary': 'X',
            'parameters': [
              {'name': 'page', 'in': 'query', 'type': 'integer', 'default': 1},
              {
                'name': 'status',
                'in': 'query',
                'type': 'string',
                'enum': ['active', 'inactive'],
              },
              {
                'name': 'X-Tenant',
                'in': 'header',
                'type': 'string',
                'x-example': 'acme',
              },
            ],
          },
        },
      },
    });
    final get = api.operations.single;
    expect(get.queryParams[0].value, '1'); // default
    expect(get.queryParams[1].value, 'active'); // first enum
    expect(get.headerParams.single.value, 'acme'); // x-example
  });

  test('path-item-level shared parameters apply to every operation', () {
    final api = normalizeSwaggerV2({
      'swagger': '2.0',
      'info': {'title': 'T'},
      'paths': {
        '/things': {
          'parameters': [
            {'name': 'tenant', 'in': 'query', 'default': 'acme'},
          ],
          'get': {
            'parameters': [
              {'name': 'verbose', 'in': 'query', 'default': 'true'},
            ],
          },
          'delete': <String, dynamic>{},
        },
      },
    });
    final get = api.operations.firstWhere((o) => o.method == 'GET');
    expect(
      {for (final p in get.queryParams) p.name: p.value},
      {'tenant': 'acme', 'verbose': 'true'},
    );
    final del = api.operations.firstWhere((o) => o.method == 'DELETE');
    expect(del.queryParams.single.name, 'tenant');
  });

  group('type-wrong leaf values (JSON-valid, schema-wrong specs)', () {
    test('non-string leaves are coerced with toString, not thrown on', () {
      // {"info":{"title":5}} used to throw TypeError out of the normalizer.
      final api = normalizeSwaggerV2({
        'swagger': '2.0',
        'info': {'title': 5},
        'host': 123,
        'basePath': 9,
        'schemes': ['https'],
        'paths': {
          '/x': {
            'get': {'summary': 7},
          },
        },
      });
      expect(api.title, '5');
      expect(api.servers.single.url, 'https://1239');
      expect(api.operations.single.name, '7');
    });

    test('a non-string securityDefinition name field is coerced', () {
      final api = normalizeSwaggerV2({
        'swagger': '2.0',
        'info': {'title': 'T'},
        'securityDefinitions': {
          'k': {'type': 'apiKey', 'in': 'header', 'name': 42},
        },
        'security': [
          {'k': <dynamic>[]},
        ],
        'paths': {
          '/x': {'get': <String, dynamic>{}},
        },
      });
      expect(api.operations.single.security?.apiKeyName, '42');
    });
  });

  group('ref fan-out budget', () {
    test('a billion-laughs definitions tree normalizes quickly and warns on '
        'the operation that crossed the budget', () {
      final definitions = <String, dynamic>{};
      for (var level = 0; level < 10; level++) {
        definitions['L$level'] = {
          'type': 'object',
          'properties': {
            for (var i = 0; i < 10; i++)
              'p$i': level == 9
                  ? {'type': 'string'}
                  : {r'$ref': '#/definitions/L${level + 1}'},
          },
        };
      }
      final api = normalizeSwaggerV2({
        'swagger': '2.0',
        'info': {'title': 'T'},
        'definitions': definitions,
        'paths': {
          '/bomb': {
            'post': {
              'parameters': [
                {
                  'name': 'body',
                  'in': 'body',
                  'schema': {r'$ref': '#/definitions/L0'},
                },
              ],
            },
          },
          '/after': {'get': <String, dynamic>{}},
        },
      });
      final bomb = api.operations.firstWhere((o) => o.path == '/bomb');
      expect(
        bomb.warnings,
        contains(
          'Spec too complex to fully resolve — some schema examples were '
          'truncated.',
        ),
      );
      final after = api.operations.firstWhere((o) => o.path == '/after');
      expect(after.warnings, isEmpty);
    });

    test('a normal spec resolves identically with no truncation warning', () {
      final api = normalizeSwaggerV2(_spec);
      for (final op in api.operations) {
        expect(op.warnings, isEmpty);
      }
      final post = api.operations.firstWhere((o) => o.method == 'POST');
      expect(post.body!.raw, contains('"name"'));
    });
  });
}
