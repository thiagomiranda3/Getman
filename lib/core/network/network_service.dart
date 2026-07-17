// NetworkService: builds/owns the live Dio client and performs every HTTP
// send, streaming the response body so it can be capped at
// kMaxRenderableResponseBytes, classified (textual vs media/binary), and
// decoded honoring a declared charset — oversize bodies become a "too
// large" placeholder instead of buffering into memory.
//
// Gotchas: redirects are followed with a MANUAL loop, not Dio's built-in
// follow — each hop is sent with followRedirects:false so the cookie
// interceptor runs per hop (a login 302's Set-Cookie is captured and
// re-matched on the next hop; dart:io's auto-follow would discard it). 303
// and POST-triggered 301/302 become bodyless GETs; 307/308 (and non-POST
// 301/302) keep method+body; `Authorization` is stripped whenever a
// redirect crosses hosts. applyConfig only rebuilds the HTTP adapter when
// NetworkConfig.sameAdapterConfig says an adapter-relevant field changed
// (SSL/proxy/cert), closing the replaced adapter — timeout/redirect-count
// edits just mutate BaseOptions in place.

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
    required this._dio,
    this._maxResponseBytes = kMaxRenderableResponseBytes,
  });
  final Dio _dio;
  final int _maxResponseBytes;

  /// The adapter-relevant config of the last [applyConfig] that rebuilt the
  /// adapter. Null until the first swap so an initial [applyConfig] always
  /// configures the adapter.
  NetworkConfig? _adapterConfig;

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
    // Rebuilding the adapter drops its socket pool, so only swap when an
    // adapter-relevant field actually changed — not on every timeout/redirect
    // keystroke (which used to orphan a fresh IOHttpClientAdapter each time).
    if (_adapterConfig != null && _adapterConfig!.sameAdapterConfig(config)) {
      return;
    }
    _adapterConfig = config;
    final old = _dio.httpClientAdapter;
    configureHttpAdapter(
      _dio,
      verifySsl: config.verifySsl,
      proxyUrl: config.proxyUrl,
      clientCertPath: config.clientCertPath,
      clientKeyPath: config.clientKeyPath,
      clientCertPassphrase: config.clientCertPassphrase,
    );
    // Release the replaced adapter's connections. The web stub leaves the
    // adapter untouched (no-op), so only close when it was actually swapped.
    if (!identical(_dio.httpClientAdapter, old)) old.close();
  }

  static const Set<int> _redirectStatuses = {301, 302, 303, 307, 308};

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

    // Redirects are followed manually (followRedirects: false per hop) so each
    // hop is a full Dio request: the cookie interceptor runs per hop, capturing
    // a login 302's Set-Cookie and sending it on the next hop — dart:io's auto
    // follow discards intermediate 3xx headers and reuses the original Cookie.
    final followRedirects = _dio.options.followRedirects;
    final maxRedirects = _dio.options.maxRedirects;

    var currentUrl = url;
    var currentMethod = method;
    dynamic currentData = data;
    final currentHeaders = <String, dynamic>{...?headers};
    // Query params apply to the first hop only; a resolved Location URL already
    // carries its own query.
    var currentQuery = queryParameters;
    var redirects = 0;

    try {
      while (true) {
        // Dio finalizes a FormData on send, and a finalized instance throws if
        // reused — so a body-preserving redirect (307/308, or 301/302 on a
        // non-POST) would fail on hop 2 with an opaque StateError. Send a
        // clone each hop and keep the original pristine (FormData.clone() is
        // dio's documented retry mechanism). String/Map/List bodies re-send
        // safely as-is.
        final hopData = currentData is FormData
            ? currentData.clone()
            : currentData;
        final response = await _dio.request<ResponseBody>(
          currentUrl,
          data: hopData,
          queryParameters: currentQuery,
          options: Options(
            method: currentMethod,
            headers: currentHeaders,
            responseType: ResponseType.stream,
            followRedirects: false,
          ),
          cancelToken: cancelToken,
        );

        final status = response.statusCode ?? 0;
        final location = response.headers.value('location')?.trim();
        final ref = (location == null || location.isEmpty)
            ? null
            : Uri.tryParse(location);

        if (followRedirects &&
            ref != null &&
            _redirectStatuses.contains(status)) {
          if (redirects >= maxRedirects) {
            // Surface the same class of error Dio would when the HttpClient
            // exceeds its redirect limit (mapped to NetworkFailure.unknown).
            throw DioException(
              requestOptions: response.requestOptions,
              message: 'Redirect limit ($maxRedirects) exceeded',
            );
          }
          // Free the 3xx body's socket before the next hop.
          await _drain(response.data?.stream);

          final fromUri = response.requestOptions.uri;
          final nextUri = fromUri.resolveUri(ref);

          // Method/body transform (browser/curl convention): 303 always becomes
          // a bodyless GET; 301/302 do too when the method was POST; 307/308
          // (and non-POST 301/302) keep both.
          final wasPost = currentMethod.toUpperCase() == 'POST';
          final toGet =
              status == 303 || ((status == 301 || status == 302) && wasPost);
          if (toGet) {
            currentMethod = 'GET';
            currentData = null;
            currentHeaders.removeWhere((k, _) {
              final lk = k.toLowerCase();
              return lk == 'content-type' || lk == 'content-length';
            });
          }
          // Never leak credentials across an origin boundary (dart:io parity).
          if (nextUri.host.toLowerCase() != fromUri.host.toLowerCase()) {
            currentHeaders.removeWhere(
              (k, _) => k.toLowerCase() == 'authorization',
            );
          }

          currentUrl = nextUri.toString();
          currentQuery = null;
          redirects++;
          continue;
        }

        return await _buildResponse(
          response,
          currentUrl,
          stopwatch,
          cancelToken,
        );
      }
    } on DioException catch (e) {
      stopwatch.stop();
      throw mapDioException(e);
    } catch (e) {
      stopwatch.stop();
      throw NetworkFailure(e.toString(), type: NetworkFailureType.unknown);
    }
  }

  /// Reads [response]'s body (capping at [_maxResponseBytes]) and classifies it
  /// into the final [HttpResponseEntity]. [url] is the final hop's URL (used in
  /// the too-large / media placeholders); [stopwatch] spans the whole chain.
  Future<HttpResponseEntity> _buildResponse(
    Response<ResponseBody> response,
    String url,
    Stopwatch stopwatch,
    CancelToken cancelToken,
  ) async {
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
    var overflow = false;
    if (stream != null) {
      await for (final chunk in stream) {
        builder.add(chunk);
        if (builder.length > _maxResponseBytes) {
          overflow = true;
          cancelToken.cancel();
          break;
        }
      }
    }
    stopwatch.stop();

    if (overflow) {
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
        body: bytes.isEmpty ? '' : _decodeTextual(bytes, headersMap),
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
  }

  /// Consumes and discards a redirect response's body stream so its underlying
  /// connection is released before the next hop. Best-effort — a stream error
  /// here must not fail the send.
  Future<void> _drain(Stream<Uint8List>? stream) async {
    if (stream == null) return;
    try {
      await stream.drain<void>();
    } on Object catch (_) {
      // Ignore: the redirect's body is irrelevant, and any error will resurface
      // on the next hop's request if the connection is truly broken.
    }
  }

  /// Decodes a textual body honoring the declared `charset` (read from the raw
  /// Content-Type header — [contentTypeOf] strips the parameters). ISO-8859-1
  /// family charsets decode as latin1; everything else falls back to UTF-8 with
  /// malformed sequences replaced (the safe default for unlabeled bodies).
  String _decodeTextual(Uint8List bytes, Map<String, String> headers) {
    switch (_charsetOf(headers)) {
      case 'iso-8859-1':
      case 'latin1':
      case 'us-ascii':
        return latin1.decode(bytes, allowInvalid: true);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static final RegExp _charsetPattern = RegExp(
    r'charset\s*=\s*"?([^";]+)"?',
    caseSensitive: false,
  );

  /// Extracts the lowercased `charset` token from the (case-insensitive)
  /// Content-Type header, or null when absent.
  String? _charsetOf(Map<String, String> headers) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'content-type') {
        final match = _charsetPattern.firstMatch(e.value);
        return match?.group(1)?.trim().toLowerCase();
      }
    }
    return null;
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
