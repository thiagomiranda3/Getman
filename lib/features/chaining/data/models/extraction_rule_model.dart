import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:hive_ce/hive.dart';

part 'extraction_rule_model.g.dart';

/// typeId 7. Enums stored as their wire string (no separate enum adapter).
@HiveType(typeId: 7)
class ExtractionRuleModel extends HiveObject {
  ExtractionRuleModel({
    required this.id,
    this.kind = 'jsonPath',
    this.expression = '',
    this.targetVariable = '',
    this.enabled = true,
  });

  factory ExtractionRuleModel.fromEntity(ExtractionRule e) =>
      ExtractionRuleModel(
        id: e.id,
        kind: e.kind.wire,
        expression: e.expression,
        targetVariable: e.targetVariable,
        enabled: e.enabled,
      );
  @HiveField(0)
  String id;

  @HiveField(1, defaultValue: 'jsonPath')
  String kind;

  @HiveField(2, defaultValue: '')
  String expression;

  @HiveField(3, defaultValue: '')
  String targetVariable;

  @HiveField(4, defaultValue: true)
  bool enabled;

  ExtractionRule toEntity() => ExtractionRule(
    id: id,
    kind: ExtractionKind.fromWire(kind),
    expression: expression,
    targetVariable: targetVariable,
    enabled: enabled,
  );
}
