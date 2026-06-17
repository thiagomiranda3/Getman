import 'package:getman/features/collections/data/models/saved_example_model.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

part 'collection_node_model.g.dart';

@HiveType(typeId: 3)
class CollectionNode extends HiveObject {
  CollectionNode({
    required this.name,
    String? id,
    this.isFolder = true,
    List<CollectionNode>? children,
    this.config,
    this.isFavorite = false,
    this.description,
    List<SavedExampleModel>? examples,
    Map<String, String>? variables,
    List<String>? secretKeys,
  }) : id = id ?? const Uuid().v4(),
       children = children ?? [],
       examples = examples ?? [],
       variables = variables ?? {},
       secretKeys = secretKeys ?? [];

  factory CollectionNode.fromEntity(CollectionNodeEntity entity) =>
      CollectionNode(
        id: entity.id,
        name: entity.name,
        isFolder: entity.isFolder,
        children: entity.children.map(CollectionNode.fromEntity).toList(),
        config: entity.config != null
            ? HttpRequestConfig.fromEntity(entity.config!)
            : null,
        isFavorite: entity.isFavorite,
        description: entity.description,
        examples: entity.examples.map(SavedExampleModel.fromEntity).toList(),
        variables: Map<String, String>.from(entity.variables),
        secretKeys: entity.secretKeys.toList(),
      );
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  bool isFolder;

  @HiveField(3)
  List<CollectionNode> children;

  @HiveField(4)
  HttpRequestConfig? config;

  @HiveField(5)
  bool isFavorite;

  @HiveField(6)
  String? description;

  @HiveField(7)
  List<SavedExampleModel> examples;

  @HiveField(8)
  Map<String, String> variables;

  @HiveField(9)
  List<String> secretKeys;

  CollectionNodeEntity toEntity() => CollectionNodeEntity(
    id: id,
    name: name,
    isFolder: isFolder,
    children: children.map((c) => c.toEntity()).toList(),
    config: config?.toEntity(),
    isFavorite: isFavorite,
    description: description,
    examples: examples.map((e) => e.toEntity()).toList(),
    variables: Map<String, String>.from(variables),
    secretKeys: secretKeys.toSet(),
  );
}
