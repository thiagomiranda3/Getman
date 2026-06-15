import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/cancel_handle.dart';
import 'package:getman/core/network/dio_adapter_config.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_config.dart';

// Re-exported so existing data-layer / test importers of `network_service.dart`
// keep resolving `NetworkCancelHandle` without churn; the domain layer imports
// `cancel_handle.dart` directly to stay dio/flutter-free.
export 'package:getman/core/network/cancel_handle.dart';

String _jsonEncode(dynamic data) => json.encode(data);

class NetworkService {
  NetworkService({required Dio dio}) : _dio = dio;
  final Dio _dio;

  static Dio buildDio([
    NetworkConfig config = NetworkConfig.defaults,
    Interceptor? cookieInterceptor,
  ]) {
    // responseType: plain keeps the raw server bytes as a String;
    // _stringifyBody's "if (data is String) return data" fast path then
    // short-circuits decode/re-encode, saving two full JSON passes per response.
    final dio = Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: config.connectTimeoutMs),
        sendTimeout: Duration(milliseconds: config.sendTimeoutMs),
        receiveTimeout: Duration(milliseconds: config.receiveTimeoutMs),
        followRedirects: config.followRedirects,
        maxRedirects: config.maxRedirects,
        validateStatus: (_) => true,
        listFormat: ListFormat.multi,
        responseType: ResponseType.plain,
      ),
    );
    configureHttpAdapter(
      dio,
      verifySsl: config.verifySsl,
      proxyUrl: config.proxyUrl,
      clientCertPath: config.clientCertPath,
      clientKeyPath: config.clientKeyPath,
      clientCertPassphrase: config.clientCertPassphrase,
    );
    if (cookieInterceptor != null) dio.interceptors.add(cookieInterceptor);
    // No dio LogInterceptor: it dumps a verbose *** Request *** / *** Response ***
    // block to the console on every send (and its onResponse prints regardless
    // of the `request` flag). The app already records every request in History
    // and surfaces responses + typed NetworkFailures in its own UI.
    return dio;
  }

  /// Re-applies [config] to the live client without rebuilding it: timeouts and
  /// follow/max-redirects are mutated on [BaseOptions]; SSL/proxy/client-cert
  /// swap the adapter. Interceptors (e.g. the cookie jar) are preserved.
  void applyConfig(NetworkConfig config) {
    _dio.options
      ..connectTimeout = Duration(milliseconds: config.connectTimeoutMs)
      ..sendTimeout = Duration(milliseconds: config.sendTimeoutMs)
      ..receiveTimeout = Duration(milliseconds: config.receiveTimeoutMs)
      ..followRedirects = config.followRedirects
      ..maxRedirects = config.maxRedirects;
    configureHttpAdapter(
      _dio,
      verifySsl: config.verifySsl,
      proxyUrl: config.proxyUrl,
      clientCertPath: config.clientCertPath,
      clientKeyPath: config.clientKeyPath,
      clientCertPassphrase: config.clientCertPassphrase,
    );
  }

  Future<HttpResponseEntity> request({
    required String url,
    required String method,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? headers,
    NetworkCancelHandle? cancelHandle,
  }) async {
    final stopwatch = Stopwatch()..start();
    final cancelToken = CancelToken();
    cancelHandle?.bindCancel(cancelToken.cancel);
    try {
      final response = await _dio.request<dynamic>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, headers: headers),
        cancelToken: cancelToken,
      );
      stopwatch.stop();

      final body = await _stringifyBody(response.data);
      return HttpResponseEntity(
        statusCode: response.statusCode ?? 0,
        body: body,
        headers: response.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      throw _mapDioException(e);
    } catch (e) {
      stopwatch.stop();
      throw NetworkFailure(e.toString(), type: NetworkFailureType.unknown);
    }
  }

  Future<String> _stringifyBody(dynamic data) async {
    if (data == null) return '';
    if (data is String) return data;
    try {
      return await compute(_jsonEncode, data);
    } on Object catch (e) {
      debugPrint('NetworkService._stringifyBody failed: $e');
      return data.toString();
    }
  }

  NetworkFailure _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const NetworkFailure(
          'Request cancelled',
          type: NetworkFailureType.cancelled,
        );
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return NetworkFailure(
          e.message ?? 'Connection failed',
          type: NetworkFailureType.connection,
        );
      case DioExceptionType.sendTimeout:
        return NetworkFailure(
          e.message ?? 'Send timeout',
          type: NetworkFailureType.sendTimeout,
        );
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(
          e.message ?? 'Receive timeout',
          type: NetworkFailureType.receiveTimeout,
        );
      case DioExceptionType.badCertificate:
        return NetworkFailure(
          e.message ?? 'Bad certificate',
          type: NetworkFailureType.badCertificate,
        );
      case DioExceptionType.badResponse:
        return NetworkFailure(
          e.message ?? 'Bad response',
          type: NetworkFailureType.badResponse,
          statusCode: e.response?.statusCode,
        );
      case DioExceptionType.unknown:
        return NetworkFailure(
          e.message ?? e.toString(),
          type: NetworkFailureType.unknown,
        );
    }
  }
}
