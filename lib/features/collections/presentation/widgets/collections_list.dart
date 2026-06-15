import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/utils/debouncer.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/collections/presentation/widgets/node_action_sheet.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

class CollectionsList extends StatefulWidget {
  const CollectionsList({super.key});

  @override
  State<CollectionsList> createState() => _CollectionsListState();
}

class _CollectionsListState extends State<CollectionsList> {
  final TreeViewController _treeController = TreeViewController();
  // The flattened forest fed to the TreeView, rebuilt from bloc state. Content
  // is a [_TreeItem] union: a collection node, or one of a leaf's saved
  // examples (examples aren't tree children, so they ride as synthetic
  // expandable rows beneath their request).
  List<TreeViewNode<_TreeItem>> _tree = const <TreeViewNode<_TreeItem>>[];
  // Expansion is tracked by [CollectionNodeEntity.id] rather than node identity
  // (the H2 fix). two_dimensional_scrollables has no id-keyed override hook, so
  // each rebuild reseeds `TreeViewNode(expanded:)` from this set; tapping a
  // node updates it via [TreeView.onNodeToggle]. Collection mutations rebuild
  // non-equal entities (copyWith rewrites the ancestor chain), so a value-keyed
  // set would lose expansion and collapse folders on every edit.
  final Set<String> _expandedIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  // Defers the recursive filter + force-expand until typing pauses, so each
  // keystroke doesn't walk the whole tree and rebuild the node forest.
  final Debouncer _searchDebouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    _rebuildTree();
    _searchController.addListener(() => _searchDebouncer.run(_rebuildTree));
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Recompute the tree from the current collections state + search query, and
  /// force-expand matching folders while searching. Called outside of `build`
  /// to avoid mutating state during paint.
  void _rebuildTree() {
    final collections = context.read<CollectionsBloc>().state.collections;
    final query = _searchController.text;
    final filtered = _filterNodes(collections, query);
    if (query.isNotEmpty) {
      _collectFolderIds(filtered, _expandedIds);
    }
    final next = _buildItems(filtered);
    if (mounted) {
      setState(() => _tree = next);
    } else {
      _tree = next;
    }
  }

  /// Map the entity forest onto [TreeViewNode]s, seeding expansion by id. A
  /// folder's children are its sub-nodes; a leaf's "children" are its saved
  /// examples (so a request with examples becomes expandable).
  List<TreeViewNode<_TreeItem>> _buildItems(List<CollectionNodeEntity> nodes) {
    return [
      for (final node in nodes)
        TreeViewNode<_TreeItem>(
          _NodeItem(node),
          children: _childrenFor(node),
          expanded: _expandedIds.contains(node.id),
        ),
    ];
  }

  List<TreeViewNode<_TreeItem>>? _childrenFor(CollectionNodeEntity node) {
    if (node.isFolder) return _buildItems(node.children);
    if (node.examples.isEmpty) return null;
    return [
      for (final e in node.examples)
        TreeViewNode<_TreeItem>(_ExampleItem(node.id, node.name, e)),
    ];
  }

  /// Add every folder id in [nodes] (recursively) to [out] — replicates the old
  /// expandAll() behaviour while searching.
  void _collectFolderIds(List<CollectionNodeEntity> nodes, Set<String> out) {
    for (final node in nodes) {
      if (node.isFolder) {
        out.add(node.id);
        _collectFolderIds(node.children, out);
      }
    }
  }

  Future<void> _importCollections(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    return importJsonFilesWithFeedback<CollectionNodeEntity>(
      context,
      parse: (content) => [PostmanCollectionMapper.fromJson(content)],
      onImported: (imported) => bloc.add(ImportCollections(imported)),
      noun: 'collection',
    );
  }

  List<CollectionNodeEntity> _filterNodes(
    List<CollectionNodeEntity> nodes,
    String query,
  ) {
    if (query.isEmpty) return nodes;
    final lowerQuery = query.toLowerCase();
    final result = <CollectionNodeEntity>[];
    for (final node in nodes) {
      final matchesSelf =
          node.name.toLowerCase().contains(lowerQuery) ||
          (node.config?.url.toLowerCase().contains(lowerQuery) ?? false);
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
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'SEARCH COLLECTIONS...',
                      hintStyle: TextStyle(
                        fontSize: layout.fontSizeSmall,
                        fontWeight: context.appTypography.displayWeight,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: layout.iconSize,
                        color: theme.colorScheme.onSurface,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          context.appShape.panelRadius,
                        ),
                        borderSide: BorderSide(
                          color: theme.dividerColor,
                          width: layout.borderThin,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      fontWeight: context.appTypography.titleWeight,
                    ),
                  ),
                ),
                SizedBox(width: layout.tabSpacing),
                context.appDecoration.wrapInteractive(
                  child: IconButton(
                    icon: Icon(
                      Icons.file_upload,
                      size: layout.iconSize,
                      color: theme.colorScheme.onSurface,
                    ),
                    tooltip: 'IMPORT FROM POSTMAN',
                    onPressed: () => _importCollections(context),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<CollectionsBloc, CollectionsState>(
              // Only switch between loading / empty / tree — not on every tree
              // mutation (the TreeView is driven by _tree, rebuilt in
              // _rebuildTree via the BlocListener above).
              buildWhen: (p, n) =>
                  p.isLoading != n.isLoading ||
                  p.collections.isEmpty != n.collections.isEmpty,
              builder: (context, state) {
                if (state.isLoading && state.collections.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.collections.isEmpty) {
                  return _buildEmptyState(context);
                }
                // Rows have unbounded cross-axis width in the 2D TreeView, so
                // we bound each one to the viewport width (restores the
                // Expanded layout + makes horizontal scroll a no-op). Row
                // height is fixed (the TreeView has no content-sized extent).
                final rowHeight =
                    context.appLayout.treeRowExtent > context.touchTargetMin
                    ? context.appLayout.treeRowExtent
                    : context.touchTargetMin;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final rowWidth = constraints.maxWidth;
                    final tree = TreeView<_TreeItem>(
                      tree: _tree,
                      controller: _treeController,
                      // Indentation is applied manually in the row (see
                      // _CollectionNodeWidget) so the hover/drag highlight spans
                      // the full row width.
                      indentation: TreeViewIndentationType.none,
                      treeRowBuilder: (node) =>
                          TreeRow(extent: FixedTreeRowExtent(rowHeight)),
                      onNodeToggle: (node) {
                        final item = node.content;
                        if (item is! _NodeItem) return;
                        final id = item.node.id;
                        if (node.isExpanded) {
                          _expandedIds.add(id);
                        } else {
                          _expandedIds.remove(id);
                        }
                      },
                      treeNodeBuilder: (context, node, animationStyle) {
                        final item = node.content;
                        if (item is _ExampleItem) {
                          return _ExampleRow(
                            key: ValueKey('${item.nodeId}/${item.example.id}'),
                            item: item,
                            depth: node.depth ?? 0,
                            rowWidth: rowWidth,
                            rowHeight: rowHeight,
                          );
                        }
                        final nodeItem = item as _NodeItem;
                        return _CollectionNodeWidget(
                          key: ValueKey(nodeItem.node.id),
                          treeNode: node,
                          node: nodeItem.node,
                          controller: _treeController,
                          rowWidth: rowWidth,
                          rowHeight: rowHeight,
                        );
                      },
                    );
                    if (context.isPhone) return tree;
                    return DragTarget<String>(
                      onAcceptWithDetails: (details) => context
                          .read<CollectionsBloc>()
                          .add(MoveNode(details.data, null)),
                      builder: (context, candidateData, rejectedData) => tree,
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

  Widget _buildEmptyState(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: layout.iconSize * 2,
              color: theme.dividerColor,
            ),
            SizedBox(height: layout.sectionSpacing),
            Text(
              'NO COLLECTIONS YET',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.displayWeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            SizedBox(height: layout.tabSpacing),
            Text(
              'Save a request or import from Postman to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.bodyWeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionNodeWidget extends StatefulWidget {
  const _CollectionNodeWidget({
    required this.treeNode,
    required this.node,
    required this.controller,
    required this.rowWidth,
    required this.rowHeight,
    super.key,
  });
  final TreeViewNode<_TreeItem> treeNode;
  final CollectionNodeEntity node;
  final TreeViewController controller;
  final double rowWidth;
  final double rowHeight;

  @override
  State<_CollectionNodeWidget> createState() => _CollectionNodeWidgetState();
}

class _CollectionNodeWidgetState extends State<_CollectionNodeWidget> {
  bool _isHovered = false;
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final node = widget.node;
    final isExpanded = widget.treeNode.isExpanded;
    final indent = (widget.treeNode.depth ?? 0) * layout.depthPaddingMultiplier;
    final isPhone = context.isPhone;
    final onLongPress = isPhone
        ? () => NodeActionSheet.show(context, node)
        : null;

    Widget content;
    if (node.isFolder) {
      final folderInner = SizedBox(
        width: widget.rowWidth,
        height: widget.rowHeight,
        child: context.appDecoration.wrapInteractive(
          child: InkWell(
            onTap: () => widget.controller.toggleNode(widget.treeNode),
            onLongPress: onLongPress,
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
                      ? Border.all(
                          color: theme.primaryColor,
                          width: layout.borderThin,
                        )
                      : Border.all(
                          color: Colors.transparent,
                          width: layout.borderThin,
                        ),
                ),
                child: Padding(
                  padding: EdgeInsets.only(left: indent),
                  child: Row(
                    children: [
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: layout.smallIconSize,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      Icon(
                        node.isFavorite ? Icons.star : Icons.folder,
                        size: layout.iconSize,
                        color: node.isFavorite
                            ? theme.primaryColor
                            : theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          node.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: layout.fontSizeNormal,
                            fontWeight: context.appTypography.displayWeight,
                          ),
                        ),
                      ),
                      _NodeContextMenu(node: node),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      content = isPhone
          ? folderInner
          : DragTarget<String>(
              onWillAcceptWithDetails: (details) {
                if (details.data == node.id) return false;
                setState(() => _isDragOver = true);
                return true;
              },
              onLeave: (_) => setState(() => _isDragOver = false),
              onAcceptWithDetails: (details) {
                setState(() => _isDragOver = false);
                context.read<CollectionsBloc>().add(
                  MoveNode(details.data, node.id),
                );
              },
              builder: (context, candidateData, rejectedData) => folderInner,
            );
    } else {
      content = SizedBox(
        width: widget.rowWidth,
        height: widget.rowHeight,
        child: context.appDecoration.wrapInteractive(
          child: InkWell(
            onTap: () {
              final config = node.config;
              if (config == null) return;
              context.read<TabsBloc>().add(
                AddTab(
                  config: config.copyWith(),
                  collectionNodeId: node.id,
                  collectionName: node.name,
                ),
              );
              Scaffold.maybeOf(context)?.closeDrawer();
            },
            onLongPress: onLongPress,
            child: MouseRegion(
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _isHovered ? theme.hoverColor : Colors.transparent,
                ),
                child: Padding(
                  padding: EdgeInsets.only(left: indent),
                  child: Row(
                    children: [
                      // A request with saved examples gets a toggle chevron;
                      // its own tap expands/collapses without opening the
                      // request.
                      if (node.examples.isNotEmpty)
                        InkWell(
                          onTap: () =>
                              widget.controller.toggleNode(widget.treeNode),
                          child: Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                            size: layout.smallIconSize,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        )
                      else
                        SizedBox(width: layout.smallIconSize),
                      MethodBadge(
                        method: node.config?.method ?? 'GET',
                        small: true,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          node.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: layout.fontSizeNormal,
                            fontWeight: context.appTypography.titleWeight,
                          ),
                        ),
                      ),
                      if (node.examples.isNotEmpty)
                        Text(
                          '${node.examples.length}',
                          style: TextStyle(
                            fontSize: layout.fontSizeSmall,
                            fontWeight: context.appTypography.bodyWeight,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      _NodeContextMenu(node: node),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (isPhone) return content;

    return Draggable<String>(
      data: node.id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: layout.inputPadding,
            vertical: layout.inputPaddingVertical,
          ),
          decoration: context.appDecoration.panelBox(
            context,
            color: theme.primaryColor,
          ),
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
  const _NodeContextMenu({required this.node});
  final CollectionNodeEntity node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return PopupMenuButton<String>(
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

/// TreeView content: either a collection node or one of a leaf's saved
/// examples.
sealed class _TreeItem {}

class _NodeItem extends _TreeItem {
  _NodeItem(this.node);
  final CollectionNodeEntity node;
}

class _ExampleItem extends _TreeItem {
  _ExampleItem(this.nodeId, this.nodeName, this.example);
  final String nodeId;
  final String nodeName;
  final SavedExampleEntity example;
}

/// A saved-example row rendered beneath its request node. Tapping opens the
/// snapshot as a fresh (unlinked) tab with its captured response shown; the
/// trailing menu renames or deletes the example.
class _ExampleRow extends StatefulWidget {
  const _ExampleRow({
    required this.item,
    required this.depth,
    required this.rowWidth,
    required this.rowHeight,
    super.key,
  });
  final _ExampleItem item;
  final int depth;
  final double rowWidth;
  final double rowHeight;

  @override
  State<_ExampleRow> createState() => _ExampleRowState();
}

class _ExampleRowState extends State<_ExampleRow> {
  bool _isHovered = false;

  void _open(BuildContext context) {
    final cfg = widget.item.example.config;
    final response = cfg.statusCode != null
        ? HttpResponseEntity(
            statusCode: cfg.statusCode!,
            body: cfg.responseBody ?? '',
            headers: cfg.responseHeaders ?? const {},
            durationMs: cfg.durationMs ?? 0,
          )
        : null;
    // Opened unlinked (no collectionNodeId) so editing/re-sending a snapshot
    // never overwrites the saved request.
    context.read<TabsBloc>().add(
      AddTab(
        config: cfg.copyWith(),
        collectionName: '${widget.item.nodeName} · ${widget.item.example.name}',
        response: response,
      ),
    );
    Scaffold.maybeOf(context)?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final indent = widget.depth * layout.depthPaddingMultiplier;

    return SizedBox(
      width: widget.rowWidth,
      height: widget.rowHeight,
      child: context.appDecoration.wrapInteractive(
        child: InkWell(
          onTap: () => _open(context),
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _isHovered ? theme.hoverColor : Colors.transparent,
              ),
              child: Padding(
                padding: EdgeInsets.only(left: indent + layout.smallIconSize),
                child: Row(
                  children: [
                    Icon(
                      Icons.bookmark_outline,
                      size: layout.smallIconSize,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.item.example.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: layout.fontSizeSmall,
                          fontWeight: context.appTypography.bodyWeight,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    _ExampleMenu(item: widget.item),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rename/delete menu for a single saved example (works on desktop + phone).
class _ExampleMenu extends StatelessWidget {
  const _ExampleMenu({required this.item});
  final _ExampleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: layout.smallIconSize,
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
            _rename(context);
          case 'delete':
            _delete(context);
        }
      },
      itemBuilder: (context) => [
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

  void _rename(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'RENAME EXAMPLE',
        initialText: item.example.name,
        onConfirm: (name) {
          bloc.add(RenameExample(item.nodeId, item.example.id, name));
          showAppSnackBarVia(messenger, 'Renamed to "$name"');
        },
      ),
    );
  }

  void _delete(BuildContext context) {
    final bloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      ConfirmDialog.show(
        context,
        title: 'Delete example?',
        message: 'Deletes "${item.example.name}". This cannot be undone.',
        onConfirm: () {
          bloc.add(DeleteExample(item.nodeId, item.example.id));
          showAppSnackBarVia(messenger, 'Deleted "${item.example.name}"');
        },
      ),
    );
  }
}
