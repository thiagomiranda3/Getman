// A saved-example row rendered beneath its request node in the tree.
// Tapping opens the snapshot as a fresh, unlinked tab with its captured
// response shown; the trailing menu renames or deletes the example.
//
// Gotcha: the opened tab gets a fresh config id (via config.withId), not
// the saved request's id — chaining rules (assertions/extractions) are
// keyed by config id, so reusing the original id would silently alias an
// "Extract to {{var}}" or a re-send onto the original saved request (D3).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/presentation/widgets/example_menu.dart';
import 'package:getman/features/collections/presentation/widgets/node_drag_data.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:uuid/uuid.dart';

/// A saved-example row rendered beneath its request node. Tapping opens the
/// snapshot as a fresh (unlinked) tab with its captured response shown; the
/// trailing menu renames or deletes the example.
class ExampleRow extends StatefulWidget {
  const ExampleRow({
    required this.nodeId,
    required this.nodeName,
    required this.example,
    required this.depth,
    required this.rowWidth,
    required this.rowHeight,
    super.key,
  });
  final String nodeId;
  final String nodeName;
  final SavedExampleEntity example;
  final int depth;
  final double rowWidth;
  final double rowHeight;

  @override
  State<ExampleRow> createState() => _ExampleRowState();
}

class _ExampleRowState extends State<ExampleRow> {
  bool _isHovered = false;

  void _open(BuildContext context) {
    final cfg = widget.example.config;
    final response = cfg.statusCode != null
        ? HttpResponseEntity(
            statusCode: cfg.statusCode!,
            body: cfg.responseBody ?? '',
            headers: cfg.responseHeaders ?? const {},
            durationMs: cfg.durationMs ?? 0,
          )
        : null;
    // Opened unlinked (no collectionNodeId) so editing/re-sending a snapshot
    // never overwrites the saved request — AND with a fresh config id (mirrors
    // TabsBloc._onDuplicateTab): chaining rules (assertions/extractions) and
    // rule-runs are keyed by config id, so reusing the saved request's id
    // would silently alias its rules — "Extract to {{var}}" from this tab
    // would add a rule to the ORIGINAL saved request, and re-sending this tab
    // would run the original's assertions (D3).
    context.read<TabsBloc>().add(
      AddTab(
        config: cfg.withId(const Uuid().v4()),
        collectionName: '${widget.nodeName} · ${widget.example.name}',
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

    // Swallow-target: without it, a node released over an example row falls
    // through to the list-level root DragTarget and gets moved to the root.
    // Typed to NodeDragData (not a bare String) so a dragged TAB neither
    // highlights nor gets swallowed here (D4).
    return DragTarget<NodeDragData>(
      onAcceptWithDetails: (_) {},
      builder: (context, candidateData, rejectedData) =>
          _row(context, theme, layout, indent),
    );
  }

  Widget _row(
    BuildContext context,
    ThemeData theme,
    AppLayout layout,
    double indent,
  ) {
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
                        widget.example.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: layout.fontSizeSmall,
                          fontWeight: context.appTypography.bodyWeight,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    ExampleMenu(
                      nodeId: widget.nodeId,
                      exampleId: widget.example.id,
                      exampleName: widget.example.name,
                    ),
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
