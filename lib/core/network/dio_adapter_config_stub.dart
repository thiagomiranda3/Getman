import 'package:dio/dio.dart';

/// Web no-op: browsers manage TLS, proxying, and client certificates
/// themselves, and the XHR-based adapter exposes no hooks for them. The cert
/// params mirror the native signature (ignored) to keep the conditional-import
/// contract type-identical.
void configureHttpAdapter(
  Dio dio, {
  required bool verifySsl,
  String? proxyUrl,
  String? clientCertPath,
  String? clientKeyPath,
  String? clientCertPassphrase,
}) {}
