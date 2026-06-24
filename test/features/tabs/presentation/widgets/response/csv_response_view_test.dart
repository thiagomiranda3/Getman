import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/csv_response_view.dart';

void main() {
  testWidgets('renders header + rows incl. quoted commas', (tester) async {
    final csv = Uint8List.fromList(
      'name,note\n"Doe, John",hi\nJane,"a,b"'.codeUnits,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('classic')(Brightness.light, isCompact: false),
        home: Scaffold(body: CsvResponseView(bytes: csv)),
      ),
    );
    expect(find.text('name'), findsOneWidget);
    expect(find.text('Doe, John'), findsOneWidget);
    expect(find.text('a,b'), findsOneWidget);
  });

  testWidgets('pins comma delimiter even when data is semicolon-heavy', (
    tester,
  ) async {
    // Each line has 3 semicolons and 1 comma. Auto-detect would pick ';' and
    // mangle the table; pinning to ',' must keep 'a;b;c' as a single cell.
    final csv = Uint8List.fromList('a;b;c,d\ne;f;g,h'.codeUnits);
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme('classic')(Brightness.light, isCompact: false),
        home: Scaffold(body: CsvResponseView(bytes: csv)),
      ),
    );
    // 'a;b;c' as one cell proves comma (not semicolon) was the delimiter.
    expect(find.text('a;b;c'), findsOneWidget);
  });
}
