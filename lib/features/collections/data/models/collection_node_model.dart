import 'package:hive/hive.dart';
import '../../../../features/history/data/models/request_config_model.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isFolder': isFolder,
    'children': children.map((c) => c.toJson()).toList(),
    'config': config?.toJson(),
    'isFavorite': isFavorite,
  };

  factory CollectionNode.fromJson(Map<String, dynamic> json) => CollectionNode(
    id: json['id'],
    name: json['name'],
    isFolder: json['isFolder'] ?? true,
    children: (json['children'] as List?)
        ?.map((c) => CollectionNode.fromJson(c))
        .toList(),
    config: json['config'] != null ? HttpRequestConfig.fromJson(json['config']) : null,
    isFavorite: json['isFavorite'] ?? false,
  );

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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CollectionNode) return false;

    return other.id == id &&
        other.name == name &&
        other.isFolder == isFolder &&
        other.isFavorite == isFavorite &&
        other.config == config &&
        const ListEquality().equals(other.children, children);
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        isFolder.hashCode ^
        isFavorite.hashCode ^
        config.hashCode ^
        const ListEquality().hash(children);
  }
}
