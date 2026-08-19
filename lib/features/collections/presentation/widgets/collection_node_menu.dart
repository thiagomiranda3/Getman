// More-actions menu for a collection node row: rename, edit description,
// variables (folders), add subfolder (folders), export to Postman, export as
// API docs, favorite/unfavorite, delete (instant + UNDO for requests; confirm
// + UNDO for folders — delete_node_with_undo.dart). Two entry points share
// the same items + actions: the row's trailing "⋮" PopupMenuButton
// (CollectionNodeMenu) and right-click anywhere on the row
// (showCollectionNodeMenuAt). Dispatches CollectionsBloc events;
// delete/favorite show a snackbar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collection_variables_dialog.dart';
import 'package:getman/features/collections/presentation/widgets/delete_node_with_undo.dart';
import 'package:getman/features/collections/presentation/widgets/export_api_docs_dialog.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

/// Shows the node's actions menu at [globalPosition] — the right-click path.
/// Same items and actions as the row's trailing [CollectionNodeMenu] button.
Future<void> showCollectionNodeMenuAt(
  BuildContext context,
  CollectionNodeEntity node,
  Offset globalPosition,
) async {
  final theme = Theme.of(context);
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx + 1,
      globalPosition.dy + 1,
    ),
    color: theme.colorScheme.surface,
    elevation: 0,
    shape: _menuShape(context),
    items: _menuItems(context, node),
  );
  if (selected == null || !context.mounted) return;
  _handleSelection(context, node, selected);
}

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
      shape: _menuShape(context),
      onSelected: (val) => _handleSelection(context, node, val),
      itemBuilder: (context) => _menuItems(context, node),
    );
  }
}

RoundedRectangleBorder _menuShape(BuildContext context) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(context.appShape.panelRadius),
    side: BorderSide(color: theme.dividerColor, width: layout.borderThick),
  );
}

List<PopupMenuEntry<String>> _menuItems(
  BuildContext context,
  CollectionNodeEntity node,
) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  return [
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
  ];
}

void _handleSelection(
  BuildContext context,
  CollectionNodeEntity node,
  String value,
) {
  switch (value) {
    case 'rename':
      _showRenameDialog(context, node);
    case 'describe':
      _showDescriptionDialog(context, node);
    case 'variables':
      unawaited(CollectionVariablesDialog.show(context, node));
    case 'delete':
      deleteNodeWithUndo(context, node);
    case 'favorite':
      context.read<CollectionsBloc>().add(ToggleFavorite(node.id));
      showAppSnackBar(
        context,
        node.isFavorite ? 'Removed from favorites' : 'Added to favorites',
      );
    case 'add_subfolder':
      _showAddSubfolderDialog(context, node);
    case 'export':
      unawaited(_exportNode(context, _liveNode(context, node)));
    case 'export_docs':
      unawaited(ExportApiDocsDialog.show(context, _liveNode(context, node)));
  }
}

/// Rows/menus receive SEARCH-FILTERED node copies (children pruned to the
/// matches) while the filter is active. Exports serialize children, so they
/// must re-fetch the live node by id — exporting the filtered copy silently
/// dropped every non-matching request from the artifact.
CollectionNodeEntity _liveNode(
  BuildContext context,
  CollectionNodeEntity node,
) =>
    CollectionsTreeHelper.findNode(
      context.read<CollectionsBloc>().state.collections,
      node.id,
    ) ??
    node;

void _showRenameDialog(BuildContext context, CollectionNodeEntity node) {
  final bloc = context.read<CollectionsBloc>();
  final tabsBloc = context.read<TabsBloc>();
  final messenger = ScaffoldMessenger.of(context);
  unawaited(
    NamePromptDialog.show(
      context,
      title: 'RENAME',
      initialText: node.name,
      onConfirm: (name) {
        bloc.add(RenameNode(node.id, name));
        renameOpenTabsForNode(tabsBloc, node.id, name);
        showAppSnackBarVia(messenger, 'Renamed to "$name"');
      },
    ),
  );
}

/// Open tabs SNAPSHOT their linked request's name (`tab.collectionName`
/// feeds `displayTitle`, persisted with the tab) — nothing else refreshes it
/// on a tree rename, so the strip/tooltip/open-tabs dropdown showed the old
/// name forever (it even survived restarts). Carry the rename to every
/// linked tab, across all panels.
void renameOpenTabsForNode(TabsBloc tabsBloc, String nodeId, String name) {
  for (final panel in tabsBloc.state.panels) {
    for (final tab in panel.tabs) {
      if (tab.collectionNodeId == nodeId) {
        tabsBloc.add(UpdateTab(tab.copyWith(collectionName: name)));
      }
    }
  }
}

void _showDescriptionDialog(BuildContext context, CollectionNodeEntity node) {
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

void _showAddSubfolderDialog(BuildContext context, CollectionNodeEntity node) {
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

Future<void> _exportNode(BuildContext context, CollectionNodeEntity node) {
  return saveJsonFileWithFeedback(
    context,
    jsonString: PostmanCollectionMapper.toJson(node),
    fileName: '${slugFilename(node.name)}.postman_collection.json',
    dialogTitle: 'EXPORT COLLECTION',
  );
}
