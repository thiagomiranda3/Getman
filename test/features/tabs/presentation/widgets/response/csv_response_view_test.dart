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
}
