// Conditional export for writeMediaTempFile: resolves to the real dart:io
// implementation on native platforms and to a throwing stub on web (where
// dart:io / path_provider are unavailable). Keeps MediaResponseView web-safe.
export 'media_temp_file_stub.dart'
    if (dart.library.io) 'media_temp_file_io.dart';
