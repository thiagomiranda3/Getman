import 'package:equatable/equatable.dart';
import '../../domain/entities/request_tab_entity.dart';
import '../../../../core/domain/entities/request_config_entity.dart';

abstract class TabsEvent extends Equatable {
  const TabsEvent();
  @override
  List<Object?> get props => [];
}

class LoadTabs extends TabsEvent {
  const LoadTabs();
}

class AddTab extends TabsEvent {
  final HttpRequestConfigEntity? config;
  final String? collectionNodeId;
  final String? collectionName;
  const AddTab({this.config, this.collectionNodeId, this.collectionName});
  @override
  List<Object?> get props => [config, collectionNodeId, collectionName];
}

class RemoveTab extends TabsEvent {
  final String tabId;
  const RemoveTab(this.tabId);
  @override
  List<Object?> get props => [tabId];
}

class SetActiveIndex extends TabsEvent {
  final int index;
  const SetActiveIndex(this.index);
  @override
  List<Object?> get props => [index];
}

class ReorderTabs extends TabsEvent {
  final int oldIndex;
  final int newIndex;
  const ReorderTabs(this.oldIndex, this.newIndex);
  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class UpdateTab extends TabsEvent {
  final HttpRequestTabEntity tab;
  const UpdateTab(this.tab);
  @override
  List<Object?> get props => [tab];
}

class CloseOtherTabs extends TabsEvent {
  final String tabId;
  const CloseOtherTabs(this.tabId);
  @override
  List<Object?> get props => [tabId];
}

class CloseTabsToTheRight extends TabsEvent {
  final String tabId;
  const CloseTabsToTheRight(this.tabId);
  @override
  List<Object?> get props => [tabId];
}

class DuplicateTab extends TabsEvent {
  final String tabId;
  const DuplicateTab(this.tabId);
  @override
  List<Object?> get props => [tabId];
}

class SendRequest extends TabsEvent {
  const SendRequest();
}

class CancelRequest extends TabsEvent {
  final String tabId;
  const CancelRequest(this.tabId);
  @override
  List<Object?> get props => [tabId];
}
