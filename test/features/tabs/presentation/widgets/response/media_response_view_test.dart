import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_temp_file_io.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

Future<void> _pump(
  WidgetTester tester, {
  required Uint8List bytes,
  bool isVideo = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme('classic')(Brightness.light, isCompact: false),
      home: Scaffold(
        body: MediaResponseView(
          bytes: bytes,
          isVideo: isVideo,
          contentType: isVideo ? 'video/mp4' : 'audio/mpeg',
          url: isVideo ? 'https://x/a.mp4' : 'https://x/a.mp3',
        ),
      ),
    ),
  );
}

/// Lets the doomed native load fail and the fallback render. The failure
/// (a platform-channel reply from the pluginless test VM) only arrives under
/// real async — hence runAsync — and the trailing bounded pump renders the
/// resulting setState without risking a settle-hang on the loading spinner.
Future<void> _letLoadFail(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

/// Like [_letLoadFail], but for the faked-path_provider harness where the
/// temp-file write does real dart:io work before the Player() failure. Under
/// the FakeAsync test binding each real-IO hop (create dir, write bytes,
/// delete on failure) completes only inside a runAsync window and its
/// continuation only runs on the next pump — so this alternates the two for a
/// bounded number of rounds instead of a single window.
Future<void> _letIoLoadFail(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('constructs and shows controls/fallback', (tester) async {
    await _pump(tester, bytes: Uint8List.fromList([0, 1, 2, 3]));
    await _letLoadFail(tester);
    expect(find.byType(MediaResponseView), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
    ); // failure must be caught, not thrown
  });

  testWidgets('audio degrades to the binary save card in the test VM', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([0, 1, 2, 3]);
    await _pump(tester, bytes: bytes);
    await _letLoadFail(tester);

    final fallback = tester.widget<BinaryResponseView>(
      find.byType(BinaryResponseView),
    );
    expect(fallback.bytes, same(bytes));
    expect(fallback.contentType, 'audio/mpeg');
    expect(tester.takeException(), isNull);
  });

  testWidgets('video variant degrades the same way', (tester) async {
    await _pump(
      tester,
      bytes: Uint8List.fromList([0, 1, 2, 3]),
      isVideo: true,
    );
    await _letLoadFail(tester);

    expect(find.byType(BinaryResponseView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a spinner while the load is still in flight', (
    tester,
  ) async {
    await _pump(tester, bytes: Uint8List.fromList([0, 1, 2, 3]));
    // The first built frame precedes the async failure landing.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _letLoadFail(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new bytes instance restarts the player pipeline', (
    tester,
  ) async {
    final bytesA = Uint8List.fromList([0, 1, 2, 3]);
    await _pump(tester, bytes: bytesA);
    await _letLoadFail(tester);
    expect(find.byType(BinaryResponseView), findsOneWidget);

    // Re-send: same length, fresh instance — didUpdateWidget must reset to
    // the loading state and start over.
    final bytesB = Uint8List.fromList([3, 2, 1, 0]);
    await _pump(tester, bytes: bytesB);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _letLoadFail(tester);
    final fallback = tester.widget<BinaryResponseView>(
      find.byType(BinaryResponseView),
    );
    expect(fallback.bytes, same(bytesB));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an identical bytes instance does not restart', (tester) async {
    final bytes = Uint8List.fromList([0, 1, 2, 3]);
    await _pump(tester, bytes: bytes);
    await _letLoadFail(tester);
    expect(find.byType(BinaryResponseView), findsOneWidget);

    await _pump(tester, bytes: bytes);
    // No loading reset: still the fallback card, no spinner frame.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(BinaryResponseView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('temp-file hygiene', () {
    // With path_provider faked, writeMediaTempFile succeeds for real and the
    // load fails one step later, at Player() (media_kit is uninitialized in
    // the test VM) — so these tests exercise the catch path's file cleanup
    // with actual files on disk. The success path (file kept while playing,
    // deleted on dispose/restart) needs a real native player and stays with
    // the unit-tested delete helper + the macOS e2e suite.
    late Directory tempDir;
    late PathProviderPlatform previousPlatform;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('media_view_test');
      previousPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      resetMediaTempPurgeForTesting();
    });

    tearDown(() {
      PathProviderPlatform.instance = previousPlatform;
      resetMediaTempPurgeForTesting();
      tempDir.deleteSync(recursive: true);
    });

    List<FileSystemEntity> mediaFiles() {
      final dir = Directory('${tempDir.path}/getman_media');
      return dir.existsSync() ? dir.listSync() : const [];
    }

    testWidgets('a failed load deletes the temp file it wrote', (
      tester,
    ) async {
      await _pump(tester, bytes: Uint8List.fromList([0, 1, 2, 3]));
      await _letIoLoadFail(tester);

      expect(find.byType(BinaryResponseView), findsOneWidget);
      expect(
        mediaFiles(),
        isEmpty,
        reason:
            'the catch path must delete the file written before Player() '
            'threw',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('re-sends do not accumulate temp files', (tester) async {
      await _pump(tester, bytes: Uint8List.fromList([0, 1, 2, 3]));
      await _letIoLoadFail(tester);

      await _pump(tester, bytes: Uint8List.fromList([3, 2, 1, 0]));
      await _letIoLoadFail(tester);

      expect(find.byType(BinaryResponseView), findsOneWidget);
      expect(mediaFiles(), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
