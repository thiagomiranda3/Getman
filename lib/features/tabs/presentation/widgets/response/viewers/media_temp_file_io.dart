import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Writes [bytes] to a temp file with the given extension and returns the file
/// path. Native (dart:io) implementation — see `media_temp_file.dart` for
/// routing.
Future<String> writeMediaTempFile(Uint8List bytes, String ext) async {
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/getman_media_${DateTime.now().millisecondsSinceEpoch}.$ext',
  );
  await file.writeAsBytes(bytes);
  return file.path;
}
