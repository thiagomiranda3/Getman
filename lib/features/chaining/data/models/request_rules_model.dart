import 'package:getman/features/chaining/data/models/assertion_model.dart';
import 'package:getman/features/chaining/data/models/extraction_rule_model.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:hive_ce/hive.dart';

part 'request_rules_model.g.dart';

/// typeId 9. One per request config id; stored in its own box keyed by
/// configId.
@HiveType(typeId: 9)
class RequestRulesModel extends HiveObject {
  RequestRulesModel({
    required this.configId,
    List<ExtractionRuleModel>? extractionRules,
    List<AssertionModel>? assertions,
  }) : extractionRules = extractionRules ?? [],
       assertions = assertions ?? [];

  factory RequestRulesModel.fromEntity(RequestRulesEntity e) =>
      RequestRulesModel(
        configId: e.configId,
        extractionRules: e.extractionRules
            .map(ExtractionRuleModel.fromEntity)
            .toList(),
        assertions: e.assertions.map(AssertionModel.fromEntity).toList(),
      );
  @HiveField(0)
  String configId;

  @HiveField(1)
  List<ExtractionRuleModel> extractionRules;

  @HiveField(2)
  List<AssertionModel> assertions;

  RequestRulesEntity toEntity() => RequestRulesEntity(
    configId: configId,
    extractionRules: extractionRules.map((m) => m.toEntity()).toList(),
    assertions: assertions.map((m) => m.toEntity()).toList(),
  );
}
