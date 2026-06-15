// Configures the Dio HTTP client adapter for SSL verification and proxy.
// Native-only (uses dart:io's HttpClient); a no-op stub on web, where the
// browser owns TLS and proxying. Resolved via conditional import so
// `dart:io` / `package:dio/io.dart` never reach the web build.
export 'dio_adapter_config_stub.dart'
    if (dart.library.io) 'dio_adapter_config_io.dart';
