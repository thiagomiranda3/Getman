// TabsBloc event definitions: tab CRUD (add/remove/reorder/duplicate/close
// variants), send/cancel, response time-travel, and panel CRUD/move events.
// Identity-addressed by tabId/panelId except SetActiveIndex/ReorderTabs
// (position is the operation) — see tabs_bloc.dart for the invariants.
// ReopenClosedTab (no payload) pops TabsBloc's in-memory closed-tab stack.
// CloseSavedTabs bulk-closes every non-dirty tab of a panel onto that stack.
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

/// Identity-addressed like every other tab event (see
/// docs/architecture/tabs-and-panels.md): the dispatcher names the tab, so a
/// concurrent tab switch can't redirect the send. [envVars] must be resolved
/// by the dispatcher via
/// `ActiveEnvironmentHelper.variablesFor(...)` — an empty map sends `{{var}}`
/// placeholders to the network verbatim.
class SendRequest extends TabsEvent {
  const SendRequest({
    required this.tabId,
    this.envVars = const {},
    this.responseHistoryLimit = 5,
    this.saveLargeResponsesInHistory = true,
  });
  final String tabId;
  final Map<String, String> envVars;

  /// How many recent responses to retain for time-travel (0 disables history).
  /// Carried on the event (like [envVars]) because the dispatcher reads it from
  /// `SettingsBloc`; the bloc holds no settings reference.
  final int responseHistoryLimit;

  /// When false, history entries whose body exceeds the large-viewer threshold
  /// are persisted metadata-only (the in-session copy stays full).
  final bool saveLargeResponsesInHistory;
  @override
  List<Object?> get props => [
    tabId,
    envVars,
    responseHistoryLimit,
    saveLargeResponsesInHistory,
  ];
}

/// Swaps the tab's displayed [HttpRequestTabEntity.response] to the history
/// entry with [entryId] without mutating the history list (time-travel).
/// Identity-addressed like every other tab event (see
/// docs/architecture/tabs-and-panels.md).
class ViewResponseHistoryEntry extends TabsEvent {
  const ViewResponseHistoryEntry({required this.tabId, required this.entryId});
  final String tabId;
  final String entryId;
  @override
  List<Object?> get props => [tabId, entryId];
}

class CancelRequest extends TabsEvent {
  const CancelRequest(this.tabId);
  final String tabId;
  @override
  List<Object?> get props => [tabId];
}

class AddPanel extends TabsEvent {
  const AddPanel({this.name});
  final String? name;
  @override
  List<Object?> get props => [name];
}

class RemovePanel extends TabsEvent {
  const RemovePanel(this.panelId);
  final String panelId;
  @override
  List<Object?> get props => [panelId];
}

class RenamePanel extends TabsEvent {
  const RenamePanel(this.panelId, this.name);
  final String panelId;
  final String name;
  @override
  List<Object?> get props => [panelId, name];
}

class SetActivePanel extends TabsEvent {
  const SetActivePanel(this.panelId);
  final String panelId;
  @override
  List<Object?> get props => [panelId];
}

class ReorderPanels extends TabsEvent {
  const ReorderPanels(this.oldIndex, this.newIndex);
  final int oldIndex;
  final int newIndex;
  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class MoveTabToPanel extends TabsEvent {
  const MoveTabToPanel(this.tabId, this.targetPanelId);
  final String tabId;
  final String targetPanelId;
  @override
  List<Object?> get props => [tabId, targetPanelId];
}

class MoveTabToNewPanel extends TabsEvent {
  const MoveTabToNewPanel(this.tabId, {this.name});
  final String tabId;
  final String? name;
  @override
  List<Object?> get props => [tabId, name];
}

/// Restores the most recently closed tab (LIFO, in-memory, max 10 — see
/// TabsBloc._closedTabs). No payload: the stack itself is the state. Bound
/// to Cmd/Ctrl+Shift+T and the tab-chip context menu.
class ReopenClosedTab extends TabsEvent {
  const ReopenClosedTab();
}

/// Closes every NON-dirty tab in [panelId] ("CLOSE SAVED TABS" — A3). Never
/// prompts; each closed tab is pushed onto the reopen stack. [savedConfigs]
/// is the dispatcher-resolved id→config index from CollectionsState — the
/// bloc holds no collections reference, same pattern as [SendRequest.envVars].
class CloseSavedTabs extends TabsEvent {
  const CloseSavedTabs({required this.panelId, required this.savedConfigs});
  final String panelId;
  final Map<String, HttpRequestConfigEntity> savedConfigs;
  @override
  List<Object?> get props => [panelId, savedConfigs];
}

/// Reverts a dirty LINKED tab's config to [savedConfig] — the saved node's
/// config, i.e. the exact baseline TabDirtyChecker compares against. The
/// dispatcher resolves it from CollectionsState.configById (the bloc holds
/// no collections reference — same pattern as [SendRequest.envVars]). The
/// displayed response and the time-travel history are untouched. No-op for
/// unlinked or missing tabs.
class RevertTab extends TabsEvent {
  const RevertTab({required this.tabId, required this.savedConfig});
  final String tabId;
  final HttpRequestConfigEntity savedConfig;
  @override
  List<Object?> get props => [tabId, savedConfig];
}
