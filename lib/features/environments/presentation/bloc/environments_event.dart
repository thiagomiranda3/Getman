// EnvironmentsBloc events. AddEnvironment carries the full entity (not just
// a name) so the dispatching widget knows the new id synchronously;
// MergeEnvironmentVariables merges into the bloc's live entity (see its own
// doc comment) for the chaining write-back's concurrent-capture safety.

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
  const AddEnvironment(this.environment);
  final EnvironmentEntity environment;
  @override
  List<Object?> get props => [environment];
}

class UpdateEnvironment extends EnvironmentsEvent {
  const UpdateEnvironment(this.environment);
  final EnvironmentEntity environment;
  @override
  List<Object?> get props => [environment];
}

/// Merges [variables] into the environment's CURRENT variable map inside the
/// bloc handler. Used by the chaining write-back: an `UpdateEnvironment`
/// carrying a full replacement built from a state snapshot loses concurrent
/// changes (two captures flushing in the same event-loop turn, or a keystroke
/// in the open env editor) — the merge must read the live entity.
class MergeEnvironmentVariables extends EnvironmentsEvent {
  const MergeEnvironmentVariables(this.environmentId, this.variables);
  final String environmentId;
  final Map<String, String> variables;
  @override
  List<Object?> get props => [environmentId, variables];
}

class DeleteEnvironment extends EnvironmentsEvent {
  const DeleteEnvironment(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class ImportEnvironments extends EnvironmentsEvent {
  const ImportEnvironments(this.environments);
  final List<EnvironmentEntity> environments;
  @override
  List<Object?> get props => [environments];
}
