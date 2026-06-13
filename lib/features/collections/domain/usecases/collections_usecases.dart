import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';

class GetCollectionsUseCase {
  final CollectionsRepository repository;
  GetCollectionsUseCase(this.repository);
  Future<List<CollectionNodeEntity>> call() => repository.getCollections();
}

class SaveCollectionsUseCase {
  final CollectionsRepository repository;
  SaveCollectionsUseCase(this.repository);
  Future<void> call(List<CollectionNodeEntity> collections) => repository.saveCollections(collections);
}
