import 'package:hive_flutter/hive_flutter.dart';
import '../models/collection_node_model.dart';

abstract class CollectionsLocalDataSource {
  Future<List<CollectionNode>> getCollections();
  Future<void> saveCollections(List<CollectionNode> collections);
}

class CollectionsLocalDataSourceImpl implements CollectionsLocalDataSource {
  static const String collectionsBoxName = 'collections';

  Future<Box<CollectionNode>> _getBox() async {
    if (Hive.isBoxOpen(collectionsBoxName)) {
      return Hive.box<CollectionNode>(collectionsBoxName);
    }
    return await Hive.openBox<CollectionNode>(collectionsBoxName);
  }

  @override
  Future<List<CollectionNode>> getCollections() async {
    final box = await _getBox();
    return box.values.toList();
  }

  @override
  Future<void> saveCollections(List<CollectionNode> collections) async {
    final box = await _getBox();
    await box.clear();
    await box.addAll(collections);
  }
}
