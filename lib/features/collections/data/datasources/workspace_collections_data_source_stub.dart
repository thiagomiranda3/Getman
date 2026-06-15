import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

WorkspaceCollectionsDataSource createWorkspaceDataSource() =>
    _StubWorkspaceDataSource();

/// Web has no filesystem; workspace mode is desktop/mobile-only and never
/// activated on web, so these are inert.
class _StubWorkspaceDataSource implements WorkspaceCollectionsDataSource {
  @override
  Future<List<CollectionNodeEntity>> read(String root) async => const [];

  @override
  Future<void> write(String root, List<CollectionNodeEntity> forest) async {}
}
