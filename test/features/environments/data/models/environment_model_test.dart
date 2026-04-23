import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

void main() {
  group('EnvironmentModel', () {
    test('entity -> model -> entity roundtrip preserves fields', () {
      final entity = EnvironmentEntity(
        id: 'env-1',
        name: 'Local',
        variables: const {'baseUrl': 'http://localhost', 'token': 'abc'},
      );
      final model = EnvironmentModel.fromEntity(entity);
      final back = model.toEntity();
      expect(back.id, 'env-1');
      expect(back.name, 'Local');
      expect(back.variables, {'baseUrl': 'http://localhost', 'token': 'abc'});
    });

    test('constructor generates id when not provided', () {
      final model = EnvironmentModel(name: 'X');
      expect(model.id.isNotEmpty, true);
    });

    test('constructor defaults variables to empty map', () {
      final model = EnvironmentModel(name: 'X');
      expect(model.variables, isEmpty);
    });

    test('EnvironmentEntity.copyWith updates name', () {
      final entity = EnvironmentEntity(id: 'a', name: 'Old');
      final copy = entity.copyWith(name: 'New');
      expect(copy.name, 'New');
      expect(copy.id, 'a');
    });

    test('EnvironmentEntity.copyWith updates variables', () {
      final entity = EnvironmentEntity(id: 'a', name: 'Env');
      final copy = entity.copyWith(variables: {'x': '1'});
      expect(copy.variables, {'x': '1'});
      expect(copy.name, 'Env');
    });
  });
}
