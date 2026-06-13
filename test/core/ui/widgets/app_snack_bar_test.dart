import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';

void main() {
  testWidgets('shows a floating, theme-styled snackbar with the message', (tester) async {
    final theme = brutalistTheme(Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAppSnackBar(context, 'REQUEST UPDATED!'),
            child: const Text('GO'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('GO'));
    await tester.pump();

    expect(find.text('REQUEST UPDATED!'), findsOneWidget);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.backgroundColor, theme.primaryColor);
  });

  testWidgets('accepts a background override', (tester) async {
    final theme = brutalistTheme(Brightness.light);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAppSnackBar(
              context,
              'copied',
              backgroundColor: theme.colorScheme.secondary,
            ),
            child: const Text('GO'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('GO'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, theme.colorScheme.secondary);
  });
}
