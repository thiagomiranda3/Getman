import 'package:hive/hive.dart';
import 'request_config.dart';
import 'package:uuid/uuid.dart';

part 'collection_node.g.dart';

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
}
