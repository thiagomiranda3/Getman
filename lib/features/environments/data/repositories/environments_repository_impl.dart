import 'package:getman/core/error/guard.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';

class EnvironmentsRepositoryImpl implements EnvironmentsRepository {
  final EnvironmentsLocalDataSource localDataSource;

  EnvironmentsRepositoryImpl(this.localDataSource);

  @override
  Future<List<EnvironmentEntity>> getEnvironments() => guardPersistence(() async {
    final models = await localDataSource.getEnvironments();
    return models.map((m) => m.toEntity()).toList();
  });

  @override
  Future<void> saveEnvironments(List<EnvironmentEntity> environments) =>
      guardPersistence(() async {
    final models = environments.map((e) => EnvironmentModel.fromEntity(e)).toList();
    await localDataSource.saveEnvironments(models);
  });
}
