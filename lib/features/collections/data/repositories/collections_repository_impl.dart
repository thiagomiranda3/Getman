import 'package:getman/core/error/guard.dart';
import 'package:getman/features/collections/data/datasources/collections_local_data_source.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';

class CollectionsRepositoryImpl implements CollectionsRepository {
  CollectionsRepositoryImpl(this.localDataSource);
  final CollectionsLocalDataSource localDataSource;

  /// Snapshot of the roots last written to disk, by id. Lets [saveCollections]
  /// rewrite only the roots whose subtree changed (and delete removed ones)
  /// rather than serializing + writing the entire forest on every edit (L12,
  /// per-root diff). Null until [getCollections] (or a save) establishes the
  /// disk state — in which case we fall back to a full keyed replace.
  Map<String, CollectionNodeEntity>? _persisted;

  @override
  Future<List<CollectionNodeEntity>> getCollections() =>
      guardPersistence(() async {
        final models = await localDataSource.getCollections();
        final entities = models.map((m) => m.toEntity()).toList();
        _persisted = {for (final e in entities) e.id: e};
        return entities;
      });

  @override
  Future<void> saveCollections(
    List<CollectionNodeEntity> collections,
  ) => guardPersistence(() async {
    final snapshot = _persisted;
    if (snapshot == null) {
      // Disk state unknown → full keyed replace (also covers import/replace).
      await localDataSource.saveCollections(
        collections.map(CollectionNode.fromEntity).toList(),
      );
    } else {
      final currentIds = {for (final e in collections) e.id};
      // A root's entity is non-equal (Equatable) iff anything in its subtree
      // changed, so only touched roots are re-serialized + written.
      final changed = collections.where((e) => snapshot[e.id] != e).toList();
      final removed = snapshot.keys
          .where((id) => !currentIds.contains(id))
          .toList();
      if (changed.isNotEmpty) {
        await localDataSource.putRoots(
          changed.map(CollectionNode.fromEntity).toList(),
        );
      }
      if (removed.isNotEmpty) {
        await localDataSource.deleteRoots(removed);
      }
    }
    _persisted = {for (final e in collections) e.id: e};
  });
}
