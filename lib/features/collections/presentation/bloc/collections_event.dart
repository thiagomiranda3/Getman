import 'package:equatable/equatable.dart';
import '../../../../core/domain/entities/request_config_entity.dart';

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

class ToggleFavorite extends CollectionsEvent {
  final String id;
  const ToggleFavorite(this.id);
  @override
  List<Object?> get props => [id];
}

class MoveNode extends CollectionsEvent {
  final String nodeId;
  final String? newParentId;
  const MoveNode(this.nodeId, this.newParentId);
  @override
  List<Object?> get props => [nodeId, newParentId];
}
