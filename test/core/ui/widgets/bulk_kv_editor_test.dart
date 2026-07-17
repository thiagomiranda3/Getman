import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';
import 'package:getman/core/utils/bulk_kv_codec.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        // BulkKvEditor's TextField uses `expands: true`, so it needs a bounded
        // height. The split-pane / unified panel hosts always give it one; in
        // the harness we wrap in a fixed-height box so every case (including
        // the Column-wrapped echo test) has a bound.
        home: Scaffold(body: SizedBox(height: 400, child: child)),
      ),
    );
  }

  testWidgets('seeds the field from initialText', (tester) async {
    await pump(
      tester,
      const BulkKvEditor(
        initialText: 'Accept: */*\nAuthorization: Bearer x',
        onChanged: _noop,
      ),
    );

    expect(
      find.widgetWithText(TextField, 'Accept: */*\nAuthorization: Bearer x'),
      findsOneWidget,
    );
  });

  testWidgets('reports the raw edited text on change', (tester) async {
    final emissions = <String>[];
    await pump(
      tester,
      BulkKvEditor(initialText: '', onChanged: emissions.add),
    );

    await tester.enterText(find.byType(TextField), 'A: 1');
    await tester.pump();

    expect(emissions.last, 'A: 1');
  });

  testWidgets('does not reset the field when the SAME text echoes back', (
    tester,
  ) async {
    // Mirror the BLoC round-trip: the owner re-passes the text the editor
    // just emitted. The controller must not be re-seeded (cursor preserved).
    var current = 'A: 1';
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            // Expanded resolves the unbounded height a Column hands its
            // children, which BulkKvEditor's `expands: true` field requires.
            Expanded(
              child: BulkKvEditor(
                initialText: current,
                onChanged: (text) => setState(() => current = text),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'A: 12');
    await tester.pump();

    // Field shows what the user typed, not a stale re-seed.
    expect(find.widgetWithText(TextField, 'A: 12'), findsOneWidget);
  });

  testWidgets(
    'does not reset the field when the CANONICALIZED text echoes back '
    '(parents re-serialize, so the echo rarely equals the raw keystrokes)',
    (tester) async {
      // Mirror the real parents (params/headers tabs): the emitted raw text
      // comes back as BulkKvCodec.serialize(parse(raw)) — e.g. typing a new
      // key 'X' echoes back as 'X: ', which used to overwrite the field
      // mid-type and invalidate the caret.
      String canonicalize(String raw) =>
          BulkKvCodec.serialize(BulkKvCodec.parse(raw));
      var current = 'Accept: */*';
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              Expanded(
                child: BulkKvEditor(
                  initialText: current,
                  canonicalize: canonicalize,
                  onChanged: (text) =>
                      setState(() => current = canonicalize(text)),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Accept: */*\nX');
      await tester.pump();

      expect(
        find.widgetWithText(TextField, 'Accept: */*\nX'),
        findsOneWidget,
        reason: 'the canonical echo (X: ) must not rewrite in-progress typing',
      );
    },
  );

  testWidgets('re-seeds when initialText genuinely changes externally', (
    tester,
  ) async {
    await pump(
      tester,
      const BulkKvEditor(initialText: 'A: 1', onChanged: _noop),
    );
    expect(find.widgetWithText(TextField, 'A: 1'), findsOneWidget);

    await pump(
      tester,
      const BulkKvEditor(initialText: 'B: 2', onChanged: _noop),
    );
    expect(find.widgetWithText(TextField, 'B: 2'), findsOneWidget);
  });

  testWidgets('fieldPrefix anchors a ValueKey for E2E targeting', (
    tester,
  ) async {
    await pump(
      tester,
      const BulkKvEditor(
        initialText: '',
        onChanged: _noop,
        fieldPrefix: 'param',
      ),
    );

    expect(find.byKey(const ValueKey('param_bulk')), findsOneWidget);
  });
}

void _noop(String _) {}
