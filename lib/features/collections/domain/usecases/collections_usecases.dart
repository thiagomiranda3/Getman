import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';

class GetCollectionsUseCase {
  GetCollectionsUseCase(this.repository);
  final CollectionsRepository repository;
  Future<List<CollectionNodeEntity>> call() => repository.getCollections();
}

class SaveCollectionsUseCase {
  SaveCollectionsUseCase(this.repository);
  final CollectionsRepository repository;
  Future<void> call(List<CollectionNodeEntity> collections) =>
      repository.saveCollections(collections);
}
