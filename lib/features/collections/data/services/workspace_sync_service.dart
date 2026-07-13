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
  String? _pendingRoot;
  List<CollectionNodeEntity>? _pendingForest;

  final StreamController<String> _mirrored =
      StreamController<String>.broadcast();

  /// Emits the workspace root after each successful Hive → disk mirror.
  /// Consumers that read the mirrored files (e.g. the git review badge) listen
  /// here instead of guessing when the debounced write has landed.
  Stream<String> get mirrored => _mirrored.stream;

  /// Roots whose last write failed. Used to log a mirror failure only once per
  /// root per session instead of on every debounced mutation (e.g. a sandbox
  /// grant that has not been re-acquired would otherwise spam the console).
  final Set<String> _quietedRoots = {};

  Future<List<CollectionNodeEntity>> read(String root) => dataSource.read(root);

  /// Debounced Hive → disk mirror. Coalesces bursts of mutations into one
  /// write.
  void scheduleMirror(String root, List<CollectionNodeEntity> forest) {
    _timer?.cancel();
    _pendingRoot = root;
    _pendingForest = forest;
    _timer = Timer(debounce, () {
      final r = _pendingRoot;
      final f = _pendingForest;
      _pendingRoot = null;
      _pendingForest = null;
      if (r == null || f == null) return;
      unawaited(_mirror(r, f));
    });
  }

  /// Runs any pending debounced write to completion, now.
  ///
  /// Callers that read the mirrored files through git (branch switch, pull,
  /// push, stash) MUST await this first: otherwise a write scheduled moments
  /// earlier has not landed, `git status` reports a clean tree, and the timer
  /// fires *after* the checkout — writing the user's edit onto the branch
  /// they switched to.
  Future<void> flushPending() async {
    _timer?.cancel();
    _timer = null;
    final root = _pendingRoot;
    final forest = _pendingForest;
    _pendingRoot = null;
    _pendingForest = null;
    if (root == null || forest == null) return;
    await _mirror(root, forest);
  }

  Future<void> _mirror(String root, List<CollectionNodeEntity> forest) async {
    try {
      await dataSource.write(root, forest);
      _quietedRoots.remove(root); // recovered — allow logging again
      if (!_mirrored.isClosed) _mirrored.add(root);
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

  void dispose() {
    _timer?.cancel();
    unawaited(_mirrored.close());
  }
}
