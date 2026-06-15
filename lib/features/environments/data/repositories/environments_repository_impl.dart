import 'package:getman/core/error/guard.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';

class EnvironmentsRepositoryImpl implements EnvironmentsRepository {
  EnvironmentsRepositoryImpl(this.localDataSource);
  final EnvironmentsLocalDataSource localDataSource;

  @override
  Future<List<EnvironmentEntity>> getEnvironments() =>
      guardPersistence(() async {
        final models = await localDataSource.getEnvironments();
        return models.map((m) => m.toEntity()).toList();
      });

  @override
  Future<void> putEnvironment(EnvironmentEntity environment) =>
      guardPersistence(() async {
        await localDataSource.putEnvironment(
          EnvironmentModel.fromEntity(environment),
        );
      });

  @override
  Future<void> deleteEnvironment(String id) => guardPersistence(() async {
    await localDataSource.deleteEnvironment(id);
  });

  @override
  Future<void> saveEnvironments(List<EnvironmentEntity> environments) =>
      guardPersistence(() async {
        final models = environments.map(EnvironmentModel.fromEntity).toList();
        await localDataSource.saveEnvironments(models);
      });
}
