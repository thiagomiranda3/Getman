// Computes the effective variable map for a request: the collection layer
// (merged ancestor folders, deepest wins) overlaid by the active environment
// (environment wins). Bridges the collections + environments feature
// layers, so it lives in core/utils beside the Postman mappers rather than
// inside either feature's domain.

import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';

/// Computes the variable map that applies to a request: the collection layer
/// (merge of the request's ancestor folders, deepest wins) overlaid by the
/// active environment (environment wins). Pure Dart — lives in core/utils
/// beside the Postman mappers, which likewise bridge feature entities.
class RequestVariableResolver {
  const RequestVariableResolver._();

  static Map<String, String> variablesFor({
    required List<EnvironmentEntity> environments,
    required String? activeEnvironmentId,
    required List<CollectionNodeEntity> collections,
    required String? collectionNodeId,
  }) {
    final env = ActiveEnvironmentHelper.variablesFor(
      environments,
      activeEnvironmentId,
    );
    if (collectionNodeId == null) return env;
    final collection = CollectionsTreeHelper.collectVariables(
      collections,
      collectionNodeId,
    ).variables;
    if (collection.isEmpty) return env;
    return {...collection, ...env};
  }
}
