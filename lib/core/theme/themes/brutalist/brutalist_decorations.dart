import 'package:flutter/material.dart';
import '../../app_theme.dart';

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
    border: Border.all(color: border, width: borderWidth ?? layout.borderThick),
    boxShadow: [
      BoxShadow(
        color: border,
        offset: Offset(offset ?? layout.borderHeavy, offset ?? layout.borderHeavy),
        blurRadius: 0,
      ),
    ],
  );
}

BoxDecoration brutalistTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final border = theme.dividerColor;
  final Color background;
  if (active) {
    background = theme.primaryColor;
  } else if (hovered) {
    background = theme.dividerColor.withValues(alpha: 0.2);
  } else {
    background = theme.cardColor;
  }
  return BoxDecoration(
    color: background,
    border: Border(
      right: BorderSide(color: border, width: layout.borderThick),
      bottom: active ? BorderSide.none : BorderSide(color: border, width: layout.borderThick),
      top: active ? BorderSide(color: border, width: layout.borderThick) : BorderSide.none,
    ),
  );
}
