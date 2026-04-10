import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/collection_node.dart';
import '../models/request_config.dart';
import '../services/storage_service.dart';

class CollectionsNotifier extends StateNotifier<List<CollectionNode>> {
  CollectionsNotifier() : super(_loadAndSort(StorageService.getCollections()));

  static List<CollectionNode> _loadAndSort(List<CollectionNode> collections) {
    final sorted = List<CollectionNode>.from(collections);
    sorted.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].children.isNotEmpty) {
        sorted[i] = CollectionNode(
          id: sorted[i].id,
          name: sorted[i].name,
          isFolder: sorted[i].isFolder,
          isFavorite: sorted[i].isFavorite,
          config: sorted[i].config,
          children: _loadAndSort(sorted[i].children),
        );
      }
    }
    return sorted;
  }

  void addFolder(String name, {String? parentId}) {
    final newNode = CollectionNode(name: name, isFolder: true);
    if (parentId == null) {
      state = _loadAndSort([...state, newNode]);
    } else {
      state = _loadAndSort(_addToParent(state, parentId, newNode));
    }
    StorageService.saveCollections(state);
  }

  String saveRequest(String name, HttpRequestConfig config, {String? parentId}) {
    final newNode = CollectionNode(
      name: name,
      isFolder: false,
      config: config,
    );
    if (parentId == null) {
      state = _loadAndSort([...state, newNode]);
    } else {
      state = _loadAndSort(_addToParent(state, parentId, newNode));
    }
    StorageService.saveCollections(state);
    return newNode.id;
  }

  void updateRequest(String id, HttpRequestConfig config) {
    state = _loadAndSort(_updateInTree(state, id, config));
    StorageService.saveCollections(state);
  }

  void deleteNode(String id) {
    state = _loadAndSort(_removeFromTree(state, id));
    StorageService.saveCollections(state);
  }

  void renameNode(String id, String newName) {
    state = _loadAndSort(_renameInTree(state, id, newName));
    StorageService.saveCollections(state);
  }

  void toggleFavorite(String id) {
    state = _loadAndSort(_toggleFavoriteInTree(state, id));
    StorageService.saveCollections(state);
  }

  void moveNode(String nodeId, String? newParentId) {
    // 1. Find the node to move
    CollectionNode? nodeToMove;
    void findNode(List<CollectionNode> nodes) {
      for (var node in nodes) {
        if (node.id == nodeId) {
          nodeToMove = node;
          return;
        }
        findNode(node.children);
      }
    }
    findNode(state);

    if (nodeToMove == null) return;
    if (nodeId == newParentId) return; // Can't move to itself

    // 2. Remove from current location
    var newState = _removeFromTree(state, nodeId);

    // 3. Add to new location
    if (newParentId == null) {
      newState = [...newState, nodeToMove!];
    } else {
      newState = _addToParent(newState, newParentId, nodeToMove!);
    }

    state = _loadAndSort(newState);
    StorageService.saveCollections(state);
  }

  List<CollectionNode> _addToParent(List<CollectionNode> nodes, String parentId, CollectionNode newNode) {
    return nodes.map((node) {
      if (node.id == parentId) {
        return CollectionNode(
          id: node.id,
          name: node.name,
          isFolder: node.isFolder,
          isFavorite: node.isFavorite,
          config: node.config,
          children: [...node.children, newNode],
        );
      } else if (node.children.isNotEmpty) {
        return CollectionNode(
          id: node.id,
          name: node.name,
          isFolder: node.isFolder,
          isFavorite: node.isFavorite,
          config: node.config,
          children: _addToParent(node.children, parentId, newNode),
        );
      }
      return node;
    }).toList();
  }

  List<CollectionNode> _removeFromTree(List<CollectionNode> nodes, String id) {
    return nodes
        .where((node) => node.id != id)
        .map((node) => CollectionNode(
              id: node.id,
              name: node.name,
              isFolder: node.isFolder,
              isFavorite: node.isFavorite,
              config: node.config,
              children: _removeFromTree(node.children, id),
            ))
        .toList();
  }

  List<CollectionNode> _renameInTree(List<CollectionNode> nodes, String id, String newName) {
    return nodes.map((node) {
      if (node.id == id) {
        return CollectionNode(
          id: node.id,
          name: newName,
          isFolder: node.isFolder,
          isFavorite: node.isFavorite,
          config: node.config,
          children: node.children,
        );
      }
      return CollectionNode(
        id: node.id,
        name: node.name,
        isFolder: node.isFolder,
        isFavorite: node.isFavorite,
        config: node.config,
        children: _renameInTree(node.children, id, newName),
      );
    }).toList();
  }

  List<CollectionNode> _toggleFavoriteInTree(List<CollectionNode> nodes, String id) {
    return nodes.map((node) {
      if (node.id == id) {
        return CollectionNode(
          id: node.id,
          name: node.name,
          isFolder: node.isFolder,
          isFavorite: !node.isFavorite,
          config: node.config,
          children: node.children,
        );
      }
      return CollectionNode(
        id: node.id,
        name: node.name,
        isFolder: node.isFolder,
        isFavorite: node.isFavorite,
        config: node.config,
        children: _toggleFavoriteInTree(node.children, id),
      );
    }).toList();
  }

  List<CollectionNode> _updateInTree(List<CollectionNode> nodes, String id, HttpRequestConfig config) {
    return nodes.map((node) {
      if (node.id == id) {
        return CollectionNode(
          id: node.id,
          name: node.name,
          isFolder: node.isFolder,
          isFavorite: node.isFavorite,
          config: config,
          children: node.children,
        );
      }
      return CollectionNode(
        id: node.id,
        name: node.name,
        isFolder: node.isFolder,
        isFavorite: node.isFavorite,
        config: node.config,
        children: _updateInTree(node.children, id, config),
      );
    }).toList();
  }

  HttpRequestConfig? getConfig(String id) {
    HttpRequestConfig? found;
    void find(List<CollectionNode> nodes) {
      for (var node in nodes) {
        if (node.id == id) {
          found = node.config;
          return;
        }
        find(node.children);
      }
    }
    find(state);
    return found;
  }
}

final collectionsProvider = StateNotifierProvider<CollectionsNotifier, List<CollectionNode>>((ref) {
  return CollectionsNotifier();
});
