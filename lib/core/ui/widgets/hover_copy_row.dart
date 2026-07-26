// Hover-copy affordance shared by every theme's dataRow component slot
// (response HEADERS/COOKIES rows): wraps a row and reveals a copy icon on
// mouse hover that puts the row's VALUE on the clipboard (tooltip
// 'Copy value', snackbar 'Value copied'). Used by app_components_defaults
// and every per-theme dataRow override so C3 behaves identically across
// themes — new themes get it by wrapping their bespoke row in this atom.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';

/// Wraps a data row (header/cookie) and reveals a copy icon on hover that
/// copies [value] — always the row's VALUE, never the label — to the
/// clipboard. Desktop-first: the affordance is hover-driven; the wrapped
/// row's own content and hit-testing are untouched.
class HoverCopyRow extends StatefulWidget {
  const HoverCopyRow({required this.value, required this.child, super.key});

  /// The text placed on the clipboard when the copy icon is pressed.
  final String value;

  /// The themed row rendering (any theme's bespoke row widget).
  final Widget child;

  @override
  State<HoverCopyRow> createState() => _HoverCopyRowState();
}

class _HoverCopyRowState extends State<HoverCopyRow> {
  bool _hovered = false;

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: widget.value));
    showAppSnackBarVia(messenger, 'Value copied');
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: [
          widget.child,
          if (_hovered)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              // Center + a transparency Material: rows can be shorter than
              // the icon's tap target, and IconButton needs a Material
              // ancestor inside themed (non-Material) panel boxes.
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: IconButton(
                    key: const ValueKey('row_copy_value_button'),
                    tooltip: 'Copy value',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.copy_outlined,
                      size: layout.smallIconSize,
                    ),
                    onPressed: () => unawaited(_copy()),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
