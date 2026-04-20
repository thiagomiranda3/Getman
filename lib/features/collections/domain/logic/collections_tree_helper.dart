import '../../../history/domain/entities/request_config_entity.dart';
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
      if (node.children.isNotEmpty) {
        return node.copyWith(
          children: sort(node.children),
        );
      }
      return node;
    }).toList();
  }

  static List<CollectionNodeEntity> addToParent(
      List<CollectionNodeEntity> nodes, String parentId, CollectionNodeEntity newNode) {
    return nodes.map((node) {
      if (node.id == parentId) {
        return node.copyWith(
          children: [...node.children, newNode],
        );
      } else if (node.children.isNotEmpty) {
        return node.copyWith(
          children: addToParent(node.children, parentId, newNode),
        );
      }
      return node;
    }).toList();
  }

  static List<CollectionNodeEntity> removeFromTree(List<CollectionNodeEntity> nodes, String id) {
    return nodes
        .where((node) => node.id != id)
        .map((node) => node.copyWith(
              children: removeFromTree(node.children, id),
            ))
        .toList();
  }

  static List<CollectionNodeEntity> renameInTree(List<CollectionNodeEntity> nodes, String id, String newName) {
    return nodes.map((node) {
      if (node.id == id) {
        return node.copyWith(name: newName);
      }
      if (node.children.isNotEmpty) {
        return node.copyWith(
          children: renameInTree(node.children, id, newName),
        );
      }
      return node;
    }).toList();
  }

  static List<CollectionNodeEntity> toggleFavoriteInTree(List<CollectionNodeEntity> nodes, String id) {
    return nodes.map((node) {
      if (node.id == id) {
        return node.copyWith(isFavorite: !node.isFavorite);
      }
      if (node.children.isNotEmpty) {
        return node.copyWith(
          children: toggleFavoriteInTree(node.children, id),
        );
      }
      return node;
    }).toList();
  }

  static List<CollectionNodeEntity> updateConfigInTree(List<CollectionNodeEntity> nodes, String id, HttpRequestConfigEntity config) {
    return nodes.map((node) {
      if (node.id == id) {
        return node.copyWith(config: config);
      }
      if (node.children.isNotEmpty) {
        return node.copyWith(
          children: updateConfigInTree(node.children, id, config),
        );
      }
      return node;
    }).toList();
  }

  static CollectionNodeEntity? findNode(List<CollectionNodeEntity> nodes, String id) {
    for (var node in nodes) {
      if (node.id == id) return node;
      final found = findNode(node.children, id);
      if (found != null) return found;
    }
    return null;
  }
}
