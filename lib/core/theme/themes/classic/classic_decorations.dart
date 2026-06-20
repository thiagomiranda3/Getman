import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Flat native-style card: surface fill + 1px hairline border + a very subtle
/// soft shadow (no hard brutalist offset). Radius defaults to the theme's
/// panel radius.
BoxDecoration classicPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final shape = context.appShape;
  final isDark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: color ?? theme.cardColor,
    borderRadius: borderRadius ?? BorderRadius.circular(shape.panelRadius),
    border: Border.all(
      color: theme.dividerColor,
      width: borderWidth ?? layout.borderThin,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
        blurRadius: 6,
        offset: const Offset(0, 1),
      ),
    ],
  );
}

/// Browser/editor-style tab: active = surface fill + accent bottom indicator;
/// hovered = subtle bg tint; inactive = transparent. No per-column rules.
BoxDecoration classicTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final accent = theme.colorScheme.primary;
  final Color bg;
  if (active) {
    bg = theme.cardColor;
  } else if (hovered) {
    bg = theme.hoverColor;
  } else {
    bg = Colors.transparent;
  }
  return BoxDecoration(
    color: bg,
    border: Border(
      bottom: BorderSide(
        color: active ? accent : Colors.transparent,
        width: layout.borderThick,
      ),
    ),
  );
}

/// Plain scaffold — no dot grid, no sparkles. Identity wrapper.
Widget classicScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) => child;
