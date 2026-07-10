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
    if (state.entries.isEmpty) {
      return const Center(child: Text('No changes to review.'));
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
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: context.appLayout.dialogWidth * 0.6,
                child: _NodeList(
                  entries: state.entries,
                  selectedPath: selected.path,
                  root: widget.root,
                  iconFor: _icon,
                ),
              ),
              const VerticalDivider(width: 1),
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
