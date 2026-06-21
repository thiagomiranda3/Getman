import 'dart:async';

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

  final Color bg;
  if (active) {
    bg = scheme.surfacePanel;
  } else if (hovered) {
    bg = scheme.surfaceInset;
  } else {
    bg = Colors.transparent;
  }

  return BoxDecoration(
    color: bg,
    border: Border(
      bottom: BorderSide(
        color: active ? scheme.primaryActive : Colors.transparent,
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
// the ambient could plumb `AmbientSignals` (pointer + click impulses + session
// pulse) ONCE as the C1/C2 foundation; the prior scanline+hex wallpaper that
// lived here had no AmbientSignals wiring. `auris_theme.dart` imports the new
// file directly.

// ---------------------------------------------------------------------------
// Press feedback
// ---------------------------------------------------------------------------

/// Auris-flavored press feedback: a quick scale-down on tap-down.
///
/// Like `GlassPress`, the [AnimationController] is created in `initState` and
/// kept for the State's lifetime — never disposed + recreated when `animate`
/// toggles (the SingleTickerProvider-one-ticker invariant). We merely
/// forward/reverse it; in reduced mode we just let it sit idle.
class AurisPress extends StatefulWidget {
  const AurisPress({
    required this.child,
    required this.animate,
    super.key,
    this.onTap,
    this.scaleDown,
  });

  final Widget child;
  final bool animate;
  final VoidCallback? onTap;
  final double? scaleDown;

  @override
  State<AurisPress> createState() => _AurisPressState();
}

class _AurisPressState extends State<AurisPress>
    with SingleTickerProviderStateMixin {
  // Built in initState — never recreated (see glass_press.dart for rationale).
  late final AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AurisTokens.durationFast, // 120 ms — crisp
    );
    _scale = _buildScale();
  }

  Animation<double> _buildScale() =>
      Tween<double>(
        begin: 1,
        end: widget.scaleDown ?? 0.97,
      ).animate(
        CurvedAnimation(parent: _controller, curve: AurisTokens.curveDefault),
      );

  @override
  void didUpdateWidget(AurisPress old) {
    super.didUpdateWidget(old);
    if (old.scaleDown != widget.scaleDown) _scale = _buildScale();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      // Reduced mode: plain tap target, no animation.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        unawaited(_controller.reverse());
        widget.onTap?.call();
      },
      onTapCancel: _controller.reverse,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
