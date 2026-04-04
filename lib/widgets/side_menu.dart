import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/history_provider.dart';
import '../providers/collections_provider.dart';
import '../providers/tabs_provider.dart';
import '../providers/settings_provider.dart';
import '../models/collection_node.dart';

class SideMenu extends ConsumerWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Column(
          children: [
            _buildHeader(context, ref),
            const TabBar(
              tabs: [
                Tab(text: 'Collections'),
                Tab(text: 'History'),
              ],
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

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Getman', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.create_new_folder),
                tooltip: 'New Folder',
                onPressed: () => _showNewFolderDialog(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
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
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Folder Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(collectionsProvider.notifier).addFolder(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Global Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('History Limit'),
              trailing: SizedBox(
                width: 60,
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(hintText: settings.historyLimit.toString()),
                  onSubmitted: (val) {
                    final limit = int.tryParse(val);
                    if (limit != null) {
                      ref.read(settingsProvider.notifier).updateHistoryLimit(limit);
                    }
                  },
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('Save Response in History'),
              value: settings.saveResponseInHistory,
              onChanged: (val) {
                ref.read(settingsProvider.notifier).updateSaveResponseInHistory(val);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final config = history[index];
        return ListTile(
          dense: true,
          title: Text(config.url.isEmpty ? '(No URL)' : config.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Row(
            children: [
              _MethodBadge(method: config.method),
              if (config.statusCode != null) ...[
                const SizedBox(width: 8),
                Text(config.statusCode.toString(), style: TextStyle(color: _getStatusColor(config.statusCode!))),
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
    if (code >= 200 && code < 300) return Colors.green;
    if (code >= 400) return Colors.red;
    return Colors.orange;
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
    Widget content;
    if (node.isFolder) {
      content = DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != node.id,
        onAcceptWithDetails: (details) => ref.read(collectionsProvider.notifier).moveNode(details.data, node.id),
        builder: (context, candidateData, rejectedData) {
          return ExpansionTile(
            leading: Icon(node.isFavorite ? Icons.star : Icons.folder,
                size: 16, color: node.isFavorite ? Colors.amber : null),
            title: Text(node.name, style: const TextStyle(fontSize: 14)),
            trailing: _NodeContextMenu(node: node),
            children: node.children
                .map((c) => _CollectionNodeWidget(node: c, depth: depth + 1))
                .toList(),
          );
        },
      );
    } else {
      content = ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + (depth * 16)),
        leading: _MethodBadge(method: node.config?.method ?? 'GET', small: true),
        title: Text(node.name, style: const TextStyle(fontSize: 13)),
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
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.all(8),
          color: Theme.of(context).cardColor,
          child: Text(node.name),
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
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16),
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
        if (widget.node.isFolder && widget.node.config == null) // only top level? user said "for the top folder... favorite button"
           PopupMenuItem(value: 'favorite', child: Text(widget.node.isFavorite ? 'Unfavorite' : 'Favorite')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (widget.node.isFolder)
           const PopupMenuItem(value: 'add_subfolder', child: Text('Add Subfolder')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.node.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(collectionsProvider.notifier).renameNode(widget.node.id, controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
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
        title: const Text('Add Subfolder'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(collectionsProvider.notifier).addFolder(controller.text, parentId: widget.node.id);
              Navigator.pop(context);
            },
            child: const Text('Add'),
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
    Color color;
    switch (method) {
      case 'GET': color = Colors.green; break;
      case 'POST': color = Colors.blue; break;
      case 'PUT': color = Colors.orange; break;
      case 'DELETE': color = Colors.red; break;
      case 'PATCH': color = Colors.purple; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 4 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        method,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: small ? 10 : 12),
      ),
    );
  }
}
