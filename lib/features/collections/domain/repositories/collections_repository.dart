import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

abstract class CollectionsRepository {
  Future<List<CollectionNodeEntity>> getCollections();
  Future<void> saveCollections(List<CollectionNodeEntity> collections);
}
