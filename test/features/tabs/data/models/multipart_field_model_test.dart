import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/features/tabs/data/models/multipart_field_model.dart';

void main() {
  group('MultipartFieldModel', () {
    test('round-trips a text row through fromEntity/toEntity', () {
      const entity = MultipartFieldEntity(name: 'field', value: 'v');
      final back = MultipartFieldModel.fromEntity(entity).toEntity();
      expect(back, entity);
    });

    test('round-trips a file row preserving path + contentType', () {
      const entity = MultipartFieldEntity(
        name: 'upload',
        isFile: true,
        filePath: '/tmp/a.png',
        contentType: 'image/png',
      );
      final back = MultipartFieldModel.fromEntity(entity).toEntity();
      expect(back, entity);
    });

    test('defaults: value empty, isFile false', () {
      final model = MultipartFieldModel(name: 'n');
      expect(model.value, '');
      expect(model.isFile, isFalse);
      expect(model.filePath, isNull);
    });
  });
}
