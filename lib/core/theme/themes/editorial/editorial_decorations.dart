import 'package:flutter/material.dart';
import '../../app_theme.dart';

BoxDecoration editorialPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final border = theme.dividerColor;
  return BoxDecoration(
    color: color ?? theme.cardColor,
    borderRadius: borderRadius ?? BorderRadius.zero,
    border: Border.all(color: border, width: borderWidth ?? layout.borderThin),
  );
}

BoxDecoration editorialTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final ink = theme.dividerColor;
  final inkSoft = theme.colorScheme.secondary;
  final BorderSide bottom;
  if (active) {
    bottom = BorderSide(color: ink, width: layout.borderThick);
  } else if (hovered) {
    bottom = BorderSide(color: ink, width: 1);
  } else {
    bottom = BorderSide(color: inkSoft.withValues(alpha: 0.4), width: 1);
  }
  final BorderSide columnRule = BorderSide(color: ink, width: 1);
  return BoxDecoration(
    color: theme.scaffoldBackgroundColor,
    border: Border(
      left: isFirst ? columnRule : BorderSide.none,
      right: columnRule,
      bottom: bottom,
    ),
  );
}

Widget editorialScaffoldBackground(BuildContext context, {required Widget child}) {
  final theme = Theme.of(context);
  return Stack(
    children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _DotGridPainter(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
            ),
          ),
        ),
      ),
    ],
  );
}

Widget editorialDoubleRule(BuildContext context) {
  final ink = Theme.of(context).dividerColor;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(height: 1, color: ink),
      const SizedBox(height: 2),
      Container(height: 3, color: ink),
    ],
  );
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color});

  final Color color;
  static const double _spacing = 4.0;
  static const double _radius = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 0; y < size.height; y += _spacing) {
      for (double x = 0; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) => old.color != color;
}
