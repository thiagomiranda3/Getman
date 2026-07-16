import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/network/network_service.dart';

class _CloseSpyAdapter implements HttpClientAdapter {
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(const [], 200);

  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  group('NetworkService.buildDio', () {
    test('applies timeouts and follow-redirects from the config', () {
      final dio = NetworkService.buildDio(
        const NetworkConfig(
          connectTimeoutMs: 1000,
          sendTimeoutMs: 2000,
          receiveTimeoutMs: 3000,
          followRedirects: false,
          maxRedirects: 2,
        ),
      );
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
    NetworkService(dio: dio).applyConfig(
      const NetworkConfig(
        connectTimeoutMs: 5000,
        receiveTimeoutMs: 7000,
        followRedirects: false,
        maxRedirects: 1,
      ),
    );

    expect(dio.options.connectTimeout, const Duration(milliseconds: 5000));
    expect(dio.options.receiveTimeout, const Duration(milliseconds: 7000));
    expect(dio.options.followRedirects, isFalse);
    expect(dio.options.maxRedirects, 1);
  });

  group('applyConfig — adapter reuse (G7)', () {
    test('a timeout-only change keeps the same adapter instance', () {
      final dio = NetworkService.buildDio();
      final svc = NetworkService(dio: dio)
        ..applyConfig(
          const NetworkConfig(connectTimeoutMs: 1000, proxyUrl: 'p:1'),
        );
      final adapter = _CloseSpyAdapter();
      dio.httpClientAdapter = adapter;

      svc.applyConfig(
        const NetworkConfig(connectTimeoutMs: 9999, proxyUrl: 'p:1'),
      );

      expect(dio.httpClientAdapter, same(adapter));
      expect(adapter.closed, isFalse);
      // Timeouts still land on BaseOptions in place.
      expect(dio.options.connectTimeout, const Duration(milliseconds: 9999));
    });

    test('a proxy change swaps the adapter and closes the old one', () {
      final dio = NetworkService.buildDio();
      final svc = NetworkService(dio: dio)
        ..applyConfig(const NetworkConfig(proxyUrl: 'a:1'));
      final adapter = _CloseSpyAdapter();
      dio.httpClientAdapter = adapter;

      svc.applyConfig(const NetworkConfig(proxyUrl: 'b:2'));

      expect(dio.httpClientAdapter, isNot(same(adapter)));
      expect(adapter.closed, isTrue);
    });
  });

  group('mapDioException — connection split', () {
    final svc = NetworkService(dio: Dio());
    DioException ex(DioExceptionType t) => DioException(
      requestOptions: RequestOptions(path: '/'),
      type: t,
    );

    test('connectionTimeout → NetworkFailureType.connectionTimeout', () {
      expect(
        svc.mapDioException(ex(DioExceptionType.connectionTimeout)).type,
        NetworkFailureType.connectionTimeout,
      );
    });
    test('connectionError → NetworkFailureType.connectionError', () {
      expect(
        svc.mapDioException(ex(DioExceptionType.connectionError)).type,
        NetworkFailureType.connectionError,
      );
    });
    test('sendTimeout → NetworkFailureType.sendTimeout', () {
      expect(
        svc.mapDioException(ex(DioExceptionType.sendTimeout)).type,
        NetworkFailureType.sendTimeout,
      );
    });
  });
}
