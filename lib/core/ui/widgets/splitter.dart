import 'package:flutter/material.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';

class Splitter extends StatelessWidget {
  final bool isVertical;
  final Function(double) onUpdate;
  final VoidCallback? onEnd;

  const Splitter({
    super.key,
    required this.isVertical,
    required this.onUpdate,
    this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;
    final splitterSize = layout.isCompact ? 12.0 : 16.0;

    return GestureDetector(
      onPanUpdate: (details) {
        onUpdate(isVertical ? details.delta.dy : details.delta.dx);
      },
      onPanEnd: (_) => onEnd?.call(),
      child: MouseRegion(
        cursor: isVertical ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: isVertical ? double.infinity : splitterSize,
          height: isVertical ? splitterSize : double.infinity,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: isVertical ? 40 : 3,
              height: isVertical ? 3 : 40,
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
