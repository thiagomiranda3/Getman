import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/pdf_response_view.dart';

void main() {
  testWidgets(
    'shows fallback (no unhandled exception) when PDF load fails in test VM',
    (tester) async {
      final pdf = Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits);
      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('classic')(Brightness.light, isCompact: false),
          home: Scaffold(body: PdfResponseView(bytes: pdf)),
        ),
      );
      // First pump: widget builds in the loading state (controller == null).
      await tester.pump();
      // Second pump: lets the async openData rejection microtask flush so
      // _error is set and the fallback branch renders.
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byType(PdfResponseView), findsOneWidget);
      // The load failure must be caught internally — no unhandled exception.
      expect(tester.takeException(), isNull);
    },
  );
}
