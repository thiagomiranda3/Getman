// Native Dio HTTP adapter config: swaps in an IOHttpClientAdapter honoring
// SSL verification, an optional host:port proxy, and client-certificate
// (mTLS) auth. Resolved into dio_adapter_config.dart via conditional
// import, so this file (and its dart:io / dio/io.dart imports) is excluded
// from web builds entirely.
//
// Gotchas: this is the ONLY place a dart:io SecurityContext gets built —
// core/network/network_config.dart deliberately keeps the cert trio as
// plain strings so no other file needs dart:io. Cert/key loading is
// wrapped in try/catch: a bad path or wrong passphrase logs and falls back
// to a default (uncertified) client instead of crashing every send.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// Swaps in an [IOHttpClientAdapter] honoring SSL verification, an optional
/// `host:port` proxy, and an optional client certificate (mTLS). Replaces only
/// the adapter — interceptors on [dio] (e.g. the cookie interceptor) are
/// preserved.
///
/// For mTLS, a [SecurityContext] is built from the PEM cert + key paths (with
/// an optional passphrase) and passed to the [HttpClient]. Cert loading is
/// guarded: a bad path / wrong passphrase logs and falls back to a default
/// client rather than crashing every send.
void configureHttpAdapter(
  Dio dio, {
  required bool verifySsl,
  String? proxyUrl,
  String? clientCertPath,
  String? clientKeyPath,
  String? clientCertPassphrase,
}) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient(
        context: _securityContext(
          clientCertPath: clientCertPath,
          clientKeyPath: clientKeyPath,
          clientCertPassphrase: clientCertPassphrase,
        ),
      );
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

/// Builds a [SecurityContext] with the client cert chain + private key when
/// both paths are supplied, else returns null (default context). Returns null
/// on any load error so a bad cert can't hard-crash a send.
SecurityContext? _securityContext({
  String? clientCertPath,
  String? clientKeyPath,
  String? clientCertPassphrase,
}) {
  final cert = clientCertPath?.trim() ?? '';
  final key = clientKeyPath?.trim() ?? '';
  if (cert.isEmpty || key.isEmpty) return null;
  try {
    final pass = clientCertPassphrase;
    final context = SecurityContext(withTrustedRoots: true)
      ..useCertificateChain(cert)
      ..usePrivateKey(
        key,
        password: (pass != null && pass.isNotEmpty) ? pass : null,
      );
    return context;
  } on Object catch (e) {
    debugPrint('Client certificate load failed (falling back to default): $e');
    return null;
  }
}
