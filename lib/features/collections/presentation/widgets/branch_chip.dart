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
import 'package:getman/features/collections/presentation/widgets/conflict_resolution_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/pull_requests_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/stash_list_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// How often the chip auto-fetches remote-tracking refs in the background, so
/// ahead/behind counts stay fresh without the user remembering to pull.
/// `@visibleForTesting` so a test can assert the interval without waiting for
/// it to elapse for real.
@visibleForTesting
const Duration kAutoFetchInterval = Duration(minutes: 5);

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
  Timer? _fetchTimer;

  // Tracked locally (not derived from `previous` inside the listener, which
  // BlocConsumer doesn't expose) so the resolver opens exactly once per bump.
  // Seeded from `state.conflictToken` on the first BlocConsumer build (not
  // read from GitSyncBloc directly in initState — the workspace may not have
  // a git repo yet, or GitSyncBloc may not even be provided above this chip
  // in a screen that never renders it) so a BranchChip remount after an
  // earlier, already-resolved conflict doesn't replay a stale open.
  int? _lastConflictToken;

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
      if (root != null && root.isNotEmpty) {
        _refresh(root);
        _fetchSilently(root);
      }
    });
    // Keeps ahead/behind counts fresh without the user remembering to pull.
    // Silent: a routine offline tick must never surface a GIT ERROR dialog.
    _fetchTimer = Timer.periodic(kAutoFetchInterval, (_) {
      if (!mounted) return;
      final root = context.read<SettingsBloc>().state.settings.workspacePath;
      if (root != null && root.isNotEmpty) _fetchSilently(root);
    });
  }

  @override
  void dispose() {
    unawaited(_mirrorSub?.cancel());
    _fetchTimer?.cancel();
    super.dispose();
  }

  void _refresh(String root) {
    if (!mounted) return;
    context.read<GitSyncBloc>().add(LoadBranchStatus(root));
  }

  void _fetchSilently(String root) {
    if (!mounted) return;
    context.read<GitSyncBloc>().add(FetchRemote(root, silent: true));
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
              (p.errorMessage != n.errorMessage && n.errorMessage != null) ||
              p.conflictToken != n.conflictToken,
          listener: (context, state) {
            // A pull halted on conflicts — open the resolver. Checked first
            // and separately from the error path below: a conflicted pull is
            // NOT an error state (see GitSyncBloc._onPull), so this is the
            // only signal for it. `_lastConflictToken` is always seeded by
            // the builder below before the first stream event can arrive, so
            // it is never null here.
            if (state.conflictToken != _lastConflictToken) {
              _lastConflictToken = state.conflictToken;
              unawaited(ConflictResolutionDialog.show(context, root: root));
              return;
            }
            final message = state.errorMessage;
            if (message == null) return;
            if (message.contains('uncommitted changes')) {
              _promptDirty(context, root);
            } else {
              _showError(context, message);
            }
          },
          builder: (context, state) {
            // Seed on the first build from `bloc.state` (not a separate
            // `.read()` — this callback already has it) so a later real bump
            // is the only thing that can ever pop the dialog.
            _lastConflictToken ??= state.conflictToken;
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
        PopupMenuItem<String>(
          key: const ValueKey('branch_menu_fetch'),
          value: 'fetch',
          enabled: branch.hasRemote,
          child: Text(branch.hasRemote ? 'FETCH' : 'FETCH — NO REMOTE'),
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
      case 'fetch':
        bloc.add(FetchRemote(root));
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
