import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/repositories/request_rules_repository.dart';

class GetRequestRulesUseCase {
  GetRequestRulesUseCase(this.repository);
  final RequestRulesRepository repository;

  Future<RequestRulesEntity> call(String configId) =>
      repository.getRules(configId);
}

class SaveRequestRulesUseCase {
  SaveRequestRulesUseCase(this.repository);
  final RequestRulesRepository repository;

  Future<void> call(RequestRulesEntity rules) => repository.saveRules(rules);
}
