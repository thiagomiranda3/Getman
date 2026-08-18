// Pure functional helpers over the collections tree: sort/addToParent/
// removeFromTree/renameInTree/toggleFavoriteInTree/updateConfigInTree/
// describeInTree/setVariablesInTree, saved-example CRUD, ancestor/parent
// lookups, overlayLocalOnly (restores app-only data after a disk reload) +
// harvestLocalOnly/reapplyLocalOnly (CollectionsBloc's session side-store of
// the same data, covering nodes absent from the live forest — M6), and
// insertIntoTree/insertExampleInNode/siblingIndexOf — the UNDO side of
// removeFromTree/removeExampleFromNode, restoring a captured node or example
// back to a remembered position.
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

/// One node's app-only data, as captured by
/// [CollectionsTreeHelper.harvestLocalOnly]: a leaf's saved examples and a
/// folder's non-empty secret variable values — exactly the field set
/// [CollectionsTreeHelper.overlayLocalOnly] preserves.
typedef LocalOnlyNodeData = ({
  List<SavedExampleEntity> examples,
  Map<String, String> secretValues,
});

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

  /// Insert [newNode] into [parentId]'s children at [index] (clamped to the
  /// valid range). A null [parentId] inserts at the root level. Like
  /// [addToParent], a missing [parentId] is a no-op walk — callers verify the
  /// parent exists first (RestoreNodeSubtree picks a surviving ancestor).
  /// The UNDO side of a delete: puts a captured subtree back in place.
  static List<CollectionNodeEntity> insertIntoTree(
    List<CollectionNodeEntity> nodes,
    String? parentId,
    CollectionNodeEntity newNode,
    int index,
  ) {
    if (parentId == null) {
      return [...nodes]..insert(index.clamp(0, nodes.length), newNode);
    }
    return nodes.map((node) {
      if (node.id == parentId) {
        final children = [...node.children]
          ..insert(index.clamp(0, node.children.length), newNode);
        return node.copyWith(children: children);
      }
      if (node.children.isEmpty) return node;
      return node.copyWith(
        children: insertIntoTree(node.children, parentId, newNode, index),
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

  /// The position of [id] among its siblings (the root list for root-level
  /// nodes), or -1 when not found. Captured at delete time so UNDO can
  /// restore the node at its original position.
  static int siblingIndexOf(List<CollectionNodeEntity> nodes, String id) {
    final parentId = parentIdOf(nodes, id);
    final siblings = parentId == null
        ? nodes
        : findNode(nodes, parentId)?.children ?? const <CollectionNodeEntity>[];
    return siblings.indexWhere((n) => n.id == id);
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

  /// Insert [example] into the node's saved examples at [index] (clamped).
  /// No-op if [id] is missing — the UNDO side of removeExampleFromNode.
  static List<CollectionNodeEntity> insertExampleInNode(
    List<CollectionNodeEntity> nodes,
    String id,
    SavedExampleEntity example,
    int index,
  ) => _updateNodeById(nodes, id, (node) {
    final examples = [...node.examples]
      ..insert(index.clamp(0, node.examples.length), example);
    return node.copyWith(examples: examples);
  });

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
  ///
  /// Layering (M6): this overlay can only preserve nodes present in
  /// [inMemory] — the *belt*. A node absent from the CURRENT forest (switch
  /// to a branch without request R, then back: R returns from disk but the
  /// live forest no longer has it) is out of its reach. The *braces* is
  /// CollectionsBloc's session-level harvest store
  /// ([harvestLocalOnly]/[reapplyLocalOnly]), applied inside every
  /// `ReplaceCollections`. Callers keep calling this with their live forest;
  /// the bloc covers the rest.
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

  /// Harvests every node's app-only data from [forest], keyed by node id:
  /// a leaf's saved examples (when non-empty) and, for folders, the
  /// non-empty values of variables flagged secret. Nodes carrying neither
  /// are omitted, so the result is compact. Mirrors exactly the field set
  /// [overlayLocalOnly] preserves — the session-store side of the M6 fix
  /// (see the layering note there); CollectionsBloc calls this on the
  /// OUTGOING forest before applying a `ReplaceCollections`.
  static Map<String, LocalOnlyNodeData> harvestLocalOnly(
    List<CollectionNodeEntity> forest,
  ) {
    final out = <String, LocalOnlyNodeData>{};
    void walk(List<CollectionNodeEntity> nodes) {
      for (final node in nodes) {
        final examples = !node.isFolder && node.examples.isNotEmpty
            ? node.examples
            : const <SavedExampleEntity>[];
        final secretValues = <String, String>{};
        if (node.isFolder) {
          for (final key in node.secretKeys) {
            final value = node.variables[key];
            if (value != null && value.isNotEmpty) secretValues[key] = value;
          }
        }
        if (examples.isNotEmpty || secretValues.isNotEmpty) {
          out[node.id] = (examples: examples, secretValues: secretValues);
        }
        walk(node.children);
      }
    }

    walk(forest);
    return out;
  }

  /// Second-layer overlay from a harvested [store] (see [harvestLocalOnly]):
  /// fills a leaf's EMPTY examples list and a folder's still-masked (`''`)
  /// secret values from the store, matching by node id. Unlike
  /// [overlayLocalOnly] it never replaces data already present — the
  /// caller's own overlay ran against the live forest and is fresher, so it
  /// must win; the store only covers nodes that were ABSENT from the live
  /// forest when the caller overlaid (the M6 branch round-trip hole). As in
  /// [overlayLocalOnly], a non-empty disk value for a secret is a deliberate
  /// upstream change and wins, and the incoming node's `secretKeys` decides
  /// which names are secret.
  static List<CollectionNodeEntity> reapplyLocalOnly(
    List<CollectionNodeEntity> forest,
    Map<String, LocalOnlyNodeData> store,
  ) {
    if (store.isEmpty) return forest;
    List<CollectionNodeEntity> walk(List<CollectionNodeEntity> nodes) {
      return nodes.map((node) {
        var merged = node;
        final stored = store[node.id];
        if (stored != null) {
          if (!node.isFolder &&
              node.examples.isEmpty &&
              stored.examples.isNotEmpty) {
            merged = merged.copyWith(examples: stored.examples);
          }
          if (node.isFolder && node.secretKeys.isNotEmpty) {
            final vars = Map<String, String>.of(node.variables);
            var changed = false;
            for (final key in node.secretKeys) {
              final storedValue = stored.secretValues[key];
              if (vars[key] == '' &&
                  storedValue != null &&
                  storedValue.isNotEmpty) {
                vars[key] = storedValue;
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

    return walk(forest);
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
