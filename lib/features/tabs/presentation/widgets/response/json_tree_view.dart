// The TREE body mode: a collapsible, virtualized row list over already-
// decoded JSON, with per-node Copy value / Copy path (JSONPath) / Extract to
// {{var}}. flattenVisibleJsonTree is a pure, unit-testable flatten pass; the
// widget only caches the expanded-paths set, so callers that want expansion
// to survive rebuilds must keep passing the same `data` instance.
// The C2 toolbar (filter + expand/collapse-all) lives in _buildToolbar;
// filtering unions filter.ancestorPaths into the effective expansion without
// mutating the user's own _expanded set.
// The flatten pass never recurses past kTreeMaxDepth (stack-overflow guard,
// shared with json_tree_filter.dart's walks): content below the cap renders
// as a single "[nested too deep — N more levels]" leaf.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/core/utils/json_path_builder.dart';
import 'package:getman/features/tabs/presentation/widgets/response/json_tree_filter.dart';

/// A collapsible, virtualized tree view of decoded JSON. Each node offers
/// copy-value and copy-path (JSONPath) actions; container rows toggle on tap.
///
/// [onExtract] (optional) adds an "Extract to {{var}}" action carrying the
/// node's JSONPath — wired by the response pane to the chaining rules.
class JsonTreeView extends StatefulWidget {
  const JsonTreeView({
    required this.data,
    this.onExtract,
    this.filterFocusNode,
    @visibleForTesting this.maxDepth = kTreeMaxDepth,
    super.key,
  });

  /// Already-decoded JSON (object / array / scalar).
  final Object? data;

  /// Called with a node's JSONPath when the user picks "Extract to {{var}}".
  final void Function(String jsonPath)? onExtract;

  /// Focus node for the TREE filter field. C1's find button focuses it when
  /// the body mode is TREE. Owned (created/disposed) by the caller.
  final FocusNode? filterFocusNode;

  /// Recursion ceiling threaded into every walk (flatten / filter /
  /// expand-all planning). Production always uses [kTreeMaxDepth]; tests
  /// override it so the "[nested too deep]" marker is reachable on a
  /// shallow, cheap fixture.
  final int maxDepth;

  @override
  State<JsonTreeView> createState() => _JsonTreeViewState();
}

/// A single visible row in the JSON tree.
class JsonTreeNode {
  JsonTreeNode({
    required this.path,
    required this.label,
    required this.value,
    required this.depth,
    this.isDepthTruncation = false,
  });

  final String path;
  final String label;
  final Object? value;
  final int depth;

  /// True for the synthetic "[nested too deep — N more levels]" leaf emitted
  /// in place of content past the depth cap (see [kTreeMaxDepth]). Its
  /// [path] is not a JSONPath and it carries no value, so the row renders
  /// without a preview or an actions menu.
  final bool isDepthTruncation;

  bool get isContainer => value is Map || value is List;

  /// Compact preview shown to the right of the key.
  String get preview {
    if (isDepthTruncation) return '';
    final v = value;
    if (v is Map) return '{ ${v.length} }';
    if (v is List) return '[ ${v.length} ]';
    if (v is String) return '"$v"';
    return v == null ? 'null' : v.toString();
  }
}

/// Max nesting depth of [root]'s subtree, walked with an explicit stack so
/// the measurement itself can't overflow — feeds the "N more levels" count
/// in the depth-truncation marker. Direct children are 1 level below.
int _levelsBelow(Object? root) {
  var deepest = 0;
  final stack = <(Object?, int)>[(root, 0)];
  while (stack.isNotEmpty) {
    final (value, depth) = stack.removeLast();
    final children = value is Map
        ? value.values
        : value is List
        ? value
        : const <Object?>[];
    for (final child in children) {
      if (depth + 1 > deepest) deepest = depth + 1;
      if (child is Map || child is List) stack.add((child, depth + 1));
    }
  }
  return deepest;
}

/// The single leaf emitted in place of [parent]'s children when they would
/// render past the depth cap. The synthetic `#truncated` path suffix keeps
/// the row id unique per truncated container without colliding with any
/// JSONPath the builder can produce.
JsonTreeNode _depthTruncationNode(
  String parentPath,
  Object? parent,
  int depth,
) {
  final levels = _levelsBelow(parent);
  return JsonTreeNode(
    path: '$parentPath#truncated',
    label: levels == 1
        ? '[nested too deep — 1 more level]'
        : '[nested too deep — $levels more levels]',
    value: null,
    depth: depth,
    isDepthTruncation: true,
  );
}

/// Flattens [data] into the visible row list given the set of [expanded] paths.
/// Pure (no widget/state deps) so it is unit-testable and benchmarkable, and so
/// the view can memoize its result across rebuilds that don't change
/// data/expansion. Paths use [JsonPathBuilder] grammar.
///
/// When [filter] is non-null, only kept rows are emitted: matched nodes, their
/// ancestors, and descendants of matched nodes (so an expanded matched
/// container still shows its children).
///
/// Recursion never descends past [maxDepth] (default [kTreeMaxDepth], the
/// stack-overflow guard): an expanded container whose children would render
/// past the cap gets a single "[nested too deep — N more levels]" leaf
/// instead.
List<JsonTreeNode> flattenVisibleJsonTree({
  required Object? data,
  required Set<String> expanded,
  JsonTreeFilterResult? filter,
  int maxDepth = kTreeMaxDepth,
}) {
  final out = <JsonTreeNode>[];

  void flatten(
    Object? value,
    String path,
    String label,
    int depth, {
    required bool underMatch,
  }) {
    final kept =
        filter == null ||
        underMatch ||
        filter.matchedPaths.contains(path) ||
        filter.ancestorPaths.contains(path);
    if (!kept) return;
    out.add(JsonTreeNode(path: path, label: label, value: value, depth: depth));
    if (!expanded.contains(path)) return;
    final hasChildren = value is Map
        ? value.isNotEmpty
        : value is List && value.isNotEmpty;
    if (hasChildren && depth + 1 >= maxDepth) {
      // Depth guard (kTreeMaxDepth): don't recurse — stand in for the whole
      // subtree with one marker leaf.
      out.add(_depthTruncationNode(path, value, depth + 1));
      return;
    }
    final childUnderMatch =
        underMatch || (filter?.matchedPaths.contains(path) ?? false);
    if (value is Map) {
      for (final e in value.entries) {
        flatten(
          e.value,
          JsonPathBuilder.appendKey(path, e.key.toString()),
          e.key.toString(),
          depth + 1,
          underMatch: childUnderMatch,
        );
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        flatten(
          value[i],
          JsonPathBuilder.appendIndex(path, i),
          '[$i]',
          depth + 1,
          underMatch: childUnderMatch,
        );
      }
    }
  }

  if (data is Map) {
    for (final e in data.entries) {
      flatten(
        e.value,
        JsonPathBuilder.appendKey(JsonPathBuilder.root, e.key.toString()),
        e.key.toString(),
        0,
        underMatch: false,
      );
    }
  } else if (data is List) {
    for (var i = 0; i < data.length; i++) {
      flatten(
        data[i],
        JsonPathBuilder.appendIndex(JsonPathBuilder.root, i),
        '[$i]',
        0,
        underMatch: false,
      );
    }
  } else if (filter == null ||
      filter.matchedPaths.contains(JsonPathBuilder.root)) {
    out.add(
      JsonTreeNode(
        path: JsonPathBuilder.root,
        label: r'$',
        value: data,
        depth: 0,
      ),
    );
  }
  return out;
}

class _JsonTreeViewState extends State<JsonTreeView> {
  final Set<String> _expanded = {};

  // Cached flattened rows; invalidated only when data, expansion, or the
  // filter changes — not on theme/hover-driven rebuilds.
  List<JsonTreeNode>? _flat;

  // C2 filter state. The filter walk is recomputed synchronously on each
  // keystroke — TREE only exists under kLargeResponseViewerChars, so the walk
  // is bounded. While a filter is active, its ancestorPaths are unioned into
  // the effective expansion (a transient lens; the user's own expansion set
  // is restored untouched when the filter clears).
  //
  // Toggling is always relative to the *effective* expansion, but only paths
  // that are effectively expanded via `_expanded` itself get persisted there.
  // A path that's effectively expanded ONLY because it's a filter ancestor
  // never touches `_expanded` when toggled — collapsing/re-expanding it is
  // recorded in `_filterCollapsedOverrides` instead, a session-visual layer
  // scoped to the current filter. Without this split, tapping a
  // filter-revealed ancestor to collapse it would find it absent from
  // `_expanded` and *add* it (toggle sees "not expanded" -> "expand"),
  // silently persisting an expansion the user never asked for — so clearing
  // the filter would leave that node (and its children) visible when they
  // shouldn't be. Overrides are cleared whenever the filter clears, the
  // query text changes to a different value (a changed query IS a new
  // filter — a collapse recorded under the old query must not suppress
  // auto-expansion under the new one), or the data changes, so "clear filter
  // restores exactly the pre-filter expansion" holds.
  final TextEditingController _filterQuery = TextEditingController();
  JsonTreeFilterResult? _filter;
  final Set<String> _filterCollapsedOverrides = {};

  @override
  void initState() {
    super.initState();
    _filterQuery.addListener(_onFilterChanged);
    _seedExpansion();
  }

  @override
  void dispose() {
    _filterQuery.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(JsonTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _expanded.clear();
      _filterCollapsedOverrides.clear();
      _flat = null;
      _seedExpansion();
      // Re-run the live filter against the new data instance.
      _filter = _filterQuery.text.trim().isEmpty
          ? null
          : filterJsonTree(
              data: widget.data,
              query: _filterQuery.text,
              maxDepth: widget.maxDepth,
            );
    }
  }

  /// Last filter text acted on — a TextEditingController also notifies on
  /// SELECTION-only changes (clicking back into the field to refine the
  /// query), which must not clear the collapse overrides or re-run the
  /// filter: only an actual text change starts a new filter session.
  String? _lastFilterText;

  void _onFilterChanged() {
    if (_filterQuery.text == _lastFilterText) return;
    _lastFilterText = _filterQuery.text;
    setState(() {
      final next = _filterQuery.text.trim().isEmpty
          ? null
          : filterJsonTree(
              data: widget.data,
              query: _filterQuery.text,
              maxDepth: widget.maxDepth,
            );
      // The override layer is scoped to "the currently active filter" — ANY
      // query change (including to a different non-empty query, not just to
      // empty) starts a new filter session, so overrides from the previous
      // query must never carry over: otherwise a collapse recorded under
      // query A could keep suppressing auto-expansion for a match that only
      // exists under query B.
      _filterCollapsedOverrides.clear();
      _filter = next;
      _flat = null;
    });
  }

  void _expandAll() {
    final plan = planExpandAll(data: widget.data, maxDepth: widget.maxDepth);
    setState(() {
      _expanded
        ..clear()
        ..addAll(plan.containerPaths);
      _filterCollapsedOverrides.clear();
      _flat = null;
    });
    if (plan.limitedToDepth) {
      showAppSnackBar(context, 'Large tree — expanded to depth 3');
    }
  }

  void _collapseAll() {
    setState(() {
      _expanded.clear();
      _filterCollapsedOverrides.clear();
      _flat = null;
    });
  }

  /// Expand the root's direct container children so the first level is open.
  void _seedExpansion() {
    final root = widget.data;
    void addIfContainer(Object? v, String path) {
      if (v is Map || v is List) _expanded.add(path);
    }

    if (root is Map) {
      for (final e in root.entries) {
        addIfContainer(
          e.value,
          JsonPathBuilder.appendKey(JsonPathBuilder.root, e.key.toString()),
        );
      }
    } else if (root is List) {
      for (var i = 0; i < root.length; i++) {
        addIfContainer(
          root[i],
          JsonPathBuilder.appendIndex(JsonPathBuilder.root, i),
        );
      }
    }
  }

  void _toggle(String path) {
    setState(() {
      final filter = _filter;
      if (filter != null && filter.ancestorPaths.contains(path)) {
        // This node is open only because the active filter auto-expanded it
        // as an ancestor of a match — never persist a toggle of it into
        // `_expanded` (see the field-doc comment above `_filter`).
        if (!_filterCollapsedOverrides.remove(path)) {
          _filterCollapsedOverrides.add(path);
        }
      } else {
        if (!_expanded.remove(path)) _expanded.add(path);
      }
      _flat = null;
    });
  }

  void _copyValue(JsonTreeNode node) {
    final text = node.value is Map || node.value is List
        ? const JsonEncoder.withIndent('  ').convert(node.value)
        : node.value?.toString() ?? 'null';
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    showAppSnackBar(context, 'Value copied');
  }

  void _copyPath(JsonTreeNode node) {
    // Same guard as the extract action: a key the builder can't represent
    // (e.g. containing `]`) yields a path JsonPath will never parse — copying
    // it with a success snackbar would hand the user a broken rule input.
    if (!JsonPath.isValid(node.path)) {
      showAppSnackBar(context, 'This key cannot be expressed as a JSON path');
      return;
    }
    unawaited(Clipboard.setData(ClipboardData(text: node.path)));
    showAppSnackBar(context, 'Path copied: ${node.path}');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final layout = context.appLayout;
    final theme = Theme.of(context);
    final filter = _filter;
    final effectiveExpanded = filter == null
        ? _expanded
        : ({..._expanded, ...filter.ancestorPaths}
            ..removeAll(_filterCollapsedOverrides));
    final nodes = _flat ??= flattenVisibleJsonTree(
      data: widget.data,
      expanded: effectiveExpanded,
      filter: filter,
      maxDepth: widget.maxDepth,
    );

    return ColoredBox(
      color: palette.codeBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(context),
          if (filter != null && filter.truncated)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
              child: Text(
                'Refine filter to see more',
                key: const ValueKey('tree_filter_truncated'),
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              primary: false,
              padding: EdgeInsets.symmetric(vertical: layout.tabSpacing),
              itemCount: nodes.length,
              itemBuilder: (context, i) => _TreeRow(
                node: nodes[i],
                expanded: effectiveExpanded.contains(nodes[i].path),
                onToggle: () => _toggle(nodes[i].path),
                onCopyValue: () => _copyValue(nodes[i]),
                onCopyPath: () => _copyPath(nodes[i]),
                onExtract: widget.onExtract == null
                    ? null
                    : () => widget.onExtract!(nodes[i].path),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// C2 toolbar: filter field (+ match count suffix) and expand/collapse-all.
  Widget _buildToolbar(BuildContext context) {
    final layout = context.appLayout;
    final filter = _filter;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding,
        layout.tabSpacing,
        layout.pagePadding,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('tree_filter_field'),
              controller: _filterQuery,
              focusNode: widget.filterFocusNode,
              decoration: InputDecoration(
                hintText: 'FILTER...',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: layout.iconSize),
                suffixText: filter == null
                    ? null
                    : (filter.matchCount == 1
                          ? '1 MATCH'
                          : '${filter.matchCount} MATCHES'),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: layout.inputPadding,
                  vertical: layout.inputPaddingVertical,
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('tree_expand_all'),
            tooltip: 'Expand all',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.unfold_more, size: layout.iconSize),
            onPressed: _expandAll,
          ),
          IconButton(
            key: const ValueKey('tree_collapse_all'),
            tooltip: 'Collapse all',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.unfold_less, size: layout.iconSize),
            onPressed: _collapseAll,
          ),
        ],
      ),
    );
  }
}

class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.node,
    required this.expanded,
    required this.onToggle,
    required this.onCopyValue,
    required this.onCopyPath,
    required this.onExtract,
  });

  final JsonTreeNode node;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onCopyValue;
  final VoidCallback onCopyPath;
  final VoidCallback? onExtract;

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final palette = context.appPalette;
    final typography = context.appTypography;
    final node = widget.node;
    final indent = layout.pagePadding + node.depth * (layout.pagePadding * 1.2);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: node.isContainer ? widget.onToggle : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(indent, 2, layout.pagePadding, 2),
          child: Row(
            children: [
              SizedBox(
                width: layout.iconSize,
                child: node.isContainer
                    ? Icon(
                        widget.expanded
                            ? Icons.arrow_drop_down
                            : Icons.arrow_right,
                        size: layout.iconSize,
                        color: theme.colorScheme.onSurface,
                      )
                    : null,
              ),
              SizedBox(width: layout.tabSpacing),
              Text(
                node.label,
                style: TextStyle(
                  fontFamily: typography.codeFontFamily,
                  fontSize: layout.fontSizeCode,
                  color: theme.colorScheme.primary,
                  fontWeight: typography.titleWeight,
                ),
              ),
              SizedBox(width: layout.tabSpacing),
              Flexible(
                child: Text(
                  node.preview,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: typography.codeFontFamily,
                    fontSize: layout.fontSizeCode,
                    color: node.isContainer
                        ? theme.colorScheme.secondary
                        : palette.variableResolved,
                  ),
                ),
              ),
              // The depth-truncation marker is informational only: it has no
              // value to copy and no JSONPath, so it gets no actions menu.
              if (!node.isDepthTruncation)
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0.25,
                  duration: const Duration(milliseconds: 120),
                  child: PopupMenuButton<String>(
                    key: ValueKey('tree_menu_${node.path}'),
                    tooltip: 'Node actions',
                    icon: Icon(
                      Icons.more_vert,
                      size: layout.iconSize,
                      color: theme.colorScheme.onSurface,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (action) {
                      switch (action) {
                        case 'value':
                          widget.onCopyValue();
                        case 'path':
                          widget.onCopyPath();
                        case 'extract':
                          widget.onExtract?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'value',
                        child: Text('Copy value'),
                      ),
                      const PopupMenuItem(
                        value: 'path',
                        child: Text('Copy path'),
                      ),
                      if (widget.onExtract != null)
                        const PopupMenuItem(
                          value: 'extract',
                          child: Text('Extract to {{var}}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
