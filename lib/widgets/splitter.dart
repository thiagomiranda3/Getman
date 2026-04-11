import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/neo_brutalist_theme.dart';

class Splitter extends ConsumerWidget {
  final bool isVertical;
  final Function(double) onUpdate;
  final VoidCallback onEnd;

  const Splitter({
    super.key,
    required this.isVertical,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Theme.of(context).extension<LayoutExtension>()!;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (details) => onUpdate(isVertical ? details.delta.dy : details.delta.dx),
      onPanEnd: (_) => onEnd(),
      child: MouseRegion(
        cursor: isVertical ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.resizeLeftRight,
        child: isVertical
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: layout.isCompact ? 8 : 12),
              child: Divider(height: 3, thickness: 3, color: theme.dividerColor),
            )
          : VerticalDivider(width: layout.verticalDividerWidth, thickness: 3, color: theme.dividerColor),
      ),
    );
  }
}
