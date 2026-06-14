import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

class MethodBadge extends StatelessWidget {
  final String method;
  final bool small;
  const MethodBadge({super.key, required this.method, this.small = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final color = context.appPalette.methodColor(method);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
      ),
      child: Text(
        method,
        style: TextStyle(
          // Contrast against the per-method color, not a fixed onPrimary (a11y).
          color: context.appPalette.methodOn(method),
          fontWeight: context.appTypography.displayWeight,
          fontSize: small ? layout.fontSizeSmall : layout.fontSizeNormal,
        ),
      ),
    );
  }
}
