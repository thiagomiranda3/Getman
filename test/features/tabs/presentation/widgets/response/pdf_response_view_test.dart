import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/pdf_response_view.dart';

Future<void> _pump(WidgetTester tester, Uint8List bytes) {
  return tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme('classic')(Brightness.light, isCompact: false),
      home: Scaffold(body: PdfResponseView(bytes: bytes)),
    ),
  );
}

/// Lets the doomed document load fail and the error branch render. The
/// failure (a platform-channel reply from the pluginless test VM) only
/// arrives under real async — hence runAsync — and the trailing bounded
/// pumps render the resulting setState without risking a settle-hang on the
/// loading spinner.
Future<void> _letLoadFail(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  final pdf = Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits);

  testWidgets(
    'shows fallback (no unhandled exception) when PDF load fails in test VM',
    (tester) async {
      await _pump(tester, pdf);
      await _letLoadFail(tester);

      expect(find.byType(PdfResponseView), findsOneWidget);
      // The load failure must be caught internally — no unhandled exception.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renders the "Cannot render PDF" fallback, never an infinite spinner',
    (tester) async {
      await _pump(tester, pdf);
      // Loading state first (controller == null, no error yet).
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _letLoadFail(tester);
      expect(find.text('Cannot render PDF'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a new bytes instance reloads the document', (tester) async {
    await _pump(tester, pdf);
    await _letLoadFail(tester);
    expect(find.text('Cannot render PDF'), findsOneWidget);

    // Re-send: fresh bytes instance — didUpdateWidget must clear the error
    // and restart the load (spinner frame) before failing again.
    final pdfB = Uint8List.fromList('%PDF-1.7\n%%EOF'.codeUnits);
    await _pump(tester, pdfB);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Cannot render PDF'), findsNothing);

    await _letLoadFail(tester);
    expect(find.text('Cannot render PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
