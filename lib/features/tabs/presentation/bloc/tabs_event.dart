import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

abstract class TabsEvent extends Equatable {
  const TabsEvent();
  @override
  List<Object?> get props => [];
}

class LoadTabs extends TabsEvent {
  const LoadTabs();
}

class AddTab extends TabsEvent {
  const AddTab({
    this.config,
    this.collectionNodeId,
    this.collectionName,
    this.response,
  });
  final HttpRequestConfigEntity? config;
  final String? collectionNodeId;
  final String? collectionName;

  /// Pre-populates the new tab's response pane — used when opening a saved
  /// example so its captured response shows immediately. Null for a fresh tab.
  final HttpResponseEntity? response;
  @override
  List<Object?> get props => [
    config,
    collectionNodeId,
    collectionName,
    response,
  ];
}

class RemoveTab extends TabsEvent {
  const RemoveTab(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

class SetActiveIndex extends TabsEvent {
  const SetActiveIndex(this.index);
  final int index;
  @override
  List<Object?> get props => [index];
}

class ReorderTabs extends TabsEvent {
  const ReorderTabs(this.oldIndex, this.newIndex);
  final int oldIndex;
  final int newIndex;
  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class UpdateTab extends TabsEvent {
  const UpdateTab(this.tab);
  final HttpRequestTabEntity tab;
  @override
  List<Object?> get props => [tab];
}

class CloseOtherTabs extends TabsEvent {
  const CloseOtherTabs(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

class CloseTabsToTheRight extends TabsEvent {
  const CloseTabsToTheRight(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

class CloseTabsToTheLeft extends TabsEvent {
  const CloseTabsToTheLeft(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

class DuplicateTab extends TabsEvent {
  const DuplicateTab(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

/// Identity-addressed like every other tab event (CLAUDE.md §4.2): the
/// dispatcher names the tab, so a concurrent tab switch can't redirect the
/// send. [envVars] must be resolved by the dispatcher via
/// `ActiveEnvironmentHelper.variablesFor(...)` — an empty map sends `{{var}}`
/// placeholders to the network verbatim.
class SendRequest extends TabsEvent {
  const SendRequest({required this.tabId, this.envVars = const {}});
  final String tabId;
  final Map<String, String> envVars;
  @override
  List<Object?> get props => [tabId, envVars];
}

class CancelRequest extends TabsEvent {
  const CancelRequest(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}
