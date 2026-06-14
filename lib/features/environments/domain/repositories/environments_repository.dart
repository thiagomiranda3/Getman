import 'package:getman/features/environments/domain/entities/environment_entity.dart';

abstract class EnvironmentsRepository {
  Future<List<EnvironmentEntity>> getEnvironments();

  /// Inserts or overwrites one environment (single keyed write).
  Future<void> putEnvironment(EnvironmentEntity environment);

  /// Deletes one environment by id.
  Future<void> deleteEnvironment(String id);

  /// Replaces the whole list (used for import).
  Future<void> saveEnvironments(List<EnvironmentEntity> environments);
}
