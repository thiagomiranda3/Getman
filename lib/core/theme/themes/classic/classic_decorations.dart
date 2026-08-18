// AppDecoration closures for Classic: a flat native-style panelBox (hairline
// border + subtle soft shadow, no brutalist offset), a browser-tab-style
// tabShape, and an identity scaffoldBackground (no ambient wallpaper — the
// calm, native default).

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
/// hovered = subtle bg tint; inactive = alpha-0 of the active surfaces. No
/// per-column rules.
BoxDecoration classicTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final accent = theme.colorScheme.primary;
  // The inactive fill/indicator are a *same-hue, zero-alpha* color, NOT
  // `Colors.transparent`. The tab's `AnimatedContainer` lerps this fill toward
  // the opaque active/hover surfaces; `Color.lerp` from premultiplied black
  // (`Colors.transparent` is RGB 0,0,0) lands on a muddy mid-gray that flashes
  // dark on every tab switch (the documented AURIS transparent-lerp gotcha —
  // see auris_decorations.dart's tabShape). Keeping the same RGB at alpha 0
  // makes the fade alpha-only. Visually identical at rest.
  final Color bg;
  if (active) {
    bg = theme.cardColor;
  } else if (hovered) {
    bg = theme.hoverColor;
  } else {
    bg = theme.cardColor.withValues(alpha: 0);
  }
  return BoxDecoration(
    color: bg,
    border: Border(
      bottom: BorderSide(
        color: active ? accent : accent.withValues(alpha: 0),
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
