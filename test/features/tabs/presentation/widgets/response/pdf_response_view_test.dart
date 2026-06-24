import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/pdf_response_view.dart';

void main() {
  testWidgets('constructs without throwing', (tester) async {
    final pdf = Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits);
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('classic')(Brightness.light, isCompact: false),
        home: Scaffold(body: PdfResponseView(bytes: pdf)),
      ),
    );
    // Single frame only — native pdfium is unavailable in the test VM so
    // pumpAndSettle would hang/throw on the async document-load path.
    await tester.pump();
    expect(find.byType(PdfResponseView), findsOneWidget);
  });
}
