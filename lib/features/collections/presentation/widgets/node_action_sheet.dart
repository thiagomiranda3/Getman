import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';

/// Touch-first replacement for the three-dot context menu. Opened via long-
/// press on a collection node when [BuildContext.isPhone] is true. Exposes
/// the same actions (favorite, rename, add subfolder, export, delete) plus a
/// Move-to picker that makes up for the lack of drag-drop on narrow screens.
class NodeActionSheet {
  static Future<void> show(BuildContext context, CollectionNodeEntity node) {
    final collectionsBloc = context.read<CollectionsBloc>();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: collectionsBloc,
        child: _SheetBody(node: node),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  final CollectionNodeEntity node;
  const _SheetBody({required this.node});

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
            padding: EdgeInsets.symmetric(horizontal: layout.inputPadding, vertical: layout.headerPaddingVertical),
            child: Row(
              children: [
                Icon(
                  node.isFolder ? (node.isFavorite ? Icons.star : Icons.folder) : Icons.link,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    node.name.toUpperCase(),
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
          Divider(color: theme.dividerColor, height: 0, thickness: layout.borderThick),
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
              NamePromptDialog.show(
                context,
                title: 'RENAME',
                initialText: node.name,
                onConfirm: (name) => bloc.add(RenameNode(node.id, name)),
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
                NamePromptDialog.show(
                  context,
                  title: 'ADD SUBFOLDER',
                  confirmLabel: 'ADD',
                  onConfirm: (name) => bloc.add(AddFolder(name, parentId: node.id)),
                );
              },
            ),
          _Action(
            icon: Icons.drive_file_move_outline,
            label: 'MOVE TO...',
            onTap: () {
              final bloc = context.read<CollectionsBloc>();
              Navigator.of(context).pop();
              _MoveToSheet.show(context, node, bloc);
            },
          ),
          _Action(
            icon: Icons.file_download,
            label: 'EXPORT TO POSTMAN',
            onTap: () {
              Navigator.of(context).pop();
              _exportNode(context, node);
            },
          ),
          _Action(
            icon: Icons.delete_outline,
            label: 'DELETE',
            isDestructive: true,
            onTap: () {
              context.read<CollectionsBloc>().add(DeleteNode(node.id));
              Navigator.of(context).pop();
            },
          ),
          SizedBox(height: layout.tabSpacing),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final color = isDestructive ? theme.colorScheme.error : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: context.touchTargetMin),
        padding: EdgeInsets.symmetric(horizontal: layout.inputPadding, vertical: layout.inputPadding),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final layout = sheetContext.appLayout;
        return FractionallySizedBox(
          heightFactor: 0.6,
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
                          'MOVE "${source.name.toUpperCase()}" TO...',
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
                Divider(color: theme.dividerColor, height: 0, thickness: layout.borderThick),
                Expanded(
                  child: ListView(
                    children: [
                      _Action(
                        icon: Icons.home_outlined,
                        label: 'ROOT (TOP LEVEL)',
                        onTap: () {
                          bloc.add(MoveNode(source.id, null));
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                      for (final f in folders)
                        _Action(
                          icon: Icons.folder,
                          label: '${'  ' * f.depth}${f.node.name.toUpperCase()}',
                          onTap: () {
                            bloc.add(MoveNode(source.id, f.node.id));
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ],
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
      result.add(_FolderEntry(node: node, depth: depth));
      result.addAll(_flattenFolders(node.children, exclude: exclude, depth: depth + 1));
    }
    return result;
  }
}

class _FolderEntry {
  final CollectionNodeEntity node;
  final int depth;
  const _FolderEntry({required this.node, required this.depth});
}

Future<void> _exportNode(BuildContext context, CollectionNodeEntity node) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final jsonString = PostmanCollectionMapper.toJson(node);
    final fileName = '${_slugFilename(node.name)}.postman_collection.json';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'EXPORT COLLECTION',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(jsonString),
    );
    if (path == null) return;
    if (!kIsWeb) {
      await File(path).writeAsString(jsonString);
    }
    messenger?.showSnackBar(SnackBar(content: Text('Exported to $path')));
  } catch (e) {
    debugPrint('Export failed: $e');
    messenger?.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

String _slugFilename(String name) {
  final trimmed = name.trim().toLowerCase();
  final slug = trimmed.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'untitled' : slug;
}
