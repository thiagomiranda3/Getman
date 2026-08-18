// Widget-layer coordinator between CollectionsBloc and the on-disk workspace:
// mirrors collection changes to disk (WorkspaceSyncService.scheduleMirror)
// AND — fix for finding M3 — imports the workspace from disk ONCE, before the
// first mirror of a session. Without the boot import, launching the app
// mirrored Hive straight over a workspace that git changed while Getman was
// closed (e.g. `git pull` in a terminal): the ~1s debounced mirror's orphan
// reconciliation deleted the teammate's new files before any human could
// trigger the documented "explicit reload".
//
// Gotchas: the boot import must wait for a LOADED CollectionsBloc emission
// (isLoading=false) — importing against the pre-load empty tree would feed
// overlayLocalOnly an empty "current" forest and drop app-only data (saved
// examples, secret values). The import runs inside withMirroringSuspended
// with the same synchronous-emit + zero-timer yield discipline as
// BranchSyncListener (see the comment there before changing CollectionsBloc's
// emit ordering). A failed boot read follows BranchSyncListener's contract:
// WorkspaceSyncService.read has already sticky-blocked mirroring for the root
// (isReloadBlocked) and nothing is wiped. Only the root already connected at
// construction time is gated: a workspace connected mid-session via
// WorkspaceSettingsTile imports before connecting, so its ReplaceCollections
// must (and does) still mirror normally.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/navigation/app_messenger.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';

/// Mirrors collection changes to the on-disk workspace when one is configured,
/// and imports the workspace from disk once per session BEFORE the first
/// mirror (disk may have been changed by git while the app was closed — the
/// mirror's orphan reconciliation would otherwise delete those changes).
///
/// Reads the workspace path from [SettingsBloc] and delegates to
/// [WorkspaceSyncService] — keeping CollectionsBloc unaware of the filesystem
/// (the coordinating widget holds all three, per the bloc-coupling rule).
///
/// Boot-import gate: the root connected at construction time (settings load
/// synchronously at boot, so the seeded [SettingsBloc] state is authoritative
/// here) must be read from disk and merged into Hive before any mirror to it
/// is allowed. The merge is `overlayLocalOnly(onDisk, current)` — the exact
/// disk-wins merge `BranchSyncListener` and the settings tile use, carrying
/// app-only data (saved examples, secret values) over the disk forest. A root
/// connected LATER via the settings tile was imported by the tile before the
/// path changed, so a path other than the boot root is never gated.
class WorkspaceSyncListener extends StatefulWidget {
  const WorkspaceSyncListener({required this.child, super.key});
  final Widget child;

  @override
  State<WorkspaceSyncListener> createState() => _WorkspaceSyncListenerState();
}

class _WorkspaceSyncListenerState extends State<WorkspaceSyncListener> {
  /// The workspace root that was already connected when this widget mounted
  /// (i.e. at app boot) and has not yet been imported from disk. Mirroring to
  /// it is suppressed until the import completes. Null when no workspace was
  /// connected at boot, or once the import has run (success or failure — on
  /// failure [WorkspaceSyncService.read] sticky-blocks the root itself, so
  /// keeping this gate would only re-trigger reads on every emission).
  String? _pendingBootImportRoot;

  /// Re-entrancy guard: emissions arriving while the (possibly slow) boot
  /// import's disk read is in flight must not start a second import.
  bool _bootImportInFlight = false;

  @override
  void initState() {
    super.initState();
    final path = context.read<SettingsBloc>().state.settings.workspacePath;
    _pendingBootImportRoot = (path == null || path.isEmpty) ? null : path;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CollectionsBloc, CollectionsState>(
      // isLoading transitions are watched too: a failed LoadCollections
      // toggles isLoading with the forest unchanged, and the boot import must
      // still run off that emission (showing disk content beats an empty
      // tree whose first edit would mirror-wipe the workspace).
      listenWhen: (prev, next) =>
          prev.collections != next.collections ||
          prev.isLoading != next.isLoading,
      listener: (context, state) {
        final path = context.read<SettingsBloc>().state.settings.workspacePath;
        if (path == null || path.isEmpty) return;
        if (path == _pendingBootImportRoot) {
          // No mirror may reach this root before the boot import lands: the
          // emission being handled is either pre-import Hive state (stale
          // relative to disk) or the import's own ReplaceCollections.
          if (state.isLoading || _bootImportInFlight) return;
          unawaited(_runBootImport(context, path));
          return;
        }
        context.read<WorkspaceSyncService>().scheduleMirror(
          path,
          state.collections,
        );
      },
      child: widget.child,
    );
  }

  /// Disk → Hive import of the boot-connected workspace, mirroring
  /// `BranchSyncListener`'s reload discipline: the read AND the
  /// ReplaceCollections hand-off run inside
  /// [WorkspaceSyncService.withMirroringSuspended], and a
  /// zero-duration yield lets the bloc's synchronous emit reach listeners
  /// before mirroring resumes (see BranchSyncListener before changing this).
  Future<void> _runBootImport(BuildContext context, String root) async {
    _bootImportInFlight = true;
    // Everything the awaits below need is read from the context up front —
    // the listener context must not be touched after an await.
    final sync = context.read<WorkspaceSyncService>();
    final collections = context.read<CollectionsBloc>();
    final settings = context.read<SettingsBloc>();
    // maybeOf, not of: in production this widget sits ABOVE MaterialApp, so
    // there is no ScaffoldMessenger ancestor — reach the app's root messenger
    // via appMessengerKey instead, degrading to a log only if that too is
    // absent. (Tests host it under a Scaffold and assert the snackbar.)
    final messenger =
        ScaffoldMessenger.maybeOf(context) ?? appMessengerKey.currentState;
    try {
      await sync.withMirroringSuspended(() async {
        final List<CollectionNodeEntity> onDisk;
        try {
          onDisk = await sync.read(root);
        } on Object catch (e) {
          // Same contract as BranchSyncListener's failed reload: nothing is
          // wiped (the in-app tree is left as loaded from Hive) and sync.read
          // has already sticky-blocked mirroring for this root, so the stale
          // forest can never be written over the files on disk.
          const message =
              'The workspace on disk could not be read — the in-app tree was '
              'loaded from local data and mirroring to this workspace is '
              'paused. Fix or remove the malformed file, then RELOAD FROM '
              'DISK in Settings → Workspace.';
          if (messenger != null) {
            showAppSnackBarVia(messenger, message);
          } else {
            debugPrint('Workspace boot import failed for "$root": $e');
          }
          return;
        }
        // The read can be slow (recursive dir scan + JSON parse per file).
        // If the workspace was disconnected or switched while it ran, this
        // result belongs to a root that is no longer connected — importing it
        // would clobber the tree the settings tile just installed.
        if (settings.state.settings.workspacePath != root) return;
        final merged = CollectionsTreeHelper.sort(
          CollectionsTreeHelper.overlayLocalOnly(
            onDisk,
            collections.state.collections,
          ),
        );
        // The common boot (disk == Hive, no external git activity) needs no
        // replace at all — skip the redundant emission + Hive write.
        if (listEquals(merged, collections.state.collections)) return;
        collections.add(ReplaceCollections(merged));
        // Yield one event-loop turn so the synchronous emit (and this
        // listener's own suppressed invocation for it) land while mirroring
        // is still suspended — identical to BranchSyncListener's yield.
        await Future<void>.delayed(Duration.zero);
      });
    } finally {
      _pendingBootImportRoot = null;
      _bootImportInFlight = false;
    }
  }
}
