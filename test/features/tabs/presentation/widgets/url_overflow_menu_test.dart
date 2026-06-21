// Widget tests for UrlOverflowMenu: popup menu items, callbacks, and label
// variations driven by isSaved / isVerticalLayout flags. Pure StatelessWidget
// with no bloc dependency — no repository / use-case mocking needed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/url_overflow_menu.dart';

Widget _build({
  bool isSaved = false,
  bool isVerticalLayout = false,
  VoidCallback? onSave,
  VoidCallback? onGenerateCode,
  VoidCallback? onToggleLayout,
}) {
  return MaterialApp(
    theme: brutalistTheme(Brightness.light),
    home: Scaffold(
      body: Center(
        child: UrlOverflowMenu(
          iconSize: 24,
          isSaved: isSaved,
          isVerticalLayout: isVerticalLayout,
          onSave: onSave ?? () {},
          onGenerateCode: onGenerateCode ?? () {},
          onToggleLayout: onToggleLayout ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'shows SAVE TO COLLECTION, GENERATE CODE and VERTICAL LAYOUT items',
    (
      tester,
    ) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('SAVE TO COLLECTION'), findsOneWidget);
      expect(find.text('GENERATE CODE'), findsOneWidget);
      expect(find.text('VERTICAL LAYOUT'), findsOneWidget);
    },
  );

  testWidgets('tapping SAVE TO COLLECTION invokes onSave callback', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(_build(onSave: () => called = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAVE TO COLLECTION'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  testWidgets('tapping GENERATE CODE invokes onGenerateCode callback', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(_build(onGenerateCode: () => called = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GENERATE CODE'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  testWidgets(
    'isSaved=true shows UPDATE REQUEST instead of SAVE TO COLLECTION',
    (
      tester,
    ) async {
      await tester.pumpWidget(_build(isSaved: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('UPDATE REQUEST'), findsOneWidget);
      expect(find.text('SAVE TO COLLECTION'), findsNothing);
    },
  );

  testWidgets('isVerticalLayout=true shows HORIZONTAL LAYOUT', (tester) async {
    await tester.pumpWidget(_build(isVerticalLayout: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('HORIZONTAL LAYOUT'), findsOneWidget);
    expect(find.text('VERTICAL LAYOUT'), findsNothing);
  });

  testWidgets('no overflow', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
