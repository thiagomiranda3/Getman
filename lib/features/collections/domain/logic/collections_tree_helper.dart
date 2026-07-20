// Pure functional helpers over the collections tree: sort/addToParent/
// removeFromTree/renameInTree/toggleFavoriteInTree/updateConfigInTree/
// describeInTree/setVariablesInTree, saved-example CRUD, ancestor/parent
// lookups, and overlayLocalOnly (restores app-only data after a disk
// reload).
//
// Gotchas: every function returns a new tree and never mutates its input.
// addToParent does NOT treat a missing parentId as an error — it's a no-op
// walk; CollectionsBloc verifies the parent exists via findNode first and
// appends to root on a miss. sort() orders favorites, then folders, then
// leaves, each group alphabetical (case-insensitive, tie-broken by id since
// List.sort isn't stable).
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
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        // Dart's List.sort is not stable — without a total order, siblings
        // whose names differ only by case can swap on every re-sort.
        return a.id.compareTo(b.id);
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

  /// Sets the collection-scoped [variables] + [secretKeys] on the node with
  /// [id]. No-op if the id is missing.
  static List<CollectionNodeEntity> setVariablesInTree(
    List<CollectionNodeEntity> nodes,
    String id,
    Map<String, String> variables,
    Set<String> secretKeys,
  ) => _updateNodeById(
    nodes,
    id,
    (node) => node.copyWith(variables: variables, secretKeys: secretKeys),
  );

  /// Merges the variables of every node on the path from a root down to
  /// [leafId] (root first, deepest last) — the deepest layer wins on name
  /// clashes, and the layer that supplies the winning value decides whether the
  /// name is secret. Returns empty maps if [leafId] is not found.
  static ({Map<String, String> variables, Set<String> secretKeys})
  collectVariables(List<CollectionNodeEntity> nodes, String leafId) {
    final path = _pathTo(nodes, leafId);
    if (path == null) {
      return (variables: const {}, secretKeys: const {});
    }
    final variables = <String, String>{};
    final secretKeys = <String>{};
    for (final node in path) {
      node.variables.forEach((key, value) {
        variables[key] = value;
        if (node.secretKeys.contains(key)) {
          secretKeys.add(key);
        } else {
          secretKeys.remove(key);
        }
      });
    }
    return (variables: variables, secretKeys: secretKeys);
  }

  /// The chain of nodes from a root down to and including the node with [id],
  /// or null if not found.
  static List<CollectionNodeEntity>? _pathTo(
    List<CollectionNodeEntity> nodes,
    String id,
  ) {
    for (final node in nodes) {
      if (node.id == id) return [node];
      final sub = _pathTo(node.children, id);
      if (sub != null) return [node, ...sub];
    }
    return null;
  }

  /// The ids of every ancestor folder on the path down to [id] (root first,
  /// nearest parent last), excluding [id] itself. Empty if [id] is a root node
  /// or is not found. Used to auto-expand a node into view.
  static List<String> ancestorFolderIds(
    List<CollectionNodeEntity> nodes,
    String id,
  ) {
    final path = _pathTo(nodes, id);
    if (path == null || path.length < 2) return const [];
    return [for (final node in path.sublist(0, path.length - 1)) node.id];
  }

  /// The id of the node that directly contains [id] (its immediate parent), or
  /// null when [id] is a root-level node or is not found.
  ///
  /// Drives "drop into the same container" for drag-and-drop: dropping a node
  /// onto a request that lives inside a folder resolves to that folder's id, so
  /// the dragged node lands beside it rather than falling through to the root.
  static String? parentIdOf(List<CollectionNodeEntity> nodes, String id) {
    final path = _pathTo(nodes, id);
    if (path == null || path.length < 2) return null;
    return path[path.length - 2].id;
  }

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

  /// Re-applies data that exists only in the app — never mirrored to disk —
  /// onto a freshly-read workspace forest [onDisk]: a leaf's saved examples,
  /// and the values of secret collection variables (the mirror masks them to
  /// `''` so secrets never land in git). Matching is by node id; nodes new on
  /// disk pass through untouched. Call before `ReplaceCollections` on any
  /// disk reload (branch switch, pull, stash, RELOAD FROM DISK), or every git
  /// operation silently destroys them.
  static List<CollectionNodeEntity> overlayLocalOnly(
    List<CollectionNodeEntity> onDisk,
    List<CollectionNodeEntity> inMemory,
  ) {
    final localById = <String, CollectionNodeEntity>{};
    void index(List<CollectionNodeEntity> nodes) {
      for (final n in nodes) {
        localById[n.id] = n;
        index(n.children);
      }
    }

    index(inMemory);

    List<CollectionNodeEntity> walk(List<CollectionNodeEntity> nodes) {
      return nodes.map((node) {
        var merged = node;
        final local = localById[node.id];
        if (local != null) {
          if (!node.isFolder && local.examples.isNotEmpty) {
            merged = merged.copyWith(examples: local.examples);
          }
          if (node.isFolder && node.secretKeys.isNotEmpty) {
            final vars = Map<String, String>.of(node.variables);
            var changed = false;
            for (final key in node.secretKeys) {
              final localValue = local.variables[key];
              // Only fill in a masked (empty) disk value — a non-empty disk
              // value is a deliberate upstream change and wins.
              if (vars[key] == '' &&
                  localValue != null &&
                  localValue.isNotEmpty) {
                vars[key] = localValue;
                changed = true;
              }
            }
            if (changed) merged = merged.copyWith(variables: vars);
          }
        }
        if (merged.children.isNotEmpty) {
          merged = merged.copyWith(children: walk(merged.children));
        }
        return merged;
      }).toList();
    }

    return walk(onDisk);
  }

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
