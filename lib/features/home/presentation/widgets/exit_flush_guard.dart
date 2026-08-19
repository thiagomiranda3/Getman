// Flushes debounced persistence (tabs: 10 s, collections: 2 s) when the app
// is asked to exit or its window hides. BlocProvider dispose — the only
// other flush — never runs on process exit, so Cmd+Q inside a debounce
// window silently lost the last edits and the just-received response.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';

/// Hooks [AppLifecycleListener.onExitRequested] (a cancellable exit request —
/// Cmd+Q / window close on desktop routes through the engine's termination
/// handler) to flush the debounced tab/collections saves before the process
/// dies. [AppLifecycleListener.onHide] flushes too, fire-and-forget, covering
/// exit paths that never emit a cancellable request.
///
/// Widget-layer coordinator (same shape as `BranchSyncListener`): it reaches
/// both blocs via `context.read`, keeping the blocs free of lifecycle wiring.
class ExitFlushGuard extends StatefulWidget {
  const ExitFlushGuard({required this.child, super.key});
  final Widget child;

  @override
  State<ExitFlushGuard> createState() => _ExitFlushGuardState();
}

class _ExitFlushGuardState extends State<ExitFlushGuard> {
  AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onExitRequested: () async {
        await _flushAll();
        return AppExitResponse.exit;
      },
      onHide: () => unawaited(_flushAll()),
    );
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  Future<void> _flushAll() => Future.wait([
    context.read<TabsBloc>().flushPendingSaves(),
    context.read<CollectionsBloc>().flushPendingSaves(),
    // The workspace MIRROR too, not just Hive: its own 1 s debounce means a
    // quit right after a tree edit would persist the edit to Hive but not
    // to the git workspace on disk — and the boot import merges DISK-wins,
    // so the un-mirrored edit would be deleted at next launch.
    context.read<WorkspaceSyncService>().flushPending(),
  ]);

  @override
  Widget build(BuildContext context) => widget.child;
}
