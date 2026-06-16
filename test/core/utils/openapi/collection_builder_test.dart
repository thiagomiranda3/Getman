import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
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
}
