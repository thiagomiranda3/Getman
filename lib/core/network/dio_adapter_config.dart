// Conditional-import seam for configureHttpAdapter (SSL verification,
// proxy, client-cert/mTLS): resolves to dio_adapter_config_io.dart natively
// (dart:io's HttpClient) or dio_adapter_config_stub.dart on web (a no-op,
// since browsers own TLS/proxying), so `dart:io` / `package:dio/io.dart`
// never reach the web build.
export 'dio_adapter_config_stub.dart'
    if (dart.library.io) 'dio_adapter_config_io.dart';
