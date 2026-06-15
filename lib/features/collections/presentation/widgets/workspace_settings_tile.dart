import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/utils/workspace/workspace_bookmark.dart';
import 'package:getman/core/utils/workspace/workspace_picker.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// Settings control for the git-friendly workspace folder. Lives in the
/// collections feature (it coordinates CollectionsBloc + the sync service); the
/// settings dialog just embeds it. Desktop/mobile only.
class WorkspaceSettingsTile extends StatelessWidget {
  const WorkspaceSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.workspacePath != n.settings.workspacePath ||
          p.settings.workspaceBookmark != n.settings.workspaceBookmark,
      builder: (context, state) {
        final path = state.settings.workspacePath;
        // macOS: a connected folder with no stored security-scoped bookmark
        // (e.g. connected before this feature) cannot be written after a
        // relaunch under the sandbox until it is reconnected once.
        final needsReconnect =
            WorkspaceBookmarks.supported &&
            path != null &&
            state.settings.workspaceBookmark == null;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.inputPadding,
            vertical: layout.tabSpacing,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, size: layout.iconSize),
                  SizedBox(width: layout.tabSpacing),
                  Text(
                    'WORKSPACE',
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      fontWeight: context.appTypography.titleWeight,
                    ),
                  ),
                ],
              ),
              SizedBox(height: layout.tabSpacing),
              if (kIsWeb)
                Text(
                  'Available in the desktop/mobile app.',
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                )
              else ...[
                Text(
                  path ?? 'Not set — collections live only in-app.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                if (needsReconnect) ...[
                  SizedBox(height: layout.tabSpacing),
                  Text(
                    'Reconnect this folder to restore write access after '
                    'restart.',
                    style: TextStyle(
                      fontSize: layout.fontSizeSmall,
                      fontWeight: context.appTypography.titleWeight,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                SizedBox(height: layout.tabSpacing),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _choose(context),
                      child: const Text('CHOOSE FOLDER'),
                    ),
                    if (path != null)
                      TextButton(
                        onPressed: () => _reload(context, path),
                        child: const Text('RELOAD FROM DISK'),
                      ),
                    if (path != null)
                      TextButton(
                        onPressed: () => context.read<SettingsBloc>().add(
                          const UpdateWorkspacePath(null),
                        ),
                        child: const Text('DISCONNECT'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _choose(BuildContext context) async {
    final picked = await pickWorkspaceDirectory();
    if (picked == null || !context.mounted) return;

    final sync = context.read<WorkspaceSyncService>();
    final collections = context.read<CollectionsBloc>();
    final settings = context.read<SettingsBloc>();
    final messenger = ScaffoldMessenger.of(context);

    List<CollectionNodeEntity> onDisk;
    try {
      onDisk = await sync.read(picked.path);
    } on Object catch (_) {
      onDisk = const [];
    }
    if (!context.mounted) return;

    void connect() {
      settings.add(UpdateWorkspacePath(picked.path, bookmark: picked.bookmark));
      showAppSnackBarVia(messenger, 'Workspace connected');
    }

    if (onDisk.isNotEmpty) {
      unawaited(
        ConfirmDialog.show(
          context,
          title: 'IMPORT WORKSPACE',
          message:
              'This folder has ${onDisk.length} item(s). Import them and '
              'REPLACE your current collections?',
          confirmLabel: 'IMPORT',
          onConfirm: () {
            collections.add(ReplaceCollections(onDisk));
            connect();
          },
        ),
      );
    } else {
      // Empty folder → export the current collections into it.
      sync.scheduleMirror(picked.path, collections.state.collections);
      connect();
    }
  }

  Future<void> _reload(BuildContext context, String path) async {
    final sync = context.read<WorkspaceSyncService>();
    final collections = context.read<CollectionsBloc>();
    List<CollectionNodeEntity> onDisk;
    try {
      onDisk = await sync.read(path);
    } on Object catch (_) {
      onDisk = const [];
    }
    if (!context.mounted) return;
    collections.add(ReplaceCollections(onDisk));
    showAppSnackBar(context, 'Reloaded ${onDisk.length} item(s) from disk');
  }
}
