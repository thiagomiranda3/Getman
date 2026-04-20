import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import 'rpg_palette.dart';

BoxDecoration rpgPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final shape = context.appShape;
  final border = theme.dividerColor;
  final radius = borderRadius ?? BorderRadius.circular(shape.panelRadius);
  final panelColor = color ?? theme.cardColor;
  return BoxDecoration(
    color: panelColor,
    borderRadius: radius,
    border: Border.all(color: border, width: borderWidth ?? layout.borderThin),
    boxShadow: [
      // Outer gold glow — the arcane aura.
      BoxShadow(
        color: RpgPalette.gold.withValues(alpha: 0.22),
        blurRadius: 14,
        spreadRadius: 0,
      ),
      // Inner deep shadow for depth.
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35),
        offset: const Offset(0, 3),
        blurRadius: 8,
      ),
    ],
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        panelColor,
        Color.lerp(panelColor, RpgPalette.goldDeep, 0.08) ?? panelColor,
      ],
    ),
  );
}

BoxDecoration rpgTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final border = theme.dividerColor;
  final gold = RpgPalette.gold;
  final Color background;
  if (active) {
    background = Color.lerp(theme.cardColor, gold, 0.18) ?? theme.cardColor;
  } else if (hovered) {
    background = Color.lerp(theme.cardColor, gold, 0.08) ?? theme.cardColor;
  } else {
    background = theme.scaffoldBackgroundColor;
  }

  final BorderSide rule = BorderSide(color: border, width: 1);
  final BorderSide goldTop = BorderSide(color: gold, width: layout.borderThick);
  final BorderSide softTop = BorderSide(color: gold.withValues(alpha: 0.4), width: 1);

  return BoxDecoration(
    color: background,
    border: Border(
      left: isFirst ? rule : BorderSide.none,
      right: rule,
      bottom: active ? BorderSide.none : rule,
      top: active ? goldTop : (hovered ? softTop : BorderSide.none),
    ),
    boxShadow: active
        ? [
            BoxShadow(
              color: gold.withValues(alpha: 0.4),
              blurRadius: 10,
              spreadRadius: -2,
            ),
          ]
        : null,
  );
}

Widget rpgScaffoldBackground(BuildContext context, {required Widget child}) {
  return _RpgAnimatedBackground(child: child);
}

Widget rpgDoubleRule(BuildContext context) {
  final color = Theme.of(context).dividerColor;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            color.withValues(alpha: 0),
            color,
            color.withValues(alpha: 0),
          ]),
        ),
      ),
      const SizedBox(height: 2),
      Container(
        height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            RpgPalette.gold.withValues(alpha: 0),
            RpgPalette.gold,
            RpgPalette.gold.withValues(alpha: 0),
          ]),
        ),
      ),
    ],
  );
}

/// Slowly drifting starfield + radial vignette behind the app.
///
/// Uses a single long-looping controller to keep cost near zero — particle
/// positions are derived from `t` so there's no per-frame state churn.
class _RpgAnimatedBackground extends StatefulWidget {
  final Widget child;
  const _RpgAnimatedBackground({required this.child});

  @override
  State<_RpgAnimatedBackground> createState() => _RpgAnimatedBackgroundState();
}

class _RpgAnimatedBackgroundState extends State<_RpgAnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Mote> _motes;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    final rng = math.Random(42);
    _motes = List.generate(45, (_) {
      return _Mote(
        seedX: rng.nextDouble(),
        seedY: rng.nextDouble(),
        speed: 0.15 + rng.nextDouble() * 0.55,
        size: 0.6 + rng.nextDouble() * 1.8,
        twinkleOffset: rng.nextDouble(),
        hue: rng.nextDouble(),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Stack(
      children: [
        // Radial vignette under everything.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  theme.scaffoldBackgroundColor,
                  isDark
                      ? Colors.black.withValues(alpha: 0.6)
                      : RpgPalette.goldDeep.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
        ),
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => CustomPaint(
                painter: _StarfieldPainter(
                  t: _controller.value,
                  motes: _motes,
                  isDark: isDark,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Mote {
  final double seedX;
  final double seedY;
  final double speed;
  final double size;
  final double twinkleOffset;
  final double hue;

  _Mote({
    required this.seedX,
    required this.seedY,
    required this.speed,
    required this.size,
    required this.twinkleOffset,
    required this.hue,
  });
}

class _StarfieldPainter extends CustomPainter {
  final double t;
  final List<_Mote> motes;
  final bool isDark;

  _StarfieldPainter({
    required this.t,
    required this.motes,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in motes) {
      final dy = ((m.seedY + t * m.speed) % 1.0) * size.height;
      final dx = ((m.seedX + math.sin((t + m.twinkleOffset) * math.pi * 2) * 0.01) % 1.0) * size.width;

      // Twinkle alpha — pulse each mote on a different phase.
      final twinkle = 0.3 +
          0.7 *
              (0.5 +
                  0.5 *
                      math.sin(
                        (t * math.pi * 2 + m.twinkleOffset * math.pi * 2) * 1.4,
                      ));
      final alphaBase = isDark ? 0.55 : 0.18;
      final color = _colorFor(m.hue).withValues(alpha: alphaBase * twinkle);

      final glow = Paint()
        ..color = color.withValues(alpha: color.a * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(dx, dy), m.size * 2, glow);

      final core = Paint()..color = color;
      canvas.drawCircle(Offset(dx, dy), m.size, core);
    }
  }

  Color _colorFor(double h) {
    // Most motes gold, a few cool-colored for variety.
    if (h < 0.7) return RpgPalette.gold;
    if (h < 0.85) return RpgPalette.arcane;
    return RpgPalette.azure;
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.t != t || old.motes != motes || old.isDark != isDark;
}
