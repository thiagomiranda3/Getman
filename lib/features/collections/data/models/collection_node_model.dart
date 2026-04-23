import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../../../features/history/data/models/request_config_model.dart';
import '../../domain/entities/collection_node_entity.dart';

part 'collection_node_model.g.dart';

@HiveType(typeId: 3)
class CollectionNode extends HiveObject {
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

  CollectionNode({
    String? id,
    required this.name,
    this.isFolder = true,
    List<CollectionNode>? children,
    this.config,
    this.isFavorite = false,
  })  : id = id ?? const Uuid().v4(),
        children = children ?? [];

  factory CollectionNode.fromEntity(CollectionNodeEntity entity) => CollectionNode(
    id: entity.id,
    name: entity.name,
    isFolder: entity.isFolder,
    children: entity.children.map((c) => CollectionNode.fromEntity(c)).toList(),
    config: entity.config != null ? HttpRequestConfig.fromEntity(entity.config!) : null,
    isFavorite: entity.isFavorite,
  );

  CollectionNodeEntity toEntity() => CollectionNodeEntity(
    id: id,
    name: name,
    isFolder: isFolder,
    children: children.map((c) => c.toEntity()).toList(),
    config: config?.toEntity(),
    isFavorite: isFavorite,
  );
}
