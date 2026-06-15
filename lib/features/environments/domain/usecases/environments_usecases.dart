import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';

class GetEnvironmentsUseCase {
  GetEnvironmentsUseCase(this.repository);
  final EnvironmentsRepository repository;
  Future<List<EnvironmentEntity>> call() => repository.getEnvironments();
}

class SaveEnvironmentsUseCase {
  SaveEnvironmentsUseCase(this.repository);
  final EnvironmentsRepository repository;
  Future<void> call(List<EnvironmentEntity> environments) =>
      repository.saveEnvironments(environments);
}

class PutEnvironmentUseCase {
  PutEnvironmentUseCase(this.repository);
  final EnvironmentsRepository repository;
  Future<void> call(EnvironmentEntity environment) =>
      repository.putEnvironment(environment);
}

class DeleteEnvironmentUseCase {
  DeleteEnvironmentUseCase(this.repository);
  final EnvironmentsRepository repository;
  Future<void> call(String id) => repository.deleteEnvironment(id);
}
