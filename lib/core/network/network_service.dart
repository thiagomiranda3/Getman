import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../error/failures.dart';
import 'http_response.dart';

String _jsonEncode(dynamic data) => json.encode(data);

class NetworkCancelHandle {
  final CancelToken _token;
  NetworkCancelHandle() : _token = CancelToken();

  bool get isCancelled => _token.isCancelled;
  void cancel([String reason = 'Cancelled']) {
    if (!_token.isCancelled) _token.cancel(reason);
  }
}

class NetworkService {
  final Dio _dio;

  NetworkService({required Dio dio}) : _dio = dio;

  static Dio buildDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      validateStatus: (_) => true,
    ));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        requestHeader: false,
        responseHeader: false,
        request: true,
        error: true,
      ));
    }
    return dio;
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
    try {
      final response = await _dio.request(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, headers: headers),
        cancelToken: cancelHandle?._token,
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
    } catch (e) {
      debugPrint('NetworkService._stringifyBody failed: $e');
      return data.toString();
    }
  }

  NetworkFailure _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const NetworkFailure('Request cancelled', type: NetworkFailureType.cancelled);
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return NetworkFailure(e.message ?? 'Connection failed', type: NetworkFailureType.connection);
      case DioExceptionType.sendTimeout:
        return NetworkFailure(e.message ?? 'Send timeout', type: NetworkFailureType.sendTimeout);
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(e.message ?? 'Receive timeout', type: NetworkFailureType.receiveTimeout);
      case DioExceptionType.badCertificate:
        return NetworkFailure(e.message ?? 'Bad certificate', type: NetworkFailureType.badCertificate);
      case DioExceptionType.badResponse:
        return NetworkFailure(
          e.message ?? 'Bad response',
          type: NetworkFailureType.badResponse,
          statusCode: e.response?.statusCode,
        );
      case DioExceptionType.unknown:
        return NetworkFailure(e.message ?? e.toString(), type: NetworkFailureType.unknown);
    }
  }
}
