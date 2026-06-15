import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

abstract class CollectionsLocalDataSource {
  Future<List<CollectionNode>> getCollections();

  /// Full keyed replace: clears the box and writes every root keyed by id.
  Future<void> saveCollections(List<CollectionNode> collections);

  /// Upserts the given root subtrees by id (leaves other roots untouched).
  Future<void> putRoots(List<CollectionNode> roots);

  /// Deletes the roots with the given ids.
  Future<void> deleteRoots(Iterable<String> ids);
}

/// Collections persist keyed by **root node id** (not the legacy auto-increment
/// int keys), so an edit can rewrite only the affected root subtree instead of
/// the whole forest (L12). Root order is not stored — the BLoC re-sorts on load
/// (favorites → folders → leaves, alphabetical), so `box.values` order is moot.
class CollectionsLocalDataSourceImpl implements CollectionsLocalDataSource {
  static Box<CollectionNode> _box() =>
      Hive.box<CollectionNode>(HiveBoxes.collections);

  @override
  Future<List<CollectionNode>> getCollections() async {
    try {
      await migrateLegacyKeysIfNeeded();
      return _box().values.toList();
    } catch (e) {
      throw PersistenceException('Failed to read collections', cause: e);
    }
  }

  @override
  Future<void> saveCollections(List<CollectionNode> collections) async {
    try {
      final box = _box();
      await box.clear();
      await box.putAll({for (final c in collections) c.id: c});
    } catch (e) {
      throw PersistenceException('Failed to save collections', cause: e);
    }
  }

  @override
  Future<void> putRoots(List<CollectionNode> roots) async {
    try {
      await _box().putAll({for (final r in roots) r.id: r});
    } catch (e) {
      throw PersistenceException('Failed to save collections', cause: e);
    }
  }

  @override
  Future<void> deleteRoots(Iterable<String> ids) async {
    try {
      await _box().deleteAll(ids);
    } catch (e) {
      throw PersistenceException('Failed to delete collections', cause: e);
    }
  }

  /// One-time migration from the legacy auto-increment int-keyed layout: re-key
  /// every root by its node id so later id-keyed put/delete overwrite the same
  /// logical root. No-op once the keys are strings. Runs on the cold-start path
  /// before collections are first read.
  static Future<void> migrateLegacyKeysIfNeeded() async {
    final box = _box();
    if (box.isEmpty || !box.keys.any((k) => k is int)) return;
    final roots = box.values.toList(growable: false);
    await box.clear();
    await box.putAll({for (final r in roots) r.id: r});
  }
}
