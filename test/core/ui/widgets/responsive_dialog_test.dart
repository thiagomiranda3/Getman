import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _pumpDialog(
  WidgetTester tester,
  ThemeData theme, {
  List<Widget>? actions,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showResponsiveDialog<void>(
                ctx,
                builder: (_) => ResponsiveDialogScaffold(
                  title: const Text('SETTINGS'),
                  content: const Text('body'),
                  actions: actions,
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

  testWidgets(
    'glass full effects with actions → actions render in an OverflowBar',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpDialog(
        tester,
        resolveTheme('glass')(Brightness.dark, isCompact: false),
        actions: [
          TextButton(onPressed: () {}, child: const Text('CANCEL')),
          TextButton(onPressed: () {}, child: const Text('SAVE')),
        ],
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(OverflowBar), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('SAVE'), findsOneWidget);
    },
  );

  group('phone width (fullscreen page)', () {
    testWidgets(
      'opens as a full-screen page, not a dialog, and BACK pops it',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900); // phone tier ≤ 700
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await _pumpDialog(
          tester,
          resolveTheme('brutalist')(Brightness.light, isCompact: false),
        );

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('SETTINGS'), findsOneWidget);
        expect(find.text('body'), findsOneWidget);

        await tester.tap(find.byTooltip('BACK'));
        await tester.pumpAndSettle();
        expect(find.text('SETTINGS'), findsNothing);
        expect(find.text('open'), findsOneWidget);
      },
    );

    testWidgets('no actions → no bottom action bar', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpDialog(
        tester,
        resolveTheme('brutalist')(Brightness.light, isCompact: false),
      );

      final scaffold = tester.widget<Scaffold>(
        find.ancestor(
          of: find.text('body'),
          matching: find.byType(Scaffold),
        ),
      );
      expect(scaffold.bottomNavigationBar, isNull);
    });

    testWidgets(
      'actions render in a bottom bar, in order, and stay tappable',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        var saved = false;
        await _pumpDialog(
          tester,
          resolveTheme('brutalist')(Brightness.light, isCompact: false),
          actions: [
            TextButton(onPressed: () {}, child: const Text('CANCEL')),
            TextButton(
              onPressed: () => saved = true,
              child: const Text('SAVE'),
            ),
          ],
        );

        expect(find.text('CANCEL'), findsOneWidget);
        expect(find.text('SAVE'), findsOneWidget);
        // Actions sit at the bottom, below the content.
        expect(
          tester.getCenter(find.text('SAVE')).dy,
          greaterThan(tester.getCenter(find.text('body')).dy),
        );
        // Right-aligned row keeps caller order: CANCEL left of SAVE.
        expect(
          tester.getCenter(find.text('CANCEL')).dx,
          lessThan(tester.getCenter(find.text('SAVE')).dx),
        );

        await tester.tap(find.text('SAVE'));
        expect(saved, isTrue);
      },
    );
  });
}
