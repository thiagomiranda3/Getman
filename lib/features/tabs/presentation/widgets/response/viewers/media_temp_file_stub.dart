import 'dart:typed_data';

/// Web (and any non-dart:io) build: writing a temp media file is unavailable.
/// The real implementation lives in `media_temp_file_io.dart`.
Future<String> writeMediaTempFile(Uint8List bytes, String ext) async {
  throw UnsupportedError('temp file unavailable on web');
}
