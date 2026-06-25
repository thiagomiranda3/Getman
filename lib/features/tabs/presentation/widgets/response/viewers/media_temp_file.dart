// Resolves to the real dart:io-based implementation on native platforms and to
// a stub on web (where dart:io / path_provider are unavailable).
export 'media_temp_file_stub.dart'
    if (dart.library.io) 'media_temp_file_io.dart';
