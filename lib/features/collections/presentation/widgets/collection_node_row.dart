// A single collection-tree row (folder or request), with hover highlight,
// long-press action sheet on phone, and desktop drag-and-drop. Expansion is
// owned by the parent tree coordinator (CollectionsList): this row only
// reflects `isExpanded` and calls `onToggle` — it never tracks expansion
// itself (the H2 fix).
//
// Gotchas: drag targets always accept (never reject) so a release over a
// row doesn't fall through to the list-level root target and move the node
// to root; illegal moves (onto self/a descendant) are still visually
// rejected via onWillAcceptWithDetails and separately guarded by the bloc.
// Drag payload is the typed NodeDragData wrapper, not a bare String, so a
// dragged tab-strip tab is never highlighted or accepted here (D4/D5).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collection_node_menu.dart';
import 'package:getman/features/collections/presentation/widgets/node_action_sheet.dart';
import 'package:getman/features/collections/presentation/widgets/node_drag_data.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

/// A single collection-tree row (folder or request) with hover highlight and
/// drag-and-drop. Expansion is owned by the parent coordinator: this row only
/// reflects [isExpanded] and asks for a toggle via [onToggle]; it never tracks
/// expansion itself (the H2 fix).
class CollectionNodeRow extends StatefulWidget {
  const CollectionNodeRow({
    required this.node,
    required this.isExpanded,
    required this.depth,
    required this.onToggle,
    required this.rowWidth,
    required this.rowHeight,
    this.isSelected = false,
    super.key,
  });
  final CollectionNodeEntity node;
  final bool isExpanded;
  final int depth;
  final VoidCallback onToggle;
  final double rowWidth;
  final double rowHeight;

  /// Whether this row is the saved request linked to the currently-focused
  /// tab — painted with an accent bar + tint so the user can see which tree
  /// node their active tab came from.
  final bool isSelected;

  @override
  State<CollectionNodeRow> createState() => _CollectionNodeRowState();
}

class _CollectionNodeRowState extends State<CollectionNodeRow> {
  bool _isHovered = false;
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final node = widget.node;
    final isExpanded = widget.isExpanded;
    final indent = widget.depth * layout.depthPaddingMultiplier;
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
            onTap: widget.onToggle,
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
                      context.appMotion.treeExpandFlourish(
                        context,
                        expanded: isExpanded,
                        child: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: layout.smallIconSize,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      Icon(
                        node.isFavorite ? Icons.star : Icons.folder,
                        size: layout.iconSize,
                        // `colorScheme.primary` (the brand accent), not
                        // `primaryColor`: AURIS leaves `primaryColor` unset, so
                        // Material defaults it to `colorScheme.surface`
                        // (near-black) in dark mode — the star vanished into
                        // the background. Other themes set the two the same.
                        color: node.isFavorite
                            ? theme.colorScheme.primary
                            : theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          node.name,
                          style: TextStyle(
                            fontSize: layout.fontSizeNormal,
                            fontWeight: context.appTypography.displayWeight,
                          ),
                        ),
                      ),
                      CollectionNodeMenu(node: node),
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
          : DragTarget<NodeDragData>(
              // Always accept: rejecting (returning false) lets the release
              // fall through to the list-level root target, which would move
              // the node to the root — releasing a drag over its own row (the
              // natural "cancel" gesture) must be swallowed instead. Only
              // legal drops highlight; the bloc guards illegal moves too.
              // Typed to NodeDragData (not a bare String) so a dragged TAB
              // neither highlights this target nor gets accepted (D4).
              onWillAcceptWithDetails: (details) {
                final legal =
                    details.data.nodeId != node.id &&
                    !CollectionsTreeHelper.isDescendantOrSelf(
                      context.read<CollectionsBloc>().state.collections,
                      details.data.nodeId,
                      node.id,
                    );
                if (legal) setState(() => _isDragOver = true);
                return true;
              },
              onLeave: (_) => setState(() => _isDragOver = false),
              onAcceptWithDetails: (details) {
                setState(() => _isDragOver = false);
                if (details.data.nodeId == node.id) return; // self: swallow
                context.read<CollectionsBloc>().add(
                  MoveNode(details.data.nodeId, node.id),
                );
              },
              builder: (context, candidateData, rejectedData) =>
                  context.appMotion.treeDropHighlight(
                    context,
                    active: _isDragOver,
                    child: folderInner,
                  ),
            );
    } else {
      final leafInner = SizedBox(
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
                  color: widget.isSelected
                      ? theme.primaryColor.withValues(alpha: 0.12)
                      : (_isHovered ? theme.hoverColor : Colors.transparent),
                  border: widget.isSelected
                      ? Border(
                          left: BorderSide(
                            color: theme.primaryColor,
                            width: layout.borderThick,
                          ),
                        )
                      : null,
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
                          onTap: widget.onToggle,
                          child: context.appMotion.treeExpandFlourish(
                            context,
                            expanded: isExpanded,
                            child: Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.keyboard_arrow_right,
                              size: layout.smallIconSize,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        )
                      else
                        SizedBox(width: layout.smallIconSize),
                      MethodBadge(
                        // Non-HTTP kinds (WS/SSE/MCP) have no method — show the
                        // protocol label instead of a misleading "GET".
                        method: switch (node.config?.kind ?? RequestKind.http) {
                          RequestKind.http => node.config?.method ?? 'GET',
                          final kind => kind.label,
                        },
                        small: true,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          node.name,
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
                      CollectionNodeMenu(node: node),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      content = isPhone
          ? leafInner
          : DragTarget<NodeDragData>(
              // Always accept — see the folder target above for why rejecting
              // is unsafe (fall-through to the root target).
              // Typed to NodeDragData (not a bare String) so a dragged TAB
              // neither highlights this target nor gets accepted (D4).
              onWillAcceptWithDetails: (details) {
                // Mirrors the folder guard above: dropping an ANCESTOR folder
                // onto one of its own descendant requests must not highlight
                // — the bloc rejects the move regardless, so highlighting it
                // advertised a drop that would silently no-op (D5).
                final legal =
                    details.data.nodeId != node.id &&
                    !CollectionsTreeHelper.isDescendantOrSelf(
                      context.read<CollectionsBloc>().state.collections,
                      details.data.nodeId,
                      node.id,
                    );
                if (legal) setState(() => _isDragOver = true);
                return true;
              },
              onLeave: (_) => setState(() => _isDragOver = false),
              onAcceptWithDetails: (details) {
                setState(() => _isDragOver = false);
                if (details.data.nodeId == node.id) return; // self: swallow
                final bloc = context.read<CollectionsBloc>();
                // Dropping onto a request moves the dragged node into that
                // request's containing folder (or root when it sits at the top
                // level), so it lands beside the row instead of falling through
                // to the list-level root drop target.
                bloc.add(
                  MoveNode(
                    details.data.nodeId,
                    CollectionsTreeHelper.parentIdOf(
                      bloc.state.collections,
                      node.id,
                    ),
                  ),
                );
              },
              builder: (context, candidateData, rejectedData) =>
                  context.appMotion.treeDropHighlight(
                    context,
                    active: _isDragOver,
                    child: leafInner,
                  ),
            );
    }

    if (isPhone) return content;

    return Draggable<NodeDragData>(
      data: NodeDragData(node.id),
      feedback: context.appMotion.treeDragFeedback(
        context,
        child: Material(
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
              node.name,
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.displayWeight,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: content),
      child: content,
    );
  }
}
