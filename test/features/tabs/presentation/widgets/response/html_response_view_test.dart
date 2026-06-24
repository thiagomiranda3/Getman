import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/html_response_view.dart';

void main() {
  testWidgets('shows source + open-in-browser button', (tester) async {
    final html = Uint8List.fromList('<h1>Hello</h1>'.codeUnits);
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('classic')(Brightness.light, isCompact: false),
        home: Scaffold(body: HtmlResponseView(bytes: html)),
      ),
    );
    expect(find.textContaining('<h1>Hello</h1>'), findsOneWidget);
    expect(find.byKey(const ValueKey('html_open_in_browser')), findsOneWidget);
  });
}
