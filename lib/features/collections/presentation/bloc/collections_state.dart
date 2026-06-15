import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart'
    show TabDirtyChecker;

// _configById is a lazily-memoized cache derived from `collections` (excluded
// from props), so equality/immutability semantics are unaffected.
// ignore: must_be_immutable
class CollectionsState extends Equatable {
  CollectionsState({
    this.collections = const [],
    this.isLoading = false,
  });
  final List<CollectionNodeEntity> collections;
  final bool isLoading;

  /// Flat index of every node id → its request config, built lazily and
  /// memoized once per state instance. Lets [TabDirtyChecker] do an O(1) lookup
  /// instead of an O(nodes) tree walk on every CollectionsState emission, per
  /// open linked tab (M4): T×O(N) becomes O(N)+T×O(1).
  Map<String, HttpRequestConfigEntity> get configById =>
      _configById ??= _buildConfigIndex(collections);
  Map<String, HttpRequestConfigEntity>? _configById;

  static Map<String, HttpRequestConfigEntity> _buildConfigIndex(
    List<CollectionNodeEntity> nodes,
  ) {
    final map = <String, HttpRequestConfigEntity>{};
    void walk(List<CollectionNodeEntity> ns) {
      for (final n in ns) {
        final config = n.config;
        if (config != null) map[n.id] = config;
        if (n.children.isNotEmpty) walk(n.children);
      }
    }

    walk(nodes);
    return map;
  }

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
