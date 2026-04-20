import '../../../collections/domain/entities/collection_node_entity.dart';
import '../../../history/domain/entities/request_config_entity.dart';
import '../../../tabs/domain/entities/request_tab_entity.dart';

class TabDirtyChecker {
  const TabDirtyChecker();

  bool call({
    required HttpRequestTabEntity tab,
    required List<CollectionNodeEntity> collections,
  }) {
    if (tab.collectionNodeId == null) {
      return tab.config != HttpRequestConfigEntity(id: tab.config.id);
    }
    final saved = _findConfig(collections, tab.collectionNodeId!);
    if (saved == null) return true;
    return tab.config != saved;
  }

  HttpRequestConfigEntity? _findConfig(List<CollectionNodeEntity> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node.config;
      final found = _findConfig(node.children, id);
      if (found != null) return found;
    }
    return null;
  }
}
