import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_sync_listener.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';

/// Reloads the collections tree from disk after a git operation changed the
/// files under the app (branch switch, pull, stash, pop).
///
/// This is a widget-layer coordinator by design: GitSyncBloc must not depend on
/// CollectionsBloc (no bloc→bloc coupling), so the widget that holds both does
/// the wiring — same shape as [WorkspaceSyncListener].
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
      },
      child: child,
    );
  }
}
