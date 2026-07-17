// Abstract repository for a request config's chaining rules (get/save).

import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';

abstract class RequestRulesRepository {
  /// Rules for [configId]; an empty [RequestRulesEntity] when none are stored.
  Future<RequestRulesEntity> getRules(String configId);

  /// Persists [rules] (deletes the record when it's empty).
  Future<void> saveRules(RequestRulesEntity rules);
}
