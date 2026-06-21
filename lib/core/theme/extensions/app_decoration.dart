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

  @override
  AppDecoration copyWith({
    PanelBoxBuilder? panelBox,
    TabShapeBuilder? tabShape,
    InteractiveWrapper? wrapInteractive,
    ScaffoldBackgroundWrapper? scaffoldBackground,
    FrostWrapper? frost,
    Decoration Function(BuildContext context, {bool topBorder})?
    brandedTabIndicator,
  }) {
    return AppDecoration(
      panelBox: panelBox ?? this.panelBox,
      tabShape: tabShape ?? this.tabShape,
      wrapInteractive: wrapInteractive ?? this.wrapInteractive,
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      frost: frost ?? this.frost,
      brandedTabIndicator: brandedTabIndicator ?? this.brandedTabIndicator,
    );
  }

  @override
  AppDecoration lerp(ThemeExtension<AppDecoration>? other, double t) => this;
}
