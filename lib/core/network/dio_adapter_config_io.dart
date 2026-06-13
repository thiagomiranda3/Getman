import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Swaps in an [IOHttpClientAdapter] honoring SSL verification and an optional
/// `host:port` proxy. Replaces only the adapter — interceptors on [dio] (e.g.
/// the cookie interceptor) are preserved.
void configureHttpAdapter(Dio dio, {required bool verifySsl, String? proxyUrl}) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      if (!verifySsl) {
        client.badCertificateCallback = (cert, host, port) => true;
      }
      final proxy = proxyUrl?.trim() ?? '';
      if (proxy.isNotEmpty) {
        client.findProxy = (uri) => 'PROXY $proxy';
      }
      return client;
    },
  );
}
