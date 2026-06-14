import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:uuid/uuid.dart';

class CollectionsBloc extends Bloc<CollectionsEvent, CollectionsState> {
  final GetCollectionsUseCase getCollectionsUseCase;
  final SaveCollectionsUseCase saveCollectionsUseCase;
  static const Uuid _uuid = Uuid();

  /// Granular edits (add/rename/move/delete/favorite) emit instantly and persist
  /// the whole tree on a debounce — coalescing a burst of edits into one write
  /// instead of one rewrite per action. Import/Replace flush immediately.
  final Duration saveDebounce;
  Timer? _saveTimer;
  bool _pendingSave = false;

  CollectionsBloc({
    required this.getCollectionsUseCase,
    required this.saveCollectionsUseCase,
    this.saveDebounce = const Duration(seconds: 2),
  }) : super(const CollectionsState()) {
    on<LoadCollections>(_onLoadCollections);
    on<AddFolder>(_onAddFolder);
    on<SaveRequestToCollection>(_onSaveRequestToCollection);
    on<UpdateNodeRequest>(_onUpdateNodeRequest);
    on<DeleteNode>(_onDeleteNode);
    on<RenameNode>(_onRenameNode);
    on<ToggleFavorite>(_onToggleFavorite);
    on<MoveNode>(_onMoveNode);
    on<ImportCollections>(_onImportCollections);
    on<ReplaceCollections>(_onReplaceCollections);
  }

  void _scheduleSave() {
    _pendingSave = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, _flush);
  }

  /// Persist the current tree if a save is pending. Logged-not-thrown so a
  /// write failure never blocks the UI (which already reflects the change).
  Future<void> _flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_pendingSave) return;
    _pendingSave = false;
    try {
      await saveCollectionsUseCase(state.collections);
    } on PersistenceFailure catch (f) {
      debugPrint('Collections save failed: ${f.message}');
    }
  }

  @override
  Future<void> close() async {
    await _flush();
    return super.close();
  }

  /// Append [newNode] to [parentId]'s children, or to the root when [parentId]
  /// is null or refers to a node that no longer exists.
  List<CollectionNodeEntity> _addToTree(CollectionNodeEntity newNode, String? parentId) {
    if (parentId == null || CollectionsTreeHelper.findNode(state.collections, parentId) == null) {
      return [...state.collections, newNode];
    }
    return CollectionsTreeHelper.addToParent(state.collections, parentId, newNode);
  }

  /// Sort + emit immediately (the user must see their action take effect), then
  /// schedule a debounced whole-tree save.
  Future<void> _commit(Emitter<CollectionsState> emit, List<CollectionNodeEntity> next) async {
    emit(state.copyWith(collections: CollectionsTreeHelper.sort(next)));
    _scheduleSave();
  }

  /// Like [_commit] but persists right away — used for bulk import/replace,
  /// where waiting out the debounce window would risk losing a large change.
  Future<void> _commitNow(Emitter<CollectionsState> emit, List<CollectionNodeEntity> next) async {
    emit(state.copyWith(collections: CollectionsTreeHelper.sort(next)));
    _pendingSave = true;
    await _flush();
  }

  Future<void> _onLoadCollections(LoadCollections event, Emitter<CollectionsState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final collections = await getCollectionsUseCase();
      emit(state.copyWith(collections: CollectionsTreeHelper.sort(collections), isLoading: false));
    } on PersistenceFailure catch (f) {
      debugPrint('LoadCollections failed: ${f.message}');
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onAddFolder(AddFolder event, Emitter<CollectionsState> emit) {
    final newNode = CollectionNodeEntity(id: _uuid.v4(), name: event.name, isFolder: true);
    return _commit(emit, _addToTree(newNode, event.parentId));
  }

  Future<void> _onSaveRequestToCollection(SaveRequestToCollection event, Emitter<CollectionsState> emit) {
    final newNode = CollectionNodeEntity(
      id: _uuid.v4(),
      name: event.name,
      isFolder: false,
      config: event.config,
    );
    return _commit(emit, _addToTree(newNode, event.parentId));
  }

  Future<void> _onUpdateNodeRequest(UpdateNodeRequest event, Emitter<CollectionsState> emit) {
    if (CollectionsTreeHelper.findNode(state.collections, event.id) == null) return Future.value();
    return _commit(emit, CollectionsTreeHelper.updateConfigInTree(state.collections, event.id, event.config));
  }

  Future<void> _onDeleteNode(DeleteNode event, Emitter<CollectionsState> emit) {
    return _commit(emit, CollectionsTreeHelper.removeFromTree(state.collections, event.id));
  }

  Future<void> _onRenameNode(RenameNode event, Emitter<CollectionsState> emit) {
    return _commit(emit, CollectionsTreeHelper.renameInTree(state.collections, event.id, event.newName));
  }

  Future<void> _onToggleFavorite(ToggleFavorite event, Emitter<CollectionsState> emit) {
    return _commit(emit, CollectionsTreeHelper.toggleFavoriteInTree(state.collections, event.id));
  }

  Future<void> _onMoveNode(MoveNode event, Emitter<CollectionsState> emit) {
    if (event.nodeId == event.newParentId) return Future.value();

    final nodeToMove = CollectionsTreeHelper.findNode(state.collections, event.nodeId);
    if (nodeToMove == null) return Future.value();

    // Reject moves into the node's own subtree — otherwise removeFromTree
    // strips the destination alongside the source and addToParent silently
    // falls through, orphaning the whole subtree.
    final newParentId = event.newParentId;
    if (newParentId != null &&
        CollectionsTreeHelper.isDescendantOrSelf(state.collections, event.nodeId, newParentId)) {
      return Future.value();
    }

    final afterRemoval = CollectionsTreeHelper.removeFromTree(state.collections, event.nodeId);
    final next = newParentId == null
        ? [...afterRemoval, nodeToMove]
        : CollectionsTreeHelper.addToParent(afterRemoval, newParentId, nodeToMove);
    return _commit(emit, next);
  }

  Future<void> _onImportCollections(ImportCollections event, Emitter<CollectionsState> emit) {
    if (event.rootNodes.isEmpty) return Future.value();
    return _commitNow(emit, [...state.collections, ...event.rootNodes]);
  }

  Future<void> _onReplaceCollections(ReplaceCollections event, Emitter<CollectionsState> emit) {
    return _commitNow(emit, event.rootNodes);
  }
}
