import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/history_provider.dart';
import '../providers/collections_provider.dart';
import '../providers/tabs_provider.dart';
import '../providers/settings_provider.dart';
import '../models/collection_node.dart';
import '../utils/neo_brutalist_theme.dart';
import '../utils/layout_constants.dart';

class SideMenu extends ConsumerWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final layout = LayoutConstants(settings.isCompactMode);
    
    return DefaultTabController(
      length: 2,
      child: Container(
        width: layout.sideMenuWidth,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(right: BorderSide(color: theme.dividerColor, width: 3)),
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
                indicator: BoxDecoration(color: theme.primaryColor),
                labelColor: theme.colorScheme.onSurface,
                unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                labelStyle: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.w900),
                tabs: const [
                  Tab(text: 'COLLECTIONS'),
                  Tab(text: 'HISTORY'),
                ],
              ),
            ),
            Expanded(
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

class _SideMenuHeader extends ConsumerWidget {
  const _SideMenuHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final layout = LayoutConstants(settings.isCompactMode);
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: settings.isCompactMode ? 12 : 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('GETMAN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: settings.isCompactMode ? 18 : 24, color: theme.colorScheme.onSurface, letterSpacing: -1)),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.create_new_folder, color: theme.colorScheme.onSurface, size: layout.iconSize),
                tooltip: 'NEW FOLDER',
                onPressed: () => _showNewFolderDialog(context, ref),
              ),
              IconButton(
                icon: Icon(Icons.settings, color: theme.colorScheme.onSurface, size: layout.iconSize),
                tooltip: 'SETTINGS',
                onPressed: () => _showSettingsDialog(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showNewFolderDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('NEW FOLDER'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'FOLDER NAME'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(collectionsProvider.notifier).addFolder(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(settingsProvider);
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
                            ref.read(settingsProvider.notifier).updateHistoryLimit(limit);
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
                      ref.read(settingsProvider.notifier).updateSaveResponseInHistory(val);
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
                      ref.read(settingsProvider.notifier).updateDarkMode(val);
                    },
                  ),
                  SwitchListTile(
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    secondary: const Icon(Icons.view_compact, size: 20),
                    title: const Text('COMPACT MODE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    value: settings.isCompactMode,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).updateCompactMode(val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList();
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final settings = ref.watch(settingsProvider);
    final layout = LayoutConstants(settings.isCompactMode);

    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final config = history[index];
        return ListTile(
          dense: true,
          title: Text(config.url.isEmpty ? '(NO URL)' : config.url, 
            maxLines: 1, 
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
              _MethodBadge(method: config.method, small: true),
              if (config.statusCode != null) ...[
                const SizedBox(width: 8),
                Text(config.statusCode.toString(), style: TextStyle(
                  color: _getStatusColor(config.statusCode!),
                  fontWeight: FontWeight.w900,
                  fontSize: layout.fontSizeNormal,
                )),
              ],
            ],
          ),
          onTap: () {
            ref.read(tabsProvider.notifier).addTab(config: config.copyWith());
          },
        );
      },
    );
  }

  Color _getStatusColor(int code) {
    if (code >= 200 && code < 300) return Colors.green.shade700;
    if (code >= 400) return Colors.red.shade700;
    return Colors.orange.shade700;
  }
}

class _CollectionsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    return DragTarget<String>(
      onAcceptWithDetails: (details) => ref.read(collectionsProvider.notifier).moveNode(details.data, null),
      builder: (context, candidateData, rejectedData) {
        return ListView.builder(
          itemCount: collections.length,
          itemBuilder: (context, index) {
            return _CollectionNodeWidget(node: collections[index]);
          },
        );
      },
    );
  }
}

class _CollectionNodeWidget extends ConsumerWidget {
  final CollectionNode node;
  final int depth;

  const _CollectionNodeWidget({required this.node, this.depth = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final layout = LayoutConstants(settings.isCompactMode);

    Widget content;
    if (node.isFolder) {
      content = DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != node.id,
        onAcceptWithDetails: (details) => ref.read(collectionsProvider.notifier).moveNode(details.data, node.id),
        builder: (context, candidateData, rejectedData) {
          return ExpansionTile(
            collapsedIconColor: theme.colorScheme.onSurface,
            iconColor: theme.colorScheme.onSurface,
            visualDensity: settings.isCompactMode ? VisualDensity.compact : null,
            leading: Icon(node.isFavorite ? Icons.star : Icons.folder,
                size: layout.iconSize, color: node.isFavorite ? theme.primaryColor : theme.colorScheme.secondary),
            title: Text(node.name.toUpperCase(), style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.w900)),
            trailing: _NodeContextMenu(node: node),
            children: node.children
                .map((c) => _CollectionNodeWidget(node: c, depth: depth + 1))
                .toList(),
          );
        },
      );
    } else {
      content = ListTile(
        dense: true,
        visualDensity: settings.isCompactMode ? VisualDensity.compact : null,
        contentPadding: EdgeInsets.only(left: 16.0 + (depth * (settings.isCompactMode ? 12 : 20))),
        leading: _MethodBadge(method: node.config?.method ?? 'GET', small: true),
        title: Text(node.name.toUpperCase(), style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold)),
        onTap: () {
          if (node.config != null) {
            ref
                .read(tabsProvider.notifier)
                .addTab(
                  config: node.config!.copyWith(),
                  collectionNodeId: node.id,
                  collectionName: node.name,
                );
          }
        },
        trailing: _NodeContextMenu(node: node),
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

class _NodeContextMenu extends ConsumerStatefulWidget {
  final CollectionNode node;
  const _NodeContextMenu({required this.node});

  @override
  _NodeContextMenuState createState() => _NodeContextMenuState();
}

class _NodeContextMenuState extends ConsumerState<_NodeContextMenu> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final layout = LayoutConstants(settings.isCompactMode);

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
            _showRenameDialog();
            break;
          case 'delete':
            ref.read(collectionsProvider.notifier).deleteNode(widget.node.id);
            break;
          case 'favorite':
            ref.read(collectionsProvider.notifier).toggleFavorite(widget.node.id);
            break;
          case 'add_subfolder':
             _showAddSubfolderDialog();
             break;
        }
      },
      itemBuilder: (context) => [
        if (widget.node.isFolder && widget.node.config == null)
           PopupMenuItem(value: 'favorite', child: Text(widget.node.isFavorite ? 'UNFAVORITE' : 'FAVORITE', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold))),
        PopupMenuItem(value: 'rename', child: Text('RENAME', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold))),
        if (widget.node.isFolder)
           PopupMenuItem(value: 'add_subfolder', child: Text('ADD SUBFOLDER', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold))),
        PopupMenuItem(value: 'delete', child: Text('DELETE', style: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold, color: Colors.red))),
      ],
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.node.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RENAME'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              ref.read(collectionsProvider.notifier).renameNode(widget.node.id, controller.text);
              Navigator.pop(context);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showAddSubfolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ADD SUBFOLDER'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              ref.read(collectionsProvider.notifier).addFolder(controller.text, parentId: widget.node.id);
              Navigator.pop(context);
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
  }
}

class _MethodBadge extends ConsumerWidget {
  final String method;
  final bool small;
  const _MethodBadge({required this.method, this.small = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final layout = LayoutConstants(settings.isCompactMode);
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
