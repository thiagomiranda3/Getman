import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';

class CollectionsTreeHelper {
  static List<CollectionNodeEntity> sort(
    List<CollectionNodeEntity> collections,
  ) {
    final sorted = List<CollectionNodeEntity>.from(collections)
      ..sort((a, b) {
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
    List<CollectionNodeEntity> nodes,
    String parentId,
    CollectionNodeEntity newNode,
  ) {
    return nodes.map((node) {
      if (node.id == parentId) {
        return node.copyWith(children: [...node.children, newNode]);
      }
      if (node.children.isEmpty) return node;
      return node.copyWith(
        children: addToParent(node.children, parentId, newNode),
      );
    }).toList();
  }

  static List<CollectionNodeEntity> removeFromTree(
    List<CollectionNodeEntity> nodes,
    String id,
  ) {
    return nodes
        .where((node) => node.id != id)
        .map(
          (node) => node.copyWith(children: removeFromTree(node.children, id)),
        )
        .toList();
  }

  static List<CollectionNodeEntity> renameInTree(
    List<CollectionNodeEntity> nodes,
    String id,
    String newName,
  ) => _updateNodeById(nodes, id, (node) => node.copyWith(name: newName));

  static List<CollectionNodeEntity> toggleFavoriteInTree(
    List<CollectionNodeEntity> nodes,
    String id,
  ) => _updateNodeById(
    nodes,
    id,
    (node) => node.copyWith(isFavorite: !node.isFavorite),
  );

  static List<CollectionNodeEntity> updateConfigInTree(
    List<CollectionNodeEntity> nodes,
    String id,
    HttpRequestConfigEntity config,
  ) => _updateNodeById(nodes, id, (node) => node.copyWith(config: config));

  static List<CollectionNodeEntity> describeInTree(
    List<CollectionNodeEntity> nodes,
    String id,
    String description,
  ) => _updateNodeById(
    nodes,
    id,
    (node) => node.copyWith(description: description),
  );

  /// Append [example] to the node's saved examples (newest last). No-op if the
  /// id is missing.
  static List<CollectionNodeEntity> addExampleToNode(
    List<CollectionNodeEntity> nodes,
    String id,
    SavedExampleEntity example,
  ) => _updateNodeById(
    nodes,
    id,
    (node) => node.copyWith(examples: [...node.examples, example]),
  );

  /// Remove the example with [exampleId] from the node. No-op if either id is
  /// missing.
  static List<CollectionNodeEntity> removeExampleFromNode(
    List<CollectionNodeEntity> nodes,
    String id,
    String exampleId,
  ) => _updateNodeById(
    nodes,
    id,
    (node) => node.copyWith(
      examples: node.examples.where((e) => e.id != exampleId).toList(),
    ),
  );

  /// Rename the example with [exampleId] inside the node. No-op if either id is
  /// missing.
  static List<CollectionNodeEntity> renameExampleInNode(
    List<CollectionNodeEntity> nodes,
    String id,
    String exampleId,
    String newName,
  ) => _updateNodeById(
    nodes,
    id,
    (node) => node.copyWith(
      examples: node.examples
          .map((e) => e.id == exampleId ? e.copyWith(name: newName) : e)
          .toList(),
    ),
  );

  static CollectionNodeEntity? findNode(
    List<CollectionNodeEntity> nodes,
    String id,
  ) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final found = findNode(node.children, id);
      if (found != null) return found;
    }
    return null;
  }

  /// True if [candidateId] is [ancestorId] or appears anywhere inside its
  /// subtree.
  /// Used by MoveNode to reject drops that would orphan a subtree (a folder
  /// cannot become its own descendant).
  static bool isDescendantOrSelf(
    List<CollectionNodeEntity> nodes,
    String ancestorId,
    String candidateId,
  ) {
    final ancestor = findNode(nodes, ancestorId);
    if (ancestor == null) return false;
    return _containsId(ancestor, candidateId);
  }

  static bool _containsId(CollectionNodeEntity node, String id) {
    if (node.id == id) return true;
    for (final child in node.children) {
      if (_containsId(child, id)) return true;
    }
    return false;
  }

  static List<CollectionNodeEntity> _updateNodeById(
    List<CollectionNodeEntity> nodes,
    String id,
    CollectionNodeEntity Function(CollectionNodeEntity node) transform,
  ) {
    return nodes.map((node) {
      if (node.id == id) return transform(node);
      if (node.children.isEmpty) return node;
      return node.copyWith(
        children: _updateNodeById(node.children, id, transform),
      );
    }).toList();
  }
}
