import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/domain/entities/request_config_entity.dart';

void main() {
  group('HttpRequestConfig', () {
    test('should convert to and from entity', () {
      const entity = HttpRequestConfigEntity(
        id: '1',
        url: 'https://example.com',
        method: 'GET',
      );

      final model = HttpRequestConfig.fromEntity(entity);
      expect(model.id, entity.id);
      expect(model.url, entity.url);

      final backToEntity = model.toEntity();
      expect(backToEntity, entity);
    });

    test('should compare correctly', () {
      final config1 = HttpRequestConfig(id: '1', method: 'GET', url: 'url');
      final config2 = HttpRequestConfig(id: '1', method: 'GET', url: 'url');
      
      expect(config1 == config2, true);
    });
  });
}
