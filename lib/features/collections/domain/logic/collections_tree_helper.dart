import '../../../../core/domain/entities/request_config_entity.dart';
import '../entities/collection_node_entity.dart';

class CollectionsTreeHelper {
  static List<CollectionNodeEntity> sort(List<CollectionNodeEntity> collections) {
    final sorted = List<CollectionNodeEntity>.from(collections);
    sorted.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return sorted.map((node) {
      if (node.children.isEmpty) return node;
      return node.copyWith(children: sort(node.children));
    }).toList();
  }

  static List<CollectionNodeEntity> addToParent(
      List<CollectionNodeEntity> nodes, String parentId, CollectionNodeEntity newNode) {
    return nodes.map((node) {
      if (node.id == parentId) {
        return node.copyWith(children: [...node.children, newNode]);
      }
      if (node.children.isEmpty) return node;
      return node.copyWith(children: addToParent(node.children, parentId, newNode));
    }).toList();
  }

  static List<CollectionNodeEntity> removeFromTree(List<CollectionNodeEntity> nodes, String id) {
    return nodes
        .where((node) => node.id != id)
        .map((node) => node.copyWith(children: removeFromTree(node.children, id)))
        .toList();
  }

  static List<CollectionNodeEntity> renameInTree(List<CollectionNodeEntity> nodes, String id, String newName) =>
      _updateNodeById(nodes, id, (node) => node.copyWith(name: newName));

  static List<CollectionNodeEntity> toggleFavoriteInTree(List<CollectionNodeEntity> nodes, String id) =>
      _updateNodeById(nodes, id, (node) => node.copyWith(isFavorite: !node.isFavorite));

  static List<CollectionNodeEntity> updateConfigInTree(
    List<CollectionNodeEntity> nodes,
    String id,
    HttpRequestConfigEntity config,
  ) =>
      _updateNodeById(nodes, id, (node) => node.copyWith(config: config));

  static CollectionNodeEntity? findNode(List<CollectionNodeEntity> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final found = findNode(node.children, id);
      if (found != null) return found;
    }
    return null;
  }

  static List<CollectionNodeEntity> _updateNodeById(
    List<CollectionNodeEntity> nodes,
    String id,
    CollectionNodeEntity Function(CollectionNodeEntity node) transform,
  ) {
    return nodes.map((node) {
      if (node.id == id) return transform(node);
      if (node.children.isEmpty) return node;
      return node.copyWith(children: _updateNodeById(node.children, id, transform));
    }).toList();
  }
}
