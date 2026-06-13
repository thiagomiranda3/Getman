import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/core/storage/hive_helpers.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
      await replaceAllInBox(_box(), collections);
    } catch (e) {
      throw PersistenceException('Failed to save collections', cause: e);
    }
  }
}
