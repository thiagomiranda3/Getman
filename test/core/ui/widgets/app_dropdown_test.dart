import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/app_dropdown.dart';

void main() {
  testWidgets('AppDropdown maps index back to T on select', (tester) async {
    String? picked;
    final base = resolveThemeData(null, Brightness.light, isCompact: false);
    final theme = base.copyWith(
      extensions: [...base.extensions.values, defaultAppComponents()],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AppDropdown<String>(
            options: const ['GET', 'POST', 'PUT'],
            value: 'GET',
            labelOf: (m) => m,
            onChanged: (m) => picked = m,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('GET'), findsOneWidget);
    // Tap the dropdown to open the popup menu.
    await tester.tap(find.byType(AppDropdown<String>));
    await tester.pumpAndSettle();
    // Tap 'POST' in the popup.
    await tester.tap(find.text('POST').last);
    await tester.pumpAndSettle();
    expect(picked, 'POST');
  });
}
