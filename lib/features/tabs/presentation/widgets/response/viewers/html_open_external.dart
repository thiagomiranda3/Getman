// Resolves to the real dart:io-based implementation on native platforms and to
// a no-op stub on web (where dart:io / path_provider are unavailable).
export 'html_open_external_stub.dart'
    if (dart.library.io) 'html_open_external_io.dart';
