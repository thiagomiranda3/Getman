// AppDecoration closures for Brutalist: panelBox (hard offset ink-shadow,
// thick border) and tabShape (per-column rules, active tab filled with
// primaryColor). No scaffold-background/frost hooks here — the animated
// halftone wallpaper lives in brutalist_ambient.dart.

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

BoxDecoration brutalistPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final shape = context.appShape;
  final border = theme.dividerColor;
  return BoxDecoration(
    color: color ?? theme.cardColor,
    borderRadius: borderRadius ?? BorderRadius.circular(shape.panelRadius),
    border: Border.all(color: border, width: borderWidth ?? layout.borderThin),
    boxShadow: [
      BoxShadow(
        color: border,
        offset: Offset(
          offset ?? layout.borderHeavy,
          offset ?? layout.borderHeavy,
        ),
      ),
    ],
  );
}

BoxDecoration brutalistTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final border = theme.dividerColor;
  final Color background;
  if (active) {
    background = theme.primaryColor;
  } else if (hovered) {
    background = theme.dividerColor.withValues(alpha: 0.2);
  } else {
    background = theme.cardColor;
  }
  final rule = BorderSide(color: border);
  return BoxDecoration(
    color: background,
    border: Border(
      left: isFirst ? rule : BorderSide.none,
      right: rule,
      bottom: active ? BorderSide.none : rule,
      top: active ? rule : BorderSide.none,
    ),
  );
}
