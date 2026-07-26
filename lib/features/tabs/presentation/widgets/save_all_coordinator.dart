// Save-all-tabs coordinator (A3, Cmd/Ctrl+Alt+S): saves every dirty
// collection-linked tab across ALL panels through the existing save path
// (CollectionsBloc UpdateNodeRequest — the same dispatch request_view's
// _handleSave and panel_close_coordinator's _saveTab use), then reports the
// counts in a single snackbar. Dirty UNLINKED tabs (and stale links whose
// node was deleted) are skipped and counted — saving them needs a name
// prompt, which a bulk action must never open.
//
// Widget-layer, not a TabsBloc event: saving writes to CollectionsBloc,
// which TabsBloc must not reach (see panel_close_coordinator.dart for the
// same pattern). planSaveAllTabs/saveAllSnackBarMessage are pure so tests
// need no widget pumping.
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';

/// One planned save: the linked node to update and the config to write.
typedef SaveAllEntry = ({String nodeId, HttpRequestConfigEntity config});

/// What a save-all pass will do: the node updates to dispatch, plus how many
/// dirty tabs were skipped (unlinked, or linked to a since-deleted node).
typedef SaveAllPlan = ({List<SaveAllEntry> toSave, int skippedCount});

/// Pure planner: walk every panel's tabs; dirty + linked + node-still-exists
/// → save; dirty otherwise → skipped; clean → ignored.
SaveAllPlan planSaveAllTabs({
  required List<PanelEntity> panels,
  required Map<String, HttpRequestConfigEntity> savedConfigs,
  TabDirtyChecker dirtyChecker = const TabDirtyChecker(),
}) {
  final toSave = <SaveAllEntry>[];
  var skipped = 0;
  for (final panel in panels) {
    for (final tab in panel.tabs) {
      if (!dirtyChecker(tab: tab, savedConfigs: savedConfigs)) continue;
      final nodeId = tab.collectionNodeId;
      if (nodeId == null || !savedConfigs.containsKey(nodeId)) {
        skipped++;
        continue;
      }
      toSave.add((nodeId: nodeId, config: tab.config));
    }
  }
  return (toSave: toSave, skippedCount: skipped);
}

/// 'Saved N requests · M unlinked tabs skipped' — the skip clause is omitted
/// when M is 0; a full no-op reads 'Nothing to save'.
String saveAllSnackBarMessage({
  required int savedCount,
  required int skippedCount,
}) {
  final skipClause = skippedCount == 0
      ? ''
      : ' · $skippedCount unlinked tab${skippedCount == 1 ? '' : 's'} skipped';
  if (savedCount == 0) return 'Nothing to save$skipClause';
  return 'Saved $savedCount request${savedCount == 1 ? '' : 's'}$skipClause';
}

/// Plan against live bloc state, dispatch one UpdateNodeRequest per dirty
/// linked tab, and report. Call from a context below MaterialApp with
/// TabsBloc/CollectionsBloc/TabDirtyChecker providers in scope.
void saveAllTabs(BuildContext context) {
  final collectionsBloc = context.read<CollectionsBloc>();
  final plan = planSaveAllTabs(
    panels: context.read<TabsBloc>().state.panels,
    savedConfigs: collectionsBloc.state.configById,
    dirtyChecker: context.read<TabDirtyChecker>(),
  );
  for (final entry in plan.toSave) {
    collectionsBloc.add(
      UpdateNodeRequest(entry.nodeId, entry.config.copyWith()),
    );
  }
  showAppSnackBar(
    context,
    saveAllSnackBarMessage(
      savedCount: plan.toSave.length,
      skippedCount: plan.skippedCount,
    ),
  );
}
