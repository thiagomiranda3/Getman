import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/features/tabs/data/models/parked_param_model.dart';

void main() {
  group('ParkedParamModel', () {
    test('round-trips through fromEntity/toEntity', () {
      const entity = ParkedParamEntity(
        key: 'debug',
        value: 'true',
        rowIndex: 2,
      );
      final back = ParkedParamModel.fromEntity(entity).toEntity();
      expect(back, entity);
    });

    test('defaults: value empty, rowIndex 0', () {
      final model = ParkedParamModel(key: 'k');
      expect(model.value, '');
      expect(model.rowIndex, 0);
    });
  });
}
