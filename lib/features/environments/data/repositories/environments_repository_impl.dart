// Serialized environment mutations against live Hive data, confirmed script
// patches, snapshot-based editor merges, and distinct sorted observation.

import 'package:collection/collection.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/error/guard.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';

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
  Stream<List<EnvironmentEntity>> watchEnvironments() => localDataSource
      .watchChanges()
      .asyncMap((_) => getEnvironments())
      .distinct(const ListEquality<EnvironmentEntity>().equals);

  Future<void> _writes = Future<void>.value();

  Future<void> _mutate(Future<void> Function() operation) {
    final result = _writes.then((_) => guardPersistence(operation));
    // An unsuccessful write must fail its caller without poisoning the queue.
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> applyVariablePatch(String environmentId, ScriptPatch patch) =>
      _mutate(() async {
        final current = (await localDataSource.getEnvironments())
            .firstWhereOrNull((environment) => environment.id == environmentId);
        if (current == null) {
          throw const PersistenceFailure('Environment no longer exists');
        }
        final variables = {...current.variables, ...patch.sets}
          ..removeWhere((key, _) => patch.unsets.contains(key));
        await localDataSource.putEnvironment(
          EnvironmentModel.fromEntity(
            current.toEntity().copyWith(
              variables: variables,
              secretKeys: current.secretKeys.toSet().intersection(
                variables.keys.toSet(),
              ),
            ),
          ),
        );
      });

  @override
  Future<void> putEnvironment(EnvironmentEntity environment) =>
      _mutate(() async {
        await localDataSource.putEnvironment(
          EnvironmentModel.fromEntity(environment),
        );
      });

  @override
  Future<void> updateEnvironment(
    EnvironmentEntity environment, {
    required EnvironmentEntity previous,
  }) => _mutate(() async {
    final current = (await localDataSource.getEnvironments())
        .firstWhereOrNull((item) => item.id == environment.id)
        ?.toEntity();
    if (current == null) {
      throw const PersistenceFailure('Environment no longer exists');
    }
    final variables = {...current.variables};
    for (final key in previous.variables.keys) {
      if (!environment.variables.containsKey(key)) variables.remove(key);
    }
    for (final entry in environment.variables.entries) {
      if (!previous.variables.containsKey(entry.key) ||
          previous.variables[entry.key] != entry.value) {
        variables[entry.key] = entry.value;
      }
    }
    final reordered = !const ListEquality<String>().equals(
      previous.variables.keys.toList(),
      environment.variables.keys.toList(),
    );
    final ordered = reordered
        ? <String, String>{
            for (final key in environment.variables.keys)
              if (variables.containsKey(key)) key: variables[key]!,
            for (final entry in variables.entries)
              if (!environment.variables.containsKey(entry.key))
                entry.key: entry.value,
          }
        : variables;
    final secrets = {...current.secretKeys}
      ..removeAll(previous.secretKeys.difference(environment.secretKeys))
      ..addAll(environment.secretKeys.difference(previous.secretKeys));
    await localDataSource.putEnvironment(
      EnvironmentModel.fromEntity(
        current.copyWith(
          name: previous.name == environment.name
              ? current.name
              : environment.name,
          variables: ordered,
          secretKeys: secrets.intersection(ordered.keys.toSet()),
        ),
      ),
    );
  });

  @override
  Future<void> deleteEnvironment(String id) => _mutate(() async {
    await localDataSource.deleteEnvironment(id);
  });

  @override
  Future<void> importEnvironments(List<EnvironmentEntity> environments) {
    final incoming = environments.map(EnvironmentModel.fromEntity).toList();
    return _mutate(() async {
      final current = await localDataSource.getEnvironments();
      await localDataSource.saveEnvironments(
        {
          for (final environment in current) environment.id: environment,
          for (final environment in incoming) environment.id: environment,
        }.values.toList(),
      );
    });
  }

  @override
  Future<void> saveEnvironments(List<EnvironmentEntity> environments) =>
      _mutate(() async {
        final models = environments.map(EnvironmentModel.fromEntity).toList();
        await localDataSource.saveEnvironments(models);
      });
}
