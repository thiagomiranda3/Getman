// The AppDecoration theme extension: panelBox (hard-shadow/thick-border
// panel), tabShape (per-tab chrome), wrapInteractive (tap animation
// wrapper), scaffoldBackground (ambient), plus the optional frost
// (frosted-glass blur), brandedTabIndicator (BrandedTabBar selected-tab
// override), and dialogSurface (custom frosted dialog card) hooks. frost /
// brandedTabIndicator / dialogSurface default to identity/null, so only
// themes that opt in (chiefly Liquid Glass, plus AURIS for
// brandedTabIndicator) are affected.
import 'package:flutter/material.dart';

typedef PanelBoxBuilder =
    BoxDecoration Function(
      BuildContext context, {
      Color? color,
      double? borderWidth,
      double? offset,
      BorderRadius? borderRadius,
    });

typedef TabShapeBuilder =
    BoxDecoration Function(
      BuildContext context, {
      required bool active,
      required bool hovered,
      required bool isFirst,
    });

typedef InteractiveWrapper =
    Widget Function({
      required Widget child,
      VoidCallback? onTap,
      double? scaleDown,
    });

typedef ScaffoldBackgroundWrapper =
    Widget Function(
      BuildContext context, {
      required Widget child,
    });

typedef FrostWrapper =
    Widget Function(
      BuildContext context, {
      required Widget child,
      BorderRadius? borderRadius,
    });

/// Per-theme frosted dialog surface. When non-null, `ResponsiveDialogScaffold`
/// renders the centered dialog as a custom card built from this (clip + blur +
/// translucent fill) instead of a plain `AlertDialog`. Null for every theme
/// that uses an opaque dialog (all themes except Liquid Glass at full effects).
typedef DialogSurfaceBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required BorderRadius borderRadius,
    });

/// Default [FrostWrapper]: returns [child] unchanged. Themes that don't frost
/// (everything except Liquid Glass) inherit this via the constructor default,
/// so they are completely unaffected by the hook.
Widget _identityFrost(
  BuildContext context, {
  required Widget child,
  BorderRadius? borderRadius,
}) => child;

class AppDecoration extends ThemeExtension<AppDecoration> {
  const AppDecoration({
    required this.panelBox,
    required this.tabShape,
    required this.wrapInteractive,
    required this.scaffoldBackground,
    this.frost = _identityFrost,
    this.brandedTabIndicator,
    this.dialogSurface,
  });
  final PanelBoxBuilder panelBox;
  final TabShapeBuilder tabShape;
  final InteractiveWrapper wrapInteractive;
  final ScaffoldBackgroundWrapper scaffoldBackground;

  /// Wraps a panel in real frosted-glass blur (`ClipRRect` + `BackdropFilter`).
  /// Identity for every theme except Liquid Glass.
  final FrostWrapper frost;

  /// Optional override for `BrandedTabBar`'s selected-tab indicator. When null
  /// (e.g. Classic / Brutalist) BrandedTabBar keeps its signature solid filled
  /// look. Glass supplies a translucent gradient-frosted lozenge, and AURIS a
  /// light-filled tab (its `primaryColor` defaults dark, which would leave the
  /// label unreadable). The `topBorder` argument is honored by the override so
  /// the Settings tab strip — which frames the tabs with its own dividers — can
  /// drop the top edge (see `BrandedTabBar.topIndicatorBorder`).
  final Decoration Function(BuildContext context, {bool topBorder})?
  brandedTabIndicator;

  /// See [DialogSurfaceBuilder]. Glass sets this at full effects; everything
  /// else leaves it null and keeps the standard `AlertDialog`.
  final DialogSurfaceBuilder? dialogSurface;

  @override
  AppDecoration copyWith({
    PanelBoxBuilder? panelBox,
    TabShapeBuilder? tabShape,
    InteractiveWrapper? wrapInteractive,
    ScaffoldBackgroundWrapper? scaffoldBackground,
    FrostWrapper? frost,
    Decoration Function(BuildContext context, {bool topBorder})?
    brandedTabIndicator,
    DialogSurfaceBuilder? dialogSurface,
  }) {
    return AppDecoration(
      panelBox: panelBox ?? this.panelBox,
      tabShape: tabShape ?? this.tabShape,
      wrapInteractive: wrapInteractive ?? this.wrapInteractive,
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      frost: frost ?? this.frost,
      brandedTabIndicator: brandedTabIndicator ?? this.brandedTabIndicator,
      dialogSurface: dialogSurface ?? this.dialogSurface,
    );
  }

  @override
  AppDecoration lerp(ThemeExtension<AppDecoration>? other, double t) => this;
}
