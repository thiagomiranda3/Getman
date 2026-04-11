import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_fancy_tree_view/flutter_fancy_tree_view.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/history/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';

class SideMenu extends StatelessWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Theme.of(context).extension<LayoutExtension>()!;
    
    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
        ),
        child: Column(
          children: [
            const _SideMenuHeader(),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.dividerColor, width: 3),
                  bottom: BorderSide(color: theme.dividerColor, width: 3),
                ),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(color: theme.primaryColor),
                labelColor: theme.colorScheme.onSurface,
                unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                labelStyle: TextStyle(
                  fontSize: layout.fontSizeNormal, 
                  fontWeight: FontWeight.w900,
                  overflow: TextOverflow.fade
                ),
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                tabs: const [
                  Tab(text: 'COLLECTIONS'),
                  Tab(text: 'HISTORY'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _CollectionsList(),
                  _HistoryList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideMenuHeader extends StatelessWidget {
  const _SideMenuHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Theme.of(context).extension<LayoutExtension>()!;
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: layout.headerPaddingVertical),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'GETMAN', 
                style: TextStyle(
                  fontWeight: FontWeight.w900, 
                  fontSize: layout.headerFontSize, 
                  color: theme.colorScheme.onSurface, 
                  letterSpacing: -1
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrutalBounce(
                child: IconButton(
                  icon: Icon(Icons.create_new_folder, color: theme.colorScheme.onSurface, size: layout.iconSize),
                  tooltip: 'NEW FOLDER',
                  onPressed: () => _showNewFolderDialog(context),
                ),
              ),
              BrutalBounce(
                child: IconButton(
                  icon: Icon(Icons.settings, color: theme.colorScheme.onSurface, size: layout.iconSize),
                  tooltip: 'SETTINGS',
                  onPressed: () => _showSettingsDialog(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showNewFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('NEW FOLDER'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'FOLDER NAME'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<CollectionsBloc>().add(AddFolder(controller.text));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          final settings = state.settings;
          return AlertDialog(
            title: const Text('SETTINGS'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('HISTORY LIMIT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    trailing: SizedBox(
                      width: 80,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        controller: TextEditingController(text: settings.historyLimit.toString())
                          ..selection = TextSelection.fromPosition(TextPosition(offset: settings.historyLimit.toString().length)),
                        onChanged: (val) {
                          final limit = int.tryParse(val);
                          if (limit != null) {
                            context.read<SettingsBloc>().add(UpdateHistoryLimit(limit));
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    title: const Text('SAVE RESPONSE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    value: settings.saveResponseInHistory,
                    onChanged: (val) {
                      context.read<SettingsBloc>().add(UpdateSaveResponseInHistory(val));
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    secondary: Icon(settings.isDarkMode ? Icons.dark_mode : Icons.light_mode, size: 20),
                    title: const Text('DARK MODE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    value: settings.isDarkMode,
                    onChanged: (val) {
                      context.read<SettingsBloc>().add(UpdateDarkMode(val));
                    },
                  ),
                  SwitchListTile(
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    secondary: const Icon(Icons.view_compact, size: 20),
                    title: const Text('COMPACT MODE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    value: settings.isCompactMode,
                    onChanged: (val) {
                      context.read<SettingsBloc>().add(UpdateCompactMode(val));
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CLOSE')),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryList extends StatefulWidget {
  const _HistoryList();
  
  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<HttpRequestConfigEntity> _items;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List.from(context.read<HistoryBloc>().state.history);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        return BlocListener<HistoryBloc, HistoryState>(
          listener: (context, state) {
            final next = state.history;
            if (_items.isEmpty && next.isNotEmpty) {
              setState(() {
                _items = List.from(next);
              });
              return;
            }

            if (next.length > _items.length) {
              final diff = next.length - _items.length;
              for (int i = 0; i < diff; i++) {
                _items.insert(i, next[i]);
                _listKey.currentState?.insertItem(i, duration: const Duration(milliseconds: 400));
              }
            } else if (next.length < _items.length) {
              if (next.isEmpty) {
                for (int i = _items.length - 1; i >= 0; i--) {
                  final removedItem = _items[i];
                  _listKey.currentState?.removeItem(
                    i, 
                    (context, animation) => _buildHistoryItem(removedItem, animation, isRemoved: true),
                    duration: const Duration(milliseconds: 300)
                  );
                }
                _items.clear();
                setState(() {});
              } else {
                setState(() {
                  _items = List.from(next);
                });
              }
            }
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'SEARCH HISTORY...',
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
                child: state.isLoading && _items.isEmpty 
                  ? const Center(child: CircularProgressIndicator()) 
                  : _buildList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList() {
    final query = _searchController.text.toLowerCase();
    final filteredItems = query.isEmpty 
      ? _items 
      : _items.where((item) => 
          item.url.toLowerCase().contains(query) || 
          (item.statusCode?.toString().contains(query) ?? false) ||
          item.method.toLowerCase().contains(query)
        ).toList();

    if (filteredItems.isEmpty) {
      return Center(
        child: Text('NO RESULTS FOUND', style: TextStyle(
          fontSize: 12, 
          fontWeight: FontWeight.w900, 
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5)
        )),
      );
    }

    if (query.isNotEmpty) {
       return ListView.builder(
         itemCount: filteredItems.length,
         itemBuilder: (context, index) {
            return _HistoryItemWidget(
              config: filteredItems[index], 
              onTap: () {
                context.read<TabsBloc>().add(AddTab(config: filteredItems[index].copyWith()));
              },
            );
         },
       );
    }

    return AnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        return _buildHistoryItem(_items[index], animation);
      },
    );
  }

  Widget _buildHistoryItem(HttpRequestConfigEntity config, Animation<double> animation, {bool isRemoved = false}) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: _HistoryItemWidget(
          config: config, 
          onTap: isRemoved ? () {} : () {
            context.read<TabsBloc>().add(AddTab(config: config.copyWith()));
          },
        ),
      ),
    );
  }
}

class _HistoryItemWidget extends StatefulWidget {
  final HttpRequestConfigEntity config;
  final VoidCallback onTap;
  const _HistoryItemWidget({required this.config, required this.onTap});

  @override
  State<_HistoryItemWidget> createState() => _HistoryItemWidgetState();
}

class _HistoryItemWidgetState extends State<_HistoryItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isHovered ? theme.hoverColor : Colors.transparent,
          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1), width: 1)),
        ),
        child: ListTile(
          dense: true,
          onTap: widget.onTap,
          title: Text(widget.config.url.isEmpty ? '(NO URL)' : widget.config.url, 
            maxLines: 1, 
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
              _MethodBadge(method: widget.config.method, small: true),
              if (widget.config.statusCode != null) ...[
                const SizedBox(width: 8),
                Text(widget.config.statusCode.toString(), style: TextStyle(
                  color: _getStatusColor(widget.config.statusCode!),
                  fontWeight: FontWeight.w900,
                  fontSize: layout.fontSizeNormal,
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(int code) {
    if (code >= 200 && code < 300) return Colors.green.shade700;
    if (code >= 400) return Colors.red.shade700;
    return Colors.orange.shade700;
  }
}

class _CollectionsList extends StatefulWidget {
  const _CollectionsList();

  @override
  State<_CollectionsList> createState() => _CollectionsListState();
}

class _CollectionsListState extends State<_CollectionsList> {
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
        if (query.isNotEmpty) {
           _treeController.expandAll();
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
        );
      },
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
    final layout = theme.extension<LayoutExtension>()!;
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
          return InkWell(
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
                    ? Border.all(color: theme.primaryColor, width: 2) 
                    : Border.all(color: Colors.transparent, width: 2),
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
                        child: Text(node.name.toUpperCase(), style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.w900)),
                      ),
                      _NodeContextMenu(node: node),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      content = InkWell(
        onTap: () {
          if (node.config != null) {
            context.read<TabsBloc>().add(AddTab(
                  config: node.config!.copyWith(),
                  collectionNodeId: node.id,
                  collectionName: node.name,
                ));
          }
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
                  _MethodBadge(method: node.config?.method ?? 'GET', small: true),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(node.name.toUpperCase(), style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold)),
                  ),
                  _NodeContextMenu(node: node),
                ],
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: NeoBrutalistTheme.brutalBox(context, color: theme.primaryColor),
          child: Text(node.name.toUpperCase(), style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
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
    final layout = theme.extension<LayoutExtension>()!;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: layout.iconSize, color: theme.colorScheme.onSurface),
      color: theme.colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: theme.dividerColor, width: 3),
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
        PopupMenuItem(value: 'delete', child: Text('DELETE', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold, color: Colors.red))),
      ],
    );
  }

  void _showRenameDialog(BuildContext context) {
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

class _MethodBadge extends StatelessWidget {
  final String method;
  final bool small;
  const _MethodBadge({required this.method, this.small = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;
    final color = NeoBrutalistTheme.getMethodColor(method);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? layout.badgePaddingHorizontal : 10, 
        vertical: layout.badgePaddingVertical
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: 2),
      ),
      child: Text(
        method,
        style: TextStyle(
          color: Colors.black, 
          fontWeight: FontWeight.w900, 
          fontSize: small ? layout.fontSizeSmall : layout.fontSizeNormal
        ),
      ),
    );
  }
}
