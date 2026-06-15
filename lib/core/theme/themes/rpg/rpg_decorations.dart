import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/rpg/rpg_palette.dart';

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
  const gold = RpgPalette.gold;
  final Color background;
  if (active) {
    background = Color.lerp(theme.cardColor, gold, 0.18) ?? theme.cardColor;
  } else if (hovered) {
    background = Color.lerp(theme.cardColor, gold, 0.08) ?? theme.cardColor;
  } else {
    background = theme.scaffoldBackgroundColor;
  }

  final rule = BorderSide(color: border);
  final goldTop = BorderSide(color: gold, width: layout.borderThick);
  final softTop = BorderSide(color: gold.withValues(alpha: 0.4));

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

/// Slowly drifting starfield + radial vignette behind the app.
///
/// Uses a single long-looping controller to keep cost near zero — particle
/// positions are derived from `t` so there's no per-frame state churn.
class _RpgAnimatedBackground extends StatefulWidget {
  const _RpgAnimatedBackground({required this.child});
  final Widget child;

  @override
  State<_RpgAnimatedBackground> createState() => _RpgAnimatedBackgroundState();
}

class _RpgAnimatedBackgroundState extends State<_RpgAnimatedBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final List<_Mote> _motes;
  late final ValueNotifier<double> _frameNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frameNotifier = ValueNotifier<double>(0);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    unawaited(_controller.repeat());
    _controller.addListener(() {
      // Quantize to 30 steps per second (60s loop × 30 steps/s = 1800 steps total).
      final q = (_controller.value * (60 * 30)).floorToDouble() / (60 * 30);
      if (q != _frameNotifier.value) _frameNotifier.value = q;
    });
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't burn CPU/battery animating the starfield while the app is hidden.
    if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) unawaited(_controller.repeat());
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _frameNotifier.dispose();
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
                radius: 1.2,
                colors: [
                  theme.scaffoldBackgroundColor,
                  if (isDark)
                    Colors.black.withValues(alpha: 0.6)
                  else
                    RpgPalette.goldDeep.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
        ),
        RepaintBoundary(child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _StarfieldPainter(
                  tListenable: _frameNotifier,
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
  _Mote({
    required this.seedX,
    required this.seedY,
    required this.speed,
    required this.size,
    required this.twinkleOffset,
    required this.hue,
  });
  final double seedX;
  final double seedY;
  final double speed;
  final double size;
  final double twinkleOffset;
  final double hue;
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.tListenable,
    required this.motes,
    required this.isDark,
  }) : super(repaint: tListenable);
  final ValueListenable<double> tListenable;
  final List<_Mote> motes;
  final bool isDark;

  // Reused across motes/frames — only `.color` changes per draw (the immutable
  // blur MaskFilter is set once). Allocating per mote per frame was the hot
  // spot.
  final Paint _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final Paint _corePaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final t = tListenable.value;
    for (final m in motes) {
      final dy = ((m.seedY + t * m.speed) % 1.0) * size.height;
      final dx =
          ((m.seedX + math.sin((t + m.twinkleOffset) * math.pi * 2) * 0.01) %
              1.0) *
          size.width;

      // Twinkle alpha — pulse each mote on a different phase.
      final twinkle =
          0.3 +
          0.7 *
              (0.5 +
                  0.5 *
                      math.sin(
                        (t * math.pi * 2 + m.twinkleOffset * math.pi * 2) * 1.4,
                      ));
      final alphaBase = isDark ? 0.55 : 0.18;
      final color = _colorFor(m.hue).withValues(alpha: alphaBase * twinkle);

      _glowPaint.color = color.withValues(alpha: color.a * 0.6);
      canvas.drawCircle(Offset(dx, dy), m.size * 2, _glowPaint);

      _corePaint.color = color;
      canvas.drawCircle(Offset(dx, dy), m.size, _corePaint);
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
      old.motes != motes || old.isDark != isDark;
}
