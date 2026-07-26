import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_response_view.dart';

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
}
