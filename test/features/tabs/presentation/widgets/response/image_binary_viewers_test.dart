import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/image_response_view.dart';

Widget _host(Widget child) => MaterialApp(
  theme: resolveTheme('classic')(Brightness.light, isCompact: false),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('ImageResponseView builds an Image widget', (tester) async {
    // 1x1 transparent PNG.
    final png = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    await tester.pumpWidget(_host(ImageResponseView(bytes: png)));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('BinaryResponseView shows type + size + Save', (tester) async {
    await tester.pumpWidget(
      _host(
        BinaryResponseView(
          bytes: Uint8List(2048),
          contentType: 'application/zip',
          url: 'https://x/a.zip',
          placeholderBody: '',
        ),
      ),
    );
    expect(find.textContaining('application/zip'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    expect(find.byKey(const ValueKey('binary_save_button')), findsOneWidget);
  });

  testWidgets('BinaryResponseView with null bytes hides Save', (tester) async {
    await tester.pumpWidget(
      _host(
        const BinaryResponseView(
          bytes: null,
          contentType: 'application/zip',
          url: null,
          placeholderBody: 'x',
        ),
      ),
    );
    expect(find.byKey(const ValueKey('binary_save_button')), findsNothing);
  });
}
