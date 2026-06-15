import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/network/network_service.dart';

void main() {
  group('NetworkService.buildDio', () {
    test('applies timeouts and follow-redirects from the config', () {
      final dio = NetworkService.buildDio(const NetworkConfig(
        connectTimeoutMs: 1000,
        sendTimeoutMs: 2000,
        receiveTimeoutMs: 3000,
        followRedirects: false,
        maxRedirects: 2,
      ));
      expect(dio.options.connectTimeout, const Duration(milliseconds: 1000));
      expect(dio.options.sendTimeout, const Duration(milliseconds: 2000));
      expect(dio.options.receiveTimeout, const Duration(milliseconds: 3000));
      expect(dio.options.followRedirects, isFalse);
      expect(dio.options.maxRedirects, 2);
    });

    test('defaults preserve the prior hardcoded timeouts', () {
      final dio = NetworkService.buildDio();
      expect(dio.options.connectTimeout, const Duration(seconds: 30));
      expect(dio.options.sendTimeout, const Duration(seconds: 30));
      expect(dio.options.receiveTimeout, const Duration(seconds: 60));
      expect(dio.options.followRedirects, isTrue);
      expect(dio.options.maxRedirects, 5);
    });
  });

  test('applyConfig mutates options on the live client', () {
    final dio = NetworkService.buildDio();
    final service = NetworkService(dio: dio);

    service.applyConfig(const NetworkConfig(
      connectTimeoutMs: 5000,
      receiveTimeoutMs: 7000,
      followRedirects: false,
      maxRedirects: 1,
    ));

    expect(dio.options.connectTimeout, const Duration(milliseconds: 5000));
    expect(dio.options.receiveTimeout, const Duration(milliseconds: 7000));
    expect(dio.options.followRedirects, isFalse);
    expect(dio.options.maxRedirects, 1);
  });
}
