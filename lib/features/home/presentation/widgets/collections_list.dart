import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_fancy_tree_view/flutter_fancy_tree_view.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';

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
    final collections = context.read<CollectionsBloc>().state.collections;
    _treeController = TreeController<CollectionNodeEntity>(
      roots: collections,
      childrenProvider: (node) => node.children,
    );
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _treeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<CollectionNodeEntity> _filterNodes(List<CollectionNodeEntity> nodes, String query) {
    if (query.isEmpty) return nodes;
    final lowerQuery = query.toLowerCase();
    List<CollectionNodeEntity> result = [];
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
    final layout = theme.extension<LayoutExtension>()!;

    return BlocBuilder<CollectionsBloc, CollectionsState>(
      builder: (context, state) {
        final collections = state.collections;
        final query = _searchController.text;

        final filteredRoots = _filterNodes(collections, query);
        _treeController.roots = filteredRoots;

        if (state.isLoading && collections.isEmpty) {
          return const Center(child: RepaintBoundary(child: CircularProgressIndicator()));
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'SEARCH COLLECTIONS...',
                  hintStyle: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  prefixIcon: Icon(Icons.search, size: layout.iconSize, color: theme.colorScheme.onSurface),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: theme.dividerColor, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: filteredRoots.isEmpty && query.isNotEmpty
                ? Center(child: Text('NO RESULTS FOUND', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: theme.dividerColor.withValues(alpha: 0.5))))
                : TreeView<CollectionNodeEntity>(
                    treeController: _treeController,
                    nodeBuilder: (context, entry) {
                      return CollectionNodeWidget(
                        entry: entry,
                        onTap: () {
                          if (entry.node.isFolder) {
                            _treeController.toggleExpansion(entry.node);
                          } else {
                            context.read<TabsBloc>().add(AddTab(
                              config: entry.node.config!.copyWith(),
                              collectionNodeId: entry.node.id,
                              collectionName: entry.node.name,
                            ));
                          }
                        },
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }
}

class CollectionNodeWidget extends StatefulWidget {
  final TreeEntry<CollectionNodeEntity> entry;
  final VoidCallback onTap;

  const CollectionNodeWidget({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  State<CollectionNodeWidget> createState() => _CollectionNodeWidgetState();
}

class _CollectionNodeWidgetState extends State<CollectionNodeWidget> {
  bool _isHovered = false;
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.entry.node;

    return Draggable<String>(
      data: node.id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: NeoBrutalistTheme.brutalBox(context),
          child: Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: _buildNode(context)),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != node.id,
        onAcceptWithDetails: (details) {
          setState(() => _isDragOver = false);
          context.read<CollectionsBloc>().add(MoveNode(details.data, node.isFolder ? node.id : null));
        },
        onMove: (_) => setState(() => _isDragOver = true),
        onLeave: (_) => setState(() => _isDragOver = false),
        builder: (context, candidateData, rejectedData) {
          return _buildNode(context);
        },
      ),
    );
  }

  Widget _buildNode(BuildContext context) {
    final node = widget.entry.node;
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isDragOver 
            ? theme.primaryColor.withValues(alpha: 0.3) 
            : (_isHovered ? theme.hoverColor : Colors.transparent),
          border: _isDragOver ? Border.all(color: theme.primaryColor, width: 2) : null,
        ),
        child: TreeIndentation(
          entry: widget.entry,
          guide: const IndentGuide(indent: 16),
          child: ListTile(
            dense: true,
            onTap: widget.onTap,
            leading: Icon(
              node.isFolder 
                ? (widget.entry.isExpanded ? Icons.folder_open : Icons.folder) 
                : Icons.description_outlined,
              size: layout.iconSize,
              color: node.isFolder ? theme.primaryColor : theme.colorScheme.onSurface,
            ),
            title: Text(
              node.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: node.isFolder ? FontWeight.w900 : FontWeight.bold,
                fontSize: layout.fontSizeNormal,
              ),
            ),
            subtitle: !node.isFolder && node.config != null 
              ? Row(
                  children: [
                    MethodBadge(method: node.config!.method, small: true),
                    const SizedBox(width: 4),
                    Expanded(child: Text(node.config!.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: layout.fontSizeSmall))),
                  ],
                ) 
              : null,
            trailing: _isHovered 
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!node.isFolder)
                      IconButton(
                        icon: Icon(node.isFavorite ? Icons.star : Icons.star_border, size: 18, color: node.isFavorite ? Colors.amber : null),
                        onPressed: () => context.read<CollectionsBloc>().add(ToggleFavorite(node.id)),
                      ),
                    _buildContextMenu(context),
                  ],
                )
              : (node.isFavorite ? const Icon(Icons.star, size: 14, color: Colors.amber) : null),
          ),
        ),
      ),
    );
  }

  Widget _buildContextMenu(BuildContext context) {
    final node = widget.entry.node;
    final layout = Theme.of(context).extension<LayoutExtension>()!;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (val) {
        if (val == 'delete') {
          context.read<CollectionsBloc>().add(DeleteNode(node.id));
        } else if (val == 'rename') {
          _showRenameDialog(context);
        } else if (val == 'add_subfolder') {
          _showAddSubfolderDialog(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'rename', child: Text('RENAME', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold))),
        if (node.isFolder)
           PopupMenuItem(value: 'add_subfolder', child: Text('ADD SUBFOLDER', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold))),
        PopupMenuItem(value: 'delete', child: Text('DELETE', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold, color: Colors.red))),
      ],
    );
  }

  void _showRenameDialog(BuildContext context) {
    final node = widget.entry.node;
    final controller = TextEditingController(text: node.name);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('RENAME'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              context.read<CollectionsBloc>().add(RenameNode(node.id, controller.text));
              Navigator.pop(dialogContext);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showAddSubfolderDialog(BuildContext context) {
    final node = widget.entry.node;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ADD SUBFOLDER'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              context.read<CollectionsBloc>().add(AddFolder(controller.text, parentId: node.id));
              Navigator.pop(dialogContext);
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
  }
}
