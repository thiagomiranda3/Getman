// lib/core/theme/themes/glass/glass_motion.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/latency_weight.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// Liquid Glass motion: a concentric ripple bloom on success, a crack-and-heal
/// on error, and a liquid ripple from the SEND button on press. Identity when
/// [reduceEffects].
AppMotion glassMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _GlassReactionOverlay(controller: controller, child: child),
    sendAffordance: (context, {required child, required isSending}) =>
        _GlassSendAffordance(isSending: isSending, child: child),
  );
}

class _GlassReactionOverlay extends StatefulWidget {
  const _GlassReactionOverlay({required this.controller, required this.child});
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_GlassReactionOverlay> createState() => _GlassReactionOverlayState();
}

class _GlassReactionOverlayState extends State<_GlassReactionOverlay>
    with TickerProviderStateMixin {
  final List<_GlassEffect> _effects = [];

  void _onReaction(ThemeReaction r) {
    final accent = Theme.of(context).primaryColor;
    final w = latencyWeight(r.durationMs);
    final controller = AnimationController(
      vsync: this,
      duration: r.isError
          ? const Duration(milliseconds: 700)
          : Duration(milliseconds: 900 + (500 * w).round()),
    );
    final effect = _GlassEffect(
      controller: controller,
      isError: r.isError,
      weight: w,
      color: r.isError ? Theme.of(context).colorScheme.error : accent,
    );
    controller.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _effects.remove(effect));
        controller.dispose();
      }
    });
    setState(() => _effects.add(effect));
    unawaited(controller.forward());
  }

  @override
  void dispose() {
    for (final e in _effects) {
      e.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      child: Stack(
        children: [
          widget.child,
          for (final e in _effects)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: e.controller,
                  builder: (_, child) => CustomPaint(
                    painter: e.isError
                        ? _GlassCrackPainter(
                            t: e.controller.value,
                            color: e.color,
                          )
                        : _GlassRipplePainter(
                            t: e.controller.value,
                            color: e.color,
                            weight: e.weight,
                          ),
                    child: child,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassEffect {
  _GlassEffect({
    required this.controller,
    required this.isError,
    required this.weight,
    required this.color,
  });
  final AnimationController controller;
  final bool isError;
  final double weight;
  final Color color;
}

/// Concentric ripple sweep from screen center + a soft accent bloom that fades.
/// [weight] (0..1) adds extra rings and grows the bloom for slow responses.
class _GlassRipplePainter extends CustomPainter {
  _GlassRipplePainter({required this.t, required this.color, this.weight = 0});
  final double t;
  final Color color;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.longestSide * 0.75 * (1 + 0.25 * weight);
    final fade = (1.0 - t).clamp(0.0, 1.0);
    final rings = 3 + (weight * 2).round();
    for (var i = 0; i < rings; i++) {
      final phase = (t - i * 0.12).clamp(0.0, 1.0);
      if (phase <= 0) continue;
      final r = Curves.easeOut.transform(phase) * maxR;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = color.withValues(alpha: 0.28 * fade);
      canvas.drawCircle(center, r, paint);
    }
    // Soft central bloom.
    final bloom = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.18 * fade),
          const Color(0x00000000),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxR * 0.5));
    canvas.drawCircle(center, maxR * 0.5, bloom);
  }

  @override
  bool shouldRepaint(covariant _GlassRipplePainter old) =>
      old.t != t || old.color != color || old.weight != weight;
}

/// A thin crack-line spider that snaps in (0..0.4) then heals/fades (0.4..1).
class _GlassCrackPainter extends CustomPainter {
  _GlassCrackPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = size.center(const Offset(0, -40));
    final grow = Curves.easeOut.transform((t / 0.4).clamp(0.0, 1.0));
    final heal = t <= 0.4 ? 1.0 : (1.0 - (t - 0.4) / 0.6).clamp(0.0, 1.0);
    final rng = math.Random(7); // stable spider geometry per paint
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.6 * heal);
    for (var i = 0; i < 7; i++) {
      final angle = i * (math.pi * 2 / 7) + rng.nextDouble() * 0.3;
      final len = (size.shortestSide * 0.55) * (0.6 + rng.nextDouble() * 0.4);
      var p = origin;
      final path = Path()..moveTo(p.dx, p.dy);
      const segs = 4;
      for (var s = 1; s <= segs; s++) {
        final frac = (s / segs) * grow;
        final jitter = (rng.nextDouble() - 0.5) * 18;
        final perp =
            Offset(
              math.cos(angle + math.pi / 2),
              math.sin(angle + math.pi / 2),
            ) *
            jitter;
        p =
            origin +
            Offset(math.cos(angle), math.sin(angle)) * (len * frac) +
            perp;
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlassCrackPainter old) =>
      old.t != t || old.color != color;
}

/// Press ripple + a translucent liquid that rises from the bottom
/// while sending.
class _GlassSendAffordance extends StatefulWidget {
  const _GlassSendAffordance({required this.isSending, required this.child});
  final bool isSending;
  final Widget child;

  @override
  State<_GlassSendAffordance> createState() => _GlassSendAffordanceState();
}

class _GlassSendAffordanceState extends State<_GlassSendAffordance>
    with TickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final AnimationController _build = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kTensionFullMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSending) unawaited(_build.forward(from: 0));
  }

  @override
  void didUpdateWidget(_GlassSendAffordance old) {
    super.didUpdateWidget(old);
    if (widget.isSending && !_build.isAnimating && _build.value == 0) {
      unawaited(_build.forward(from: 0));
    } else if (!widget.isSending && _build.value != 0) {
      _build
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    _build.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).primaryColor;
    return Listener(
      onPointerDown: (_) {
        _ripple.reset();
        unawaited(_ripple.forward());
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([_ripple, _build]),
                builder: (_, child) => CustomPaint(
                  painter: _GlassSendPainter(
                    ripple: _ripple.value,
                    level: widget.isSending
                        ? inFlightTension(
                            (_build.value * kTensionFullMs).round(),
                          )
                        : 0,
                    color: accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Press ripple + a translucent liquid that rises from the bottom with the
/// in-flight [level] (0..1).
class _GlassSendPainter extends CustomPainter {
  _GlassSendPainter({
    required this.ripple,
    required this.level,
    required this.color,
  });
  final double ripple;
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (level > 0) {
      final h = size.height * level;
      final fill = Paint()..color = color.withValues(alpha: 0.22);
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - h, size.width, h),
        fill,
      );
      // Meniscus line.
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.5);
      canvas.drawLine(
        Offset(0, size.height - h),
        Offset(size.width, size.height - h),
        line,
      );
    }
    if (ripple > 0) {
      final center = size.center(Offset.zero);
      final r = Curves.easeOut.transform(ripple) * size.longestSide;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.5 * (1 - ripple)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassSendPainter old) =>
      old.ripple != ripple || old.level != level || old.color != color;
}
