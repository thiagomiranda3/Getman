// Rename/delete popup menu for a single saved example (desktop + phone). Delete is instant with a 5s UNDO snackbar (A1) — no confirm.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';

/// Rename/delete menu for a single saved example (works on desktop + phone).
class ExampleMenu extends StatelessWidget {
  const ExampleMenu({
    required this.nodeId,
    required this.exampleId,
    required this.exampleName,
    super.key,
  });
  final String nodeId;
  final String exampleId;
  final String exampleName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: layout.smallIconSize,
        color: theme.colorScheme.onSurface,
      ),
      color: theme.colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        side: BorderSide(color: theme.dividerColor, width: layout.borderThick),
      ),
      onSelected: (val) {
        switch (val) {
          case 'rename':
            _rename(context);
          case 'delete':
            _delete(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          child: Text(
            'RENAME',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'DELETE',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  void _rename(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'RENAME EXAMPLE',
        initialText: exampleName,
        onConfirm: (name) {
          bloc.add(RenameExample(nodeId, exampleId, name));
          showAppSnackBarVia(messenger, 'Renamed to "$name"');
        },
      ),
    );
  }

  /// A1: single-item delete is INSTANT — no ConfirmDialog — with a 5s UNDO
  /// snackbar. The example entity + its index are captured from live state
  /// BEFORE dispatch so RestoreExample can put it back in place. Only the
  /// latest snackbar is undoable (messenger replaces).
  void _delete(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final node = CollectionsTreeHelper.findNode(
      bloc.state.collections,
      nodeId,
    );
    final index = node?.examples.indexWhere((e) => e.id == exampleId) ?? -1;
    if (node == null || index == -1) return;
    final example = node.examples[index];

    bloc.add(DeleteExample(nodeId, exampleId));
    showAppSnackBarVia(
      messenger,
      'Deleted "$exampleName"',
      actionLabel: 'UNDO',
      duration: const Duration(seconds: 5),
      onAction: () => bloc.add(
        RestoreExample(nodeId: nodeId, example: example, exampleIndex: index),
      ),
    );
  }
}
