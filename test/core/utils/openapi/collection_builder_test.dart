import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/utils/openapi/collection_builder.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';

NormalizedApi get _api => const NormalizedApi(
  title: 'Demo',
  servers: [
    NormalizedServer(url: 'https://api.example.com/v1', description: 'prod'),
    NormalizedServer(
      url: 'https://{host}/v1',
      description: 'custom',
      variables: {'host': 'staging.example.com'},
    ),
  ],
  operations: [
    NormalizedOperation(
      method: 'GET',
      path: '/users/{id}',
      name: 'Get user',
      tag: 'Users',
      queryParams: [NormalizedParam(name: 'verbose', value: 'true')],
      headerParams: [NormalizedParam(name: 'X-Trace', value: 't')],
      security: NormalizedSecurityScheme(kind: SecuritySchemeKind.bearer),
    ),
    NormalizedOperation(
      method: 'GET',
      path: '/ping',
      name: 'Ping', // untagged → grouped by first path segment 'ping'
    ),
  ],
);

void main() {
  test('root is named after the title', () {
    final result = buildImport(_api);
    expect(result.root.name, 'Demo');
    expect(result.root.isFolder, isTrue);
  });

  test('one environment per server, baseUrl concrete (vars substituted)', () {
    final result = buildImport(_api);
    expect(result.environments, hasLength(2));
    expect(
      result.environments[0].variables['baseUrl'],
      'https://api.example.com/v1',
    );
    expect(
      result.environments[1].variables['baseUrl'],
      'https://staging.example.com/v1',
    );
  });

  test('bearer secret var seeded into every environment', () {
    final result = buildImport(_api);
    for (final env in result.environments) {
      expect(env.variables.containsKey('bearerToken'), isTrue);
      expect(env.secretKeys.contains('bearerToken'), isTrue);
    }
  });

  test('tagged op lands in a folder named after the tag', () {
    final result = buildImport(_api);
    final usersFolder = result.root.children.firstWhere(
      (n) => n.name == 'Users',
    );
    expect(usersFolder.isFolder, isTrue);
    expect(usersFolder.children.single.name, 'Get user');
  });

  test('untagged op grouped by first path segment', () {
    final result = buildImport(_api);
    expect(result.root.children.any((n) => n.name == 'ping'), isTrue);
  });

  test(
    'operation-level server override produces a concrete absolute URL, '
    'bypassing {{baseUrl}}',
    () {
      const api = NormalizedApi(
        title: 'Demo',
        servers: [NormalizedServer(url: 'https://api.example.com/v1')],
        operations: [
          NormalizedOperation(
            method: 'POST',
            path: '/webhook',
            name: 'Webhook',
            server: NormalizedServer(
              url: 'https://{host}',
              variables: {'host': 'hooks.example.com'},
            ),
          ),
        ],
      );
      final result = buildImport(api);
      final leaf = result.root.children.single.children.single;
      expect(leaf.config!.url, 'https://hooks.example.com/webhook');
    },
  );

  test('leaf config: templated url, path-param tokenized, query + header', () {
    final result = buildImport(_api);
    final leaf = result.root.children
        .firstWhere((n) => n.name == 'Users')
        .children
        .single;
    final cfg = leaf.config!;
    expect(cfg.method, 'GET');
    expect(cfg.url, contains('{{baseUrl}}/users/{{id}}'));
    expect(cfg.url, contains('verbose=true'));
    expect(cfg.headers['X-Trace'], 't');
    expect(AuthConfig.fromMap(cfg.auth).type, AuthType.bearer);
  });

  test('no servers → single "Imported" environment with an empty baseUrl', () {
    const api = NormalizedApi(
      title: 'T',
      operations: [
        NormalizedOperation(
          method: 'GET',
          path: '/a',
          name: 'A',
          security: NormalizedSecurityScheme(
            kind: SecuritySchemeKind.apiKeyHeader,
            apiKeyName: 'X-K',
          ),
        ),
      ],
    );
    final result = buildImport(api);
    final env = result.environments.single;
    expect(env.name, 'Imported');
    expect(env.variables['baseUrl'], '');
    expect(
      env.variables['apiKey'],
      '',
      reason: 'secret vars are still seeded (empty) with no servers',
    );
    expect(env.secretKeys, contains('apiKey'));
  });

  test(
    'oauth2 auth warning is prefixed with method+path and op warnings '
    'propagate to the result',
    () {
      const api = NormalizedApi(
        title: 'T',
        operations: [
          NormalizedOperation(
            method: 'POST',
            path: '/pets',
            name: 'Create pet',
            security: NormalizedSecurityScheme(kind: SecuritySchemeKind.oauth2),
            warnings: ['body guessed from the first content type'],
          ),
        ],
      );
      final result = buildImport(api);
      expect(
        result.warnings,
        contains('body guessed from the first content type'),
      );
      expect(
        result.warnings.any(
          (w) => w.startsWith('POST /pets:') && w.contains('OAuth2'),
        ),
        isTrue,
      );
      expect(
        AuthConfig.fromMap(
          result.root.children.single.children.single.config!.auth,
        ).type,
        AuthType.none,
        reason: 'oauth2 maps to no auth',
      );
    },
  );

  test('an untagged op on the root path groups under "default"', () {
    const api = NormalizedApi(
      title: 'T',
      operations: [NormalizedOperation(method: 'GET', path: '/', name: 'Root')],
    );
    final result = buildImport(api);
    expect(result.root.children.single.name, 'default');
  });

  test('duplicate server names get numbered suffixes', () {
    const api = NormalizedApi(
      title: 'T',
      servers: [
        NormalizedServer(url: 'https://a.dev', description: 'prod'),
        NormalizedServer(url: 'https://b.dev', description: 'prod'),
        NormalizedServer(url: 'https://c.dev', description: 'prod'),
      ],
    );
    final result = buildImport(api);
    expect(result.environments.map((e) => e.name), [
      'prod',
      'prod (2)',
      'prod (3)',
    ]);
  });

  test(
    'server without a usable description is named by host, or "server" '
    'when the URL has no host',
    () {
      const api = NormalizedApi(
        title: 'T',
        servers: [
          NormalizedServer(url: 'https://api.example.com/v1'),
          NormalizedServer(url: 'https://h.dev', description: '   '),
          NormalizedServer(url: ''),
        ],
      );
      final result = buildImport(api);
      expect(result.environments.map((e) => e.name), [
        'api.example.com',
        'h.dev',
        'server',
      ]);
    },
  );

  test('raw JSON body lands on the leaf with its Content-Type header', () {
    const api = NormalizedApi(
      title: 'T',
      operations: [
        NormalizedOperation(
          method: 'POST',
          path: '/users',
          name: 'Create',
          body: NormalizedBody(
            bodyType: BodyType.raw,
            raw: '{\n  "name": ""\n}',
            contentType: 'application/json',
          ),
        ),
      ],
    );
    final result = buildImport(api);
    final cfg = result.root.children.single.children.single.config!;
    expect(cfg.bodyType, BodyType.raw);
    expect(cfg.body, contains('"name"'));
    expect(cfg.headers['Content-Type'], 'application/json');
  });

  test('form body carries its fields and sets no Content-Type header', () {
    const api = NormalizedApi(
      title: 'T',
      operations: [
        NormalizedOperation(
          method: 'POST',
          path: '/upload',
          name: 'Upload',
          body: NormalizedBody(
            bodyType: BodyType.multipart,
            formFields: [
              MultipartFieldEntity(name: 'avatar', isFile: true),
              MultipartFieldEntity(name: 'notes'),
            ],
          ),
        ),
      ],
    );
    final result = buildImport(api);
    final cfg = result.root.children.single.children.single.config!;
    expect(cfg.bodyType, BodyType.multipart);
    expect(cfg.formFields.map((f) => f.name), ['avatar', 'notes']);
    expect(
      cfg.headers.containsKey('Content-Type'),
      isFalse,
      reason: 'multipart content-type (with boundary) is set at send time',
    );
  });
}
