// Review Changes dialog: stage/unstage files, view a per-file semantic
// diff (SemanticDiffView), commit, and push. Dispatches ReviewBloc for
// stage/commit and GitSyncBloc for push (widget-layer coordination).
//
// Gotchas: a commit that fails for lack of a git identity transitions
// ReviewState to `needsIdentity`, which this dialog catches via
// listenWhen to prompt for name/email, save it to Settings, and retry the
// same commit message. PUSH only *starts* the push (busy/error/ahead-
// count feedback surfaces later on the branch chip, not here) and is
// dropped silently by GitSyncBloc if another op is already in flight —
// checked again at dispatch time so the "Pushing..." snackbar can't lie.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:getman/features/collections/presentation/widgets/semantic_diff_view.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';

/// Opens the Review Changes dialog and dispatches the initial [LoadReview].
class ReviewChangesDialog {
  const ReviewChangesDialog._();

  static Future<void> show(BuildContext context, {required String root}) {
    final reviewBloc = context.read<ReviewBloc>()..add(LoadReview(root));
    // Captured + re-provided (not just read at dispatch time below): the
    // fullscreen route path in showResponsiveDialog pushes onto the root
    // Navigator, so the identity-prompt flow needs SettingsBloc reachable
    // from that subtree the same way ReviewBloc already is. GitSyncBloc is
    // captured the same way so the PUSH button can read `hasRemote` and
    // dispatch — it's provided at the app root (main.dart), reachable here.
    final settingsBloc = context.read<SettingsBloc>();
    final gitSyncBloc = context.read<GitSyncBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (dialogContext) => MultiBlocProvider(
        providers: [
          BlocProvider<ReviewBloc>.value(value: reviewBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<GitSyncBloc>.value(value: gitSyncBloc),
        ],
        child: ReviewChangesBody(root: root),
      ),
    );
  }
}

/// The dialog content (public for widget testing).
class ReviewChangesBody extends StatefulWidget {
  const ReviewChangesBody({required this.root, super.key});
  final String root;

  @override
  State<ReviewChangesBody> createState() => _ReviewChangesBodyState();
}

class _ReviewChangesBodyState extends State<ReviewChangesBody> {
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  IconData _icon(ChangeType t) => switch (t) {
    ChangeType.added => Icons.add,
    ChangeType.deleted => Icons.remove,
    ChangeType.modified => Icons.edit,
  };

  void _commit(BuildContext context) {
    final identity = context.read<SettingsBloc>().state.settings;
    context.read<ReviewBloc>().add(
      Commit(
        widget.root,
        _message.text.trim(),
        authorName: identity.gitUserName,
        authorEmail: identity.gitUserEmail,
      ),
    );
  }

  /// PUSH from the review dialog. When the repo has a remote, pushes right
  /// away; otherwise prompts for a URL first (the bloc adds it as `origin`
  /// before pushing — see `GitSyncBloc._maybeAddRemote`). Either way, this
  /// only *starts* the push: feedback (busy/error/updated ahead-count) surfaces
  /// on the branch chip, not here — closing the dialog hands the user back to
  /// it immediately.
  void _push(BuildContext context) {
    final gitSyncBloc = context.read<GitSyncBloc>();
    if (gitSyncBloc.state.branch.hasRemote) {
      _dispatchPush(context, gitSyncBloc, null);
      return;
    }
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'ADD REMOTE',
        hintText: 'https://github.com/you/repo.git',
        confirmLabel: 'ADD REMOTE',
        onConfirm: (url) {
          final trimmed = url.trim();
          if (trimmed.isEmpty) return;
          _dispatchPush(context, gitSyncBloc, trimmed);
        },
      ),
    );
  }

  /// Dispatches the actual `PushChanges` — checked here, at the point of
  /// dispatch (after any add-remote prompt is confirmed), so it reflects
  /// current bloc state: `GitSyncBloc` silently drops a `PushChanges` while
  /// another op is in flight (e.g. the 5-min auto-fetch), so an unconditional
  /// "Pushing to remote…" would lie to the user.
  void _dispatchPush(
    BuildContext context,
    GitSyncBloc gitSyncBloc,
    String? addRemoteUrl,
  ) {
    if (gitSyncBloc.state.isBusy) {
      showAppSnackBar(context, 'Git is busy — try again in a moment.');
      return;
    }
    gitSyncBloc.add(PushChanges(widget.root, addRemoteUrl: addRemoteUrl));
    showAppSnackBar(context, 'Pushing to remote…');
    unawaited(Navigator.of(context).maybePop());
  }

  /// A commit failed because neither Getman nor the OS git has a configured
  /// commit identity — prompt for name/email, save it, and retry the same
  /// commit message.
  void _promptIdentity(BuildContext context) {
    final settingsBloc = context.read<SettingsBloc>();
    final reviewBloc = context.read<ReviewBloc>();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => _GitIdentityDialog(
          initialName: settingsBloc.state.settings.gitUserName,
          initialEmail: settingsBloc.state.settings.gitUserEmail,
          onSave: (name, email) {
            settingsBloc.add(UpdateGitIdentity(name: name, email: email));
            reviewBloc.add(
              Commit(
                widget.root,
                _message.text.trim(),
                authorName: name,
                authorEmail: email,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return BlocConsumer<ReviewBloc, ReviewState>(
      listenWhen: (p, c) =>
          p.status != ReviewStatus.needsIdentity &&
          c.status == ReviewStatus.needsIdentity,
      listener: (context, state) => _promptIdentity(context),
      builder: (context, state) {
        return ResponsiveDialogScaffold(
          title: Text(
            state.branch == null
                ? 'REVIEW CHANGES'
                : 'REVIEW CHANGES · ${state.branch}',
          ),
          content: SizedBox(
            width: layout.dialogWidth * 1.8,
            height: layout.settingsDialogHeight,
            child: _body(context, state),
          ),
          actions: [
            if (state.repoExists)
              TextButton(
                key: const ValueKey('review_push_button'),
                onPressed: () => _push(context),
                child: const Text('PUSH'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context, ReviewState state) {
    if (!state.gitAvailable) {
      return const Center(child: Text('git was not found on your PATH.'));
    }
    if (!state.repoExists) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This workspace is not a git repository.'),
            SizedBox(height: context.appLayout.inputPadding),
            ElevatedButton(
              onPressed: () =>
                  context.read<ReviewBloc>().add(InitRepo(widget.root)),
              child: const Text('Initialize git here'),
            ),
          ],
        ),
      );
    }

    final showError =
        state.status == ReviewStatus.error && state.errorMessage != null;
    final errorBanner = showError
        ? _ErrorBanner(message: state.errorMessage!)
        : null;

    if (state.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (errorBanner != null) ...[
              errorBanner,
              SizedBox(height: context.appLayout.inputPadding),
            ],
            const Text('No changes to review.'),
          ],
        ),
      );
    }

    final selected = state.entries.firstWhere(
      (e) => e.path == state.selectedPath,
      orElse: () => state.entries.first,
    );
    final canCommit =
        state.stagedCount > 0 &&
        _message.text.trim().isNotEmpty &&
        state.status != ReviewStatus.committing;

    return Column(
      children: [
        if (errorBanner != null) ...[
          errorBanner,
          SizedBox(height: context.appLayout.inputPadding),
        ],
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: context.appLayout.dialogWidth * 0.6,
                child: Column(
                  children: [
                    _SelectAllRow(
                      root: widget.root,
                      total: state.entries.length,
                      staged: state.stagedCount,
                    ),
                    Expanded(
                      child: _NodeList(
                        entries: state.entries,
                        selectedPath: selected.path,
                        root: widget.root,
                        iconFor: _icon,
                      ),
                    ),
                  ],
                ),
              ),
              VerticalDivider(
                width: context.appLayout.borderThick,
                thickness: context.appLayout.borderThin,
              ),
              Expanded(child: SemanticDiffView(diff: selected.diff)),
            ],
          ),
        ),
        SizedBox(height: context.appLayout.inputPadding),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _message,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Commit message…'),
              ),
            ),
            SizedBox(width: context.appLayout.inputPadding),
            ElevatedButton(
              key: const ValueKey('review_commit_button'),
              onPressed: canCommit ? () => _commit(context) : null,
              child: Text(
                state.status == ReviewStatus.committing
                    ? 'COMMITTING…'
                    : 'COMMIT (${state.stagedCount})',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Just-in-time prompt for a Getman-owned commit identity, shown when a
/// commit fails because neither Getman's stored identity nor the OS git
/// config has one. Prefilled from the current Settings value (if any); SAVE
/// hands the trimmed name/email back to the caller, which persists it and
/// retries the commit.
class _GitIdentityDialog extends StatefulWidget {
  const _GitIdentityDialog({
    required this.onSave,
    this.initialName,
    this.initialEmail,
  });
  final String? initialName;
  final String? initialEmail;
  final void Function(String name, String email) onSave;

  @override
  State<_GitIdentityDialog> createState() => _GitIdentityDialogState();
}

class _GitIdentityDialogState extends State<_GitIdentityDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _email = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop();
    widget.onSave(_name.text.trim(), _email.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final canSave =
        _name.text.trim().isNotEmpty && _email.text.trim().isNotEmpty;
    return AlertDialog(
      key: const ValueKey('git_identity_dialog'),
      title: const Text('WHO ARE YOU?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Getman needs a name and email to author commits — this is '
            'stored in Getman only, never written to your git config.',
          ),
          SizedBox(height: layout.inputPadding),
          TextField(
            key: const ValueKey('git_identity_name_field'),
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          SizedBox(height: layout.inputPadding),
          TextField(
            key: const ValueKey('git_identity_email_field'),
            controller: _email,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Your email'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          key: const ValueKey('git_identity_save'),
          onPressed: canSave ? _save : null,
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

/// Inline error banner surfaced above the commit row when a review load or
/// commit attempt fails (e.g. missing git identity on first run).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      key: const ValueKey('review_error_banner'),
      width: double.infinity,
      padding: EdgeInsets.all(layout.inputPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: theme.colorScheme.onError,
          fontWeight: context.appTypography.bodyWeight,
        ),
      ),
    );
  }
}

/// Select-all header over the entry list. Tri-state: checked when every entry
/// is staged, dashed when some are, empty when none — tapping stages all, or
/// clears the selection when everything is already staged.
class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({
    required this.root,
    required this.total,
    required this.staged,
  });
  final String root;
  final int total;
  final int staged;

  @override
  Widget build(BuildContext context) {
    final all = staged == total;
    final none = staged == 0;
    return Row(
      children: [
        Checkbox(
          key: const ValueKey('review_select_all'),
          value: none ? false : (all ? true : null),
          tristate: true,
          onChanged: (_) => context.read<ReviewBloc>().add(
            all ? UnstageAll(root) : StageAll(root),
          ),
        ),
        Expanded(
          child: Text(
            all ? 'DESELECT ALL' : 'SELECT ALL',
            style: TextStyle(
              fontSize: context.appLayout.fontSizeSmall,
              fontWeight: context.appTypography.titleWeight,
            ),
          ),
        ),
        Text(
          '$staged/$total',
          style: TextStyle(fontSize: context.appLayout.fontSizeSmall),
        ),
        SizedBox(width: context.appLayout.inputPadding),
      ],
    );
  }
}

class _NodeList extends StatelessWidget {
  const _NodeList({
    required this.entries,
    required this.selectedPath,
    required this.root,
    required this.iconFor,
  });
  final List<ReviewEntry> entries;
  final String selectedPath;
  final String root;
  final IconData Function(ChangeType) iconFor;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          dense: true,
          selected: e.path == selectedPath,
          leading: Checkbox(
            value: e.staged,
            onChanged: (v) => context.read<ReviewBloc>().add(
              (v ?? false)
                  ? StageNode(root, e.path)
                  : UnstageNode(root, e.path),
            ),
          ),
          title: Text(e.displayName, overflow: TextOverflow.ellipsis),
          // The row is narrow, so the repo-relative path is ellipsized;
          // hovering reveals where the file actually lives on disk.
          subtitle: Tooltip(
            message: '$root/${e.path}',
            waitDuration: const Duration(milliseconds: 400),
            child: Text(e.path, overflow: TextOverflow.ellipsis),
          ),
          trailing: Icon(
            iconFor(e.changeType),
            size: context.appLayout.smallIconSize,
          ),
          onTap: () => context.read<ReviewBloc>().add(SelectEntry(e.path)),
        );
      },
    );
  }
}
