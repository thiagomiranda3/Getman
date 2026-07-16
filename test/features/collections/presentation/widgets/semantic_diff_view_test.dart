import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/presentation/widgets/semantic_diff_view.dart';

void main() {
  Widget host(SemanticDiff diff) => MaterialApp(
    theme: resolveTheme('classic')(Brightness.light),
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: SemanticDiffView(diff: diff),
      ),
    ),
  );

  testWidgets('renders a field label and no overflow', (tester) async {
    await tester.pumpWidget(
      host(
        const SemanticDiff([
          FieldChange(
            field: 'method',
            kind: ChangeKind.changed,
            before: 'GET',
            after: 'POST',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('method'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty diff shows a no-changes hint', (tester) async {
    await tester.pumpWidget(host(const SemanticDiff([])));
    expect(find.textContaining('No field-level changes'), findsOneWidget);
  });
}
