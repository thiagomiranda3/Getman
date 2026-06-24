import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collection_variables_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/export_api_docs_dialog.dart';

/// The trailing more-actions menu on a collection node row
/// (rename / describe / delete / favorite / add-subfolder / export).
class CollectionNodeMenu extends StatelessWidget {
  const CollectionNodeMenu({required this.node, super.key});
  final CollectionNodeEntity node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return PopupMenuButton<String>(
      key: ValueKey('node_menu_${node.id}'),
      icon: Icon(
        Icons.more_vert,
        size: layout.iconSize,
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
            _showRenameDialog(context);
          case 'describe':
            _showDescriptionDialog(context);
          case 'variables':
            unawaited(CollectionVariablesDialog.show(context, node));
          case 'delete':
            unawaited(
              ConfirmDialog.show(
                context,
                title: node.isFolder ? 'Delete folder?' : 'Delete request?',
                message: node.isFolder
                    ? 'Deletes "${node.name}" and everything inside it. '
                          'This cannot be undone.'
                    : 'Deletes "${node.name}". This cannot be undone.',
                onConfirm: () {
                  context.read<CollectionsBloc>().add(DeleteNode(node.id));
                  showAppSnackBar(context, 'Deleted "${node.name}"');
                },
              ),
            );
          case 'favorite':
            context.read<CollectionsBloc>().add(ToggleFavorite(node.id));
            showAppSnackBar(
              context,
              node.isFavorite ? 'Removed from favorites' : 'Added to favorites',
            );
          case 'add_subfolder':
            _showAddSubfolderDialog(context);
          case 'export':
            unawaited(_exportNode(context));
          case 'export_docs':
            unawaited(ExportApiDocsDialog.show(context, node));
        }
      },
      itemBuilder: (context) => [
        if (node.isFolder && node.config == null)
          PopupMenuItem(
            value: 'favorite',
            child: Text(
              node.isFavorite ? 'UNFAVORITE' : 'FAVORITE',
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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
          value: 'describe',
          child: Text(
            'EDIT DESCRIPTION',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (node.isFolder)
          PopupMenuItem(
            value: 'variables',
            child: Text(
              'VARIABLES',
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (node.isFolder)
          PopupMenuItem(
            value: 'add_subfolder',
            child: Text(
              'ADD SUBFOLDER',
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        PopupMenuItem(
          value: 'export',
          child: Text(
            'EXPORT TO POSTMAN',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'export_docs',
          child: Text(
            'EXPORT AS API DOCS…',
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

  void _showRenameDialog(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'RENAME',
        initialText: node.name,
        onConfirm: (name) {
          bloc.add(RenameNode(node.id, name));
          showAppSnackBarVia(messenger, 'Renamed to "$name"');
        },
      ),
    );
  }

  void _showDescriptionDialog(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'DESCRIPTION',
        initialText: node.description ?? '',
        hintText: 'Notes for this ${node.isFolder ? 'folder' : 'request'}',
        allowEmpty: true,
        multiline: true,
        onConfirm: (text) {
          bloc.add(UpdateNodeDescription(node.id, text.trim()));
          showAppSnackBarVia(messenger, 'Description updated');
        },
      ),
    );
  }

  void _showAddSubfolderDialog(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'ADD SUBFOLDER',
        confirmLabel: 'ADD',
        onConfirm: (name) {
          bloc.add(AddFolder(name, parentId: node.id));
          showAppSnackBarVia(messenger, 'Folder "$name" created');
        },
      ),
    );
  }

  Future<void> _exportNode(BuildContext context) {
    return saveJsonFileWithFeedback(
      context,
      jsonString: PostmanCollectionMapper.toJson(node),
      fileName: '${slugFilename(node.name)}.postman_collection.json',
      dialogTitle: 'EXPORT COLLECTION',
    );
  }
}
