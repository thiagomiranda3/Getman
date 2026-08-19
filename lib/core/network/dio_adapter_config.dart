// Conditional-import seam for configureHttpAdapter (SSL verification,
// proxy, client-cert/mTLS): resolves to dio_adapter_config_io.dart natively
// (dart:io's HttpClient) or dio_adapter_config_stub.dart on web (a no-op,
// since browsers own TLS/proxying), so `dart:io` / `package:dio/io.dart`
// never reach the web build. Also re-exports lastCertificateError — the
// observable signal that the configured client certificate failed to load
// and requests are going out WITHOUT mTLS (always null on web). The
// native-only buildConfiguredHttpClient (returns a dart:io HttpClient) is
// deliberately NOT exported — *_io.dart files import the io file directly.
export 'dio_adapter_config_stub.dart'
    if (dart.library.io) 'dio_adapter_config_io.dart'
    show configureHttpAdapter, lastCertificateError;
