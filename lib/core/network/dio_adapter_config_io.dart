// Native Dio HTTP adapter config: swaps in an IOHttpClientAdapter honoring
// SSL verification, an optional host:port proxy, and client-certificate
// (mTLS) auth. Resolved into dio_adapter_config.dart via conditional
// import, so this file (and its dart:io / dio/io.dart imports) is excluded
// from web builds entirely. Also exposes buildConfiguredHttpClient — the
// same verify-SSL/proxy/mTLS/connect-timeout HttpClient as a standalone
// client for web_socket_connector_io.dart, so wss:// handshakes honor the
// exact settings plain https:// requests do.
//
// Gotchas: this is the ONLY place a dart:io SecurityContext gets built —
// core/network/network_config.dart deliberately keeps the cert trio as
// plain strings so no other file needs dart:io. Cert/key loading is
// wrapped in try/catch: a bad path or wrong passphrase falls back to a
// default (uncertified) client instead of crashing every send — but the
// failure is OBSERVABLE, never silent: every load attempt updates the
// top-level `lastCertificateError` (null on success / not configured), and
// callers may pass `onCertificateError` to be told the moment a load fails.
// The context is loaded EAGERLY (at configureHttpAdapter / per WS connect),
// not inside the adapter's createHttpClient callback, so a broken cert
// surfaces when settings are applied rather than on some later request.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// The failure message of the most recent client-certificate load attempt,
/// or null when it succeeded (or no certificate was configured). Updated by
/// [configureHttpAdapter] and [buildConfiguredHttpClient]; a UI surface can
/// read this to warn that requests are going out WITHOUT the configured mTLS
/// identity. Web builds always report null (see dio_adapter_config_stub.dart).
String? get lastCertificateError => _lastCertificateError;
String? _lastCertificateError;

/// Swaps in an [IOHttpClientAdapter] honoring SSL verification, an optional
/// `host:port` proxy, and an optional client certificate (mTLS). Replaces only
/// the adapter — interceptors on [dio] (e.g. the cookie interceptor) are
/// preserved.
///
/// For mTLS, a [SecurityContext] is built from the PEM cert + key paths (with
/// an optional passphrase) and passed to the [HttpClient]. Cert loading is
/// guarded: a bad path / wrong passphrase falls back to a default client
/// rather than crashing every send, records [lastCertificateError], and
/// invokes [onCertificateError] (when given) with the failure message.
void configureHttpAdapter(
  Dio dio, {
  required bool verifySsl,
  String? proxyUrl,
  String? clientCertPath,
  String? clientKeyPath,
  String? clientCertPassphrase,
  void Function(String message)? onCertificateError,
}) {
  // Loaded once per configure (not per createHttpClient call) so a broken
  // cert is reported the moment the config is applied.
  final context = _loadClientSecurityContext(
    clientCertPath: clientCertPath,
    clientKeyPath: clientKeyPath,
    clientCertPassphrase: clientCertPassphrase,
    onCertificateError: onCertificateError,
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => _httpClientWith(
      context: context,
      verifySsl: verifySsl,
      proxyUrl: proxyUrl,
    ),
  );
}

/// Builds a standalone [HttpClient] with the same verify-SSL / proxy / mTLS
/// behavior [configureHttpAdapter] gives the Dio adapter, plus an optional
/// socket [connectionTimeout] (ignored unless positive — 0/negative means
/// disabled, matching the Dio timeout convention). Used as the `customClient`
/// for wss:// handshakes (web_socket_connector_io.dart).
HttpClient buildConfiguredHttpClient({
  required bool verifySsl,
  String? proxyUrl,
  String? clientCertPath,
  String? clientKeyPath,
  String? clientCertPassphrase,
  Duration? connectionTimeout,
  void Function(String message)? onCertificateError,
}) => _httpClientWith(
  context: _loadClientSecurityContext(
    clientCertPath: clientCertPath,
    clientKeyPath: clientKeyPath,
    clientCertPassphrase: clientCertPassphrase,
    onCertificateError: onCertificateError,
  ),
  verifySsl: verifySsl,
  proxyUrl: proxyUrl,
  connectionTimeout: connectionTimeout,
);

/// Shared [HttpClient] construction for the adapter and the WS connector.
HttpClient _httpClientWith({
  required bool verifySsl,
  SecurityContext? context,
  String? proxyUrl,
  Duration? connectionTimeout,
}) {
  final client = HttpClient(context: context);
  if (!verifySsl) {
    client.badCertificateCallback = (cert, host, port) => true;
  }
  final proxy = proxyUrl?.trim() ?? '';
  if (proxy.isNotEmpty) {
    client.findProxy = (uri) => 'PROXY $proxy';
  }
  if (connectionTimeout != null && connectionTimeout > Duration.zero) {
    client.connectionTimeout = connectionTimeout;
  }
  return client;
}

/// Builds a [SecurityContext] with the client cert chain + private key when
/// both paths are supplied, else returns null (default context). Returns null
/// on any load error so a bad cert can't hard-crash a send — recording the
/// failure in [lastCertificateError] and forwarding it to
/// [onCertificateError] so the drop to a cert-less client is never silent.
SecurityContext? _loadClientSecurityContext({
  String? clientCertPath,
  String? clientKeyPath,
  String? clientCertPassphrase,
  void Function(String message)? onCertificateError,
}) {
  // Every attempt resets the signal: removing a broken cert config (or fixing
  // it) clears the stale error.
  _lastCertificateError = null;
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
    final message = 'Client certificate load failed: $e';
    _lastCertificateError = message;
    onCertificateError?.call(message);
    debugPrint('$message (falling back to a certificate-less client)');
    return null;
  }
}
