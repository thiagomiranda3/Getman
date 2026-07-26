// Magnifier-toggled filter bar for the response HEADERS/COOKIES tables — the
// C1 "find everywhere" affordance for table modes (ResponseBodyControls only
// renders on the BODY tab, so these tables carry their own find button).
// Toggling open shows a TextField that reports its query via onQueryChanged;
// toggling closed clears the query so the host restores all rows. The
// TextField's contentPadding routes through AppLayout.inputPadding /
// inputPaddingVertical (matching json_tree_view.dart's filter field) rather
// than a hardcoded EdgeInsets literal — theme adherence mandate.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// A magnifier icon that expands into a row-filter [TextField].
///
/// The host filters its rows by name+value case-insensitive contains on the
/// string reported through [onQueryChanged] (`''` = no filter).
class ResponseRowFilterBar extends StatefulWidget {
  const ResponseRowFilterBar({required this.onQueryChanged, super.key});

  /// Reports the current filter query; `''` when cleared or closed.
  final ValueChanged<String> onQueryChanged;

  @override
  State<ResponseRowFilterBar> createState() => _ResponseRowFilterBarState();
}

class _ResponseRowFilterBarState extends State<ResponseRowFilterBar> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _open = false;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      if (_open) {
        _focus.requestFocus();
      } else {
        _query.clear();
        widget.onQueryChanged('');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.pagePadding,
        vertical: layout.tabSpacing,
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('row_filter_toggle'),
            tooltip: 'Filter rows',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _open ? Icons.search_off : Icons.search,
              size: layout.iconSize,
            ),
            onPressed: _toggle,
          ),
          if (_open)
            Expanded(
              child: TextField(
                key: const ValueKey('row_filter_field'),
                controller: _query,
                focusNode: _focus,
                onChanged: widget.onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'FILTER...',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: layout.inputPadding,
                    vertical: layout.inputPaddingVertical,
                  ),
                ),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }
}
