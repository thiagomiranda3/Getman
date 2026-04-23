import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/collection_node_entity.dart';
import '../../domain/usecases/collections_usecases.dart';
import '../../domain/logic/collections_tree_helper.dart';
import 'collections_event.dart';
import 'collections_state.dart';

class CollectionsBloc extends Bloc<CollectionsEvent, CollectionsState> {
  final GetCollectionsUseCase getCollectionsUseCase;
  final SaveCollectionsUseCase saveCollectionsUseCase;
  final Uuid uuid = const Uuid();

  CollectionsBloc({
    required this.getCollectionsUseCase,
    required this.saveCollectionsUseCase,
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
  }

  /// Append [newNode] to [parentId]'s children, or to the root when [parentId]
  /// is null or refers to a node that no longer exists.
  List<CollectionNodeEntity> _addToTree(CollectionNodeEntity newNode, String? parentId) {
    if (parentId == null || CollectionsTreeHelper.findNode(state.collections, parentId) == null) {
      return [...state.collections, newNode];
    }
    return CollectionsTreeHelper.addToParent(state.collections, parentId, newNode);
  }

  /// Sort [next], persist, emit. Persistence failures are logged but never
  /// block the UI update — the user must see their action take effect.
  Future<void> _commit(Emitter<CollectionsState> emit, List<CollectionNodeEntity> next) async {
    final sorted = CollectionsTreeHelper.sort(next);
    emit(state.copyWith(collections: sorted));
    try {
      await saveCollectionsUseCase(sorted);
    } on PersistenceFailure catch (f) {
      debugPrint('Collections save failed: ${f.message}');
    }
  }

  Future<void> _onLoadCollections(LoadCollections event, Emitter<CollectionsState> emit) async {
    emit(state.copyWith(isLoading: true));
    final collections = await getCollectionsUseCase();
    emit(state.copyWith(collections: CollectionsTreeHelper.sort(collections), isLoading: false));
  }

  Future<void> _onAddFolder(AddFolder event, Emitter<CollectionsState> emit) {
    final newNode = CollectionNodeEntity(id: uuid.v4(), name: event.name, isFolder: true);
    return _commit(emit, _addToTree(newNode, event.parentId));
  }

  Future<void> _onSaveRequestToCollection(SaveRequestToCollection event, Emitter<CollectionsState> emit) {
    final newNode = CollectionNodeEntity(
      id: uuid.v4(),
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
    return _commit(emit, [...state.collections, ...event.rootNodes]);
  }
}
