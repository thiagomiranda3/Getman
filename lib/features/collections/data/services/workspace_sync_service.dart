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

  /// The currently-running `_mirror` write, if any. Set the instant a write
  /// starts (from the debounce timer or [flushPending]) and cleared when it
  /// completes — this is how [flushPending] can await a write that has
  /// *already started* but not yet landed on disk.
  Future<void>? _inFlight;

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
      final pending = _takePending();
      if (pending == null) return;
      unawaited(_startMirror(pending.$1, pending.$2));
    });
  }

  /// Runs any pending or in-flight debounced write to completion, now.
  ///
  /// Callers that read the mirrored files through git (branch switch, pull,
  /// push, stash) MUST await this first: otherwise a write scheduled moments
  /// earlier has not landed, `git status` reports a clean tree, and the timer
  /// fires *after* the checkout — writing the user's edit onto the branch
  /// they switched to. This also covers the narrower window where the
  /// debounce timer has *already* fired and `dataSource.write` is mid-flight:
  /// [_inFlight] tracks that write so it is awaited too, not just the
  /// not-yet-started pending one.
  Future<void> flushPending() async {
    _timer?.cancel();
    _timer = null;
    // Capture any already-running write before (possibly) starting a new
    // one below, so both are awaited — starting the new write must never
    // overwrite [_inFlight] before the older write has been captured.
    final inFlightBefore = _inFlight;
    final pending = _takePending();
    final newWrite = pending == null
        ? null
        : _startMirror(pending.$1, pending.$2);
    if (inFlightBefore != null) await inFlightBefore;
    if (newWrite != null) await newWrite;
  }

  /// Reads and clears the pending write, if any.
  (String, List<CollectionNodeEntity>)? _takePending() {
    final root = _pendingRoot;
    final forest = _pendingForest;
    _pendingRoot = null;
    _pendingForest = null;
    if (root == null || forest == null) return null;
    return (root, forest);
  }

  /// Starts a mirror write, tracking it in [_inFlight] until it completes.
  Future<void> _startMirror(
    String root,
    List<CollectionNodeEntity> forest,
  ) {
    final future = _mirror(root, forest);
    _inFlight = future;
    unawaited(future.whenComplete(() => _inFlight = null));
    return future;
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
