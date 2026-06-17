import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/utils/json_path_builder.dart';

/// A collapsible, virtualized tree view of decoded JSON. Each node offers
/// copy-value and copy-path (JSONPath) actions; container rows toggle on tap.
///
/// [onExtract] (optional) adds an "Extract to {{var}}" action carrying the
/// node's JSONPath — wired by the response pane to the chaining rules.
class JsonTreeView extends StatefulWidget {
  const JsonTreeView({required this.data, this.onExtract, super.key});

  /// Already-decoded JSON (object / array / scalar).
  final Object? data;

  /// Called with a node's JSONPath when the user picks "Extract to {{var}}".
  final void Function(String jsonPath)? onExtract;

  @override
  State<JsonTreeView> createState() => _JsonTreeViewState();
}

class _JsonTreeViewState extends State<JsonTreeView> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _seedExpansion();
  }

  @override
  void didUpdateWidget(JsonTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _expanded.clear();
      _seedExpansion();
    }
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

  List<_Node> _visible() {
    final out = <_Node>[];
    final root = widget.data;
    if (root is Map) {
      _addMap(root, JsonPathBuilder.root, 0, out);
    } else if (root is List) {
      _addList(root, JsonPathBuilder.root, 0, out);
    } else {
      out.add(
        _Node(path: JsonPathBuilder.root, label: r'$', value: root, depth: 0),
      );
    }
    return out;
  }

  void _flatten(
    Object? value,
    String path,
    String label,
    int depth,
    List<_Node> out,
  ) {
    out.add(_Node(path: path, label: label, value: value, depth: depth));
    if (!_expanded.contains(path)) return;
    if (value is Map) {
      _addMap(value, path, depth + 1, out);
    } else if (value is List) {
      _addList(value, path, depth + 1, out);
    }
  }

  void _addMap(
    Map<dynamic, dynamic> map,
    String path,
    int depth,
    List<_Node> out,
  ) {
    for (final e in map.entries) {
      _flatten(
        e.value,
        JsonPathBuilder.appendKey(path, e.key.toString()),
        e.key.toString(),
        depth,
        out,
      );
    }
  }

  void _addList(List<dynamic> list, String path, int depth, List<_Node> out) {
    for (var i = 0; i < list.length; i++) {
      _flatten(
        list[i],
        JsonPathBuilder.appendIndex(path, i),
        '[$i]',
        depth,
        out,
      );
    }
  }

  void _toggle(String path) {
    setState(() {
      if (!_expanded.remove(path)) _expanded.add(path);
    });
  }

  void _copyValue(_Node node) {
    final text = node.value is Map || node.value is List
        ? const JsonEncoder.withIndent('  ').convert(node.value)
        : node.value?.toString() ?? 'null';
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    showAppSnackBar(context, 'Value copied');
  }

  void _copyPath(_Node node) {
    unawaited(Clipboard.setData(ClipboardData(text: node.path)));
    showAppSnackBar(context, 'Path copied: ${node.path}');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final nodes = _visible();

    return ColoredBox(
      color: palette.codeBackground,
      child: ListView.builder(
        primary: false,
        padding: EdgeInsets.symmetric(vertical: context.appLayout.tabSpacing),
        itemCount: nodes.length,
        itemBuilder: (context, i) => _TreeRow(
          node: nodes[i],
          expanded: _expanded.contains(nodes[i].path),
          onToggle: () => _toggle(nodes[i].path),
          onCopyValue: () => _copyValue(nodes[i]),
          onCopyPath: () => _copyPath(nodes[i]),
          onExtract: widget.onExtract == null
              ? null
              : () => widget.onExtract!(nodes[i].path),
        ),
      ),
    );
  }
}

class _Node {
  _Node({
    required this.path,
    required this.label,
    required this.value,
    required this.depth,
  });

  final String path;
  final String label;
  final Object? value;
  final int depth;

  bool get isContainer => value is Map || value is List;

  /// Compact preview shown to the right of the key.
  String get preview {
    final v = value;
    if (v is Map) return '{ ${v.length} }';
    if (v is List) return '[ ${v.length} ]';
    if (v is String) return '"$v"';
    return v == null ? 'null' : v.toString();
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

  final _Node node;
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
