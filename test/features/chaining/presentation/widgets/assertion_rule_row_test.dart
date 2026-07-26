// Widget tests for AssertionRuleRow: target/comparator dropdowns drive which
// fields show (path for BODY/HEADER, expected hidden for exists, lo-hi hint
// for in range), edits/toggle emit an updated Assertion, delete calls back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/presentation/widgets/assertion_rule_row.dart';

void main() {
  late List<Assertion> changes;
  late int deletes;

  setUp(() {
    changes = [];
    deletes = 0;
  });

  Widget host(Assertion assertion) => MaterialApp(
    theme: brutalistTheme(Brightness.light),
    home: Scaffold(
      body: ListView(
        children: [
          AssertionRuleRow(
            index: 0,
            assertion: assertion,
            onChanged: changes.add,
            onDelete: () => deletes++,
          ),
        ],
      ),
    ),
  );

  Future<void> pickDropdownItem(
    WidgetTester tester,
    Key dropdownKey,
    String label,
  ) async {
    await tester.tap(find.byKey(dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('default STATUS row hides the path field, shows expected', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Assertion(id: 'a1')));

    expect(find.byKey(const ValueKey('assertion_path_0')), findsNothing);
    expect(find.byKey(const ValueKey('assertion_expected_0')), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('='), findsOneWidget);
  });

  testWidgets('selecting HEADER target shows the header-name field and emits', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Assertion(id: 'a1')));

    await pickDropdownItem(
      tester,
      const ValueKey('assertion_target_0'),
      'HEADER',
    );

    expect(changes.single.target, AssertionTarget.header);
    expect(changes.single.id, 'a1');
    expect(find.byKey(const ValueKey('assertion_path_0')), findsOneWidget);
    expect(find.text('HEADER NAME'), findsOneWidget); // path hint
  });

  testWidgets('selecting BODY target shows the JSONPath field', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Assertion(id: 'a1')));

    await pickDropdownItem(
      tester,
      const ValueKey('assertion_target_0'),
      'BODY (JSONPath)',
    );

    expect(changes.single.target, AssertionTarget.bodyJsonPath);
    expect(find.text('JSONPath'), findsOneWidget); // path hint
  });

  testWidgets('selecting exists comparator hides the expected field', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Assertion(id: 'a1')));

    await pickDropdownItem(
      tester,
      const ValueKey('assertion_comp_0'),
      'exists',
    );

    expect(changes.single.comparator, AssertionComparator.exists);
    expect(find.byKey(const ValueKey('assertion_expected_0')), findsNothing);
  });

  testWidgets('selecting in range relabels the expected field', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Assertion(id: 'a1')));

    await pickDropdownItem(
      tester,
      const ValueKey('assertion_comp_0'),
      'in range',
    );

    expect(changes.single.comparator, AssertionComparator.inRange);
    expect(find.text('EXPECTED (lo-hi)'), findsOneWidget); // expected hint
  });

  testWidgets('typing an expected value emits it with the id preserved', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Assertion(id: 'a1')));

    await tester.enterText(
      find.byKey(const ValueKey('assertion_expected_0')),
      '200',
    );

    expect(changes.last.expected, '200');
    expect(changes.last.id, 'a1');
    expect(changes.last.target, AssertionTarget.statusCode);
  });

  testWidgets('typing a header name emits it as the path', (tester) async {
    await tester.pumpWidget(
      host(const Assertion(id: 'a1', target: AssertionTarget.header)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('assertion_path_0')),
      'X-Request-Id',
    );

    expect(changes.last.path, 'X-Request-Id');
    expect(changes.last.target, AssertionTarget.header);
  });

  testWidgets('toggling the switch emits enabled=false', (tester) async {
    await tester.pumpWidget(host(const Assertion(id: 'a1')));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(changes.single.enabled, isFalse);
  });

  testWidgets('the delete button invokes onDelete', (tester) async {
    await tester.pumpWidget(host(const Assertion(id: 'a1')));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(deletes, 1);
    expect(changes, isEmpty);
  });
}
