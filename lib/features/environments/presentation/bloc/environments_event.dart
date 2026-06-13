import 'package:equatable/equatable.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

abstract class EnvironmentsEvent extends Equatable {
  const EnvironmentsEvent();
  @override
  List<Object?> get props => [];
}

class LoadEnvironments extends EnvironmentsEvent {
  const LoadEnvironments();
}

/// Carries the full entity (not just a name) so the dispatching widget knows
/// the new environment's id up front — bloc state updates are asynchronous,
/// so an id generated inside the handler would be unknowable at the call site.
class AddEnvironment extends EnvironmentsEvent {
  final EnvironmentEntity environment;
  const AddEnvironment(this.environment);
  @override
  List<Object?> get props => [environment];
}

class UpdateEnvironment extends EnvironmentsEvent {
  final EnvironmentEntity environment;
  const UpdateEnvironment(this.environment);
  @override
  List<Object?> get props => [environment];
}

class DeleteEnvironment extends EnvironmentsEvent {
  final String id;
  const DeleteEnvironment(this.id);
  @override
  List<Object?> get props => [id];
}

class ImportEnvironments extends EnvironmentsEvent {
  final List<EnvironmentEntity> environments;
  const ImportEnvironments(this.environments);
  @override
  List<Object?> get props => [environments];
}
