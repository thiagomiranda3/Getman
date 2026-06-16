// test/core/utils/openapi/openapi_v3_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/openapi_v3_normalizer.dart';

Map<String, dynamic> get _spec => {
  'openapi': '3.0.0',
  'info': {'title': 'Demo API'},
  'servers': [
    {'url': 'https://api.example.com/v1', 'description': 'prod'},
    {
      'url': 'https://{host}/v1',
      'description': 'custom',
      'variables': {
        'host': {'default': 'staging.example.com'},
      },
    },
  ],
  'components': {
    'securitySchemes': {
      'bearerAuth': {'type': 'http', 'scheme': 'bearer'},
    },
    'schemas': {
      'NewUser': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      },
    },
  },
  'security': [
    {'bearerAuth': <dynamic>[]},
  ],
  'paths': {
    '/users/{id}': {
      'get': {
        'summary': 'Get user',
        'tags': ['Users'],
        'parameters': [
          {
            'name': 'id',
            'in': 'path',
            'required': true,
            'schema': {'type': 'integer'},
          },
          {
            'name': 'verbose',
            'in': 'query',
            'schema': {'type': 'boolean', 'example': true},
          },
          {
            'name': 'X-Trace',
            'in': 'header',
            'schema': {'type': 'string'},
          },
        ],
      },
    },
    '/users': {
      'post': {
        'operationId': 'createUser',
        'tags': ['Users'],
        'requestBody': {
          'content': {
            'application/json': {
              'schema': {r'$ref': '#/components/schemas/NewUser'},
            },
          },
        },
      },
    },
  },
};

void main() {
  test('reads title and servers with variable defaults', () {
    final api = normalizeOpenApiV3(_spec);
    expect(api.title, 'Demo API');
    expect(api.servers, hasLength(2));
    expect(api.servers[0].url, 'https://api.example.com/v1');
    expect(api.servers[1].variables['host'], 'staging.example.com');
  });

  test('GET op: method/path/name/tag, query+header params, path untouched', () {
    final api = normalizeOpenApiV3(_spec);
    final get = api.operations.firstWhere((o) => o.method == 'GET');
    expect(get.path, '/users/{id}');
    expect(get.name, 'Get user');
    expect(get.tag, 'Users');
    expect(get.queryParams.single.name, 'verbose');
    expect(get.queryParams.single.value, 'true');
    expect(get.headerParams.single.name, 'X-Trace');
    expect(get.body, isNull);
    expect(get.security?.kind, SecuritySchemeKind.bearer); // inherits global
  });

  test(r'POST op: json body sampled from a $ref schema', () {
    final api = normalizeOpenApiV3(_spec);
    final post = api.operations.firstWhere((o) => o.method == 'POST');
    expect(post.name, 'createUser');
    expect(post.body!.bodyType, BodyType.raw);
    expect(post.body!.contentType, 'application/json');
    expect(post.body!.raw, contains('"name"'));
  });
}
