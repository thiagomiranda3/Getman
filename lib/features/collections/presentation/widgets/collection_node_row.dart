import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collection_node_menu.dart';
import 'package:getman/features/collections/presentation/widgets/node_action_sheet.dart';
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
    super.key,
  });
  final CollectionNodeEntity node;
  final bool isExpanded;
  final int depth;
  final VoidCallback onToggle;
  final double rowWidth;
  final double rowHeight;

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
                          onTap: widget.onToggle,
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
            node.name,
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
