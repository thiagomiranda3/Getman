import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_sync_listener.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

/// Reloads the collections tree from disk after a git operation changed the
/// files under the app (branch switch, pull, stash, pop), and brings untouched
/// open tabs along so a pulled request shows its new version.
///
/// This is a widget-layer coordinator by design: GitSyncBloc must not depend on
/// CollectionsBloc/TabsBloc (no bloc→bloc coupling), so the widget that holds
/// them does the wiring — same shape as [WorkspaceSyncListener].
class BranchSyncListener extends StatelessWidget {
  const BranchSyncListener({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<GitSyncBloc, GitSyncState>(
      listenWhen: (prev, next) => prev.reloadToken != next.reloadToken,
      listener: (context, state) async {
        final path = context.read<SettingsBloc>().state.settings.workspacePath;
        if (path == null || path.isEmpty) return;
        final sync = context.read<WorkspaceSyncService>();
        final collections = context.read<CollectionsBloc>();
        final tabs = context.read<TabsBloc>();
        // Snapshot the saved configs *before* the reload so we can tell open
        // tabs that were untouched (safe to refresh) from those the user has
        // edited (must not be clobbered).
        final beforeIndex = collections.state.configById;
        // The disk read runs *inside* the suspension, not before it.
        // GitBranchService resumes mirroring the moment git returns, so the
        // window this listener opens starts there: while `read` walks the
        // workspace (a recursive dir scan + a JSON parse per file — slow on a
        // big tree or a cold FS), Hive still holds the OLD branch's forest
        // while disk holds the NEW one. An edit landing in that window would
        // arm a mirror of the old forest and write it onto the new branch.
        //
        // The suspension also covers the hand-off that follows: the
        // CollectionsBloc state change is seen by WorkspaceSyncListener, which
        // would otherwise mirror this very forest straight back onto the files
        // git just wrote — a reload → mirror → reload loop.
        await sync.withMirroringSuspended(() async {
          final List<CollectionNodeEntity> onDisk;
          try {
            onDisk = await sync.read(path);
          } on Object catch (_) {
            return; // best-effort: a failed read must not break the session
          }
          collections.add(ReplaceCollections(onDisk));
          // Yield one event-loop turn: the bloc delivers the event, runs the
          // handler and notifies its state listeners over microtasks, so they
          // have all run by the time a zero-duration timer fires. This relies
          // on CollectionsBloc._commitNow emitting SYNCHRONOUSLY on entry
          // (before its awaited save) — move that emit after an awaited write,
          // or give ReplaceCollections a debounce/restartable transformer, and
          // the yield is no longer enough to cover the emission.
          // (Resuming a touch early would at worst re-write byte-identical
          // files; holding the gate open on a state that never arrives would
          // kill mirroring for the session — so this errs on the safe side
          // deliberately.)
          await Future<void>.delayed(Duration.zero);
        });
        // The tree is now the pulled/switched version. Bring untouched open
        // tabs along so "pull → my open request updates" holds; tabs with
        // unsaved edits are deliberately left as-is (never clobbered). Outside
        // the suspension: UpdateTab touches the tabs box, not the collections
        // mirror, so it can't feed the reload→mirror loop above.
        for (final refreshed in tabsToRefreshAfterReload(
          tabs.state.panels,
          beforeIndex,
          collections.state.configById,
        )) {
          tabs.add(UpdateTab(refreshed));
        }
      },
      child: child,
    );
  }
}

/// Pure reconciliation: given every open tab (across [panels]) and the saved
/// request configs keyed by collection-node id *before* and *after* a git
/// reload, returns the tab entities whose linked request changed upstream and
/// that had **no local edits** — updated to the new config. Tabs that were
/// edited, unlinked, or whose node was deleted upstream are left out.
///
/// "Untouched" mirrors `TabDirtyChecker`: a clean tab's config equals what was
/// saved before the pull. `HttpRequestConfigEntity` equality excludes `id`, so
/// the comparison is on the request signature; the pulled config keeps the
/// same persisted `id`, so linkage (e.g. chaining rules) survives the refresh.
@visibleForTesting
List<HttpRequestTabEntity> tabsToRefreshAfterReload(
  List<PanelEntity> panels,
  Map<String, HttpRequestConfigEntity> before,
  Map<String, HttpRequestConfigEntity> after,
) {
  final out = <HttpRequestTabEntity>[];
  for (final panel in panels) {
    for (final tab in panel.tabs) {
      final nodeId = tab.collectionNodeId;
      if (nodeId == null) continue; // unlinked tab — nothing to track
      final saved = after[nodeId];
      if (saved == null) continue; // node deleted upstream — leave the tab
      final previouslySaved = before[nodeId];
      final untouched =
          previouslySaved != null && tab.config == previouslySaved;
      if (untouched && tab.config != saved) {
        out.add(tab.copyWith(config: saved));
      }
    }
  }
  return out;
}
