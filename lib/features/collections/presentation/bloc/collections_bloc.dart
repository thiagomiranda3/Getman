import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
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
  }

  Future<void> _onLoadCollections(LoadCollections event, Emitter<CollectionsState> emit) async {
    emit(state.copyWith(isLoading: true));
    final collections = await getCollectionsUseCase();
    emit(state.copyWith(collections: CollectionsTreeHelper.sort(collections), isLoading: false));
  }

  Future<void> _onAddFolder(AddFolder event, Emitter<CollectionsState> emit) async {
    final newNode = CollectionNodeEntity(
      id: uuid.v4(),
      name: event.name,
      isFolder: true,
    );

    final parentId = event.parentId;
    final List<CollectionNodeEntity> newCollections;
    if (parentId == null || CollectionsTreeHelper.findNode(state.collections, parentId) == null) {
      newCollections = [...state.collections, newNode];
    } else {
      newCollections = CollectionsTreeHelper.addToParent(state.collections, parentId, newNode);
    }

    final sorted = CollectionsTreeHelper.sort(newCollections);
    await saveCollectionsUseCase(sorted);
    emit(state.copyWith(collections: sorted));
  }

  Future<void> _onSaveRequestToCollection(SaveRequestToCollection event, Emitter<CollectionsState> emit) async {
    final newNode = CollectionNodeEntity(
      id: uuid.v4(),
      name: event.name,
      isFolder: false,
      config: event.config,
    );

    final parentId = event.parentId;
    final List<CollectionNodeEntity> newCollections;
    if (parentId == null || CollectionsTreeHelper.findNode(state.collections, parentId) == null) {
      newCollections = [...state.collections, newNode];
    } else {
      newCollections = CollectionsTreeHelper.addToParent(state.collections, parentId, newNode);
    }

    final sorted = CollectionsTreeHelper.sort(newCollections);
    await saveCollectionsUseCase(sorted);
    emit(state.copyWith(collections: sorted));
  }

  Future<void> _onUpdateNodeRequest(UpdateNodeRequest event, Emitter<CollectionsState> emit) async {
    if (CollectionsTreeHelper.findNode(state.collections, event.id) == null) return;
    final newCollections = CollectionsTreeHelper.updateConfigInTree(state.collections, event.id, event.config);
    final sorted = CollectionsTreeHelper.sort(newCollections);
    await saveCollectionsUseCase(sorted);
    emit(state.copyWith(collections: sorted));
  }

  Future<void> _onDeleteNode(DeleteNode event, Emitter<CollectionsState> emit) async {
    final newCollections = CollectionsTreeHelper.removeFromTree(state.collections, event.id);
    final sorted = CollectionsTreeHelper.sort(newCollections);
    await saveCollectionsUseCase(sorted);
    emit(state.copyWith(collections: sorted));
  }

  Future<void> _onRenameNode(RenameNode event, Emitter<CollectionsState> emit) async {
    final newCollections = CollectionsTreeHelper.renameInTree(state.collections, event.id, event.newName);
    final sorted = CollectionsTreeHelper.sort(newCollections);
    await saveCollectionsUseCase(sorted);
    emit(state.copyWith(collections: sorted));
  }

  Future<void> _onToggleFavorite(ToggleFavorite event, Emitter<CollectionsState> emit) async {
    final newCollections = CollectionsTreeHelper.toggleFavoriteInTree(state.collections, event.id);
    final sorted = CollectionsTreeHelper.sort(newCollections);
    await saveCollectionsUseCase(sorted);
    emit(state.copyWith(collections: sorted));
  }

  Future<void> _onMoveNode(MoveNode event, Emitter<CollectionsState> emit) async {
    if (event.nodeId == event.newParentId) return;

    final nodeToMove = CollectionsTreeHelper.findNode(state.collections, event.nodeId);
    if (nodeToMove == null) return;

    var newCollections = CollectionsTreeHelper.removeFromTree(state.collections, event.nodeId);
    if (event.newParentId == null) {
      newCollections = [...newCollections, nodeToMove];
    } else {
      newCollections = CollectionsTreeHelper.addToParent(newCollections, event.newParentId!, nodeToMove);
    }

    final sorted = CollectionsTreeHelper.sort(newCollections);
    await saveCollectionsUseCase(sorted);
    emit(state.copyWith(collections: sorted));
  }
}
