import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/response_diff_view.dart';
import 'package:getman/core/utils/line_diff.dart';
import 'package:getman/core/utils/response_diff_builder.dart';

Future<void> _pump(WidgetTester tester, ResponseDiffModel model) {
  return tester.pumpWidget(
    MaterialApp(
      theme: resolveTheme(kBrutalistThemeId)(
        Brightness.light,
        isCompact: false,
      ),
      home: Scaffold(
        body: ResponseDiffView(
          model: model,
          leftLabel: 'This response',
          rightLabel: 'Example: 200',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders both source labels', (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 200,
        bodyLines: [],
        headerDeltas: [],
        bodiesIdentical: true,
        tooLarge: false,
      ),
    );
    expect(find.text('This response'), findsOneWidget);
    expect(find.text('Example: 200'), findsOneWidget);
  });

  testWidgets('identical bodies show the identical note', (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 200,
        bodyLines: [],
        headerDeltas: [],
        bodiesIdentical: true,
        tooLarge: false,
      ),
    );
    expect(find.textContaining('identical'), findsOneWidget);
  });

  testWidgets('too-large shows the banner instead of a body list', (
    tester,
  ) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 200,
        bodyLines: [],
        headerDeltas: [],
        bodiesIdentical: false,
        tooLarge: true,
      ),
    );
    expect(find.textContaining('too large'), findsOneWidget);
  });

  testWidgets('added/removed lines render with gutter glyphs', (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 201,
        bodyLines: [
          DiffLine(DiffLineKind.equal, 'kept'),
          DiffLine(DiffLineKind.removed, 'gone'),
          DiffLine(DiffLineKind.added, 'fresh'),
        ],
        headerDeltas: [],
        bodiesIdentical: false,
        tooLarge: false,
      ),
    );
    expect(find.text('gone'), findsOneWidget);
    expect(find.text('fresh'), findsOneWidget);
    // Gutter glyphs are keyed so we can assert per-line color in the impl.
    expect(find.byKey(const ValueKey('diff_gutter_added')), findsOneWidget);
    expect(find.byKey(const ValueKey('diff_gutter_removed')), findsOneWidget);
  });

  testWidgets('header-delta count is summarized', (tester) async {
    await _pump(
      tester,
      const ResponseDiffModel(
        leftStatus: 200,
        rightStatus: 200,
        bodyLines: [],
        headerDeltas: [
          HeaderDelta(key: 'ETag', left: 'v1', right: 'v2'),
          HeaderDelta(key: 'X-New', left: null, right: 'y'),
        ],
        bodiesIdentical: true,
        tooLarge: false,
      ),
    );
    expect(find.textContaining('2 header'), findsOneWidget);
  });
}
