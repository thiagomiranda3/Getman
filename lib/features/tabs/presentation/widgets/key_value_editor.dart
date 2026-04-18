import 'package:flutter/material.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';

class KeyValueEditor extends StatefulWidget {
  final Map<String, String> items;
  final Function(Map<String, String>) onChanged;

  const KeyValueEditor({super.key, required this.items, required this.onChanged});

  @override
  State<KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<KeyValueEditor> {
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _keyControllers = [];
    _valControllers = [];
    
    for (var entry in widget.items.entries) {
      _keyControllers.add(TextEditingController(text: entry.key));
      _valControllers.add(TextEditingController(text: entry.value));
    }
    _keyControllers.add(TextEditingController());
    _valControllers.add(TextEditingController());
  }

  @override
  void didUpdateWidget(KeyValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSame(oldWidget.items, widget.items)) {
       _disposeControllers();
       _initControllers();
    }
  }

  bool _isSame(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (var key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  void _disposeControllers() {
    for (var c in _keyControllers) {
      c.dispose();
    }
    for (var c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _update() {
    final Map<String, String> map = {};
    for (int i = 0; i < _keyControllers.length; i++) {
      final key = _keyControllers[i].text;
      final val = _valControllers[i].text;
      if (key.isNotEmpty) {
        map[key] = val;
      }
    }
    widget.onChanged(map);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Theme.of(context).extension<LayoutExtension>()!;

    return ListView.builder(
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return _KeyValueRow(
          key: ValueKey(index),
          keyController: _keyControllers[index],
          valController: _valControllers[index],
          layout: layout,
          isLast: index == _keyControllers.length - 1,
          onKeyChanged: (val) {
            if (index == _keyControllers.length - 1 && val.isNotEmpty) {
               setState(() {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
               });
            }
            _update();
          },
          onValChanged: (val) => _update(),
          onDelete: () {
            setState(() {
               _keyControllers[index].dispose();
               _valControllers[index].dispose();
               _keyControllers.removeAt(index);
               _valControllers.removeAt(index);
               if (_keyControllers.isEmpty) {
                 _keyControllers.add(TextEditingController());
                 _valControllers.add(TextEditingController());
               }
               _update();
            });
          },
        );
      },
    );
  }
}

class _KeyValueRow extends StatefulWidget {
  final TextEditingController keyController;
  final TextEditingController valController;
  final LayoutExtension layout;
  final bool isLast;
  final Function(String) onKeyChanged;
  final Function(String) onValChanged;
  final VoidCallback onDelete;

  const _KeyValueRow({
    super.key,
    required this.keyController,
    required this.valController,
    required this.layout,
    required this.isLast,
    required this.onKeyChanged,
    required this.onValChanged,
    required this.onDelete,
  });

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: widget.layout.isCompact ? 8.0 : 12.0),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _isHovered ? theme.hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _isHovered ? theme.dividerColor.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'KEY', 
                  isDense: true, 
                  contentPadding: EdgeInsets.all(widget.layout.isCompact ? 8 : 12)
                ),
                controller: widget.keyController,
                onChanged: widget.onKeyChanged,
              ),
            ),
            SizedBox(width: widget.layout.isCompact ? 8 : 12),
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'VALUE', 
                  isDense: true, 
                  contentPadding: EdgeInsets.all(widget.layout.isCompact ? 8 : 12)
                ),
                controller: widget.valController,
                onChanged: widget.onValChanged,
              ),
            ),
            SizedBox(width: widget.layout.isCompact ? 4 : 8),
            IconButton(
              icon: Icon(Icons.delete_outline, size: widget.layout.isCompact ? 20 : 24, color: Colors.red),
              onPressed: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
