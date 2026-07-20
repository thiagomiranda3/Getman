// Web stub half of writeMediaTempFile — throws, since media_kit playback
// needs a filesystem path; MediaResponseView catches this and shows the
// binary fallback card. See media_temp_file.dart for the routing.
import 'dart:typed_data';

/// Web (and any non-dart:io) build: writing a temp media file is unavailable.
/// The real implementation lives in `media_temp_file_io.dart`.
Future<String> writeMediaTempFile(Uint8List bytes, String ext) async {
  throw UnsupportedError('temp file unavailable on web');
}
