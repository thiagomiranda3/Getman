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

  test('no op/path-level servers override leaves server null', () {
    final api = normalizeOpenApiV3(_spec);
    for (final op in api.operations) {
      expect(op.server, isNull);
    }
  });

  test(
    'operation-level servers win over path-level, which wins over global',
    () {
      final spec = {
        'openapi': '3.0.0',
        'info': {'title': 'T'},
        'servers': [
          {'url': 'https://global.example.com'},
        ],
        'paths': {
          '/webhook': {
            'servers': [
              {'url': 'https://path.example.com'},
            ],
            'get': {
              'servers': [
                {'url': 'https://op.example.com'},
              ],
            },
            'post': <String, dynamic>{},
          },
        },
      };
      final api = normalizeOpenApiV3(spec);
      final get = api.operations.firstWhere((o) => o.method == 'GET');
      expect(get.server?.url, 'https://op.example.com');
      final post = api.operations.firstWhere((o) => o.method == 'POST');
      expect(
        post.server?.url,
        'https://path.example.com',
        reason: 'no op-level override; falls back to the path-item servers',
      );
    },
  );

  test(
    'path-item-level shared parameters apply to every operation, '
    'op-level winning on the same name+in',
    () {
      final spec = {
        'openapi': '3.0.0',
        'info': {'title': 'T'},
        'paths': {
          '/things': {
            'parameters': [
              {
                'name': 'tenant',
                'in': 'query',
                'schema': {'default': 'acme'},
              },
              {
                'name': 'verbose',
                'in': 'query',
                'schema': {'default': 'false'},
              },
            ],
            'get': {
              'parameters': [
                {
                  'name': 'verbose',
                  'in': 'query',
                  'schema': {'default': 'true'},
                },
              ],
            },
            'delete': <String, dynamic>{},
          },
        },
      };
      final api = normalizeOpenApiV3(spec);
      final get = api.operations.firstWhere((o) => o.method == 'GET');
      expect(
        {for (final p in get.queryParams) p.name: p.value},
        {'tenant': 'acme', 'verbose': 'true'},
        reason: 'shared param inherited; op-level override wins',
      );
      final del = api.operations.firstWhere((o) => o.method == 'DELETE');
      expect(
        {for (final p in del.queryParams) p.name: p.value},
        {'tenant': 'acme', 'verbose': 'false'},
        reason: 'ops with no own list still inherit shared params',
      );
    },
  );
}
