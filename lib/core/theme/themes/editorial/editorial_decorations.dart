import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

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
    bottom = BorderSide(color: ink);
  } else {
    bottom = BorderSide(color: inkSoft.withValues(alpha: 0.4));
  }
  final columnRule = BorderSide(color: ink);
  return BoxDecoration(
    color: theme.scaffoldBackgroundColor,
    border: Border(
      left: isFirst ? columnRule : BorderSide.none,
      right: columnRule,
      bottom: bottom,
    ),
  );
}

Widget editorialScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) {
  final theme = Theme.of(context);
  return Stack(
    children: [
      RepaintBoundary(child: child),
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              painter: _DotGridPainter(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color});

  final Color color;
  static const double _spacing = 4;

  // Cache of raw float coordinates keyed by the last painted size.
  // Recomputed only when the canvas size changes.
  Float32List? _cachedPoints;
  Size _cachedSize = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size != _cachedSize || _cachedPoints == null) {
      _cachedSize = size;
      final cols = (size.width / _spacing).ceil();
      final rows = (size.height / _spacing).ceil();
      final points = Float32List(cols * rows * 2);
      var i = 0;
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < cols; col++) {
          points[i++] = col * _spacing;
          points[i++] = row * _spacing;
        }
      }
      _cachedPoints = points;
    }
    final paint = ui.Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawRawPoints(ui.PointMode.points, _cachedPoints!, paint);
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) => old.color != color;
}
