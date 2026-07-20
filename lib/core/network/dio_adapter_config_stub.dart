// Web no-op counterpart to dio_adapter_config_io.dart: browsers own TLS,
// proxying, and client certs, so this does nothing. Signature is kept
// identical (unused cert params included) so the conditional-import
// contract in dio_adapter_config.dart type-checks on both platforms.

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
