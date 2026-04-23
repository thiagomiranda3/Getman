import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';

void main() {
  group('ActiveEnvironmentHelper.variablesFor', () {
    final envs = [
      EnvironmentEntity(id: 'a', name: 'Local', variables: const {'host': 'localhost'}),
      EnvironmentEntity(id: 'b', name: 'Prod', variables: const {'host': 'api.example.com'}),
    ];

    test('null activeId returns empty map', () {
      expect(ActiveEnvironmentHelper.variablesFor(envs, null), isEmpty);
    });

    test('missing activeId returns empty map', () {
      expect(ActiveEnvironmentHelper.variablesFor(envs, 'ghost'), isEmpty);
    });

    test('returns matching environment variables', () {
      expect(
        ActiveEnvironmentHelper.variablesFor(envs, 'b'),
        {'host': 'api.example.com'},
      );
    });

    test('empty env list returns empty map', () {
      expect(ActiveEnvironmentHelper.variablesFor(const [], 'a'), isEmpty);
    });
  });
}
