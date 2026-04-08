import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/history_provider.dart';
import '../providers/collections_provider.dart';
import '../providers/tabs_provider.dart';
import '../providers/settings_provider.dart';
import '../models/collection_node.dart';
import '../utils/neo_brutalist_theme.dart';

class SideMenu extends ConsumerWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Container(
        width: 300,
        decoration: const BoxDecoration(
          color: NeoBrutalistTheme.surface,
          border: Border(right: BorderSide(color: NeoBrutalistTheme.border, width: 3)),
        ),
        child: Column(
          children: [
            const _SideMenuHeader(),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: NeoBrutalistTheme.border, width: 3),
                  bottom: BorderSide(color: NeoBrutalistTheme.border, width: 3),
                ),
              ),
              child: const TabBar(
                indicator: BoxDecoration(color: NeoBrutalistTheme.primary),
                labelColor: NeoBrutalistTheme.text,
                unselectedLabelColor: NeoBrutalistTheme.text,
                labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                tabs: [
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('GETMAN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: NeoBrutalistTheme.text, letterSpacing: -1)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.create_new_folder, color: NeoBrutalistTheme.text, size: 20),
                tooltip: 'NEW FOLDER',
                onPressed: () => _showNewFolderDialog(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: NeoBrutalistTheme.text, size: 20),
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
    final settings = ref.watch(settingsProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SETTINGS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('HISTORY LIMIT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              trailing: SizedBox(
                width: 80,
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(hintText: settings.historyLimit.toString(), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  onSubmitted: (val) {
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
              activeThumbColor: NeoBrutalistTheme.secondary,
              activeTrackColor: NeoBrutalistTheme.primary,
              title: const Text('SAVE RESPONSE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              value: settings.saveResponseInHistory,
              onChanged: (val) {
                ref.read(settingsProvider.notifier).updateSaveResponseInHistory(val);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
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
          title: Text(config.url.isEmpty ? '(NO URL)' : config.url, 
            maxLines: 1, 
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
              _MethodBadge(method: config.method, small: true),
              if (config.statusCode != null) ...[
                const SizedBox(width: 8),
                Text(config.statusCode.toString(), style: TextStyle(
                  color: _getStatusColor(config.statusCode!),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
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
    Widget content;
    if (node.isFolder) {
      content = DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != node.id,
        onAcceptWithDetails: (details) => ref.read(collectionsProvider.notifier).moveNode(details.data, node.id),
        builder: (context, candidateData, rejectedData) {
          return ExpansionTile(
            collapsedIconColor: NeoBrutalistTheme.text,
            iconColor: NeoBrutalistTheme.text,
            leading: Icon(node.isFavorite ? Icons.star : Icons.folder,
                size: 20, color: node.isFavorite ? NeoBrutalistTheme.primary : NeoBrutalistTheme.secondary),
            title: Text(node.name.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
            trailing: _NodeContextMenu(node: node),
            children: node.children
                .map((c) => _CollectionNodeWidget(node: c, depth: depth + 1))
                .toList(),
          );
        },
      );
    } else {
      content = ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + (depth * 20)),
        leading: _MethodBadge(method: node.config?.method ?? 'GET', small: true),
        title: Text(node.name.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
          decoration: NeoBrutalistTheme.brutalBox(color: NeoBrutalistTheme.primary),
          child: Text(node.name.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: NeoBrutalistTheme.text)),
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
      icon: const Icon(Icons.more_vert, size: 20, color: NeoBrutalistTheme.text),
      color: NeoBrutalistTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: NeoBrutalistTheme.border, width: 3),
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
           PopupMenuItem(value: 'favorite', child: Text(widget.node.isFavorite ? 'UNFAVORITE' : 'FAVORITE', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
        PopupMenuItem(value: 'rename', child: Text('RENAME', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
        if (widget.node.isFolder)
           PopupMenuItem(value: 'add_subfolder', child: Text('ADD SUBFOLDER', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
        PopupMenuItem(value: 'delete', child: Text('DELETE', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red))),
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

class _MethodBadge extends StatelessWidget {
  final String method;
  final bool small;
  const _MethodBadge({required this.method, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = NeoBrutalistTheme.getMethodColor(method);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: NeoBrutalistTheme.border, width: 2),
      ),
      child: Text(
        method,
        style: TextStyle(color: NeoBrutalistTheme.text, fontWeight: FontWeight.w900, fontSize: small ? 10 : 12),
      ),
    );
  }
}

