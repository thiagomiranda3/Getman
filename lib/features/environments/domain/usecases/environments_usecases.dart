// Use cases wrapping EnvironmentsRepository: get all, save (replace) all,
// put one, delete one.

import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';

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
  Future<void> import(List<EnvironmentEntity> environments) =>
      repository.importEnvironments(environments);
}

class PutEnvironmentUseCase {
  PutEnvironmentUseCase(this.repository);
  final EnvironmentsRepository repository;
  Future<void> mergeVariables(String id, Map<String, String> variables) =>
      repository.applyVariablePatch(id, ScriptPatch(sets: variables));
  Future<void> call(
    EnvironmentEntity environment, {
    EnvironmentEntity? previous,
  }) => previous == null
      ? repository.putEnvironment(environment)
      : repository.updateEnvironment(environment, previous: previous);
}

class DeleteEnvironmentUseCase {
  DeleteEnvironmentUseCase(this.repository);
  final EnvironmentsRepository repository;
  Future<void> call(String id) => repository.deleteEnvironment(id);
}

/// Observes committed environments without coupling one BLoC to another.
class WatchEnvironmentsUseCase {
  WatchEnvironmentsUseCase(this.repository);
  final EnvironmentsRepository repository;
  Stream<List<EnvironmentEntity>> call() => repository.watchEnvironments();
}
