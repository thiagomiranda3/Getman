// Hive-backed persistence for environments (box: 'environments', keyed by
// id). Sorts case-insensitively by name on read (UUID keys carry no
// display order) and migrates legacy int keys to id via
// migrateLegacyKeysIfNeeded.

import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

abstract class EnvironmentsLocalDataSource {
  Future<List<EnvironmentModel>> getEnvironments();

  /// Inserts or overwrites one environment, keyed by its id — a single put, not
  /// a whole-list rewrite.
  Future<void> putEnvironment(EnvironmentModel environment);

  /// Deletes one environment by id.
  Future<void> deleteEnvironment(String id);

  /// Replaces the whole list (used for import). Keyed by id.
  Future<void> saveEnvironments(List<EnvironmentModel> environments);
}

class EnvironmentsLocalDataSourceImpl implements EnvironmentsLocalDataSource {
  static Box<EnvironmentModel> _box() =>
      Hive.box<EnvironmentModel>(HiveBoxes.environments);

  @override
  Future<List<EnvironmentModel>> getEnvironments() async {
    try {
      // Keys are UUIDs (post key-migration), so Hive's key order has nothing
      // to do with display order — restart would otherwise show environments
      // in random UUID-lexicographic order while in-session adds append.
      // Sort case-insensitively by name for a stable, predictable list.
      final models = _box().values.toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      return models;
    } catch (e) {
      throw PersistenceException('Failed to read environments', cause: e);
    }
  }

  @override
  Future<void> putEnvironment(EnvironmentModel environment) async {
    try {
      await _box().put(environment.id, environment);
    } catch (e) {
      throw PersistenceException('Failed to save environment', cause: e);
    }
  }

  @override
  Future<void> deleteEnvironment(String id) async {
    try {
      await _box().delete(id);
    } catch (e) {
      throw PersistenceException('Failed to delete environment', cause: e);
    }
  }

  @override
  Future<void> saveEnvironments(List<EnvironmentModel> environments) async {
    try {
      final box = _box();
      await box.clear();
      await box.putAll({for (final e in environments) e.id: e});
    } catch (e) {
      throw PersistenceException('Failed to save environments', cause: e);
    }
  }

  /// One-time migration of environments stored under legacy auto-increment int
  /// keys to their `id`, so later [putEnvironment]s overwrite the same logical
  /// environment. No-op once keys are strings. The box must already be open.
  static Future<void> migrateLegacyKeysIfNeeded() async {
    final box = _box();
    if (box.isEmpty || !box.keys.any((k) => k is int)) return;
    final values = box.values.toList(growable: false);
    await box.clear();
    await box.putAll({for (final e in values) e.id: e});
  }
}
