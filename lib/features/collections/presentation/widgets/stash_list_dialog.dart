import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';

/// Lists `git stash` entries with pop/drop. Without this, a stash Getman
/// creates would be invisible work the user cannot get back to.
class StashListDialog {
  const StashListDialog._();

  static Future<void> show(BuildContext context, {required String root}) {
    final bloc = context.read<GitSyncBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) => BlocProvider<GitSyncBloc>.value(
        value: bloc,
        child: StashListBody(root: root),
      ),
    );
  }
}

/// The dialog content (public for widget testing).
///
/// `StashInfo.index` is positional and shifts on every pop/drop, so the list
/// is re-read from bloc state on every rebuild (via [BlocBuilder]) and the
/// row actions are disabled while an op is in flight. Combined with the bloc
/// dropping any event received while busy, no action can ever run against a
/// stale index captured from an earlier snapshot.
class StashListBody extends StatelessWidget {
  const StashListBody({required this.root, super.key});
  final String root;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return BlocBuilder<GitSyncBloc, GitSyncState>(
      builder: (context, state) {
        final stashes = state.branch.stashes;
        final busy = state.isBusy;
        return ResponsiveDialogScaffold(
          title: const Text('STASHES'),
          content: SizedBox(
            width: layout.dialogWidth,
            height: layout.settingsDialogHeight,
            child: stashes.isEmpty
                ? const Center(child: Text('No stashes.'))
                : ListView.builder(
                    itemCount: stashes.length,
                    itemBuilder: (context, i) {
                      final s = stashes[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          s.message,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              key: ValueKey('stash_pop_${s.index}'),
                              onPressed: busy
                                  ? null
                                  : () => context.read<GitSyncBloc>().add(
                                      PopStash(root, s.index),
                                    ),
                              child: const Text('POP'),
                            ),
                            TextButton(
                              key: ValueKey('stash_drop_${s.index}'),
                              onPressed: busy
                                  ? null
                                  : () => _confirmDrop(context, s.index),
                              child: const Text('DROP'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDrop(BuildContext context, int index) {
    final bloc = context.read<GitSyncBloc>();
    unawaited(
      ConfirmDialog.show(
        context,
        title: 'DROP STASH',
        message: 'This discards the stashed changes for good.',
        confirmLabel: 'DROP',
        onConfirm: () => bloc.add(DropStash(root, index)),
      ),
    );
  }
}
