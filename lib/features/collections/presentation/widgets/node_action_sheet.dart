import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';

/// Touch-first replacement for the three-dot context menu. Opened via long-
/// press on a collection node when `BuildContext.isPhone` is true. Exposes
/// the same actions (favorite, rename, add subfolder, export, delete) plus a
/// Move-to picker that makes up for the lack of drag-drop on narrow screens.
class NodeActionSheet {
  static Future<void> show(BuildContext context, CollectionNodeEntity node) {
    final collectionsBloc = context.read<CollectionsBloc>();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.appShape.sheetRadius),
        ),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: collectionsBloc,
        child: sheetContext.appDecoration.frost(
          sheetContext,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(sheetContext.appShape.sheetRadius),
          ),
          child: ColoredBox(
            color: Theme.of(sheetContext).scaffoldBackgroundColor,
            child: _SheetBody(node: node),
          ),
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.node});
  final CollectionNodeEntity node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.inputPadding,
              vertical: layout.headerPaddingVertical,
            ),
            child: Row(
              children: [
                Icon(
                  node.isFolder
                      ? (node.isFavorite ? Icons.star : Icons.folder)
                      : Icons.link,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: layout.headerFontSize,
                      fontWeight: context.appTypography.displayWeight,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            color: theme.dividerColor,
            height: 0,
            thickness: layout.borderThick,
          ),
          if (node.isFolder && node.config == null)
            _Action(
              icon: node.isFavorite ? Icons.star_border : Icons.star,
              label: node.isFavorite ? 'UNFAVORITE' : 'FAVORITE',
              onTap: () {
                context.read<CollectionsBloc>().add(ToggleFavorite(node.id));
                Navigator.of(context).pop();
              },
            ),
          _Action(
            icon: Icons.edit,
            label: 'RENAME',
            onTap: () {
              final bloc = context.read<CollectionsBloc>();
              Navigator.of(context).pop();
              unawaited(
                NamePromptDialog.show(
                  context,
                  title: 'RENAME',
                  initialText: node.name,
                  onConfirm: (name) => bloc.add(RenameNode(node.id, name)),
                ),
              );
            },
          ),
          _Action(
            icon: Icons.description_outlined,
            label: 'EDIT DESCRIPTION',
            onTap: () {
              final bloc = context.read<CollectionsBloc>();
              Navigator.of(context).pop();
              unawaited(
                NamePromptDialog.show(
                  context,
                  title: 'DESCRIPTION',
                  initialText: node.description ?? '',
                  hintText:
                      'Notes for this ${node.isFolder ? 'folder' : 'request'}',
                  allowEmpty: true,
                  multiline: true,
                  onConfirm: (text) =>
                      bloc.add(UpdateNodeDescription(node.id, text.trim())),
                ),
              );
            },
          ),
          if (node.isFolder)
            _Action(
              icon: Icons.create_new_folder,
              label: 'ADD SUBFOLDER',
              onTap: () {
                final bloc = context.read<CollectionsBloc>();
                Navigator.of(context).pop();
                unawaited(
                  NamePromptDialog.show(
                    context,
                    title: 'ADD SUBFOLDER',
                    confirmLabel: 'ADD',
                    onConfirm: (name) =>
                        bloc.add(AddFolder(name, parentId: node.id)),
                  ),
                );
              },
            ),
          _Action(
            icon: Icons.drive_file_move_outline,
            label: 'MOVE TO...',
            onTap: () {
              final bloc = context.read<CollectionsBloc>();
              Navigator.of(context).pop();
              unawaited(_MoveToSheet.show(context, node, bloc));
            },
          ),
          _Action(
            icon: Icons.file_download,
            label: 'EXPORT TO POSTMAN',
            onTap: () {
              Navigator.of(context).pop();
              unawaited(_exportNode(context, node));
            },
          ),
          _Action(
            icon: Icons.delete_outline,
            label: 'DELETE',
            isDestructive: true,
            onTap: () {
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
                    Navigator.of(context).pop(); // close the action sheet
                  },
                ),
              );
            },
          ),
          SizedBox(height: layout.tabSpacing),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final color = isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: context.touchTargetMin),
        padding: EdgeInsets.symmetric(
          horizontal: layout.inputPadding,
          vertical: layout.inputPadding,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: layout.iconSize),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.displayWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveToSheet {
  static Future<void> show(
    BuildContext context,
    CollectionNodeEntity source,
    CollectionsBloc bloc,
  ) {
    final folders = _flattenFolders(bloc.state.collections, exclude: source.id);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.appShape.sheetRadius),
        ),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final layout = sheetContext.appLayout;
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: sheetContext.appDecoration.frost(
            sheetContext,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(sheetContext.appShape.sheetRadius),
            ),
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(layout.inputPadding),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'MOVE "${source.name}" TO...',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: layout.fontSizeSubtitle,
                                fontWeight: context.appTypography.displayWeight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      color: theme.dividerColor,
                      height: 0,
                      thickness: layout.borderThick,
                    ),
                    Expanded(
                      // Lazy build: a deep collection can flatten to many
                      // folders; only the visible window needs constructing.
                      child: ListView.builder(
                        itemCount: folders.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _Action(
                              icon: Icons.home_outlined,
                              label: 'ROOT (TOP LEVEL)',
                              onTap: () {
                                bloc.add(MoveNode(source.id, null));
                                Navigator.of(sheetContext).pop();
                              },
                            );
                          }
                          final f = folders[index - 1];
                          return _Action(
                            icon: Icons.folder,
                            label: '${'  ' * f.depth}${f.node.name}',
                            onTap: () {
                              bloc.add(MoveNode(source.id, f.node.id));
                              Navigator.of(sheetContext).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static List<_FolderEntry> _flattenFolders(
    List<CollectionNodeEntity> nodes, {
    required String exclude,
    int depth = 0,
  }) {
    final result = <_FolderEntry>[];
    for (final node in nodes) {
      if (!node.isFolder) continue;
      if (node.id == exclude) continue;
      result
        ..add(_FolderEntry(node: node, depth: depth))
        ..addAll(
          _flattenFolders(node.children, exclude: exclude, depth: depth + 1),
        );
    }
    return result;
  }
}

class _FolderEntry {
  const _FolderEntry({required this.node, required this.depth});
  final CollectionNodeEntity node;
  final int depth;
}

Future<void> _exportNode(BuildContext context, CollectionNodeEntity node) {
  return saveJsonFileWithFeedback(
    context,
    jsonString: PostmanCollectionMapper.toJson(node),
    fileName: '${slugFilename(node.name)}.postman_collection.json',
    dialogTitle: 'EXPORT COLLECTION',
  );
}
