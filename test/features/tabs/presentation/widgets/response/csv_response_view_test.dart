import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/utils/csv_preview.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/csv_response_view.dart';

void main() {
  testWidgets(
    'rebuilds reuse parsing and offstage replacements show new rows',
    (tester) async {
      final first = Uint8List.fromList('name\nold'.codeUnits);
      final second = Uint8List.fromList('name\nnew'.codeUnits);
      Future<void> mount(Uint8List bytes, {bool offstage = false}) async {
        await tester.runAsync(
          () => tester.pumpWidget(
            MaterialApp(
              theme: resolveTheme('classic')(
                Brightness.light,
                isCompact: false,
              ),
              home: Scaffold(
                body: Offstage(
                  offstage: offstage,
                  child: TickerMode(
                    enabled: !offstage,
                    child: CsvResponseView(bytes: bytes),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await mount(first);
      final initial = _previewFuture(tester);
      await _finishPreview(tester);
      await mount(first);
      expect(_previewFuture(tester), same(initial));
      expect(find.text('old').hitTestable(), findsOneWidget);
      await mount(first, offstage: true);
      await mount(second, offstage: true);
      await _finishPreview(tester);
      await mount(second);
      expect(find.text('new').hitTestable(), findsOneWidget);
      expect(find.text('old'), findsNothing);
    },
  );

  testWidgets('rapid replacement discards old results and disposal is safe', (
    tester,
  ) async {
    Future<void> mount(String value) async {
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            theme: resolveTheme('classic')(Brightness.light, isCompact: false),
            home: Scaffold(
              body: CsvResponseView(
                bytes: Uint8List.fromList('name\n$value'.codeUnits),
              ),
            ),
          ),
        ),
      );
    }

    await mount('old');
    final old = _previewFuture(tester);
    await mount('new');
    expect(find.text('Loading CSV…'), findsOneWidget);
    expect(find.text('old'), findsNothing);
    await _finishPreview(tester);
    await tester.runAsync(() async {
      await old;
    });
    await tester.pump();
    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsNothing);
    await mount('disposed');
    final pending = _previewFuture(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await pending;
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders header + rows incl. quoted commas', (tester) async {
    final csv = Uint8List.fromList(
      'name,note\n"Doe, John",hi\nJane,"a,b"'.codeUnits,
    );
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('classic')(Brightness.light, isCompact: false),
          home: Scaffold(body: CsvResponseView(bytes: csv)),
        ),
      ),
    );
    expect(find.text('Loading CSV…'), findsOneWidget);
    await _finishPreview(tester);
    expect(find.text('name'), findsOneWidget);
    expect(find.text('Doe, John'), findsOneWidget);
    expect(find.text('a,b'), findsOneWidget);
  });

  testWidgets('pins comma delimiter even when data is semicolon-heavy', (
    tester,
  ) async {
    // Each line has 3 semicolons and 1 comma. Auto-detect would pick ';' and
    // mangle the table; pinning to ',' must keep 'a;b;c' as a single cell.
    final csv = Uint8List.fromList('a;b;c,d\ne;f;g,h'.codeUnits);
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('classic')(Brightness.light, isCompact: false),
          home: Scaffold(body: CsvResponseView(bytes: csv)),
        ),
      ),
    );
    expect(find.text('Loading CSV…'), findsOneWidget);
    await _finishPreview(tester);
    // 'a;b;c' as one cell proves comma (not semicolon) was the delimiter.
    expect(find.text('a;b;c'), findsOneWidget);
  });

  testWidgets('does not throw on non-UTF-8 (malformed) bytes', (tester) async {
    // Invalid UTF-8 sequence — must decode with replacement chars, not throw.
    final csv = Uint8List.fromList([
      0xFF,
      0xFE,
      0x41,
      0x2C,
      0x42,
    ]); // ...,A,B-ish
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('classic')(Brightness.light, isCompact: false),
          home: Scaffold(body: CsvResponseView(bytes: csv)),
        ),
      ),
    );
    await _finishPreview(tester);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _finishPreview(WidgetTester tester) async {
  final future = _previewFuture(tester);
  await tester.runAsync(() async {
    await future;
  });
  await tester.pump();
}

Future<CsvPreview> _previewFuture(WidgetTester tester) => tester
    .widget<FutureBuilder<CsvPreview>>(
      find.byType(FutureBuilder<CsvPreview>, skipOffstage: false),
    )
    .future!;
