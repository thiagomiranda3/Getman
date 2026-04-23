import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_fancy_tree_view/flutter_fancy_tree_view.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

class CollectionsList extends StatefulWidget {
  const CollectionsList({super.key});

  @override
  State<CollectionsList> createState() => _CollectionsListState();
}

class _CollectionsListState extends State<CollectionsList> {
  late final TreeController<CollectionNodeEntity> _treeController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _treeController = TreeController<CollectionNodeEntity>(
      roots: const [],
      childrenProvider: (node) => node.children,
    );
    _rebuildTree();
    _searchController.addListener(_rebuildTree);
  }

  @override
  void dispose() {
    _searchController.removeListener(_rebuildTree);
    _treeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Recompute the tree roots from the current collections state + search
  /// query, and expand everything while searching. Called outside of `build`
  /// to avoid mutating the controller during paint.
  void _rebuildTree() {
    final collections = context.read<CollectionsBloc>().state.collections;
    final query = _searchController.text;
    _treeController.roots = _filterNodes(collections, query);
    if (query.isNotEmpty) {
      _treeController.expandAll();
    }
  }

  List<CollectionNodeEntity> _filterNodes(List<CollectionNodeEntity> nodes, String query) {
    if (query.isEmpty) return nodes;
    final lowerQuery = query.toLowerCase();
    final result = <CollectionNodeEntity>[];
    for (var node in nodes) {
      final matchesSelf = node.name.toLowerCase().contains(lowerQuery) || (node.config?.url.toLowerCase().contains(lowerQuery) ?? false);
      if (node.isFolder) {
         final filteredChildren = _filterNodes(node.children, query);
         if (matchesSelf || filteredChildren.isNotEmpty) {
           result.add(node.copyWith(children: filteredChildren));
         }
      } else if (matchesSelf) {
         result.add(node);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocListener<CollectionsBloc, CollectionsState>(
      listenWhen: (prev, next) => prev.collections != next.collections,
      listener: (_, _) => _rebuildTree(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'SEARCH COLLECTIONS...',
                hintStyle: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: context.appTypography.displayWeight, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                prefixIcon: Icon(Icons.search, size: layout.iconSize, color: theme.colorScheme.onSurface),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.appShape.panelRadius), borderSide: BorderSide(color: theme.dividerColor, width: layout.borderThin)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
            ),
          ),
          Expanded(
            child: DragTarget<String>(
              onAcceptWithDetails: (details) => context.read<CollectionsBloc>().add(MoveNode(details.data, null)),
              builder: (context, candidateData, rejectedData) {
                return AnimatedTreeView<CollectionNodeEntity>(
                  treeController: _treeController,
                  nodeBuilder: (context, entry) {
                    return _CollectionNodeWidget(
                      entry: entry,
                      onToggle: () => _treeController.toggleExpansion(entry.node),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionNodeWidget extends StatefulWidget {
  final TreeEntry<CollectionNodeEntity> entry;
  final VoidCallback onToggle;

  const _CollectionNodeWidget({
    required this.entry,
    required this.onToggle,
  });

  @override
  State<_CollectionNodeWidget> createState() => _CollectionNodeWidgetState();
}

class _CollectionNodeWidgetState extends State<_CollectionNodeWidget> {
  bool _isHovered = false;
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<AppLayout>()!;
    final node = widget.entry.node;

    Widget content;
    if (node.isFolder) {
      content = DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          if (details.data == node.id) return false;
          setState(() => _isDragOver = true);
          return true;
        },
        onLeave: (_) => setState(() => _isDragOver = false),
        onAcceptWithDetails: (details) {
          setState(() => _isDragOver = false);
          context.read<CollectionsBloc>().add(MoveNode(details.data, node.id));
        },
        builder: (context, candidateData, rejectedData) {
          return context.appDecoration.wrapInteractive(
            child: InkWell(
              onTap: widget.onToggle,
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _isDragOver
                        ? theme.primaryColor.withValues(alpha: 0.3)
                        : (_isHovered ? theme.hoverColor : Colors.transparent),
                    border: _isDragOver
                        ? Border.all(color: theme.primaryColor, width: layout.borderThin)
                        : Border.all(color: Colors.transparent, width: layout.borderThin),
                  ),
                  child: TreeIndentation(
                    entry: widget.entry,
                    child: Row(
                      children: [
                        Icon(
                          widget.entry.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                          size: layout.smallIconSize,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        Icon(node.isFavorite ? Icons.star : Icons.folder,
                            size: layout.iconSize, color: node.isFavorite ? theme.primaryColor : theme.colorScheme.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(node.name.toUpperCase(), style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.displayWeight)),
                        ),
                        _NodeContextMenu(node: node),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      content = context.appDecoration.wrapInteractive(
        child: InkWell(
          onTap: () {
            final config = node.config;
            if (config == null) return;
            context.read<TabsBloc>().add(AddTab(
                  config: config.copyWith(),
                  collectionNodeId: node.id,
                  collectionName: node.name,
                ));
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _isHovered ? theme.hoverColor : Colors.transparent,
              ),
              child: TreeIndentation(
                entry: widget.entry,
                child: Row(
                  children: [
                    SizedBox(width: layout.smallIconSize),
                    MethodBadge(method: node.config?.method ?? 'GET', small: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(node.name.toUpperCase(), style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight)),
                    ),
                    _NodeContextMenu(node: node),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Draggable<String>(
      data: node.id,
      feedback: Material(
        elevation: 0,
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: layout.inputPadding,
            vertical: layout.inputPaddingVertical,
          ),
          decoration: context.appDecoration.panelBox(context, color: theme.primaryColor),
          child: Text(
            node.name.toUpperCase(),
            style: TextStyle(
              fontSize: layout.fontSizeNormal,
              fontWeight: context.appTypography.displayWeight,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: content),
      child: content,
    );
  }
}

class _NodeContextMenu extends StatelessWidget {
  final CollectionNodeEntity node;
  const _NodeContextMenu({required this.node});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<AppLayout>()!;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: layout.iconSize, color: theme.colorScheme.onSurface),
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
            break;
          case 'delete':
            context.read<CollectionsBloc>().add(DeleteNode(node.id));
            break;
          case 'favorite':
            context.read<CollectionsBloc>().add(ToggleFavorite(node.id));
            break;
          case 'add_subfolder':
             _showAddSubfolderDialog(context);
             break;
        }
      },
      itemBuilder: (context) => [
        if (node.isFolder && node.config == null)
           PopupMenuItem(value: 'favorite', child: Text(node.isFavorite ? 'UNFAVORITE' : 'FAVORITE', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold))),
        PopupMenuItem(value: 'rename', child: Text('RENAME', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold))),
        if (node.isFolder)
           PopupMenuItem(value: 'add_subfolder', child: Text('ADD SUBFOLDER', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold))),
        PopupMenuItem(value: 'delete', child: Text('DELETE', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold, color: theme.colorScheme.error))),
      ],
    );
  }

  void _showRenameDialog(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    NamePromptDialog.show(
      context,
      title: 'RENAME',
      initialText: node.name,
      onConfirm: (name) => bloc.add(RenameNode(node.id, name)),
    );
  }

  void _showAddSubfolderDialog(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    NamePromptDialog.show(
      context,
      title: 'ADD SUBFOLDER',
      confirmLabel: 'ADD',
      onConfirm: (name) => bloc.add(AddFolder(name, parentId: node.id)),
    );
  }
}
