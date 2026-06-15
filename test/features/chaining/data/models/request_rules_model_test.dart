import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';

void main() {
  test('round-trips entity ↔ model preserving enums', () {
    const entity = RequestRulesEntity(
      configId: 'c1',
      extractionRules: [
        ExtractionRule(
          id: 'e1',
          kind: ExtractionKind.regex,
          expression: r'(\d+)',
          targetVariable: 'n',
        ),
      ],
      assertions: [
        Assertion(
          id: 'a1',
          target: AssertionTarget.bodyJsonPath,
          comparator: AssertionComparator.contains,
          path: 'token',
          expected: 'abc',
        ),
      ],
    );
    final back = RequestRulesModel.fromEntity(entity).toEntity();
    expect(back, entity);
  });

  test('empty rules round-trip', () {
    const entity = RequestRulesEntity(configId: 'c2');
    final back = RequestRulesModel.fromEntity(entity).toEntity();
    expect(back.isEmpty, isTrue);
    expect(back.configId, 'c2');
  });
}
