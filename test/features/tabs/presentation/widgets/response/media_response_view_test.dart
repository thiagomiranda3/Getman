import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_response_view.dart';

void main() {
  testWidgets('constructs and shows controls/fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('classic')(Brightness.light),
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
    await tester.pump();
    expect(find.byType(MediaResponseView), findsOneWidget);
  });
}
