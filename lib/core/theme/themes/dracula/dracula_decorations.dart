// AppDecoration closures for Dracula: a clean/flat panelBox (rounded corners,
// thin border, soft blurred shadow — no brutalist offset), a VS Code-style
// tabShape (top accent line on the active tab, no bottom rule), and an
// identity scaffoldBackground (no ambient wallpaper — clean & flat visual
// personality, no animated background per design).

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Clean & flat panel: rounded corners, a thin border, and a soft blurred drop
/// shadow (no brutalist hard offset). Honors the optional [color],
/// [borderWidth] and [borderRadius] overrides; [offset] is accepted for API
/// parity but the shadow is intentionally a gentle, near-centered blur.
BoxDecoration draculaPanelBox(
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
  final isDark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: color ?? theme.cardColor,
    borderRadius: borderRadius ?? BorderRadius.circular(shape.panelRadius),
    border: Border.all(color: border, width: borderWidth ?? layout.borderThin),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.10),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

/// VS Code-style tab: the active tab keeps the surface color and grows a purple
/// accent line on top (no bottom rule); hover gets a subtle selection-color
/// tint; inactive tabs sit flush on the scaffold background.
BoxDecoration draculaTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final border = theme.dividerColor;
  final accent = theme.primaryColor;
  final Color background;
  if (active) {
    background = theme.cardColor;
  } else if (hovered) {
    background = border.withValues(alpha: 0.25);
  } else {
    background = theme.scaffoldBackgroundColor;
  }

  final rule = BorderSide(color: border);
  return BoxDecoration(
    color: background,
    border: Border(
      left: isFirst ? rule : BorderSide.none,
      right: rule,
      bottom: active ? BorderSide.none : rule,
      top: active
          ? BorderSide(color: accent, width: layout.borderThick)
          : BorderSide.none,
    ),
  );
}

/// Clean & flat: no animated background — render the app as-is.
Widget draculaScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) => child;
