import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';

void main() {
  group('ParkedParamEntity', () {
    test('value equality across identical instances', () {
      const a = ParkedParamEntity(key: 'debug', value: 'true', rowIndex: 2);
      const b = ParkedParamEntity(key: 'debug', value: 'true', rowIndex: 2);
      expect(a, b);
    });

    test('props cover every field', () {
      const base = ParkedParamEntity(key: 'k', value: 'v', rowIndex: 0);
      expect(base == base.copyWith(key: 'other'), isFalse);
      expect(base == base.copyWith(value: 'other'), isFalse);
      expect(base == base.copyWith(rowIndex: 9), isFalse);
    });

    test('copyWith keeps omitted fields', () {
      const base = ParkedParamEntity(key: 'k', value: 'v', rowIndex: 3);
      final next = base.copyWith(value: 'w');
      expect(next.key, 'k');
      expect(next.value, 'w');
      expect(next.rowIndex, 3);
    });
  });
}
