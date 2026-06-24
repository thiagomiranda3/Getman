import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/cancel_handle.dart';
import 'package:getman/core/network/dio_adapter_config.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/core/utils/response_media.dart';

// Re-exported so existing data-layer / test importers of `network_service.dart`
// keep resolving `NetworkCancelHandle` without churn; the domain layer imports
// `cancel_handle.dart` directly to stay dio/flutter-free.
export 'package:getman/core/network/cancel_handle.dart';

class NetworkService {
  NetworkService({
    required Dio dio,
    int maxResponseBytes = kMaxRenderableResponseBytes,
  }) : _dio = dio,
       _maxResponseBytes = maxResponseBytes;
  final Dio _dio;
  final int _maxResponseBytes;

  static Dio buildDio([
    NetworkConfig config = NetworkConfig.defaults,
    Interceptor? cookieInterceptor,
  ]) {
    // responseType: stream delivers the body as a raw byte stream so we can
    // cap it at _maxResponseBytes, classify it, and either decode to a String
    // (textual) or keep the raw bytes (media/binary) without two JSON passes.
    final dio = Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: config.connectTimeoutMs),
        sendTimeout: Duration(milliseconds: config.sendTimeoutMs),
        receiveTimeout: Duration(milliseconds: config.receiveTimeoutMs),
        followRedirects: config.followRedirects,
        maxRedirects: config.maxRedirects,
        validateStatus: (_) => true,
        listFormat: ListFormat.multi,
        responseType: ResponseType.stream,
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
    // Hoisted outside the try/catch so the DioException handler can read it.
    // Set to true when the accumulation loop exceeds _maxResponseBytes; a
    // cap-overflow cancel that subsequently races into the outer catch must
    // still produce a normal "too large" entity rather than a NetworkFailure.
    var capOverflow = false;
    try {
      final response = await _dio.request<ResponseBody>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
      final headersMap = response.headers.map.map(
        (k, v) => MapEntry(k, v.join(', ')),
      );
      final status = response.statusCode ?? 0;

      // Early-out: declared length already over the cap → don't read at all.
      final declared = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (declared != null && declared > _maxResponseBytes) {
        cancelToken.cancel();
        stopwatch.stop();
        return HttpResponseEntity(
          statusCode: status,
          body: _tooLargePlaceholder(headersMap, url, declared),
          headers: headersMap,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }

      final stream = response.data?.stream;
      final builder = BytesBuilder(copy: false);
      if (stream != null) {
        try {
          await for (final chunk in stream) {
            builder.add(chunk);
            if (builder.length > _maxResponseBytes) {
              capOverflow = true;
              cancelToken.cancel();
              break;
            }
          }
        } on DioException catch (e) {
          // Cap-overflow cancel raced the `break` — absorb it; `capOverflow`
          // drives the result below. Re-throw anything else so it falls
          // through to the outer handler (genuine transport cancel, etc.).
          if (!(capOverflow && e.type == DioExceptionType.cancel)) rethrow;
        }
      }
      stopwatch.stop();

      if (capOverflow) {
        return HttpResponseEntity(
          statusCode: status,
          body: _tooLargePlaceholder(headersMap, url, builder.length),
          headers: headersMap,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }

      final bytes = builder.takeBytes();
      final contentType = contentTypeOf(headersMap);
      final kind = bytes.isEmpty
          ? ResponseMediaKind.textual
          : classifyResponseMedia(
              contentType: contentType,
              url: url,
              sniffBytes: bytes,
            );

      if (kind == ResponseMediaKind.textual) {
        return HttpResponseEntity(
          statusCode: status,
          body: bytes.isEmpty ? '' : utf8.decode(bytes, allowMalformed: true),
          headers: headersMap,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
      return HttpResponseEntity(
        statusCode: status,
        body: _mediaPlaceholder(contentType, kind, bytes.length),
        headers: headersMap,
        durationMs: stopwatch.elapsedMilliseconds,
        bodyBytes: bytes,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      // If a cap-overflow cancel raced through Dio's adapter pipeline and
      // escaped the inner try/catch (e.g. via subscription.cancel() rejection
      // propagating through handleResponseStream), absorb it and return the
      // too-large placeholder. Any cancel that is NOT from an overflow is
      // a genuine user/transport cancel → NetworkFailure as normal.
      if (capOverflow && e.type == DioExceptionType.cancel) {
        // Cap-overflow cancel escaped through Dio's pipeline. Return a
        // generic too-large entity (headers/size unavailable at this point).
        return HttpResponseEntity(
          statusCode: 0,
          body: '[too large to buffer — open externally]',
          headers: const {},
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
      throw mapDioException(e);
    } catch (e) {
      stopwatch.stop();
      throw NetworkFailure(e.toString(), type: NetworkFailureType.unknown);
    }
  }

  String _mediaPlaceholder(String? contentType, ResponseMediaKind kind, int n) {
    final label = contentType ?? kind.name;
    return '[$label · ${formatBytes(n)} — open the PREVIEW tab to view]';
  }

  String _tooLargePlaceholder(
    Map<String, String> headers,
    String url,
    int size,
  ) {
    final ct = contentTypeOf(headers) ?? 'binary';
    final sz = formatBytes(size);
    return '[$ct · $sz — too large to buffer; open externally]';
  }

  @visibleForTesting
  NetworkFailure mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const NetworkFailure(
          'Request cancelled',
          type: NetworkFailureType.cancelled,
        );
      case DioExceptionType.connectionTimeout:
        return NetworkFailure(
          e.message ?? 'Connection timed out',
          type: NetworkFailureType.connectionTimeout,
        );
      case DioExceptionType.connectionError:
        return NetworkFailure(
          e.message ?? 'Connection failed',
          type: NetworkFailureType.connectionError,
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
