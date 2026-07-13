import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:getman/features/collections/presentation/widgets/semantic_diff_view.dart';

/// Opens the Review Changes dialog and dispatches the initial [LoadReview].
class ReviewChangesDialog {
  const ReviewChangesDialog._();

  static Future<void> show(BuildContext context, {required String root}) {
    final reviewBloc = context.read<ReviewBloc>()..add(LoadReview(root));
    return showResponsiveDialog<void>(
      context,
      builder: (dialogContext) => BlocProvider<ReviewBloc>.value(
        value: reviewBloc,
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

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return BlocBuilder<ReviewBloc, ReviewState>(
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
              onPressed: canCommit
                  ? () => context.read<ReviewBloc>().add(
                      Commit(widget.root, _message.text.trim()),
                    )
                  : null,
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
          subtitle: Text(e.path, overflow: TextOverflow.ellipsis),
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
