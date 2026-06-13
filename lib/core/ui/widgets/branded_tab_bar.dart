import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// The app's signature filled-indicator [TabBar]: active tab gets the primary
/// color with a thick top/left/right border, labels use the display weight.
///
/// Used by the request config panel, the unified phone panel, the response
/// panel, and the side menu — keep the chrome here so it stays identical.
class BrandedTabBar extends StatelessWidget implements PreferredSizeWidget {
  final List<String> labels;
  final TabController? controller;
  final bool isScrollable;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? labelPadding;

  const BrandedTabBar({
    super.key,
    required this.labels,
    this.controller,
    this.isScrollable = false,
    this.padding,
    this.labelPadding,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return TabBar(
      controller: controller,
      dividerColor: Colors.transparent,
      isScrollable: isScrollable,
      padding: padding,
      labelPadding: labelPadding,
      indicator: BoxDecoration(
        color: theme.primaryColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: layout.borderThick),
          left: BorderSide(color: theme.dividerColor, width: layout.borderThick),
          right: BorderSide(color: theme.dividerColor, width: layout.borderThick),
        ),
      ),
      labelColor: theme.colorScheme.onPrimary,
      unselectedLabelColor: theme.colorScheme.onSurface,
      labelStyle: TextStyle(
        fontSize: layout.fontSizeNormal,
        fontWeight: context.appTypography.displayWeight,
        overflow: TextOverflow.fade,
      ),
      tabs: [for (final label in labels) Tab(text: label)],
    );
  }
}
