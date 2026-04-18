import 'package:equatable/equatable.dart';
import '../../domain/entities/collection_node_entity.dart';

class CollectionsState extends Equatable {
  final List<CollectionNodeEntity> collections;
  final bool isLoading;

  const CollectionsState({
    this.collections = const [],
    this.isLoading = false,
  });

  @override
  List<Object?> get props => [collections, isLoading];

  CollectionsState copyWith({
    List<CollectionNodeEntity>? collections,
    bool? isLoading,
  }) {
    return CollectionsState(
      collections: collections ?? this.collections,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
