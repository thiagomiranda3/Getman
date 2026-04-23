import '../../../collections/domain/entities/collection_node_entity.dart';
import '../../../collections/domain/logic/collections_tree_helper.dart';
import '../../../../core/domain/entities/request_config_entity.dart';
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
    final saved = CollectionsTreeHelper.findNode(collections, tab.collectionNodeId!)?.config;
    if (saved == null) return true;
    return tab.config != saved;
  }
}
