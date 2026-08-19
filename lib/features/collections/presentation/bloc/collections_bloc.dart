// CollectionsBloc: owns the collections tree state, handling CRUD/move/
// import/replace events via CollectionsTreeHelper's pure tree functions.
// Granular edits (_commit) emit immediately and debounce a whole-tree save
// (2s, coalescing a burst of edits); import/replace (_commitNow) flush right
// away since waiting out the debounce risks losing a large change.
//
// Gotchas: _onMoveNode rejects moving a node into its own subtree (would
// orphan it via removeFromTree) and falls back to appending at root if the
// destination parent vanished since the event was built (e.g. a concurrent
// git reload) — addToParent itself no-ops on a missing parent rather than
// erroring. ReplaceCollections harvests app-only data (saved examples,
// secret variable values) from the outgoing forest into _localOnlyStore and
// re-applies it onto the incoming one — the braces behind the callers' own
// overlayLocalOnly belt (M6 branch round-trip data loss); see
// _localOnlyStore. Saves are serialized on _saveInFlight (chained-future
// pattern, same as WorkspaceSyncService._startMirror): _flush has four
// concurrent triggers (debounce timer, _commitNow, close, flushPendingSaves)
// and the repository's diff-save must never overlap itself — two saves
// diffing the same stale _persisted snapshot let a delete land after a
// re-add, silently dropping the root from disk.
import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:uuid/uuid.dart';

class CollectionsBloc extends Bloc<CollectionsEvent, CollectionsState> {
  CollectionsBloc({
    required this._getCollectionsUseCase,
    required this._saveCollectionsUseCase,
    this._saveDebounce = const Duration(seconds: 2),
  }) : super(CollectionsState()) {
    on<LoadCollections>(_onLoadCollections);
    on<AddFolder>(_onAddFolder);
    on<SaveRequestToCollection>(_onSaveRequestToCollection);
    on<UpdateNodeRequest>(_onUpdateNodeRequest);
    on<DeleteNode>(_onDeleteNode);
    on<RenameNode>(_onRenameNode);
    on<UpdateNodeDescription>(_onUpdateNodeDescription);
    on<UpdateNodeVariables>(_onUpdateNodeVariables);
    on<ToggleFavorite>(_onToggleFavorite);
    on<SaveExampleToNode>(_onSaveExampleToNode);
    on<DeleteExample>(_onDeleteExample);
    on<RenameExample>(_onRenameExample);
    on<RestoreNodeSubtree>(_onRestoreNodeSubtree);
    on<RestoreExample>(_onRestoreExample);
    on<MoveNode>(_onMoveNode);
    on<ImportCollections>(_onImportCollections);
    on<ReplaceCollections>(_onReplaceCollections);
  }
  final GetCollectionsUseCase _getCollectionsUseCase;
  final SaveCollectionsUseCase _saveCollectionsUseCase;
  static const Uuid _uuid = Uuid();

  /// Session-level side-store of app-only data (saved examples, secret
  /// variable VALUES) harvested from every forest a ReplaceCollections
  /// throws away — the *braces* behind the callers' overlayLocalOnly *belt*
  /// (M6): callers overlay from the LIVE forest, so a node absent from it
  /// (switch to a branch without request R, then switch back) would lose its
  /// examples/secrets permanently without this store. Keyed by node id.
  ///
  /// Memory bound: after every replace, entries for nodes present in the new
  /// forest are pruned (their data was just restored, or the incoming tree
  /// legitimately superseded it — either way the live tree is now the
  /// authority and gets re-harvested on the next replace), so the store only
  /// ever holds nodes NOT in the live forest. It is in-memory only (dies
  /// with the session) and LRU-capped at [_localOnlyStoreCap] entries by
  /// harvest recency, because saved examples can carry large response
  /// bodies.
  final Map<String, LocalOnlyNodeData> _localOnlyStore = {};

  /// Max node entries kept in [_localOnlyStore] (LRU by harvest recency).
  static const int _localOnlyStoreCap = 200;

  /// Granular edits (add/rename/move/delete/favorite) emit instantly and persist
  /// the whole tree on a debounce — coalescing a burst of edits into one write
  /// instead of one rewrite per action. Import/Replace flush immediately.
  final Duration _saveDebounce;
  Timer? _saveTimer;
  bool _pendingSave = false;

  /// Tail of the serialized save chain. [_flush] queues every save behind the
  /// previous one, because the repository's per-root diff-save snapshots its
  /// last-persisted map at start and updates it only at the end: two saves
  /// running concurrently diff against the same stale snapshot, so a save
  /// that re-adds root X (import/undo) can skip writing it while the earlier
  /// save's `deleteRoots([X])` lands afterwards — X vanishes from disk with
  /// no pending save left to restore it.
  Future<void>? _saveInFlight;

  void _scheduleSave() {
    _pendingSave = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _flush);
  }

  /// Persist the current tree if a save is pending, serialized behind any
  /// save already in flight (see [_saveInFlight]). Returns the chain tail, so
  /// awaiting it awaits every outstanding save, not just the one queued here.
  Future<void> _flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final previous = _saveInFlight;
    // _save never throws (PersistenceFailure is caught), so the chain cannot
    // break mid-sequence.
    final future = previous == null ? _save() : previous.then((_) => _save());
    _saveInFlight = future;
    // Only the *current* tail may clear the field — an older save completing
    // must not wipe the handle on a save queued after it.
    unawaited(
      future.whenComplete(() {
        if (identical(_saveInFlight, future)) _saveInFlight = null;
      }),
    );
    return future;
  }

  /// One save pass: re-checks [_pendingSave] and re-reads `state.collections`
  /// at run time — after the previous save in the chain landed — so a queued
  /// flush always persists the latest tree (or no-ops if a chained-ahead pass
  /// already covered it). Logged-not-thrown so a write failure never blocks
  /// the UI (which already reflects the change).
  Future<void> _save() async {
    if (!_pendingSave) return;
    _pendingSave = false;
    try {
      await _saveCollectionsUseCase(state.collections);
    } on PersistenceFailure catch (f) {
      log('Collections save failed: ${f.message}', name: 'CollectionsBloc');
    }
  }

  @override
  Future<void> close() async {
    await _flush();
    return super.close();
  }

  /// Persists a pending debounced tree save NOW. Called by `ExitFlushGuard`
  /// when the app is about to exit (or its window hides): `close()` — the
  /// only other flush — never runs on process exit, so quitting inside the
  /// debounce window silently lost the last tree edits.
  // Persistence flush, not a state-mutation entry point (emits nothing).
  // ignore: avoid_public_bloc_methods
  Future<void> flushPendingSaves() => _flush();

  /// Append [newNode] to [parentId]'s children, or to the root when [parentId]
  /// is null or refers to a node that no longer exists.
  List<CollectionNodeEntity> _addToTree(
    CollectionNodeEntity newNode,
    String? parentId,
  ) {
    if (parentId == null ||
        CollectionsTreeHelper.findNode(state.collections, parentId) == null) {
      return [...state.collections, newNode];
    }
    return CollectionsTreeHelper.addToParent(
      state.collections,
      parentId,
      newNode,
    );
  }

  /// Sort + emit immediately (the user must see their action take effect), then
  /// schedule a debounced whole-tree save.
  Future<void> _commit(
    Emitter<CollectionsState> emit,
    List<CollectionNodeEntity> next,
  ) async {
    emit(state.copyWith(collections: CollectionsTreeHelper.sort(next)));
    _scheduleSave();
  }

  /// Like [_commit] but persists right away — used for bulk import/replace,
  /// where waiting out the debounce window would risk losing a large change.
  Future<void> _commitNow(
    Emitter<CollectionsState> emit,
    List<CollectionNodeEntity> next,
  ) async {
    emit(state.copyWith(collections: CollectionsTreeHelper.sort(next)));
    _pendingSave = true;
    await _flush();
  }

  Future<void> _onLoadCollections(
    LoadCollections event,
    Emitter<CollectionsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      final collections = await _getCollectionsUseCase();
      emit(
        state.copyWith(
          collections: CollectionsTreeHelper.sort(collections),
          isLoading: false,
        ),
      );
    } on PersistenceFailure catch (f) {
      log('LoadCollections failed: ${f.message}', name: 'CollectionsBloc');
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onAddFolder(AddFolder event, Emitter<CollectionsState> emit) {
    final newNode = CollectionNodeEntity(id: _uuid.v4(), name: event.name);
    return _commit(emit, _addToTree(newNode, event.parentId));
  }

  Future<void> _onSaveRequestToCollection(
    SaveRequestToCollection event,
    Emitter<CollectionsState> emit,
  ) {
    final newNode = CollectionNodeEntity(
      id: event.id ?? _uuid.v4(),
      name: event.name,
      isFolder: false,
      config: event.config,
    );
    return _commit(emit, _addToTree(newNode, event.parentId));
  }

  Future<void> _onUpdateNodeRequest(
    UpdateNodeRequest event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.id) == null) {
      return Future.value();
    }
    return _commit(
      emit,
      CollectionsTreeHelper.updateConfigInTree(
        state.collections,
        event.id,
        event.config,
      ),
    );
  }

  Future<void> _onDeleteNode(DeleteNode event, Emitter<CollectionsState> emit) {
    return _commit(
      emit,
      CollectionsTreeHelper.removeFromTree(state.collections, event.id),
    );
  }

  Future<void> _onRenameNode(RenameNode event, Emitter<CollectionsState> emit) {
    return _commit(
      emit,
      CollectionsTreeHelper.renameInTree(
        state.collections,
        event.id,
        event.newName,
      ),
    );
  }

  Future<void> _onUpdateNodeDescription(
    UpdateNodeDescription event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.id) == null) {
      return Future.value();
    }
    return _commit(
      emit,
      CollectionsTreeHelper.describeInTree(
        state.collections,
        event.id,
        event.description,
      ),
    );
  }

  Future<void> _onUpdateNodeVariables(
    UpdateNodeVariables event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.id) == null) {
      return Future.value();
    }
    return _commit(
      emit,
      CollectionsTreeHelper.setVariablesInTree(
        state.collections,
        event.id,
        event.variables,
        event.secretKeys,
      ),
    );
  }

  Future<void> _onToggleFavorite(
    ToggleFavorite event,
    Emitter<CollectionsState> emit,
  ) {
    return _commit(
      emit,
      CollectionsTreeHelper.toggleFavoriteInTree(state.collections, event.id),
    );
  }

  Future<void> _onSaveExampleToNode(
    SaveExampleToNode event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.nodeId) ==
        null) {
      return Future.value();
    }
    return _commit(
      emit,
      CollectionsTreeHelper.addExampleToNode(
        state.collections,
        event.nodeId,
        event.example,
      ),
    );
  }

  Future<void> _onDeleteExample(
    DeleteExample event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.nodeId) ==
        null) {
      return Future.value();
    }
    return _commit(
      emit,
      CollectionsTreeHelper.removeExampleFromNode(
        state.collections,
        event.nodeId,
        event.exampleId,
      ),
    );
  }

  Future<void> _onRenameExample(
    RenameExample event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.nodeId) ==
        null) {
      return Future.value();
    }
    return _commit(
      emit,
      CollectionsTreeHelper.renameExampleInNode(
        state.collections,
        event.nodeId,
        event.exampleId,
        event.newName,
      ),
    );
  }

  /// UNDO of DeleteNode. Restores under the nearest surviving captured
  /// ancestor (root when none survive); no-op if the id is already back
  /// (double-restore / concurrent import must never duplicate ids). _commit
  /// re-sorts, so the node lands in its original visual position.
  Future<void> _onRestoreNodeSubtree(
    RestoreNodeSubtree event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.node.id) !=
        null) {
      return Future.value();
    }
    String? parentId;
    for (final id in event.ancestorIds.reversed) {
      if (CollectionsTreeHelper.findNode(state.collections, id) != null) {
        parentId = id;
        break;
      }
    }
    return _commit(
      emit,
      CollectionsTreeHelper.insertIntoTree(
        state.collections,
        parentId,
        event.node,
        event.siblingIndex,
      ),
    );
  }

  /// UNDO of DeleteExample. No-op when the owning node vanished.
  Future<void> _onRestoreExample(
    RestoreExample event,
    Emitter<CollectionsState> emit,
  ) {
    if (CollectionsTreeHelper.findNode(state.collections, event.nodeId) ==
        null) {
      return Future.value();
    }
    return _commit(
      emit,
      CollectionsTreeHelper.insertExampleInNode(
        state.collections,
        event.nodeId,
        event.example,
        event.exampleIndex,
      ),
    );
  }

  Future<void> _onMoveNode(MoveNode event, Emitter<CollectionsState> emit) {
    if (event.nodeId == event.newParentId) return Future.value();

    final nodeToMove = CollectionsTreeHelper.findNode(
      state.collections,
      event.nodeId,
    );
    if (nodeToMove == null) return Future.value();

    // Reject moves into the node's own subtree — otherwise removeFromTree
    // strips the destination alongside the source and addToParent silently
    // falls through, orphaning the whole subtree.
    final newParentId = event.newParentId;
    if (newParentId != null &&
        CollectionsTreeHelper.isDescendantOrSelf(
          state.collections,
          event.nodeId,
          newParentId,
        )) {
      return Future.value();
    }

    final afterRemoval = CollectionsTreeHelper.removeFromTree(
      state.collections,
      event.nodeId,
    );
    // A destination deleted since the event was built (e.g. a git reload
    // finishing while the Move-to sheet was open) must not silently drop the
    // node: addToParent no-ops on a missing parent, so fall back to root.
    final destinationExists =
        newParentId != null &&
        CollectionsTreeHelper.findNode(afterRemoval, newParentId) != null;
    final next = destinationExists
        ? CollectionsTreeHelper.addToParent(
            afterRemoval,
            newParentId,
            nodeToMove,
          )
        : [...afterRemoval, nodeToMove];
    return _commit(emit, next);
  }

  Future<void> _onImportCollections(
    ImportCollections event,
    Emitter<CollectionsState> emit,
  ) {
    if (event.rootNodes.isEmpty) return Future.value();
    return _commitNow(emit, [...state.collections, ...event.rootNodes]);
  }

  Future<void> _onReplaceCollections(
    ReplaceCollections event,
    Emitter<CollectionsState> emit,
  ) {
    // Harvest the OUTGOING forest before it is replaced, then overlay the
    // store onto the incoming one for nodes the caller's own
    // overlayLocalOnly (run against the live forest) couldn't cover — the
    // M6 branch round-trip fix. See [_localOnlyStore].
    _harvestLocalOnly();
    final next = CollectionsTreeHelper.reapplyLocalOnly(
      event.rootNodes,
      _localOnlyStore,
    );
    _pruneLocalOnlyStore(next);
    return _commitNow(emit, next);
  }

  /// Merges the live forest's app-only data into [_localOnlyStore]. A fresh
  /// harvest wins over an older entry for the same node; entries for nodes
  /// absent from the live forest are KEPT (they may be several branch
  /// switches old and still owed a restore). Re-inserting refreshes LRU
  /// recency (Dart maps are insertion-ordered), and the oldest entries are
  /// evicted past [_localOnlyStoreCap].
  void _harvestLocalOnly() {
    final harvested = CollectionsTreeHelper.harvestLocalOnly(
      state.collections,
    );
    for (final entry in harvested.entries) {
      _localOnlyStore
        ..remove(entry.key)
        ..[entry.key] = entry.value;
    }
    while (_localOnlyStore.length > _localOnlyStoreCap) {
      _localOnlyStore.remove(_localOnlyStore.keys.first);
    }
  }

  /// Drops store entries for every node present in [forest]: its data was
  /// just restored by reapplyLocalOnly (or the incoming tree legitimately
  /// superseded it), and a kept entry would let a stale harvest resurrect
  /// deliberately-deleted data on a later replace. Entries for still-absent
  /// nodes survive — they are the whole point of the store.
  void _pruneLocalOnlyStore(List<CollectionNodeEntity> forest) {
    for (final node in forest) {
      _localOnlyStore.remove(node.id);
      _pruneLocalOnlyStore(node.children);
    }
  }
}
