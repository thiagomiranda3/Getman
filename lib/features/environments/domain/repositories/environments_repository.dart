// Abstract repository for environments: get/put/delete one, or save
// (replace) the whole list for import.

import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';

abstract class EnvironmentsRepository {
  Future<List<EnvironmentEntity>> getEnvironments();

  /// Starts with the current sorted list and observes subsequent changes.
  Stream<List<EnvironmentEntity>> watchEnvironments();

  /// Applies an admitted script patch to the live environment.
  /// A deleted environment is never recreated.
  Future<void> applyVariablePatch(String environmentId, ScriptPatch patch);

  /// Inserts or overwrites one environment (single keyed write).
  Future<void> putEnvironment(EnvironmentEntity environment);

  /// Merges only editor fields changed from [previous] into the live record.
  /// A deleted environment is never recreated by a delayed editor update.
  Future<void> updateEnvironment(
    EnvironmentEntity environment, {
    required EnvironmentEntity previous,
  });

  /// Deletes one environment by id.
  Future<void> deleteEnvironment(String id);

  /// Adds or replaces incoming records against live data in the write queue.
  Future<void> importEnvironments(List<EnvironmentEntity> environments);

  /// Explicitly replaces the whole list; normal imports use importEnvironments.
  Future<void> saveEnvironments(List<EnvironmentEntity> environments);
}
