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
  const AddFolder(this.name, {this.parentId});
  final String name;
  final String? parentId;
  @override
  List<Object?> get props => [name, parentId];
}

class SaveRequestToCollection extends CollectionsEvent {
  const SaveRequestToCollection(this.name, this.config, {this.parentId});
  final String name;
  final HttpRequestConfigEntity config;
  final String? parentId;
  @override
  List<Object?> get props => [name, config, parentId];
}

class UpdateNodeRequest extends CollectionsEvent {
  const UpdateNodeRequest(this.id, this.config);
  final String id;
  final HttpRequestConfigEntity config;
  @override
  List<Object?> get props => [id, config];
}

class DeleteNode extends CollectionsEvent {
  const DeleteNode(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class RenameNode extends CollectionsEvent {
  const RenameNode(this.id, this.newName);
  final String id;
  final String newName;
  @override
  List<Object?> get props => [id, newName];
}

/// Sets the free-text description on a node. An empty string clears it.
class UpdateNodeDescription extends CollectionsEvent {
  const UpdateNodeDescription(this.id, this.description);
  final String id;
  final String description;
  @override
  List<Object?> get props => [id, description];
}

class ToggleFavorite extends CollectionsEvent {
  const ToggleFavorite(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

/// Appends a saved request+response snapshot to a leaf (request) node.
class SaveExampleToNode extends CollectionsEvent {
  const SaveExampleToNode(this.nodeId, this.example);
  final String nodeId;
  final SavedExampleEntity example;
  @override
  List<Object?> get props => [nodeId, example];
}

/// Removes a saved example from a node.
class DeleteExample extends CollectionsEvent {
  const DeleteExample(this.nodeId, this.exampleId);
  final String nodeId;
  final String exampleId;
  @override
  List<Object?> get props => [nodeId, exampleId];
}

/// Renames a saved example.
class RenameExample extends CollectionsEvent {
  const RenameExample(this.nodeId, this.exampleId, this.newName);
  final String nodeId;
  final String exampleId;
  final String newName;
  @override
  List<Object?> get props => [nodeId, exampleId, newName];
}

class MoveNode extends CollectionsEvent {
  const MoveNode(this.nodeId, this.newParentId);
  final String nodeId;
  final String? newParentId;
  @override
  List<Object?> get props => [nodeId, newParentId];
}

class ImportCollections extends CollectionsEvent {
  const ImportCollections(this.rootNodes);
  final List<CollectionNodeEntity> rootNodes;
  @override
  List<Object?> get props => [rootNodes];
}

/// Replaces the entire collection tree (used when opening a workspace folder).
class ReplaceCollections extends CollectionsEvent {
  const ReplaceCollections(this.rootNodes);
  final List<CollectionNodeEntity> rootNodes;
  @override
  List<Object?> get props => [rootNodes];
}
