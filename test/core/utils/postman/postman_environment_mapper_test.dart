import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/postman/postman_environment_mapper.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

void main() {
  group('PostmanEnvironmentMapper.toJson', () {
    test('emits id, name, values with enabled=true', () {
      final env = EnvironmentEntity(
        name: 'Staging',
        variables: const {'host': 'staging.api', 'token': 'abc'},
      );
      final decoded = jsonDecode(PostmanEnvironmentMapper.toJson(env)) as Map<String, dynamic>;
      expect(decoded['name'], 'Staging');
      expect(decoded['_postman_variable_scope'], 'environment');
      expect(decoded['id'], isA<String>());
      final values = decoded['values'] as List;
      expect(values, hasLength(2));
      expect(values.every((v) => (v as Map)['enabled'] == true), isTrue);
      final hostEntry = values.firstWhere((v) => (v as Map)['key'] == 'host') as Map;
      expect(hostEntry['value'], 'staging.api');
    });
  });

  group('PostmanEnvironmentMapper.toJsonAll', () {
    test('emits a JSON array when given multiple envs', () {
      final a = EnvironmentEntity(name: 'A', variables: const {'x': '1'});
      final b = EnvironmentEntity(name: 'B', variables: const {'y': '2'});
      final decoded = jsonDecode(PostmanEnvironmentMapper.toJsonAll([a, b])) as List;
      expect(decoded, hasLength(2));
      expect((decoded[0] as Map)['name'], 'A');
      expect((decoded[1] as Map)['name'], 'B');
    });
  });

  group('PostmanEnvironmentMapper.fromJson', () {
    test('parses a single-env JSON object', () {
      const source = '''
{
  "id": "orig-id",
  "name": "Prod",
  "values": [
    {"key": "API_HOST", "value": "https://api.prod", "enabled": true},
    {"key": "DEBUG", "value": "false", "enabled": false}
  ]
}
''';
      final envs = PostmanEnvironmentMapper.fromJson(source);
      expect(envs, hasLength(1));
      final env = envs.first;
      expect(env.name, 'Prod');
      expect(env.variables, {'API_HOST': 'https://api.prod'});
      expect(env.id, isNot('orig-id'),
          reason: 'imported envs must get fresh UUIDs to avoid collisions');
    });

    test('parses a JSON array of envs', () {
      const source = '''
[
  {"name": "A", "values": [{"key": "x", "value": "1"}]},
  {"name": "B", "values": [{"key": "y", "value": "2"}]}
]
''';
      final envs = PostmanEnvironmentMapper.fromJson(source);
      expect(envs.map((e) => e.name), ['A', 'B']);
      expect(envs[0].variables, {'x': '1'});
      expect(envs[1].variables, {'y': '2'});
    });

    test('throws FormatException on malformed input', () {
      expect(() => PostmanEnvironmentMapper.fromJson('nope'), throwsFormatException);
    });

    test('throws FormatException when the top-level value is not an object or array', () {
      expect(() => PostmanEnvironmentMapper.fromJson('42'), throwsFormatException);
    });
  });

  group('round-trip', () {
    test('single env round-trip preserves name and variables', () {
      final original = EnvironmentEntity(
        name: 'Dev',
        variables: const {'a': '1', 'b': '2'},
      );
      final json = PostmanEnvironmentMapper.toJson(original);
      final envs = PostmanEnvironmentMapper.fromJson(json);
      expect(envs, hasLength(1));
      expect(envs.first.name, 'Dev');
      expect(envs.first.variables, original.variables);
    });

    test('multi env round-trip preserves all envs', () {
      final envs = [
        EnvironmentEntity(name: 'A', variables: const {'x': '1'}),
        EnvironmentEntity(name: 'B', variables: const {'y': '2', 'z': '3'}),
      ];
      final json = PostmanEnvironmentMapper.toJsonAll(envs);
      final reimported = PostmanEnvironmentMapper.fromJson(json);
      expect(reimported.map((e) => e.name), ['A', 'B']);
      expect(reimported[0].variables, {'x': '1'});
      expect(reimported[1].variables, {'y': '2', 'z': '3'});
    });
  });
}
