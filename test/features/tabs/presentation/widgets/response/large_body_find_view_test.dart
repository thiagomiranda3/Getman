import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/utils/plain_text_find.dart';
import 'package:getman/features/tabs/presentation/widgets/response/large_body_find_view.dart';

/// > 1 MiB fixture: first match deep in the A-region, second match followed
/// by a distinctive C-region so window recentering is observable.
final String kBigBody =
    '${'A' * 600000}needle${'B' * 500000}needle${'C' * 100}';

Future<void> _pump(
  WidgetTester tester, {
  required String body,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme(kClassicThemeId)(Brightness.light, isCompact: false),
      home: Scaffold(
        body: LargeBodyFindView(
          body: body,
          fallback: const Text('FALLBACK_VIEW'),
          onClose: onClose ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Types [query], lets the debounce fire, and waits for the compute() scan
/// (a real isolate) to complete — same runAsync pattern as
/// response_body_view_lazy_tree_test.dart.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('large_find_field')), query);
  await tester.pump(const Duration(milliseconds: 250)); // debounce fires
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty query shows the fallback view and a 0/0 counter', (
    tester,
  ) async {
    await _pump(tester, body: kBigBody);
    expect(find.text('FALLBACK_VIEW'), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('large_find_window_text')),
      findsNothing,
    );
  });

  testWidgets(
    '1 MiB body: off-isolate scan finds matches; the windowed snippet '
    'replaces the fallback and is size-capped',
    (tester) async {
      expect(kBigBody.length, greaterThan(1024 * 1024));
      await _pump(tester, body: kBigBody);
      await _search(tester, 'needle');

      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('FALLBACK_VIEW'), findsNothing);

      final selectable = tester.widget<SelectableText>(
        find.byKey(const ValueKey('large_find_window_text')),
      );
      final plain = selectable.textSpan!.toPlainText();
      // Window size is independent of the 1 MiB body: 4 KiB + ellipses.
      expect(plain.length, lessThanOrEqualTo(kPlainTextFindWindowChars + 4));
      expect(plain, contains('needle'));
      // The first match's window is deep in the A/B region — no C in sight.
      expect(plain, isNot(contains('C')));
    },
  );

  testWidgets('next re-centers the window on the second match', (
    tester,
  ) async {
    await _pump(tester, body: kBigBody);
    await _search(tester, 'needle');

    await tester.tap(find.byKey(const ValueKey('large_find_next')));
    await tester.pump();

    expect(find.text('2/2'), findsOneWidget);
    final selectable = tester.widget<SelectableText>(
      find.byKey(const ValueKey('large_find_window_text')),
    );
    final plain = selectable.textSpan!.toPlainText();
    expect(plain, contains('C'), reason: 'window moved to the second match');

    // prev wraps back.
    await tester.tap(find.byKey(const ValueKey('large_find_prev')));
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('exactly one span carries the active-match highlight', (
    tester,
  ) async {
    await _pump(tester, body: kBigBody);
    await _search(tester, 'needle');

    final palette = Theme.of(
      tester.element(find.byType(LargeBodyFindView)),
    ).extension<AppPalette>()!;
    final selectable = tester.widget<SelectableText>(
      find.byKey(const ValueKey('large_find_window_text')),
    );
    var active = 0;
    selectable.textSpan!.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.backgroundColor == palette.findMatchActiveHighlight) {
        active++;
      }
      return true;
    });
    expect(active, 1);
  });

  testWidgets('close button fires onClose', (tester) async {
    var closed = false;
    await _pump(tester, body: kBigBody, onClose: () => closed = true);
    await tester.tap(find.byKey(const ValueKey('large_find_close')));
    expect(closed, isTrue);
  });
}
