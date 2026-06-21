import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// The app's signature filled-indicator [TabBar]: active tab gets the primary
/// color with a thick top/left/right border, labels use the display weight.
///
/// Used by the request config panel, the unified phone panel, the response
/// panel, and the side menu — keep the chrome here so it stays identical.
class BrandedTabBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandedTabBar({
    required this.labels,
    super.key,
    this.controller,
    this.isScrollable = false,
    this.padding,
    this.labelPadding,
    this.tabKeyPrefix,
    this.topIndicatorBorder = true,
    this.tabAlignment,
  });
  final List<String> labels;
  final TabController? controller;
  final bool isScrollable;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? labelPadding;

  /// When false, the selected-tab indicator drops its top border. Used by the
  /// Settings tab strip, which already frames the tabs with a divider above and
  /// below, so a tab top border would double up against the upper divider.
  final bool topIndicatorBorder;

  /// Overrides the scrollable tab strip's alignment. Null keeps Material's
  /// default (`TabAlignment.startOffset` when scrollable — a ~52px leading
  /// offset that pushes the tabs right). The Settings strip passes
  /// [TabAlignment.center] so its tabs sit centered with equal space on both
  /// sides. Only meaningful with [isScrollable] true.
  final TabAlignment? tabAlignment;

  /// When set, each [Tab] gets a stable `ValueKey('<prefix>_tab_<label>')` so
  /// E2E tests can target a specific tab even when labels collide across panels
  /// (e.g. request and response both have a `BODY` tab). Null leaves tabs
  /// unkeyed (the production default).
  final String? tabKeyPrefix;

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    // Themes can override the selected-tab indicator (glass does, for a
    // translucent gradient lozenge); everyone else keeps the signature solid
    // filled look with a thick top/left/right border.
    final indicator =
        context.appDecoration.brandedTabIndicator?.call(
          context,
          topBorder: topIndicatorBorder,
        ) ??
        BoxDecoration(
          color: theme.primaryColor,
          border: Border(
            top: topIndicatorBorder
                ? BorderSide(
                    color: theme.dividerColor,
                    width: layout.borderThick,
                  )
                : BorderSide.none,
            left: BorderSide(
              color: theme.dividerColor,
              width: layout.borderThick,
            ),
            right: BorderSide(
              color: theme.dividerColor,
              width: layout.borderThick,
            ),
          ),
        );

    return TabBar(
      controller: controller,
      dividerColor: Colors.transparent,
      isScrollable: isScrollable,
      tabAlignment: tabAlignment,
      padding: padding,
      labelPadding: labelPadding,
      indicator: indicator,
      labelColor: theme.colorScheme.onPrimary,
      unselectedLabelColor: theme.colorScheme.onSurface,
      labelStyle: TextStyle(
        fontSize: layout.fontSizeNormal,
        fontWeight: context.appTypography.displayWeight,
        overflow: TextOverflow.fade,
      ),
      tabs: [
        for (final label in labels)
          Tab(
            key: tabKeyPrefix == null
                ? null
                : ValueKey('${tabKeyPrefix}_tab_$label'),
            text: label,
          ),
      ],
    );
  }
}
