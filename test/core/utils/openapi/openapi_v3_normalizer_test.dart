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

  group('spec-shape edge cases', () {
    test('missing info/servers/paths → fallback title, empty api', () {
      final api = normalizeOpenApiV3({'openapi': '3.0.0'});
      expect(api.title, 'Imported API');
      expect(api.servers, isEmpty);
      expect(api.operations, isEmpty);
    });

    test('non-map info is ignored (fallback title)', () {
      final api = normalizeOpenApiV3({'info': 'not-a-map'});
      expect(api.title, 'Imported API');
    });

    test(
      'non-map server entries are skipped; a variable without a default '
      'becomes an empty string',
      () {
        final api = normalizeOpenApiV3({
          'info': {'title': 'T'},
          'servers': [
            'not-a-map',
            {
              'url': 'https://{h}/v1',
              'variables': {'h': <String, dynamic>{}},
            },
          ],
        });
        expect(api.servers, hasLength(1));
        expect(api.servers.single.url, 'https://{h}/v1');
        expect(api.servers.single.variables, {'h': ''});
      },
    );

    test('non-map path items and non-map operations are skipped', () {
      final api = normalizeOpenApiV3({
        'info': {'title': 'T'},
        'paths': {
          '/bad-item': 'nope',
          '/bad-op': {'get': 'nope'},
        },
      });
      expect(api.operations, isEmpty);
    });

    test('name falls back to "METHOD path" without summary/operationId', () {
      final api = normalizeOpenApiV3({
        'info': {'title': 'T'},
        'paths': {
          '/ping': {'get': <String, dynamic>{}},
        },
      });
      expect(api.operations.single.name, 'GET /ping');
    });
  });

  group('parameter examples', () {
    test(
      'literal example wins, integer schema samples to "0", nameless and '
      'cookie params are dropped',
      () {
        final api = normalizeOpenApiV3({
          'info': {'title': 'T'},
          'paths': {
            '/things': {
              'get': {
                'parameters': [
                  {
                    // No name → skipped entirely.
                    'in': 'query',
                    'schema': {'type': 'string'},
                  },
                  {
                    'name': 'lit',
                    'in': 'query',
                    'example': 42,
                    'schema': {'type': 'string'},
                  },
                  {
                    'name': 'num',
                    'in': 'query',
                    'schema': {'type': 'integer'},
                  },
                  {
                    'name': 'session',
                    'in': 'cookie',
                    'schema': {'type': 'string'},
                  },
                ],
              },
            },
          },
        });
        final op = api.operations.single;
        expect(
          {for (final p in op.queryParams) p.name: p.value},
          {'lit': '42', 'num': '0'},
        );
        expect(op.headerParams, isEmpty);
      },
    );
  });

  group('request-body content negotiation', () {
    Map<String, dynamic> specWithContent(Map<String, dynamic> content) => {
      'info': {'title': 'T'},
      'paths': {
        '/x': {
          'post': {
            'requestBody': {'content': content},
          },
        },
      },
    };

    test('JSON is preferred over a form content type when both exist', () {
      final api = normalizeOpenApiV3(
        specWithContent({
          'application/x-www-form-urlencoded': {
            'schema': {
              'properties': {
                'a': {'type': 'string'},
              },
            },
          },
          'application/json': {
            'schema': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
          },
        }),
      );
      final body = api.operations.single.body!;
      expect(body.bodyType, BodyType.raw);
      expect(body.contentType, 'application/json');
    });

    test('urlencoded body maps schema properties to form fields', () {
      final api = normalizeOpenApiV3(
        specWithContent({
          'application/x-www-form-urlencoded': {
            'schema': {
              'type': 'object',
              'properties': {
                'username': {'type': 'string'},
                'password': {'type': 'string'},
              },
            },
          },
        }),
      );
      final body = api.operations.single.body!;
      expect(body.bodyType, BodyType.urlencoded);
      expect(body.formFields.map((f) => f.name), ['username', 'password']);
      expect(body.formFields.any((f) => f.isFile), isFalse);
    });

    test('multipart body flags binary/byte-format properties as files', () {
      final api = normalizeOpenApiV3(
        specWithContent({
          'multipart/form-data': {
            'schema': {
              'type': 'object',
              'properties': {
                'avatar': {'type': 'string', 'format': 'binary'},
                'blob': {'type': 'string', 'format': 'byte'},
                'notes': {'type': 'string'},
              },
            },
          },
        }),
      );
      final body = api.operations.single.body!;
      expect(body.bodyType, BodyType.multipart);
      expect(
        {for (final f in body.formFields) f.name: f.isFile},
        {'avatar': true, 'blob': true, 'notes': false},
      );
    });

    test('an unknown single content type falls back to raw with that type', () {
      final api = normalizeOpenApiV3(
        specWithContent({
          'text/plain': {
            'schema': {'type': 'string', 'example': 'hello'},
          },
        }),
      );
      final body = api.operations.single.body!;
      expect(body.bodyType, BodyType.raw);
      expect(body.contentType, 'text/plain');
      expect(body.raw, contains('hello'));
    });

    test('empty content map yields no body', () {
      final api = normalizeOpenApiV3(specWithContent(<String, dynamic>{}));
      expect(api.operations.single.body, isNull);
    });
  });

  group('security schemes', () {
    test('every scheme type maps to its SecuritySchemeKind', () {
      const schemeNames = [
        'basicAuth',
        'digestAuth',
        'keyHeader',
        'keyQuery',
        'oauth',
        'oidc',
        'mtls',
      ];
      final api = normalizeOpenApiV3({
        'info': {'title': 'T'},
        'components': {
          'securitySchemes': {
            'basicAuth': {'type': 'http', 'scheme': 'basic'},
            'digestAuth': {'type': 'http', 'scheme': 'digest'},
            'keyHeader': {'type': 'apiKey', 'in': 'header', 'name': 'X-Key'},
            'keyQuery': {'type': 'apiKey', 'in': 'query', 'name': 'k'},
            'oauth': {'type': 'oauth2'},
            'oidc': {'type': 'openIdConnect'},
            'mtls': {'type': 'mutualTLS'},
          },
        },
        'paths': {
          for (final name in schemeNames)
            '/$name': {
              'get': {
                'security': [
                  {name: <dynamic>[]},
                ],
              },
            },
        },
      });
      NormalizedSecurityScheme? kindOf(String name) =>
          api.operations.firstWhere((o) => o.path == '/$name').security;
      expect(kindOf('basicAuth')?.kind, SecuritySchemeKind.basic);
      expect(kindOf('digestAuth')?.kind, SecuritySchemeKind.unsupported);
      expect(kindOf('keyHeader')?.kind, SecuritySchemeKind.apiKeyHeader);
      expect(kindOf('keyHeader')?.apiKeyName, 'X-Key');
      expect(kindOf('keyQuery')?.kind, SecuritySchemeKind.apiKeyQuery);
      expect(kindOf('keyQuery')?.apiKeyName, 'k');
      expect(kindOf('oauth')?.kind, SecuritySchemeKind.oauth2);
      expect(kindOf('oidc')?.kind, SecuritySchemeKind.oauth2);
      expect(kindOf('mtls')?.kind, SecuritySchemeKind.unsupported);
    });

    test('op-level security: [] disables the inherited global scheme', () {
      final api = normalizeOpenApiV3({
        'info': {'title': 'T'},
        'components': {
          'securitySchemes': {
            'bearerAuth': {'type': 'http', 'scheme': 'bearer'},
          },
        },
        'security': [
          {'bearerAuth': <dynamic>[]},
        ],
        'paths': {
          '/open': {
            'get': {'security': <dynamic>[]},
          },
          '/locked': {'get': <String, dynamic>{}},
        },
      });
      final open = api.operations.firstWhere((o) => o.path == '/open');
      expect(open.security, isNull);
      final locked = api.operations.firstWhere((o) => o.path == '/locked');
      expect(locked.security?.kind, SecuritySchemeKind.bearer);
    });

    test('op-level security naming an undeclared scheme resolves to null', () {
      final api = normalizeOpenApiV3({
        'info': {'title': 'T'},
        'paths': {
          '/x': {
            'get': {
              'security': [
                {'ghost': <dynamic>[]},
              ],
            },
          },
        },
      });
      expect(api.operations.single.security, isNull);
    });
  });
}
