import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';

class CollectionNodeEntity extends Equatable {
  const CollectionNodeEntity({
    required this.id,
    required this.name,
    this.isFolder = true,
    this.children = const [],
    this.config,
    this.isFavorite = false,
    this.description,
    this.examples = const [],
    this.variables = const {},
    this.secretKeys = const {},
  });
  final String id;
  final String name;
  final bool isFolder;
  final List<CollectionNodeEntity> children;
  final HttpRequestConfigEntity? config;
  final bool isFavorite;

  /// Free-text notes for a folder or request. Null/empty means "no description".
  final String? description;

  /// Saved request+response snapshots for a leaf (request) node. Kept separate
  /// from [children] so tree-walk logic never treats an example as a tree node.
  final List<SavedExampleEntity> examples;

  /// Collection-scoped variables for a folder. A request inherits the merge of
  /// every ancestor folder's variables (deepest wins), overlaid by the active
  /// environment at send time. Empty for leaf (request) nodes.
  final Map<String, String> variables;

  /// Names within [variables] flagged secret (masked in the editor + on
  /// export).
  final Set<String> secretKeys;

  CollectionNodeEntity copyWith({
    String? name,
    bool? isFolder,
    List<CollectionNodeEntity>? children,
    HttpRequestConfigEntity? config,
    bool? isFavorite,
    String? description,
    List<SavedExampleEntity>? examples,
    Map<String, String>? variables,
    Set<String>? secretKeys,
  }) {
    return CollectionNodeEntity(
      id: id,
      name: name ?? this.name,
      isFolder: isFolder ?? this.isFolder,
      children: children ?? this.children,
      config: config ?? this.config,
      isFavorite: isFavorite ?? this.isFavorite,
      description: description ?? this.description,
      examples: examples ?? this.examples,
      variables: variables ?? this.variables,
      secretKeys: secretKeys ?? this.secretKeys,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    isFolder,
    children,
    config,
    isFavorite,
    description,
    examples,
    variables,
    secretKeys,
  ];
}
