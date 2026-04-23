import '../../../../core/error/guard.dart';
import '../../domain/entities/collection_node_entity.dart';
import '../../domain/repositories/collections_repository.dart';
import '../datasources/collections_local_data_source.dart';
import '../models/collection_node_model.dart';

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
