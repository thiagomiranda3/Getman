import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/utils/debouncer.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/collections/presentation/widgets/branch_chip.dart';
import 'package:getman/features/collections/presentation/widgets/collection_node_row.dart';
import 'package:getman/features/collections/presentation/widgets/example_row.dart';
import 'package:getman/features/collections/presentation/widgets/node_drag_data.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_button.dart';
import 'package:getman/features/collections/presentation/widgets/spec_import_dialog.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
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

  /// The user's expansion state snapshotted when a search begins, restored
  /// when the query is cleared — searching force-expands matching folders,
  /// and that must not permanently overwrite the manual state.
  Set<String>? _preSearchExpandedIds;
  final TextEditingController _searchController = TextEditingController();
  // Defers the recursive filter + force-expand until typing pauses, so each
  // keystroke doesn't walk the whole tree and rebuild the node forest.
  final Debouncer _searchDebouncer = Debouncer();
  // The id of the saved request linked to the currently-focused tab, or null
  // (unlinked tab / no tabs / linked node deleted). Drives the row highlight.
  String? _selectedNodeId;
  // Owns the TreeView's vertical scroll so we can scroll the selected row into
  // view when the focused tab changes.
  final ScrollController _verticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _rebuildTree();
    _searchController.addListener(() => _searchDebouncer.run(_rebuildTree));
    _selectedNodeId = _activeLinkedNodeId(context.read<TabsBloc>().state);
    final initial = _selectedNodeId;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealAndScrollTo(initial);
      });
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// The collectionNodeId of the active panel's focused tab, or null when the
  /// tab is unlinked, there are no tabs, or the index is out of range.
  String? _activeLinkedNodeId(TabsState s) {
    if (s.activeIndex < 0 || s.activeIndex >= s.tabs.length) return null;
    return s.tabs[s.activeIndex].collectionNodeId;
  }

  /// React to the focused tab changing: update the highlight, then (if the tab
  /// links to a known node) expand its ancestor folders and scroll it in.
  void _onSelectedNodeChanged(String? id) {
    setState(() => _selectedNodeId = id);
    if (id != null) _revealAndScrollTo(id);
  }

  /// Expand the ancestor folders of [id] and scroll its row into view. No-op if
  /// the node isn't in the current tree.
  void _revealAndScrollTo(String id) {
    final collections = context.read<CollectionsBloc>().state.collections;
    if (CollectionsTreeHelper.findNode(collections, id) == null) return;
    final ancestors = CollectionsTreeHelper.ancestorFolderIds(collections, id);
    final before = _expandedIds.length;
    _expandedIds.addAll(ancestors);
    if (_expandedIds.length != before) {
      _rebuildTree();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToNode(id);
    });
  }

  /// Scroll the vertical viewport so the row for [id] is visible. Uses the
  /// fixed row height; honours the current expansion state.
  void _scrollToNode(String id) {
    if (!_verticalController.hasClients) return;
    final index = _visibleRowIndexOf(id);
    if (index == null) return;
    final rowHeight = _rowHeight();
    final target = (index * rowHeight).clamp(
      0.0,
      _verticalController.position.maxScrollExtent,
    );
    unawaited(
      _verticalController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  /// The display-order (flattened, expansion-aware) row index of node [id], or
  /// null if it isn't currently visible.
  int? _visibleRowIndexOf(String id) {
    var row = 0;
    int? walk(List<TreeViewNode<_TreeItem>> nodes) {
      for (final n in nodes) {
        final item = n.content;
        if (item is _NodeItem && item.node.id == id) return row;
        row++;
        if (item is _NodeItem && _expandedIds.contains(item.node.id)) {
          final found = walk(n.children);
          if (found != null) return found;
        }
      }
      return null;
    }

    return walk(_tree);
  }

  /// The fixed row height the TreeView uses (mirrors the build()-time calc).
  double _rowHeight() =>
      context.appLayout.treeRowExtent > context.touchTargetMin
      ? context.appLayout.treeRowExtent
      : context.touchTargetMin;

  /// Recompute the tree from the current collections state + search query, and
  /// force-expand matching folders while searching. Called outside of `build`
  /// to avoid mutating state during paint.
  void _rebuildTree() {
    final collections = context.read<CollectionsBloc>().state.collections;
    final query = _searchController.text;
    final filtered = _filterNodes(collections, query);
    if (query.isNotEmpty) {
      _preSearchExpandedIds ??= {..._expandedIds};
      _collectFolderIds(filtered, _expandedIds);
    } else if (_preSearchExpandedIds != null) {
      _expandedIds
        ..clear()
        ..addAll(_preSearchExpandedIds!);
      _preSearchExpandedIds = null;
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

  /// Coordinator for the OpenAPI / Swagger importer. Reads both blocs +
  /// [NetworkService] here (the dialog is bloc-agnostic), captures the
  /// messenger before the dialog, then dispatches the import to both blocs on
  /// commit — no bloc→bloc coupling.
  void _importSpec(BuildContext context) {
    final collectionsBloc = context.read<CollectionsBloc>();
    final environmentsBloc = context.read<EnvironmentsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      SpecImportDialog.show(
        context,
        networkService: context.read<NetworkService>(),
        onImport: (result) {
          collectionsBloc.add(ImportCollections([result.root]));
          if (result.environments.isNotEmpty) {
            environmentsBloc.add(ImportEnvironments(result.environments));
          }
          showAppSnackBarVia(messenger, 'Imported "${result.root.name}".');
          for (final w in result.warnings.take(1)) {
            // Surface the first warning so OAuth2/unsupported stays visible.
            showAppSnackBarVia(messenger, w);
          }
        },
      ),
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

    return MultiBlocListener(
      listeners: [
        BlocListener<CollectionsBloc, CollectionsState>(
          listenWhen: (prev, next) => prev.collections != next.collections,
          listener: (_, _) => _rebuildTree(),
        ),
        BlocListener<TabsBloc, TabsState>(
          listenWhen: (prev, next) =>
              _activeLinkedNodeId(prev) != _activeLinkedNodeId(next),
          listener: (_, state) =>
              _onSelectedNodeChanged(_activeLinkedNodeId(state)),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
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
                SizedBox(height: layout.tabSpacing),
                Row(
                  children: [
                    const BranchChip(),
                    const Spacer(),
                    context.appDecoration.wrapInteractive(
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.file_upload,
                          size: layout.iconSize,
                          color: theme.colorScheme.onSurface,
                        ),
                        tooltip: 'IMPORT',
                        color: theme.colorScheme.surface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            context.appShape.panelRadius,
                          ),
                          side: BorderSide(
                            color: theme.dividerColor,
                            width: layout.borderThick,
                          ),
                        ),
                        onSelected: (val) {
                          switch (val) {
                            case 'postman':
                              unawaited(_importCollections(context));
                            case 'openapi':
                              _importSpec(context);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'postman',
                            child: Text(
                              'FROM POSTMAN',
                              style: TextStyle(
                                fontSize: layout.fontSizeSmall,
                                fontWeight: context.appTypography.titleWeight,
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'openapi',
                            child: Text(
                              'FROM OPENAPI / SWAGGER',
                              style: TextStyle(
                                fontSize: layout.fontSizeSmall,
                                fontWeight: context.appTypography.titleWeight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: layout.tabSpacing),
                    const ReviewChangesButton(),
                  ],
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
                      verticalDetails: ScrollableDetails.vertical(
                        controller: _verticalController,
                      ),
                      // Indentation is applied manually in the row (see
                      // CollectionNodeRow) so the hover/drag highlight spans
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
                          return ExampleRow(
                            key: ValueKey('${item.nodeId}/${item.example.id}'),
                            nodeId: item.nodeId,
                            nodeName: item.nodeName,
                            example: item.example,
                            depth: node.depth ?? 0,
                            rowWidth: rowWidth,
                            rowHeight: rowHeight,
                          );
                        }
                        final nodeItem = item as _NodeItem;
                        return CollectionNodeRow(
                          key: ValueKey(nodeItem.node.id),
                          node: nodeItem.node,
                          isExpanded: node.isExpanded,
                          depth: node.depth ?? 0,
                          onToggle: () => _treeController.toggleNode(node),
                          rowWidth: rowWidth,
                          rowHeight: rowHeight,
                          isSelected: nodeItem.node.id == _selectedNodeId,
                        );
                      },
                    );
                    if (context.isPhone) return tree;
                    // Typed to NodeDragData (not a bare String) so a dragged
                    // TAB neither highlights nor gets accepted by the
                    // root-of-tree drop target (D4).
                    return DragTarget<NodeDragData>(
                      onAcceptWithDetails: (details) => context
                          .read<CollectionsBloc>()
                          .add(MoveNode(details.data.nodeId, null)),
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
