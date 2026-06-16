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
}
