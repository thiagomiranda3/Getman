import 'package:getman/core/error/guard.dart';
import 'package:getman/features/chaining/data/datasources/request_rules_local_data_source.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/repositories/request_rules_repository.dart';

class RequestRulesRepositoryImpl implements RequestRulesRepository {
  RequestRulesRepositoryImpl(this.localDataSource);
  final RequestRulesLocalDataSource localDataSource;

  @override
  Future<RequestRulesEntity> getRules(String configId) =>
      guardPersistence(() async {
        final model = localDataSource.getRules(configId);
        return model?.toEntity() ?? RequestRulesEntity(configId: configId);
      });

  @override
  Future<void> saveRules(RequestRulesEntity rules) =>
      guardPersistence(() async {
        if (rules.isEmpty) {
          await localDataSource.deleteRules(rules.configId);
          return;
        }
        await localDataSource.saveRules(RequestRulesModel.fromEntity(rules));
      });
}
