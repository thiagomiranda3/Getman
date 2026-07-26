import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';

void main() {
  testWidgets('shows a floating, theme-styled snackbar with the message', (
    tester,
  ) async {
    final theme = brutalistTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppSnackBar(context, 'REQUEST UPDATED!'),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('GO'));
    await tester.pump();

    expect(find.text('REQUEST UPDATED!'), findsOneWidget);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.backgroundColor, theme.primaryColor);
  });

  testWidgets('accepts a background override', (tester) async {
    final theme = brutalistTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );

    await tester.tap(find.text('GO'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, theme.colorScheme.secondary);
  });

  testWidgets('renders a themed action and fires the callback', (
    tester,
  ) async {
    final theme = brutalistTheme(Brightness.light);
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppSnackBar(
                context,
                'Request deleted',
                actionLabel: 'UNDO',
                onAction: () => undone = true,
              ),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    expect(action.textColor, theme.colorScheme.onPrimary);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    // SnackBarAction dismisses the snackbar after firing.
    expect(find.text('Request deleted'), findsNothing);
  });

  testWidgets('renders no action when actionLabel/onAction are omitted', (
    tester,
  ) async {
    final theme = brutalistTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppSnackBar(context, 'plain'),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('GO'));
    await tester.pump();

    expect(find.byType(SnackBarAction), findsNothing);
  });

  testWidgets(
    // FIX I1: ScaffoldMessenger queues by default — two quick deletes would
    // otherwise show two 5s snackbars serially, keeping the first UNDO live
    // well past the point the spec says "earlier deletes are accepted
    // loss". Only the latest action-carrying snackbar may be undoable.
    'two rapid action snackbars: the second REPLACES the first instantly '
    '(only the latest UNDO exists)',
    (tester) async {
      final theme = brutalistTheme(Brightness.light);
      var firstUndone = false;
      var secondUndone = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => showAppSnackBar(
                      context,
                      'First deleted',
                      actionLabel: 'UNDO',
                      onAction: () => firstUndone = true,
                    ),
                    child: const Text('FIRST'),
                  ),
                  ElevatedButton(
                    onPressed: () => showAppSnackBar(
                      context,
                      'Second deleted',
                      actionLabel: 'UNDO',
                      onAction: () => secondUndone = true,
                    ),
                    child: const Text('SECOND'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('FIRST'));
      await tester.pump();
      await tester.tap(find.text('SECOND'));
      await tester.pump();

      expect(
        find.text('First deleted'),
        findsNothing,
        reason: 'the first snackbar must be gone, not queued behind',
      );
      expect(find.text('Second deleted'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pumpAndSettle();
      await tester.tap(find.text('UNDO'));
      await tester.pumpAndSettle();
      expect(secondUndone, isTrue);
      expect(firstUndone, isFalse);
    },
  );

  testWidgets('showAppSnackBarVia also renders the action', (tester) async {
    final theme = brutalistTheme(Brightness.light);
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(context);
                showAppSnackBarVia(
                  messenger,
                  'Example deleted',
                  actionLabel: 'UNDO',
                  onAction: () => undone = true,
                );
              },
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    expect(find.text('Example deleted'), findsOneWidget);
    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
  });
}
