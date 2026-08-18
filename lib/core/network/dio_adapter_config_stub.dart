// Web no-op counterpart to dio_adapter_config_io.dart: browsers own TLS,
// proxying, and client certs, so this does nothing. Signature is kept
// identical (unused cert params + onCertificateError included) so the
// conditional-import contract in dio_adapter_config.dart type-checks on
// both platforms; lastCertificateError is always null on web (no cert is
// ever loaded here, so it can never fail).

import 'package:dio/dio.dart';

/// Web counterpart of the native `lastCertificateError`: always null — the
/// browser owns client certificates, so this build never loads (or fails to
/// load) one.
String? get lastCertificateError => null;

/// Web no-op: browsers manage TLS, proxying, and client certificates
/// themselves, and the XHR-based adapter exposes no hooks for them. The cert
/// params and [onCertificateError] mirror the native signature (ignored) to
/// keep the conditional-import contract type-identical.
void configureHttpAdapter(
  Dio dio, {
  required bool verifySsl,
  String? proxyUrl,
  String? clientCertPath,
  String? clientKeyPath,
  String? clientCertPassphrase,
  void Function(String message)? onCertificateError,
}) {}
