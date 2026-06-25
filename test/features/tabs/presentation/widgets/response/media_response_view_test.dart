import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_response_view.dart';

void main() {
  testWidgets('constructs and shows controls/fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('classic')(Brightness.light, isCompact: false),
        home: Scaffold(
          body: MediaResponseView(
            bytes: Uint8List.fromList([0, 1, 2, 3]),
            isVideo: false,
            contentType: 'audio/mpeg',
            url: 'https://x/a.mp3',
          ),
        ),
      ),
    );
    await tester.pump(); // start the async load
    await tester.pump(
      const Duration(milliseconds: 100),
    ); // let it fail + degrade
    expect(find.byType(MediaResponseView), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
    ); // failure must be caught, not thrown
  });
}
