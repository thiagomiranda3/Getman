import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// A second >1 MiB fixture whose single "needle" match sits at offset
/// 300000 — far from kBigBody's first match at offset 600000, and
/// surrounded by 'D' filler instead of 'A'/'B'/'C'. If a body swap ever
/// renders a window using kBigBody's stale offset(s) sliced into this
/// body's text, offset 600000 lands deep in the pure-'D' region (no
/// "needle" anywhere near it) — exposing the stale-highlight bug without
/// crashing (the offset is still in-bounds).
final String kOtherBigBody = '${'C' * 300000}needle${'D' * 500000}';

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

  testWidgets(
    'body swap clears stale offsets before any stale-highlight window '
    'can render over the new text',
    (tester) async {
      await _pump(tester, body: kBigBody);
      await _search(tester, 'needle');
      expect(find.text('1/2'), findsOneWidget); // sanity: matches on body A

      // Swap to a different >1 MiB body while the same query is still
      // active. Deliberately do NOT runAsync yet — this is the exact
      // synchronous frame during which the rescan's compute() is pending,
      // where the stale-highlight bug would show through.
      await _pump(tester, body: kOtherBigBody);

      expect(
        find.byKey(const ValueKey('large_find_window_text')),
        findsNothing,
        reason:
            'offsets must be cleared synchronously on body change so the '
            'window never renders a stale match position over new text',
      );
      expect(find.text('FALLBACK_VIEW'), findsOneWidget);

      // Let the rescan against the new body land, then verify it finds the
      // new body's own (correctly positioned) match.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();

      expect(find.text('1/1'), findsOneWidget);
      final selectable = tester.widget<SelectableText>(
        find.byKey(const ValueKey('large_find_window_text')),
      );
      expect(selectable.textSpan!.toPlainText(), contains('needle'));
    },
  );

  testWidgets(
    'Enter navigates to the next match, Shift+Enter to the previous',
    (tester) async {
      await _pump(tester, body: kBigBody);
      await _search(tester, 'needle');
      expect(find.text('1/2'), findsOneWidget);

      Future<void> enter({bool shift = false}) async {
        if (shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'macos');
        if (shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pump();
      }

      // Enter (no shift) steps forward through the Focus onKeyEvent path,
      // not a button tap.
      await enter();
      expect(find.text('2/2'), findsOneWidget);

      // Shift+Enter steps back.
      await enter(shift: true);
      expect(find.text('1/2'), findsOneWidget);
    },
  );
}
