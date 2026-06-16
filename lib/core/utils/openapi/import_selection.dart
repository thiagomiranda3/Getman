import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

/// Every request-leaf id in [node]'s subtree.
Set<String> collectLeafIds(CollectionNodeEntity node) {
  final ids = <String>{};
  void walk(CollectionNodeEntity n) {
    if (!n.isFolder) {
      ids.add(n.id);
      return;
    }
    n.children.forEach(walk);
  }

  walk(node);
  return ids;
}

/// Prunes [full]'s tree to only the request leaves in [selectedLeafIds],
/// dropping folders left empty. Environments and warnings are preserved.
ImportResult applySelection(ImportResult full, Set<String> selectedLeafIds) {
  final pruned = _prune(full.root, selectedLeafIds);
  return ImportResult(
    root: pruned ?? full.root.copyWith(children: const []),
    environments: full.environments,
    warnings: full.warnings,
  );
}

CollectionNodeEntity? _prune(CollectionNodeEntity node, Set<String> selected) {
  if (!node.isFolder) {
    return selected.contains(node.id) ? node : null;
  }
  final kids = <CollectionNodeEntity>[];
  for (final c in node.children) {
    final p = _prune(c, selected);
    if (p != null) kids.add(p);
  }
  if (kids.isEmpty) return null;
  return node.copyWith(children: kids);
}
