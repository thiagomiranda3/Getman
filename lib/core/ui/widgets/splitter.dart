import 'package:flutter/material.dart';

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
    return GestureDetector(
      onPanUpdate: (details) {
        onUpdate(isVertical ? details.delta.dy : details.delta.dx);
      },
      onPanEnd: (_) => onEnd?.call(),
      child: MouseRegion(
        cursor: isVertical ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: isVertical ? double.infinity : 6,
          height: isVertical ? 6 : double.infinity,
          color: theme.dividerColor,
        ),
      ),
    );
  }
}
