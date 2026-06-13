import 'package:getman/core/error/guard.dart';
import 'package:getman/features/collections/data/datasources/collections_local_data_source.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';

class CollectionsRepositoryImpl implements CollectionsRepository {
  final CollectionsLocalDataSource localDataSource;

  CollectionsRepositoryImpl(this.localDataSource);

  @override
  Future<List<CollectionNodeEntity>> getCollections() => guardPersistence(() async {
    final models = await localDataSource.getCollections();
    return models.map((m) => m.toEntity()).toList();
  });

  @override
  Future<void> saveCollections(List<CollectionNodeEntity> collections) =>
      guardPersistence(() async {
    final models = collections.map((e) => CollectionNode.fromEntity(e)).toList();
    await localDataSource.saveCollections(models);
  });
}
