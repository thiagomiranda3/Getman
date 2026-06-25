import 'package:auris/auris_widgets.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Plain panel box: [AurisScheme.surfacePanel] fill +
/// [AurisScheme.borderResting] hairline + theme panel radius.
/// The `offset` parameter is ignored — auris has no hard brutalist shadow.
BoxDecoration aurisPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final radius =
      borderRadius ?? BorderRadius.circular(context.appShape.panelRadius);
  // Transitional theme guard: AppDecoration.lerp returns `this`, so this auris
  // closure can run while AurisScheme has been dropped (see _hasAurisScheme in
  // auris_components.dart). Fall back to a plain themed box, not a throw.
  final scheme = theme.extension<AurisScheme>();
  if (scheme == null) {
    return BoxDecoration(
      color: color ?? theme.cardColor,
      border: Border.all(
        color: theme.dividerColor,
        width: borderWidth ?? layout.borderThin,
      ),
      borderRadius: radius,
    );
  }
  return BoxDecoration(
    color: color ?? scheme.surfacePanel,
    border: Border.all(
      color: scheme.borderResting,
      width: borderWidth ?? layout.borderThin,
    ),
    borderRadius: radius,
  );
}

/// Browser-style tab: active = [AurisScheme.surfacePanel] + gold bottom
/// indicator; hovered = [AurisScheme.surfaceInset]; inactive = transparent.
BoxDecoration aurisTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  // Transitional theme guard (see aurisPanelBox): degrade to a plain themed tab
  // when AurisScheme is absent rather than throwing on every frame.
  final scheme = theme.extension<AurisScheme>();
  if (scheme == null) {
    return BoxDecoration(
      color: active
          ? theme.cardColor
          : (hovered ? theme.hoverColor : Colors.transparent),
      border: Border(
        bottom: BorderSide(
          color: active ? theme.primaryColor : Colors.transparent,
          width: layout.borderThick,
        ),
      ),
    );
  }

  // The inactive fill/indicator are a *same-hue, zero-alpha* color, NOT
  // `Colors.transparent`. The tab's `AnimatedContainer` lerps this fill toward
  // the opaque LIGHT hover/active surfaces; `Color.lerp` from premultiplied
  // black (`Colors.transparent` is RGB 0,0,0) lands on a muddy mid-gray that
  // flashes dark against AURIS's light surfaces (the reported light-mode hover
  // flicker; masked in dark mode). Keeping the same RGB at alpha 0 makes the
  // fade alpha-only, so it stays light throughout. Visually identical at rest.
  final Color bg;
  if (active) {
    bg = scheme.surfacePanel;
  } else if (hovered) {
    bg = scheme.surfaceInset;
  } else {
    bg = scheme.surfacePanel.withValues(alpha: 0);
  }

  return BoxDecoration(
    color: bg,
    border: Border(
      bottom: BorderSide(
        color: active
            ? scheme.primaryActive
            : scheme.primaryActive.withValues(alpha: 0),
        width: layout.borderThick,
      ),
    ),
  );
}

/// `BrandedTabBar` selected-tab indicator for AURIS.
///
/// AURIS composes the external `auris` kit, which never sets
/// `ThemeData.primaryColor`; in dark mode it therefore defaults to a dark
/// surface. The shared default indicator would paint that dark fill under the
/// (dark) `onPrimary` label, leaving the selected tab's text unreadable
/// (dark-on-dark — the reported bug on Settings / request-response /
/// collections tabs). We give the selected tab a light fill in dark mode
/// ([AurisScheme.textBright]) so the dark label reads as crisp light text, and
/// keep the gold fill in light mode (where the default already worked).
///
/// [topBorder] is dropped by the Settings tab strip (see
/// `BrandedTabBar.topIndicatorBorder`), which frames its tabs with dividers.
BoxDecoration aurisBrandedTabIndicator(
  BuildContext context, {
  bool topBorder = true,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final scheme = theme.extension<AurisScheme>();
  final isDark = theme.brightness == Brightness.dark;
  final fill = scheme == null
      ? theme.primaryColor
      : (isDark ? scheme.textBright : scheme.primaryActive);
  final borderColor = scheme?.borderBright ?? theme.dividerColor;
  return BoxDecoration(
    color: fill,
    border: Border(
      top: topBorder
          ? BorderSide(color: borderColor, width: layout.borderThick)
          : BorderSide.none,
      left: BorderSide(color: borderColor, width: layout.borderThick),
      right: BorderSide(color: borderColor, width: layout.borderThick),
    ),
  );
}

// ---------------------------------------------------------------------------
// Scaffold background
// ---------------------------------------------------------------------------
//
// The animated ambient (scanning HUD grid + radar sweep + drifting telemetry
// ticks) lives in `auris_ambient.dart` (`aurisScaffoldBackgroundAnimated` /
// `aurisStaticScaffoldBackground`). It was moved out of this file in Task 12 so
// the ambient could plumb `AmbientSignals` (pointer + session
// pulse) ONCE as the C1/C2 foundation; the prior scanline+hex wallpaper that
// lived here had no AmbientSignals wiring. `auris_theme.dart` imports the new
// file directly.

// ---------------------------------------------------------------------------
// Press feedback
// ---------------------------------------------------------------------------
//
// Press feedback is now the shared `SubtlePress`
// (lib/core/theme/themes/shared/subtle_press.dart), wired in `auris_theme.dart`'s
// `wrapInteractive`. The old AURIS-specific press widget was removed when all
// themes converged on the single subtle press.
