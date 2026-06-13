import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';

/// Generic editable key/value row list backing the params, headers, and
/// environment-variable editors. The canonical value type [T] (ordered list,
/// map, …) is supplied via a codec:
///
/// - [decode] turns [items] into ordered (key, value) rows;
/// - [encode] turns the current rows back into a [T] for [onChanged];
/// - [equals] compares two [T]s in canonical space.
///
/// Echo suppression: when the parent echoes back exactly what this editor
/// just emitted (the usual BLoC round-trip), the text controllers are NOT
/// rebuilt — that keeps focus and half-typed state alive. Only a genuinely
/// external change resets the rows. See CLAUDE.md §6.
class KeyValueListEditor<T extends Object> extends StatefulWidget {
  final T items;
  final ValueChanged<T> onChanged;
  final List<(String, String)> Function(T items) decode;
  final T Function(List<(String, String)> rows) encode;
  final bool Function(T a, T b) equals;

  const KeyValueListEditor({
    super.key,
    required this.items,
    required this.onChanged,
    required this.decode,
    required this.encode,
    required this.equals,
  });

  @override
  State<KeyValueListEditor<T>> createState() => _KeyValueListEditorState<T>();
}

class _KeyValueListEditorState<T extends Object> extends State<KeyValueListEditor<T>> {
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;
  T? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.decode(widget.items));
  }

  void _initControllers(List<(String, String)> rows) {
    _keyControllers = [for (final (key, _) in rows) TextEditingController(text: key)];
    _valControllers = [for (final (_, value) in rows) TextEditingController(text: value)];
    _addEmptyRow();
  }

  void _addEmptyRow() {
    _keyControllers.add(TextEditingController());
    _valControllers.add(TextEditingController());
  }

  @override
  void didUpdateWidget(KeyValueListEditor<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lastEmitted = _lastEmitted;
    if (lastEmitted != null && widget.equals(widget.items, lastEmitted)) {
      return;
    }
    if (widget.equals(widget.items, oldWidget.items)) {
      return;
    }
    _disposeControllers();
    _initControllers(widget.decode(widget.items));
    _lastEmitted = null;
  }

  void _disposeControllers() {
    for (final c in _keyControllers) {
      c.dispose();
    }
    for (final c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _emit() {
    final rows = [
      for (int i = 0; i < _keyControllers.length; i++)
        (_keyControllers[i].text, _valControllers[i].text),
    ];
    final value = widget.encode(rows);
    _lastEmitted = value;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return ListView.builder(
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return _KeyValueRow(
          key: ValueKey(_keyControllers[index]),
          keyController: _keyControllers[index],
          valController: _valControllers[index],
          layout: layout,
          onKeyChanged: (val) {
            if (index == _keyControllers.length - 1 && val.isNotEmpty) {
              setState(_addEmptyRow);
            }
            _emit();
          },
          onValChanged: (_) => _emit(),
          onDelete: () {
            setState(() {
              _keyControllers.removeAt(index).dispose();
              _valControllers.removeAt(index).dispose();
              if (_keyControllers.isEmpty) {
                _addEmptyRow();
              }
              _emit();
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
  final AppLayout layout;
  final ValueChanged<String> onKeyChanged;
  final ValueChanged<String> onValChanged;
  final VoidCallback onDelete;

  const _KeyValueRow({
    super.key,
    required this.keyController,
    required this.valController,
    required this.layout,
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
    final isPhone = context.isPhone;
    final fieldPadding = EdgeInsets.all(widget.layout.isCompact ? 8 : 12);
    final textStyle = TextStyle(
      fontSize: widget.layout.fontSizeNormal,
      fontWeight: context.appTypography.titleWeight,
    );

    final keyField = TextField(
      style: textStyle,
      decoration: InputDecoration(
        hintText: 'KEY',
        isDense: true,
        contentPadding: fieldPadding,
      ),
      controller: widget.keyController,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      onChanged: widget.onKeyChanged,
    );
    final valueField = TextField(
      style: textStyle,
      decoration: InputDecoration(
        hintText: 'VALUE',
        isDense: true,
        contentPadding: fieldPadding,
      ),
      controller: widget.valController,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      onChanged: widget.onValChanged,
    );
    final deleteButton = context.appDecoration.wrapInteractive(
      child: IconButton(
        icon: Icon(
          Icons.delete_outline,
          size: widget.layout.isCompact ? 20 : 24,
          color: theme.colorScheme.error,
        ),
        onPressed: widget.onDelete,
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: widget.layout.isCompact ? 8.0 : 12.0),
        padding: EdgeInsets.symmetric(horizontal: isPhone ? 8 : 4, vertical: isPhone ? 8 : 2),
        decoration: BoxDecoration(
          color: _isHovered ? theme.hoverColor : (isPhone ? theme.colorScheme.surface : Colors.transparent),
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          border: Border.all(
            color: isPhone
                ? theme.dividerColor.withValues(alpha: 0.6)
                : (_isHovered ? theme.dividerColor.withValues(alpha: 0.5) : Colors.transparent),
            width: widget.layout.borderThin,
          ),
        ),
        child: isPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: keyField),
                      deleteButton,
                    ],
                  ),
                  SizedBox(height: widget.layout.tabSpacing),
                  valueField,
                ],
              )
            : Row(
                children: [
                  Expanded(child: keyField),
                  SizedBox(width: widget.layout.isCompact ? 8 : 12),
                  Expanded(child: valueField),
                  SizedBox(width: widget.layout.isCompact ? 4 : 8),
                  deleteButton,
                ],
              ),
      ),
    );
  }
}
