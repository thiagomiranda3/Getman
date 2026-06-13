import 'package:dio/dio.dart';

/// Web no-op: browsers manage TLS and proxying themselves, and the XHR-based
/// adapter exposes no hooks for them.
void configureHttpAdapter(Dio dio, {required bool verifySsl, String? proxyUrl}) {}
