import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';

class CodeFindPanel extends StatefulWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const CodeFindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  @override
  State<CodeFindPanel> createState() => _CodeFindPanelState();

  @override
  Size get preferredSize => controller.value == null ? Size.zero : const Size.fromHeight(54);
}

class _CodeFindPanelState extends State<CodeFindPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.value == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller.findInputController,
              focusNode: widget.controller.findInputFocusNode,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'FIND...',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: layout.iconSize),
                suffixText: (widget.controller.value?.result?.matches.length ?? 0) > 0 
                  ? '${(widget.controller.value?.result?.index ?? 0) + 1}/${widget.controller.value?.result?.matches.length}' 
                  : '0/0',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: (value) => widget.controller.nextMatch(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_up, size: layout.iconSize),
            onPressed: () => widget.controller.previousMatch(),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, size: layout.iconSize),
            onPressed: () => widget.controller.nextMatch(),
          ),
          IconButton(
            icon: Icon(Icons.close, size: layout.iconSize),
            onPressed: () => widget.controller.close(),
          ),
        ],
      ),
    );
  }
}
