// test/features/tabs/presentation/widgets/response/media_temp_file_io_test.dart
//
// Disk hygiene of the native media temp-file helpers: writeMediaTempFile
// lands files in a dedicated <tmp>/getman_media/ directory, purges that
// directory exactly once per session (sweeping leftovers from crashed or
// previous sessions), and deleteMediaTempFile removes a single file without
// ever throwing. Drives path_provider through a fake platform instance
// pointed at a per-test system temp dir.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_temp_file_io.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform previousPlatform;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('media_temp_file_test');
    previousPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    resetMediaTempPurgeForTesting();
  });

  tearDown(() {
    PathProviderPlatform.instance = previousPlatform;
    resetMediaTempPurgeForTesting();
    tempDir.deleteSync(recursive: true);
  });

  Directory mediaDir() => Directory('${tempDir.path}/getman_media');

  test(
    'writes into the getman_media subdirectory and returns the path',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final path = await writeMediaTempFile(bytes, 'mp4');

      final file = File(path);
      expect(file.existsSync(), isTrue);
      expect(file.parent.path, mediaDir().path);
      expect(path, endsWith('.mp4'));
      expect(file.readAsBytesSync(), bytes);
    },
  );

  test('deleteMediaTempFile removes a written file', () async {
    final path = await writeMediaTempFile(Uint8List.fromList([9]), 'mp3');
    expect(File(path).existsSync(), isTrue);

    await deleteMediaTempFile(path);
    expect(File(path).existsSync(), isFalse);
  });

  test('deleteMediaTempFile is best-effort on a missing path', () async {
    // Must complete silently — callers fire-and-forget it from dispose.
    await deleteMediaTempFile('${tempDir.path}/getman_media/nope.mp4');
  });

  test(
    'first write of a session purges leftovers from a previous one',
    () async {
      // A file orphaned by a crash in a "previous session".
      final stale = File('${mediaDir().path}/getman_media_stale.mp4')
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xDE, 0xAD]);

      final path = await writeMediaTempFile(Uint8List.fromList([1]), 'mp4');

      expect(
        stale.existsSync(),
        isFalse,
        reason: 'startup purge must sweep it',
      );
      expect(File(path).existsSync(), isTrue);
    },
  );

  test('the purge runs once per session, not once per write', () async {
    // Distinct extensions so the paths differ even within one millisecond.
    final first = await writeMediaTempFile(Uint8List.fromList([1]), 'mp4');
    final second = await writeMediaTempFile(Uint8List.fromList([2]), 'mp3');

    expect(
      File(first).existsSync(),
      isTrue,
      reason: 'a second write must not purge files from this session',
    );
    expect(File(second).existsSync(), isTrue);
  });
}
