// Equality/props tests for every RulesBloc event: equal instances compare
// equal, and each constructor field participates in Equatable props.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart';

void main() {
  const rule = ExtractionRule(
    id: 'x1',
    kind: ExtractionKind.header,
    expression: 'X-Token',
    targetVariable: 'token',
    enabled: false,
  );
  const rules = RequestRulesEntity(
    configId: 'c1',
    extractionRules: [rule],
    assertions: [Assertion(id: 'a1', expected: '200')],
  );

  group('LoadRules', () {
    test('equal instances compare equal, differs by configId', () {
      expect(const LoadRules('c1'), equals(const LoadRules('c1')));
      expect(const LoadRules('c1').hashCode, const LoadRules('c1').hashCode);
      expect(const LoadRules('c1'), isNot(const LoadRules('c2')));
    });

    test('props expose configId', () {
      expect(const LoadRules('c1').props, ['c1']);
    });
  });

  group('SaveRules', () {
    test('equal instances compare equal', () {
      expect(const SaveRules(rules), equals(const SaveRules(rules)));
    });

    test('differs when the rules entity differs', () {
      expect(
        const SaveRules(rules),
        isNot(const SaveRules(RequestRulesEntity(configId: 'c1'))),
      );
      expect(
        const SaveRules(rules),
        isNot(const SaveRules(RequestRulesEntity(configId: 'c2'))),
      );
    });

    test('props expose the rules entity', () {
      expect(const SaveRules(rules).props, [rules]);
    });
  });

  group('AddExtractionRule', () {
    const base = AddExtractionRule(configId: 'c1', rule: rule);

    test('equal instances compare equal', () {
      expect(base, equals(const AddExtractionRule(configId: 'c1', rule: rule)));
    });

    test('differs by configId and by rule', () {
      expect(base, isNot(const AddExtractionRule(configId: 'c2', rule: rule)));
      expect(
        base,
        isNot(
          const AddExtractionRule(
            configId: 'c1',
            rule: ExtractionRule(id: 'x2'),
          ),
        ),
      );
    });

    test('props expose configId and rule', () {
      expect(base.props, ['c1', rule]);
    });
  });
}
