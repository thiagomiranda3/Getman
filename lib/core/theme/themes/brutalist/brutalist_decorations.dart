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
    border: Border.all(color: border, width: borderWidth ?? layout.borderThin),
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
  final BorderSide rule = BorderSide(color: border, width: 1);
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

Widget brutalistScaffoldBackground(BuildContext context, {required Widget child}) => child;

Widget brutalistDoubleRule(BuildContext context) {
  final layout = context.appLayout;
  final color = Theme.of(context).dividerColor;
  return Container(height: layout.borderThick, color: color);
}
