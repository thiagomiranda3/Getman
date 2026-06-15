import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:getman/core/theme/themes/rpg/rpg_palette.dart';

/// Interactive wrapper for the RPG theme.
///
/// Two layered effects:
///   1. A scale-down press bounce (consistent with the app's feel-language).
///   2. On tap-down, spawns a burst of sparkle particles at the tap position
///      that fly outward, rotate, scale, and fade. Stack uses `Clip.none` so
///      sparkles can leave the widget bounds.
class RpgSparkle extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  const RpgSparkle({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.96,
  });

  @override
  State<RpgSparkle> createState() => _RpgSparkleState();
}

class _RpgSparkleState extends State<RpgSparkle>
    with TickerProviderStateMixin {
  late final AnimationController _scaleController;
  late Animation<double> _scaleAnim;
  final List<_Burst> _bursts = [];
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: widget.scaleDown)
        .animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant RpgSparkle old) {
    super.didUpdateWidget(old);
    if (old.scaleDown != widget.scaleDown) {
      _scaleAnim = Tween<double>(begin: 1.0, end: widget.scaleDown)
          .animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut));
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    for (final b in _bursts) {
      b.controller.dispose();
    }
    _bursts.clear();
    super.dispose();
  }

  void _emitBurst(Offset origin) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    final particles = List.generate(8, (i) {
      final angle = (i * (math.pi * 2 / 8)) + _rng.nextDouble() * 0.5 - 0.25;
      return _Particle(
        angle: angle,
        distance: 22 + _rng.nextDouble() * 28,
        size: 4 + _rng.nextDouble() * 4,
        rotation: _rng.nextDouble() * math.pi * 2,
        spin: (_rng.nextDouble() - 0.5) * 4,
        color: _pickColor(),
      );
    });
    final burst = _Burst(origin: origin, controller: controller, particles: particles);
    burst.controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _bursts.remove(burst));
        burst.controller.dispose();
      }
    });
    setState(() => _bursts.add(burst));
    burst.controller.forward();
  }

  Color _pickColor() {
    const choices = <Color>[
      RpgPalette.gold,
      RpgPalette.emerald,
      RpgPalette.azure,
      RpgPalette.arcane,
      Color(0xFFFFF4CC),
    ];
    return choices[_rng.nextInt(choices.length)];
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        _scaleController.forward();
        _emitBurst(details.localPosition);
      },
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ScaleTransition(scale: _scaleAnim, child: widget.child),
          for (final b in _bursts)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: b.controller,
                  builder: (_, _) => CustomPaint(
                    painter: _SparklePainter(burst: b, t: b.controller.value),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Burst {
  final Offset origin;
  final AnimationController controller;
  final List<_Particle> particles;

  _Burst({required this.origin, required this.controller, required this.particles});
}

class _Particle {
  final double angle;
  final double distance;
  final double size;
  final double rotation;
  final double spin;
  final Color color;

  _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.rotation,
    required this.spin,
    required this.color,
  });
}

class _SparklePainter extends CustomPainter {
  final _Burst burst;
  final double t;

  _SparklePainter({required this.burst, required this.t});

  // Reused across particles/frames — `.color` is the only per-draw mutation.
  // The unit-size 4-point star path is built once and scaled via the canvas.
  final Paint _glowPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  final Paint _sparklePaint = Paint();
  final Path _sparkleUnitPath = _buildSparkleUnitPath();

  @override
  void paint(Canvas canvas, Size size) {
    // Eased outward distance and scale-then-fade alpha curve.
    final travel = Curves.easeOutCubic.transform(t);
    final alpha = t < 0.35
        ? (t / 0.35).clamp(0.0, 1.0)
        : (1.0 - ((t - 0.35) / 0.65)).clamp(0.0, 1.0);
    final scale = t < 0.3 ? 0.5 + (t / 0.3) * 0.5 : 1.0 - (t - 0.3) * 0.4;

    for (final p in burst.particles) {
      final offset = burst.origin +
          Offset(math.cos(p.angle) * p.distance * travel,
                 math.sin(p.angle) * p.distance * travel);
      final rotation = p.rotation + p.spin * t;
      final opacity = (alpha).clamp(0.0, 1.0);
      final halfSize = p.size * scale;

      // Soft glow halo.
      _glowPaint.color = p.color.withValues(alpha: 0.35 * opacity);
      canvas.drawCircle(offset, halfSize * 1.8, _glowPaint);

      // Four-point sparkle — draw the unit path scaled to halfSize.
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(rotation);
      canvas.scale(halfSize, halfSize);
      _sparklePaint.color = p.color.withValues(alpha: opacity);
      canvas.drawPath(_sparkleUnitPath, _sparklePaint);
      canvas.restore();
    }
  }

  /// Classic 4-point star at unit radius (r = 1.0): two crossed diamond shapes
  /// pinched at center. Scaled per particle via a canvas transform.
  static Path _buildSparkleUnitPath() {
    final path = Path();
    const wide = 1.0;
    const thin = wide * 0.18;
    path.moveTo(0, -wide);
    path.lineTo(thin, -thin);
    path.lineTo(wide, 0);
    path.lineTo(thin, thin);
    path.lineTo(0, wide);
    path.lineTo(-thin, thin);
    path.lineTo(-wide, 0);
    path.lineTo(-thin, -thin);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) =>
      old.t != t || old.burst != burst;
}
