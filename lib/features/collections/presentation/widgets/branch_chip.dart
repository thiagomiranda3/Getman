import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/pull_requests_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/stash_list_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// Collections-header chip: current branch + ahead/behind, opening the branch
/// and sync menu. Hidden on web, without a workspace, or when the workspace is
/// not a git repo (the Review dialog owns `git init`).
///
/// Stateful only to load the initial branch status: dispatch
/// [LoadBranchStatus] in a post-frame callback and refresh it whenever the
/// Hive → disk mirror lands (mirroring `ReviewChangesButton`).
class BranchChip extends StatefulWidget {
  const BranchChip({super.key});

  @override
  State<BranchChip> createState() => _BranchChipState();
}

class _BranchChipState extends State<BranchChip> {
  StreamSubscription<String>? _mirrorSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    // Git state must be re-read after the debounced Hive → disk write lands,
    // otherwise the ahead/behind counts lag the working tree.
    _mirrorSub = context.read<WorkspaceSyncService>().mirrored.listen(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final root = context.read<SettingsBloc>().state.settings.workspacePath;
      if (root != null && root.isNotEmpty) _refresh(root);
    });
  }

  @override
  void dispose() {
    unawaited(_mirrorSub?.cancel());
    super.dispose();
  }

  void _refresh(String root) {
    if (!mounted) return;
    context.read<GitSyncBloc>().add(LoadBranchStatus(root));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) => p.settings.workspacePath != n.settings.workspacePath,
      builder: (context, settingsState) {
        final root = settingsState.settings.workspacePath;
        if (root == null || root.isEmpty) return const SizedBox.shrink();

        return BlocConsumer<GitSyncBloc, GitSyncState>(
          listenWhen: (p, n) =>
              p.errorMessage != n.errorMessage && n.errorMessage != null,
          listener: (context, state) {
            final message = state.errorMessage;
            if (message == null) return;
            if (message.contains('uncommitted changes')) {
              _promptDirty(context, root);
            } else {
              _showError(context, message);
            }
          },
          builder: (context, state) {
            final branch = state.branch;
            if (!branch.isRepo || branch.current == null) {
              return const SizedBox.shrink();
            }
            return _chip(context, root, state);
          },
        );
      },
    );
  }

  Widget _chip(BuildContext context, String root, GitSyncState state) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    final branch = state.branch;

    return PopupMenuButton<String>(
      key: const ValueKey('branch_chip'),
      tooltip: 'Branch & sync',
      enabled: !state.isBusy,
      onSelected: (value) => _onSelected(context, root, value),
      itemBuilder: (context) => [
        for (final b in branch.branches)
          PopupMenuItem<String>(
            value: 'switch:$b',
            child: Row(
              children: [
                Icon(
                  b == branch.current ? Icons.check : null,
                  size: layout.smallIconSize,
                ),
                SizedBox(width: layout.tabSpacing),
                Text(b),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'new',
          child: Text('NEW BRANCH…'),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('branch_menu_pull'),
          value: 'pull',
          enabled: branch.hasRemote,
          child: Text(
            branch.hasRemote ? 'PULL (REBASE)' : 'PULL — NO REMOTE',
          ),
        ),
        PopupMenuItem<String>(
          key: const ValueKey('branch_menu_push'),
          value: 'push',
          enabled: branch.hasRemote,
          child: Text(branch.hasRemote ? 'PUSH' : 'PUSH — NO REMOTE'),
        ),
        PopupMenuItem<String>(
          value: 'stashes',
          child: Text('STASHES (${branch.stashCount})'),
        ),
        const PopupMenuItem<String>(
          value: 'prs',
          child: Text('PULL REQUESTS…'),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.tabSpacing),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_split, size: layout.smallIconSize),
            SizedBox(width: layout.tabSpacing),
            // Cap the name so a pathologically long branch cannot grow the
            // chip past the panel and squeeze the (Expanded) header search
            // field to zero — the chip is a non-flex child measured with
            // unbounded main-axis width, so the ellipsis needs a bound to
            // engage.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.sideMenuWidth),
              child: Text(
                branch.current!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  fontWeight: context.appTypography.titleWeight,
                ),
              ),
            ),
            if (branch.ahead > 0)
              Text(
                ' ↑${branch.ahead}',
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (branch.behind > 0)
              Text(
                ' ↓${branch.behind}',
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onSelected(BuildContext context, String root, String value) {
    final bloc = context.read<GitSyncBloc>();
    if (value.startsWith('switch:')) {
      bloc.add(SwitchBranch(root, value.substring('switch:'.length)));
      return;
    }
    switch (value) {
      case 'new':
        unawaited(
          NamePromptDialog.show(
            context,
            title: 'NEW BRANCH',
            hintText: 'feat/my-change',
            confirmLabel: 'CREATE',
            onConfirm: (name) => bloc.add(CreateBranch(root, name)),
          ),
        );
      case 'pull':
        bloc.add(PullChanges(root));
      case 'push':
        bloc.add(PushChanges(root));
      case 'stashes':
        unawaited(StashListDialog.show(context, root: root));
      case 'prs':
        unawaited(PullRequestsDialog.show(context, root: root));
    }
  }

  /// A switch was refused because the tree is dirty: offer the two ways out.
  void _promptDirty(BuildContext context, String root) {
    final bloc = context.read<GitSyncBloc>();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('UNCOMMITTED CHANGES'),
          content: const Text(
            'Commit or stash your changes before switching branches.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(ReviewChangesDialog.show(context, root: root));
              },
              child: const Text('REVIEW CHANGES…'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                bloc.add(StashChanges(root, 'Getman WIP'));
              },
              child: const Text('STASH CHANGES'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCEL'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('branch_error_dialog'),
          title: const Text('GIT ERROR'),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      ),
    );
  }
}
