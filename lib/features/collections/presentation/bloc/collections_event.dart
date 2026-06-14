import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';

abstract class CollectionsEvent extends Equatable {
  const CollectionsEvent();
  @override
  List<Object?> get props => [];
}

class LoadCollections extends CollectionsEvent {
  const LoadCollections();
}

class AddFolder extends CollectionsEvent {
  final String name;
  final String? parentId;
  const AddFolder(this.name, {this.parentId});
  @override
  List<Object?> get props => [name, parentId];
}

class SaveRequestToCollection extends CollectionsEvent {
  final String name;
  final HttpRequestConfigEntity config;
  final String? parentId;
  const SaveRequestToCollection(this.name, this.config, {this.parentId});
  @override
  List<Object?> get props => [name, config, parentId];
}

class UpdateNodeRequest extends CollectionsEvent {
  final String id;
  final HttpRequestConfigEntity config;
  const UpdateNodeRequest(this.id, this.config);
  @override
  List<Object?> get props => [id, config];
}

class DeleteNode extends CollectionsEvent {
  final String id;
  const DeleteNode(this.id);
  @override
  List<Object?> get props => [id];
}

class RenameNode extends CollectionsEvent {
  final String id;
  final String newName;
  const RenameNode(this.id, this.newName);
  @override
  List<Object?> get props => [id, newName];
}

/// Sets the free-text description on a node. An empty string clears it.
class UpdateNodeDescription extends CollectionsEvent {
  final String id;
  final String description;
  const UpdateNodeDescription(this.id, this.description);
  @override
  List<Object?> get props => [id, description];
}

class ToggleFavorite extends CollectionsEvent {
  final String id;
  const ToggleFavorite(this.id);
  @override
  List<Object?> get props => [id];
}

/// Appends a saved request+response snapshot to a leaf (request) node.
class SaveExampleToNode extends CollectionsEvent {
  final String nodeId;
  final SavedExampleEntity example;
  const SaveExampleToNode(this.nodeId, this.example);
  @override
  List<Object?> get props => [nodeId, example];
}

/// Removes a saved example from a node.
class DeleteExample extends CollectionsEvent {
  final String nodeId;
  final String exampleId;
  const DeleteExample(this.nodeId, this.exampleId);
  @override
  List<Object?> get props => [nodeId, exampleId];
}

/// Renames a saved example.
class RenameExample extends CollectionsEvent {
  final String nodeId;
  final String exampleId;
  final String newName;
  const RenameExample(this.nodeId, this.exampleId, this.newName);
  @override
  List<Object?> get props => [nodeId, exampleId, newName];
}

class MoveNode extends CollectionsEvent {
  final String nodeId;
  final String? newParentId;
  const MoveNode(this.nodeId, this.newParentId);
  @override
  List<Object?> get props => [nodeId, newParentId];
}

class ImportCollections extends CollectionsEvent {
  final List<CollectionNodeEntity> rootNodes;
  const ImportCollections(this.rootNodes);
  @override
  List<Object?> get props => [rootNodes];
}

/// Replaces the entire collection tree (used when opening a workspace folder).
class ReplaceCollections extends CollectionsEvent {
  final List<CollectionNodeEntity> rootNodes;
  const ReplaceCollections(this.rootNodes);
  @override
  List<Object?> get props => [rootNodes];
}
