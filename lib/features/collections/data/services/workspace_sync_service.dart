import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

/// Coordinates the one-directional, in-session mirror of collections to disk.
///
/// Strategy (pragmatic v1): Hive is the source of truth during a session.
/// On workspace open the caller imports disk → Hive ([read]); thereafter every
/// mutation mirrors Hive → disk ([scheduleMirror], debounced, best-effort).
/// No file watcher — manual git edits are picked up on an explicit reload.
class WorkspaceSyncService {
  WorkspaceSyncService(
    this.dataSource, {
    this.debounce = const Duration(seconds: 1),
  });
  final WorkspaceCollectionsDataSource dataSource;
  final Duration debounce;
  Timer? _timer;

  /// Roots whose last write failed. Used to log a mirror failure only once per
  /// root per session instead of on every debounced mutation (e.g. a sandbox
  /// grant that has not been re-acquired would otherwise spam the console).
  final Set<String> _quietedRoots = {};

  Future<List<CollectionNodeEntity>> read(String root) => dataSource.read(root);

  /// Debounced Hive → disk mirror. Coalesces bursts of mutations into one
  /// write.
  void scheduleMirror(String root, List<CollectionNodeEntity> forest) {
    _timer?.cancel();
    _timer = Timer(debounce, () => _mirror(root, forest));
  }

  Future<void> _mirror(String root, List<CollectionNodeEntity> forest) async {
    try {
      await dataSource.write(root, forest);
      _quietedRoots.remove(root); // recovered — allow logging again
    } on Object catch (e) {
      // Best-effort: a failed mirror must never break the in-app session.
      // Log the first failure for a root, then stay quiet until it recovers.
      if (_quietedRoots.add(root)) {
        debugPrint(
          'Workspace mirror failed for "$root" '
          '(further failures silenced this session): $e',
        );
      }
    }
  }

  void dispose() => _timer?.cancel();
}
