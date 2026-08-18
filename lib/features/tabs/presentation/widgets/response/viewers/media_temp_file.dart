// Conditional export for the media temp-file helpers (writeMediaTempFile /
// deleteMediaTempFile): resolves to the real dart:io implementation on native
// platforms and to a throwing/no-op stub on web (where dart:io /
// path_provider are unavailable). Keeps MediaResponseView web-safe.
export 'media_temp_file_stub.dart'
    if (dart.library.io) 'media_temp_file_io.dart';
