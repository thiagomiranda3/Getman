import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';

/// Mirrors collection changes to the on-disk workspace when one is configured.
/// Reads the workspace path from [SettingsBloc] and delegates to
/// [WorkspaceSyncService] — keeping CollectionsBloc unaware of the filesystem
/// (the coordinating widget holds all three, per the bloc-coupling rule).
class WorkspaceSyncListener extends StatelessWidget {
  const WorkspaceSyncListener({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<CollectionsBloc, CollectionsState>(
      listenWhen: (prev, next) => prev.collections != next.collections,
      listener: (context, state) {
        final path = context.read<SettingsBloc>().state.settings.workspacePath;
        if (path != null && path.isNotEmpty) {
          context.read<WorkspaceSyncService>().scheduleMirror(
            path,
            state.collections,
          );
        }
      },
      child: child,
    );
  }
}
