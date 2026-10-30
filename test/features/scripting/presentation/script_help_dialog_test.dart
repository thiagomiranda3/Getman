// Script help remains readable across themes, window sizes and text scaling.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/scripting/presentation/widgets/script_help_dialog.dart';

Future<void> _open(
  WidgetTester tester,
  String theme, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme(theme)(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScriptHelpDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

void main() {
  for (final theme in appThemes.keys) {
    testWidgets('$theme help keeps readable width and scrolls after resize', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(2400, 1200);
      addTearDown(tester.view.reset);
      await _open(tester, theme);
      final paragraphs = find.byType(SelectableText);
      for (final paragraph in paragraphs.evaluate()) {
        expect(
          tester.getSize(find.byWidget(paragraph.widget)).width,
          lessThanOrEqualTo(600),
        );
      }
      expect(find.text('CLOSE').hitTestable(), findsOneWidget);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1000, 400);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('CLOSE').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('LIMITS PER STAGE'));
      await tester.pumpAndSettle();
      expect(find.text('LIMITS PER STAGE').hitTestable(), findsOneWidget);
      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.text('SCRIPT HELP'), findsNothing);
    });
  }

  for (final theme in ['classic', 'glass']) {
    testWidgets('$theme help supports narrow windows and enlarged text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 500);
      addTearDown(tester.view.reset);
      await _open(tester, theme, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('CLOSE').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('LIMITS PER STAGE'));
      await tester.pumpAndSettle();
      expect(find.text('LIMITS PER STAGE').hitTestable(), findsOneWidget);
      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.text('SCRIPT HELP'), findsNothing);
    });
  }
}
