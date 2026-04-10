import 'package:flutter_test/flutter_test.dart';
import 'package:getman/models/request_config.dart';

void main() {
  group('Model Serialization Tests', () {
    test('HttpRequestConfig toJson/fromJson', () {
      final config = HttpRequestConfig(
        method: 'POST',
        url: 'https://api.example.com',
        headers: {'Content-Type': 'application/json'},
        body: '{"test": true}',
      );

      final json = config.toJson();
      final fromJson = HttpRequestConfig.fromJson(json);

      expect(fromJson.method, config.method);
      expect(fromJson.url, config.url);
      expect(fromJson.headers['Content-Type'], 'application/json');
      expect(fromJson.body, config.body);
    });

    test('HttpRequestConfig Equality', () {
      final config1 = HttpRequestConfig(url: 'https://test.com', method: 'GET');
      final config2 = HttpRequestConfig(url: 'https://test.com', method: 'GET');
      // They have different auto-generated IDs, so we set them same for test
      config2.id = config1.id;

      expect(config1 == config2, true);
      expect(config1.hashCode == config2.hashCode, true);

      final config3 = config1.copyWith(method: 'POST');
      expect(config1 == config3, false);
    });
  });
}
