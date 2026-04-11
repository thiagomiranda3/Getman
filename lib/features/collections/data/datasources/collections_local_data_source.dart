import 'package:hive_flutter/hive_flutter.dart';
import '../models/collection_node_model.dart';

abstract class CollectionsLocalDataSource {
  Future<List<CollectionNode>> getCollections();
  Future<void> saveCollections(List<CollectionNode> collections);
}

class CollectionsLocalDataSourceImpl implements CollectionsLocalDataSource {
  static const String collectionsBoxName = 'collections';

  @override
  Future<List<CollectionNode>> getCollections() async {
    final box = Hive.box<CollectionNode>(collectionsBoxName);
    return box.values.toList();
  }

  @override
  Future<void> saveCollections(List<CollectionNode> collections) async {
    final box = Hive.box<CollectionNode>(collectionsBoxName);
    await box.clear();
    await box.addAll(collections);
  }
}
