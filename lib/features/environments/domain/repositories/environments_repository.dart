import '../entities/environment_entity.dart';

abstract class EnvironmentsRepository {
  Future<List<EnvironmentEntity>> getEnvironments();
  Future<void> saveEnvironments(List<EnvironmentEntity> environments);
}
