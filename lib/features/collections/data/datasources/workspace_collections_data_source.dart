// Abstract data source for mirroring the collections forest to a workspace
// directory on disk; implemented by the io/stub pair selected in
// workspace_data_source_factory.dart.
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

/// Reads/writes the collection forest to a workspace directory on disk.
/// Native-only; on web a no-op stub is used (web never sets a workspace path).
abstract class WorkspaceCollectionsDataSource {
  /// Reconstructs the forest from the workspace at [root] (empty if none).
  Future<List<CollectionNodeEntity>> read(String root);

  /// Mirrors [forest] to disk under [root], reconciling orphaned files.
  Future<void> write(String root, List<CollectionNodeEntity> forest);
}
