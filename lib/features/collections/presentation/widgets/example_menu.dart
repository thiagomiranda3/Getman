// Rename/delete popup menu for a single saved example (desktop + phone).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
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

  void _delete(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      ConfirmDialog.show(
        context,
        title: 'Delete example?',
        message: 'Deletes "$exampleName". This cannot be undone.',
        onConfirm: () {
          bloc.add(DeleteExample(nodeId, exampleId));
          showAppSnackBarVia(messenger, 'Deleted "$exampleName"');
        },
      ),
    );
  }
}
