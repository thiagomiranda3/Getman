import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _pumpDialog(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => const ResponsiveDialogScaffold(
                  title: Text('SETTINGS'),
                  content: Text('body'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'glass full effects → frosted card with a BackdropFilter, no AlertDialog',
    (tester) async {
      tester.view.physicalSize = const Size(
        1400,
        1000,
      ); // wide → centered (not fullscreen)
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpDialog(
        tester,
        resolveTheme('glass')(Brightness.dark, isCompact: false),
      );
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
    },
  );

  testWidgets('glass reduced effects → AlertDialog, no BackdropFilter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpDialog(
      tester,
      resolveTheme('glass')(
        Brightness.dark,
        isCompact: false,
        reduceEffects: true,
      ),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets(
    'non-glass theme → AlertDialog, no BackdropFilter (regression guard)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpDialog(
        tester,
        resolveTheme('brutalist')(Brightness.dark, isCompact: false),
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    },
  );
}
