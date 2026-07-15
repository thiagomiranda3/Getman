import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/open_url.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_state.dart';

/// GitHub pull-request panel reached from the branch chip. Renders one of three
/// views off `availability`: install prompt / auth prompt / the open-PR list
/// with create + refresh. Rides on the user's `gh auth` — stores no credential.
class PullRequestsDialog {
  const PullRequestsDialog._();

  static Future<void> show(BuildContext context, {required String root}) {
    // Capture both blocs before the dialog's own subtree: the list lives under
    // PullRequestsBloc; a create that pushed nudges the branch chip via
    // GitSyncBloc (widget-layer coordination — no bloc→bloc coupling).
    final prs = context.read<PullRequestsBloc>();
    final git = context.read<GitSyncBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<PullRequestsBloc>.value(value: prs),
          BlocProvider<GitSyncBloc>.value(value: git),
        ],
        child: PullRequestsBody(root: root),
      ),
    );
  }
}

/// The dialog content (public for widget testing). Stateful only to dispatch
/// the one-shot [LoadPullRequests] on open, mirroring `ReviewChangesButton`.
class PullRequestsBody extends StatefulWidget {
  const PullRequestsBody({required this.root, super.key});
  final String root;

  @override
  State<PullRequestsBody> createState() => _PullRequestsBodyState();
}

class _PullRequestsBodyState extends State<PullRequestsBody> {
  @override
  void initState() {
    super.initState();
    context.read<PullRequestsBloc>().add(LoadPullRequests(widget.root));
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return BlocConsumer<PullRequestsBloc, PullRequestsState>(
      listenWhen: (p, c) =>
          (c.status == PrStatus.error &&
              p.errorMessage != c.errorMessage &&
              c.errorMessage != null) ||
          // Consume lastCreated exactly once — it is sticky, so gate on change.
          (p.lastCreated != c.lastCreated && c.lastCreated != null),
      listener: (context, state) {
        if (state.status == PrStatus.error) {
          _showError(context, state.errorMessage!);
        } else {
          _onCreated(context, state.lastCreated!);
        }
      },
      builder: (context, state) {
        return ResponsiveDialogScaffold(
          title: const Text('PULL REQUESTS'),
          content: SizedBox(
            width: layout.dialogWidth,
            height: layout.settingsDialogHeight,
            child: _view(context, state),
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

  Widget _view(BuildContext context, PullRequestsState state) {
    switch (state.availability) {
      case GhAvailability.notInstalled:
        return const _InstallPrompt();
      case GhAvailability.notAuthenticated:
        return _AuthPrompt(root: widget.root);
      case GhAvailability.available:
        return _AvailableView(root: widget.root, state: state);
    }
  }

  void _onCreated(BuildContext context, PullRequestRef ref) {
    showAppSnackBar(context, 'PR #${ref.number} opened.');
    // The push changed ahead/behind — refresh the branch chip.
    context.read<GitSyncBloc>().add(LoadBranchStatus(widget.root));
  }

  void _showError(BuildContext context, String message) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('pr_error_dialog'),
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

class _InstallPrompt extends StatelessWidget {
  const _InstallPrompt();

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'GitHub CLI (gh) not found',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: layout.tabSpacing),
        const Text(
          'Getman opens pull requests through the gh command-line tool.',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: layout.pagePadding),
        FilledButton(
          key: const ValueKey('pr_install_gh'),
          onPressed: () => unawaited(openUrl('https://cli.github.com')),
          child: const Text('INSTALL GH'),
        ),
      ],
    );
  }
}

class _AuthPrompt extends StatelessWidget {
  const _AuthPrompt({required this.root});
  final String root;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Sign in with the GitHub CLI',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: layout.tabSpacing),
        const Text(
          'Run this in a terminal, then refresh:',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: layout.tabSpacing),
        SelectableText(
          'gh auth login',
          style: TextStyle(
            fontFamily: context.appTypography.codeFontFamily,
          ),
        ),
        SizedBox(height: layout.pagePadding),
        OutlinedButton(
          onPressed: () =>
              context.read<PullRequestsBloc>().add(LoadPullRequests(root)),
          child: const Text('REFRESH'),
        ),
      ],
    );
  }
}

class _AvailableView extends StatelessWidget {
  const _AvailableView({required this.root, required this.state});
  final String root;
  final PullRequestsState state;

  // `initial` is the pre-first-load state; treat it like busy so the fresh
  // bloc's first paint shows the spinner, not a one-frame "no PRs" flash.
  bool get _busy => state.isBusy || state.status == PrStatus.initial;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final busy = _busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            OutlinedButton(
              key: const ValueKey('pr_refresh'),
              onPressed: busy
                  ? null
                  : () => context.read<PullRequestsBloc>().add(
                      LoadPullRequests(root),
                    ),
              child: const Text('REFRESH'),
            ),
            const Spacer(),
            FilledButton(
              key: const ValueKey('pr_create'),
              onPressed: busy ? null : () => _openCreateForm(context),
              child: const Text('CREATE PULL REQUEST…'),
            ),
          ],
        ),
        SizedBox(height: layout.tabSpacing),
        Expanded(child: _list(context)),
      ],
    );
  }

  Widget _list(BuildContext context) {
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.prs.isEmpty) {
      return const Center(child: Text('No open pull requests.'));
    }
    return ListView.builder(
      itemCount: state.prs.length,
      itemBuilder: (context, i) => _PrRow(pr: state.prs[i]),
    );
  }

  void _openCreateForm(BuildContext context) {
    // Prefer the repo's real default branch (gh repo view); fall back to a
    // main/master/first-branch heuristic only when it couldn't be resolved.
    final base = state.defaultBase ?? _heuristicBase(context);
    unawaited(_CreatePrForm.show(context, root: root, initialBase: base));
  }

  String _heuristicBase(BuildContext context) {
    final branches = context.read<GitSyncBloc>().state.branch.branches;
    if (branches.contains('main')) return 'main';
    if (branches.contains('master')) return 'master';
    return branches.isNotEmpty ? branches.first : '';
  }
}

class _PrRow extends StatelessWidget {
  const _PrRow({required this.pr});
  final PullRequestEntity pr;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ListTile(
      key: ValueKey('pr_row_${pr.number}'),
      dense: true,
      leading: _ChecksGlyph(checks: pr.checks),
      title: Text(pr.title, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Text('#${pr.number}'),
          if (pr.isDraft) ...[
            SizedBox(width: layout.tabSpacing),
            Text(
              'DRAFT',
              style: TextStyle(
                fontWeight: context.appTypography.titleWeight,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(Icons.open_in_new, size: layout.smallIconSize),
      onTap: () => unawaited(_open(context)),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await openUrl(pr.url);
    if (!ok) showAppSnackBarVia(messenger, 'Could not open the PR url.');
  }
}

class _ChecksGlyph extends StatelessWidget {
  const _ChecksGlyph({required this.checks});
  final PrChecks checks;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final size = context.appLayout.iconSize;
    switch (checks) {
      case PrChecks.passing:
        return Icon(
          Icons.check_circle,
          size: size,
          color: palette.statusAccentSuccess,
        );
      case PrChecks.failing:
        return Icon(Icons.cancel, size: size, color: palette.statusAccentError);
      case PrChecks.pending:
        return Icon(
          Icons.schedule,
          size: size,
          color: palette.statusAccentWarning,
        );
      case PrChecks.none:
        return Icon(
          Icons.remove,
          size: size,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    }
  }
}

/// The create form (a second dialog). Base + title + optional body + draft.
class _CreatePrForm extends StatefulWidget {
  const _CreatePrForm({required this.root, required this.initialBase});
  final String root;
  final String initialBase;

  static Future<void> show(
    BuildContext context, {
    required String root,
    required String initialBase,
  }) {
    final bloc = context.read<PullRequestsBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) => BlocProvider<PullRequestsBloc>.value(
        value: bloc,
        child: _CreatePrForm(root: root, initialBase: initialBase),
      ),
    );
  }

  @override
  State<_CreatePrForm> createState() => _CreatePrFormState();
}

class _CreatePrFormState extends State<_CreatePrForm> {
  late final TextEditingController _base = TextEditingController(
    text: widget.initialBase,
  );
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _draft = false;

  @override
  void dispose() {
    _base.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ResponsiveDialogScaffold(
      title: const Text('CREATE PULL REQUEST'),
      content: SizedBox(
        width: layout.dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('pr_form_base'),
              controller: _base,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'BASE BRANCH',
                hintText: 'main',
              ),
            ),
            SizedBox(height: layout.tabSpacing),
            TextField(
              key: const ValueKey('pr_form_title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'PR TITLE'),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: layout.tabSpacing),
            TextField(
              key: const ValueKey('pr_form_body'),
              controller: _body,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'PR body (optional)',
              ),
            ),
            SizedBox(height: layout.tabSpacing),
            SwitchListTile(
              key: const ValueKey('pr_form_draft'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Create as draft'),
              value: _draft,
              onChanged: (v) => setState(() => _draft = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          key: const ValueKey('pr_form_submit'),
          onPressed: _canSubmit ? _submit : null,
          child: const Text('CREATE'),
        ),
      ],
    );
  }

  bool get _canSubmit =>
      _base.text.trim().isNotEmpty && _title.text.trim().isNotEmpty;

  void _submit() {
    context.read<PullRequestsBloc>().add(
      CreatePullRequest(
        widget.root,
        base: _base.text.trim(),
        title: _title.text.trim(),
        body: _body.text,
        draft: _draft,
      ),
    );
    unawaited(Navigator.of(context).maybePop());
  }
}
