// lib/core/theme/themes/rpg/rpg_motion.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/rpg/rpg_palette.dart';

/// Arcane Quest motion: a golden sparkle shower ("spell lands") on success, a
/// crimson runic crack + a brief screen shake on error, and a spinning rune
/// ring around SEND while sending. Identity when [reduceEffects].
AppMotion rpgMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _RpgReactionOverlay(controller: controller, child: child),
    sendAffordance: (context, {required child, required isSending}) =>
        _RpgSendAffordance(isSending: isSending, child: child),
  );
}

class _RpgReactionOverlay extends StatefulWidget {
  const _RpgReactionOverlay({required this.controller, required this.child});
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_RpgReactionOverlay> createState() => _RpgReactionOverlayState();
}

class _RpgReactionOverlayState extends State<_RpgReactionOverlay>
    with TickerProviderStateMixin {
  final List<_RpgEffect> _effects = [];
  final math.Random _rng = math.Random();

  void _onReaction(ThemeReaction r) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final effect = _RpgEffect(
      controller: controller,
      isError: r.isError,
      seed: _rng.nextInt(1 << 30),
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

  // Error reactions shake; success doesn't. Amplitude decays over the effect.
  double _shakeDx() {
    var dx = 0.0;
    for (final e in _effects.where((e) => e.isError)) {
      final decay = (1 - e.controller.value).clamp(0.0, 1.0);
      dx += math.sin(e.controller.value * math.pi * 12) * 6 * decay;
    }
    return dx;
  }

  @override
  Widget build(BuildContext context) {
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      child: AnimatedBuilder(
        animation: Listenable.merge(_effects.map((e) => e.controller).toList()),
        child: widget.child, // hoisted — not rebuilt per frame
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_shakeDx(), 0),
            child: Stack(
              children: [
                child!,
                for (final e in _effects)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: e.isError
                            ? _RunicCrackPainter(
                                t: e.controller.value,
                                seed: e.seed,
                              )
                            : _SparkleShowerPainter(
                                t: e.controller.value,
                                seed: e.seed,
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RpgEffect {
  _RpgEffect({
    required this.controller,
    required this.isError,
    required this.seed,
  });
  final AnimationController controller;
  final bool isError;
  final int seed;
}

/// Gold sparkles rain from the top + a gold shimmer sweep.
class _SparkleShowerPainter extends CustomPainter {
  _SparkleShowerPainter({required this.t, required this.seed});
  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final core = Paint();
    for (var i = 0; i < 36; i++) {
      final x = rng.nextDouble() * size.width;
      final delay = rng.nextDouble() * 0.3;
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = Curves.easeIn.transform(p) * size.height;
      final alpha = (1 - p).clamp(0.0, 1.0);
      final r = 1.5 + rng.nextDouble() * 2.5;
      final color = rng.nextDouble() < 0.8
          ? RpgPalette.gold
          : RpgPalette.arcane;
      core.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), r, core);
    }
    // Shimmer sweep band.
    final sweepY = Curves.easeOut.transform(t) * size.height;
    final band = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0x00000000),
          RpgPalette.gold.withValues(alpha: 0.10 * (1 - t)),
          const Color(0x00000000),
        ],
      ).createShader(Rect.fromLTWH(0, sweepY - 60, size.width, 120));
    canvas.drawRect(Rect.fromLTWH(0, sweepY - 60, size.width, 120), band);
  }

  @override
  bool shouldRepaint(covariant _SparkleShowerPainter old) => old.t != t;
}

/// Crimson runic crack flash + dark vignette pulse.
class _RunicCrackPainter extends CustomPainter {
  _RunicCrackPainter({required this.t, required this.seed});
  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = math.sin(t * math.pi).clamp(0.0, 1.0);
    // Dark vignette pulse.
    final vignette = Paint()
      ..shader = RadialGradient(
        radius: 1.1,
        colors: [
          const Color(0x00000000),
          RpgPalette.statusError.withValues(alpha: 0.18 * pulse),
        ],
        stops: const [0.6, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
    // Cracks from center.
    final rng = math.Random(seed);
    final origin = size.center(const Offset(0, -30));
    final grow = Curves.easeOut.transform((t / 0.35).clamp(0.0, 1.0));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = RpgPalette.statusError.withValues(alpha: 0.7 * pulse);
    for (var i = 0; i < 6; i++) {
      final angle = i * (math.pi * 2 / 6) + rng.nextDouble() * 0.4;
      final len = size.shortestSide * 0.5 * grow;
      canvas.drawLine(
        origin,
        origin + Offset(math.cos(angle), math.sin(angle)) * len,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunicCrackPainter old) => old.t != t;
}

/// Spinning rune ring around SEND while [isSending].
class _RpgSendAffordance extends StatefulWidget {
  const _RpgSendAffordance({required this.isSending, required this.child});
  final bool isSending;
  final Widget child;

  @override
  State<_RpgSendAffordance> createState() => _RpgSendAffordanceState();
}

class _RpgSendAffordanceState extends State<_RpgSendAffordance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSending) unawaited(_spin.repeat());
  }

  @override
  void didUpdateWidget(_RpgSendAffordance old) {
    super.didUpdateWidget(old);
    if (widget.isSending && !_spin.isAnimating) {
      unawaited(_spin.repeat());
    } else if (!widget.isSending && _spin.isAnimating) {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSending) return widget.child;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _spin,
              builder: (_, child) => CustomPaint(
                painter: _RuneRingPainter(t: _spin.value),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _RuneRingPainter extends CustomPainter {
  _RuneRingPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.65;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(t * math.pi * 2);
    final tick = Paint()
      ..strokeWidth = 1.5
      ..color = RpgPalette.gold.withValues(alpha: 0.7);
    for (var i = 0; i < 12; i++) {
      final a = i * (math.pi * 2 / 12);
      final o = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(o * (radius - 3), o * (radius + 3), tick);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RuneRingPainter old) => old.t != t;
}
