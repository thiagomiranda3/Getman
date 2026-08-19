// Native (dart:io) half of the media temp-file helpers used by
// MediaResponseView to hand media_kit a playable file path. Files live in a
// dedicated <tmp>/getman_media/ directory: the first write of a session
// purges that directory (sweeping files orphaned by crashes or previous
// sessions — macOS doesn't clean the temp dir intra-session), and
// deleteMediaTempFile best-effort removes a single file when its player
// restarts or unmounts. Routed to only on non-web platforms — see
// media_temp_file.dart.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Memoizes the once-per-session purge of the getman_media directory so
/// concurrent first writes share a single sweep.
Future<void>? _sessionPurge;

/// Writes [bytes] to `<tmp>/getman_media/getman_media_<ts>.<ext>` and returns
/// the file path. The first call of the session purges the directory first
/// (files orphaned by a crash or a previous session). Native (dart:io)
/// implementation — see `media_temp_file.dart` for routing.
Future<String> writeMediaTempFile(Uint8List bytes, String ext) async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/getman_media');
  await (_sessionPurge ??= _purgeMediaTempDir(dir));
  await dir.create(recursive: true);
  final file = File(
    '${dir.path}/getman_media_${DateTime.now().millisecondsSinceEpoch}.$ext',
  );
  await file.writeAsBytes(bytes);
  return file.path;
}

/// Best-effort delete of a file previously returned by [writeMediaTempFile].
/// Swallows errors — the player may still hold the file open (Windows), or it
/// may already be gone; any survivor is swept by the next session's purge.
Future<void> deleteMediaTempFile(String path) async {
  try {
    await File(path).delete();
  } on Object {
    // Best-effort: leftovers are swept by the next session's purge.
  }
}

Future<void> _purgeMediaTempDir(Directory dir) async {
  try {
    if (dir.existsSync()) await dir.delete(recursive: true);
  } on Object {
    // Best-effort: a locked leftover must not block the preview from loading.
  }
}

/// Resets the once-per-session purge memo so tests can exercise the purge
/// more than once per isolate.
@visibleForTesting
void resetMediaTempPurgeForTesting() => _sessionPurge = null;
