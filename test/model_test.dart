import 'package:flutter_test/flutter_test.dart';
import 'package:getman/models/request_config.dart';
import 'package:getman/models/settings_model.dart';

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

    test('SettingsModel toJson/fromJson', () {
      final settings = SettingsModel(historyLimit: 50, saveResponseInHistory: true);
      final json = settings.toJson();
      final fromJson = SettingsModel.fromJson(json);

      expect(fromJson.historyLimit, 50);
      expect(fromJson.saveResponseInHistory, true);
    });
  });
}
