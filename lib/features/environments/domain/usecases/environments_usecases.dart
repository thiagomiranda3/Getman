import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';

class GetEnvironmentsUseCase {
  final EnvironmentsRepository repository;
  GetEnvironmentsUseCase(this.repository);
  Future<List<EnvironmentEntity>> call() => repository.getEnvironments();
}

class SaveEnvironmentsUseCase {
  final EnvironmentsRepository repository;
  SaveEnvironmentsUseCase(this.repository);
  Future<void> call(List<EnvironmentEntity> environments) =>
      repository.saveEnvironments(environments);
}

class PutEnvironmentUseCase {
  final EnvironmentsRepository repository;
  PutEnvironmentUseCase(this.repository);
  Future<void> call(EnvironmentEntity environment) => repository.putEnvironment(environment);
}

class DeleteEnvironmentUseCase {
  final EnvironmentsRepository repository;
  DeleteEnvironmentUseCase(this.repository);
  Future<void> call(String id) => repository.deleteEnvironment(id);
}
