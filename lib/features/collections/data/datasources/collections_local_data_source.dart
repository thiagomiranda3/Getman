import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../models/collection_node_model.dart';

abstract class CollectionsLocalDataSource {
  Future<List<CollectionNode>> getCollections();
  Future<void> saveCollections(List<CollectionNode> collections);
}

class CollectionsLocalDataSourceImpl implements CollectionsLocalDataSource {
  Box<CollectionNode> _box() => Hive.box<CollectionNode>(HiveBoxes.collections);

  @override
  Future<List<CollectionNode>> getCollections() async {
    try {
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
      await box.addAll(collections);
    } catch (e) {
      throw PersistenceException('Failed to save collections', cause: e);
    }
  }
}
