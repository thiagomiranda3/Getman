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

  /// Tail of the serialized chain of `_mirror` writes, or null when no write is
  /// outstanding. Every write is chained after the previous one rather than
  /// started alongside it, so two overlapping debounce cycles can never race
  /// each other onto disk — and awaiting the tail awaits *all* outstanding
  /// writes, which is what lets [flushPending] guarantee a quiet tree.
  Future<void>? _inFlight;

  final StreamController<String> _mirrored =
      StreamController<String>.broadcast();

  /// Emits the workspace root after each successful Hive → disk mirror.
  /// Consumers that read the mirrored files (e.g. the git review badge) listen
  /// here instead of guessing when the debounced write has landed.
  Stream<String> get mirrored => _mirrored.stream;

  /// Whether the most recent mirror write failed. Sticky: it stays `true`
  /// until a later write succeeds, so a background failure that landed before
  /// [flushPending] was ever called is still reported to the flushing caller
  /// (its pending forest was consumed and dropped — the tree on disk is
  /// stale). Cleared on the first successful write.
  bool _lastMirrorFailed = false;

  /// Roots whose last write failed. Used to log a mirror failure only once per
  /// root per session instead of on every debounced mutation (e.g. a sandbox
  /// grant that has not been re-acquired would otherwise spam the console).
  final Set<String> _quietedRoots = {};

  /// Depth of the current mirroring suspension. A counter rather than a flag as
  /// defence-in-depth against nesting: today's wiring never nests (the git op
  /// fully resumes before the reload listener suspends again, so this never
  /// exceeds 1 in production), but if a future caller ever wraps one suspended
  /// scope in another, an inner resume must not re-open the gate the outer
  /// scope still holds.
  int _suspendCount = 0;

  /// Whether mirroring is currently gated off. See [suspendMirroring].
  bool get isMirroringSuspended => _suspendCount > 0;

  Future<List<CollectionNodeEntity>> read(String root) => dataSource.read(root);

  /// Turns [scheduleMirror] into a no-op (and drops anything already armed)
  /// until the matching [resumeMirroring].
  ///
  /// Two callers need this, both for the same reason — Hive must not be
  /// mirrored back onto a tree that something else owns right now:
  ///
  /// * git working-tree ops (switch/create/pull/stash/pop): an edit made *while*
  ///   the checkout runs would fire its debounce afterwards and write the old
  ///   branch's tree onto the new branch. ([flushPending] closes the same race
  ///   from the other side — the write armed *before* the op — so the order is
  ///   always flush, then suspend, then run git.)
  /// * the disk → Hive reload that follows such an op: pushing the freshly-read
  ///   forest into CollectionsBloc emits a state change, which the mirroring
  ///   listener would happily mirror straight back to disk — a reload → mirror
  ///   → reload loop over files git just checked out.
  ///
  /// Prefer [withMirroringSuspended], which cannot leak the gate on a throw.
  void suspendMirroring() {
    _suspendCount++;
    _cancelPending();
  }

  /// Ends one [suspendMirroring] scope. Mirroring resumes when the last one
  /// ends; the next mutation schedules a fresh (non-stale) mirror.
  void resumeMirroring() {
    assert(
      _suspendCount > 0,
      'resumeMirroring() without a matching suspendMirroring() — the gate is '
      'mis-paired somewhere; prefer withMirroringSuspended().',
    );
    if (_suspendCount > 0) _suspendCount--;
  }

  /// Runs [action] with mirroring suspended, resuming it even if [action]
  /// throws (a leaked gate would silently stop mirroring for the session).
  Future<T> withMirroringSuspended<T>(Future<T> Function() action) async {
    suspendMirroring();
    try {
      return await action();
    } finally {
      resumeMirroring();
    }
  }

  /// Debounced Hive → disk mirror. Coalesces bursts of mutations into one
  /// write. A no-op while mirroring is suspended — the forest it carries is
  /// about to be (or has just been) invalidated by git, so it is dropped
  /// rather than deferred.
  void scheduleMirror(String root, List<CollectionNodeEntity> forest) {
    if (isMirroringSuspended) {
      _cancelPending();
      return;
    }
    _timer?.cancel();
    _pendingRoot = root;
    _pendingForest = forest;
    _timer = Timer(debounce, () {
      final pending = _takePending();
      if (pending == null) return;
      unawaited(_startMirror(pending.$1, pending.$2));
    });
  }

  /// Disarms the debounce timer and drops the forest it was going to write.
  void _cancelPending() {
    _timer?.cancel();
    _timer = null;
    _takePending();
  }

  /// Runs any pending or in-flight debounced write to completion, now.
  ///
  /// Callers that read the mirrored files through git (branch switch, pull,
  /// push, stash) MUST await this first: otherwise a write scheduled moments
  /// earlier has not landed, `git status` reports a clean tree, and the timer
  /// fires *after* the checkout — writing the user's edit onto the branch
  /// they switched to. This also covers the narrower window where the
  /// debounce timer has *already* fired and `dataSource.write` is mid-flight:
  /// awaiting [_inFlight] (the tail of the serialized write chain) awaits
  /// every outstanding write, not just the not-yet-started pending one.
  ///
  /// Returns `false` when a mirror write failed and the tree on disk is
  /// therefore stale (`_mirror` swallows the error — it must never break the
  /// session — but the pending forest it consumed is gone, so the caller
  /// cannot assume the disk matches Hive). Callers that are about to run git
  /// over the workspace MUST abort on `false`.
  Future<bool> flushPending() async {
    _timer?.cancel();
    _timer = null;
    final pending = _takePending();
    if (pending != null) unawaited(_startMirror(pending.$1, pending.$2));
    // Read the tail *after* starting the pending write: it now sits at the end
    // of the chain, so this single await covers both it and anything already
    // writing ahead of it.
    await _inFlight;
    return !_lastMirrorFailed;
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

  /// Queues a mirror write behind any write still outstanding, and publishes
  /// the new tail on [_inFlight].
  ///
  /// Chaining (rather than firing the write immediately) is what makes two
  /// overlapping debounce cycles safe: the second write cannot start until the
  /// first has landed, and the tail stays a valid handle on *all* outstanding
  /// work. `_mirror` never throws, so the chain can never break.
  Future<void> _startMirror(
    String root,
    List<CollectionNodeEntity> forest,
  ) {
    final previous = _inFlight;
    final future = previous == null
        ? _mirror(root, forest)
        : previous.then((_) => _mirror(root, forest));
    _inFlight = future;
    // Only the *current* tail may clear the field — an older write completing
    // must not wipe the handle on a write queued after it.
    unawaited(
      future.whenComplete(() {
        if (identical(_inFlight, future)) _inFlight = null;
      }),
    );
    return future;
  }

  Future<void> _mirror(String root, List<CollectionNodeEntity> forest) async {
    try {
      await dataSource.write(root, forest);
      _lastMirrorFailed = false;
      _quietedRoots.remove(root); // recovered — allow logging again
      if (!_mirrored.isClosed) _mirrored.add(root);
    } on Object catch (e) {
      // Best-effort: a failed mirror must never break the in-app session — but
      // it is recorded so [flushPending] can refuse to certify the tree.
      _lastMirrorFailed = true;
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
