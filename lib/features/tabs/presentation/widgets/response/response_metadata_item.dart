import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// A single status/time/size chip in the response metadata row, with a brief
/// color-fade-in animation keyed by [value] so it flashes on each new send.
class ResponseMetadataItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final AppLayout layout;
  const ResponseMetadataItem({
    super.key,
    required this.label,
    required this.value,
    this.color,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = color ?? theme.primaryColor;

    return TweenAnimationBuilder<Color?>(
      key: ValueKey(value),
      duration: const Duration(milliseconds: 600),
      tween: ColorTween(begin: baseColor.withValues(alpha: 1.0), end: baseColor.withValues(alpha: 0.2)),
      builder: (context, animColor, child) {
        return Container(
          margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: layout.isCompact ? 4 : 8),
          decoration: BoxDecoration(
            color: animColor,
            border: Border.all(color: theme.dividerColor, width: layout.borderThin),
            borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: context.appPalette.onColor(baseColor), fontSize: layout.fontSizeSmall, fontWeight: context.appTypography.titleWeight)),
          Text(value, style: TextStyle(color: context.appPalette.onColor(baseColor), fontWeight: context.appTypography.displayWeight, fontSize: layout.fontSizeNormal)),
        ],
      ),
    );
  }
}
