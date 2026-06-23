// lib/core/theme/themes/rpg/rpg_motion.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/latency_weight.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/rpg/rpg_palette.dart';

/// Visual effect style for the Arcane (rpg) reaction overlay.
enum RpgFx { sparkle, echo, ward, scatter, crack }

/// Parameters that drive a single rpg reaction effect.
class RpgSpec {
  const RpgSpec(this.style, {this.repeat = 1, this.amplitude = 1.0});
  final RpgFx style;
  final int repeat;
  final double amplitude;
}

/// Selects the [RpgSpec] for a given [StatusReactionFlavor].
RpgSpec rpgSpecFor(StatusReactionFlavor f) => switch (f) {
  StatusReactionFlavor.noContent => const RpgSpec(
    RpgFx.sparkle,
    amplitude: 0.4,
  ),
  StatusReactionFlavor.notModified => const RpgSpec(RpgFx.echo),
  StatusReactionFlavor.unauthorized ||
  StatusReactionFlavor.forbidden => const RpgSpec(RpgFx.ward),
  StatusReactionFlavor.notFound => const RpgSpec(RpgFx.scatter),
  StatusReactionFlavor.timeout => const RpgSpec(RpgFx.sparkle, amplitude: 0.5),
  StatusReactionFlavor.rateLimited => const RpgSpec(RpgFx.sparkle, repeat: 3),
  StatusReactionFlavor.serverCrash ||
  StatusReactionFlavor.serverError ||
  StatusReactionFlavor.clientError ||
  StatusReactionFlavor.networkError ||
  StatusReactionFlavor.serviceUnavailable => const RpgSpec(RpgFx.crack),
  StatusReactionFlavor.badCertificate => const RpgSpec(RpgFx.ward),
  _ => const RpgSpec(RpgFx.sparkle),
};

/// Arcane Quest motion: a golden sparkle shower ("spell lands") on success, a
/// crimson runic crack + a brief screen shake on error, and a spinning rune
/// ring around SEND while sending. Identity when [reduceEffects].
AppMotion rpgMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _RpgReactionOverlay(controller: controller, child: child),
    treeDragFeedback: (context, {required child}) =>
        _RpgTreeDragFeedback(child: child),
    treeDropHighlight: (context, {required child, required active}) =>
        _RpgTreeDropHighlight(active: active, child: child),
    treeExpandFlourish: (context, {required child, required expanded}) =>
        _RpgTreeExpandFlourish(expanded: expanded, child: child),
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
    if (r.kind == ThemeReactionKind.sendStarted) return;
    final w = latencyWeight(r.durationMs);
    final spec = rpgSpecFor(flavorFor(r));
    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 900 + (500 * w).round()),
    );
    final effect = _RpgEffect(
      controller: controller,
      isError: r.isError,
      seed: _rng.nextInt(1 << 30),
      weight: w,
      spec: spec,
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
      final amplitude = 6 * (0.6 + 0.7 * e.weight);
      dx += math.sin(e.controller.value * math.pi * 12) * amplitude * decay;
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
                        painter: switch (e.spec.style) {
                          RpgFx.crack => _RunicCrackPainter(
                            t: e.controller.value,
                            seed: e.seed,
                          ),
                          RpgFx.ward => _WardPainter(t: e.controller.value),
                          RpgFx.scatter => _MoteScatterPainter(
                            t: e.controller.value,
                            seed: e.seed,
                          ),
                          RpgFx.echo => _RuneEchoPainter(t: e.controller.value),
                          RpgFx.sparkle => _SparkleShowerPainter(
                            t: e.controller.value,
                            seed: e.seed,
                            weight: e.weight,
                            repeat: e.spec.repeat,
                            amplitude: e.spec.amplitude,
                          ),
                        },
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
    required this.weight,
    required this.spec,
  });
  final AnimationController controller;
  final bool isError;
  final int seed;
  final double weight;
  final RpgSpec spec;
}

/// Gold sparkles rain from the top + a gold shimmer sweep.
class _SparkleShowerPainter extends CustomPainter {
  _SparkleShowerPainter({
    required this.t,
    required this.seed,
    required this.weight,
    this.repeat = 1,
    this.amplitude = 1.0,
  });
  final double t;
  final int seed;
  final double weight;
  final int repeat;
  final double amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final core = Paint();
    final count = ((36 + (weight * 30).round()) * amplitude).round();
    // For repeat > 1, phase time so sparkles fall in staggered waves.
    final tPhased = repeat > 1 ? (t * repeat) % 1.0 : t;
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final delay = rng.nextDouble() * 0.3;
      final p = ((tPhased - delay) / (1 - delay)).clamp(0.0, 1.0);
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
  bool shouldRepaint(covariant _SparkleShowerPainter old) =>
      old.t != t ||
      old.weight != weight ||
      old.repeat != repeat ||
      old.amplitude != amplitude;
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

/// Hexagonal arcane ward that flares then fades — "blocked by magic".
class _WardPainter extends CustomPainter {
  _WardPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final flare = math.sin(t.clamp(0.0, 1.0) * math.pi).clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.32;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = RpgPalette.arcane.withValues(alpha: 0.8 * flare);
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * (math.pi * 2 / 6);
      final p = center + Offset(math.cos(a), math.sin(a)) * radius;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WardPainter old) => old.t != t;
}

/// Motes scatter outward and wink out — "vanished / not found".
class _MoteScatterPainter extends CustomPainter {
  _MoteScatterPainter({required this.t, required this.seed});
  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final center = size.center(Offset.zero);
    final fade = (1 - t).clamp(0.0, 1.0);
    final core = Paint();
    for (var i = 0; i < 28; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final dist =
          Curves.easeOut.transform(t) *
          size.shortestSide *
          (0.2 + rng.nextDouble() * 0.4);
      final p = center + Offset(math.cos(a), math.sin(a)) * dist;
      core.color =
          (rng.nextDouble() < 0.8 ? RpgPalette.gold : RpgPalette.arcane)
              .withValues(alpha: fade);
      canvas.drawCircle(p, 1.5 + rng.nextDouble() * 2, core);
    }
  }

  @override
  bool shouldRepaint(covariant _MoteScatterPainter old) => old.t != t;
}

/// A translucent rune doubles and drifts — déjà-vu (304 not-modified).
class _RuneEchoPainter extends CustomPainter {
  _RuneEchoPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final fade = math.sin(t.clamp(0.0, 1.0) * math.pi).clamp(0.0, 1.0);
    for (var k = 0; k < 2; k++) {
      final r = size.shortestSide * (0.18 + k * 0.04);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = RpgPalette.arcane.withValues(alpha: (0.5 - k * 0.2) * fade);
      canvas.drawCircle(center + Offset(k * 10.0, 0), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RuneEchoPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// VM-B3: Tree drag/drop/expand juice — Arcane Quest (RPG)
// ---------------------------------------------------------------------------

/// Rune-glow chip shown under the cursor while dragging a tree node.
class _RpgTreeDragFeedback extends StatelessWidget {
  const _RpgTreeDragFeedback({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: RpgPalette.gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: RpgPalette.gold.withValues(alpha: 0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: RpgPalette.gold.withValues(alpha: 0.25),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      ),
    );
  }
}

/// Gold glow-pull border around drop targets while [active].
class _RpgTreeDropHighlight extends StatefulWidget {
  const _RpgTreeDropHighlight({
    required this.active,
    required this.child,
  });
  final bool active;
  final Widget child;

  @override
  State<_RpgTreeDropHighlight> createState() => _RpgTreeDropHighlightState();
}

class _RpgTreeDropHighlightState extends State<_RpgTreeDropHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.value = 1.0;
  }

  @override
  void didUpdateWidget(_RpgTreeDropHighlight old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      unawaited(_c.forward(from: 0));
    } else if (!widget.active && old.active) {
      unawaited(_c.reverse());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _c.value == 0) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child, // hoisted — not rebuilt per frame
      builder: (ctx, child) {
        if (_c.value == 0) return child!;
        return Stack(
          children: [
            child!, // child first — receives taps/drops
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: RpgPalette.gold.withValues(alpha: 0.8 * _c.value),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: RpgPalette.gold.withValues(
                          alpha: 0.3 * _c.value,
                        ),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Gold glow flourish around the expand icon on expand/collapse.
class _RpgTreeExpandFlourish extends StatelessWidget {
  const _RpgTreeExpandFlourish({
    required this.expanded,
    required this.child,
  });
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(expanded),
      tween: Tween(begin: 0, end: expanded ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 200),
      builder: (ctx, v, ch) {
        if (v <= 0) return ch!;
        return Stack(
          children: [
            ch!, // child first — receives taps
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: RpgPalette.gold.withValues(alpha: 0.6 * v),
                        blurRadius: 8 * v,
                        spreadRadius: 2 * v,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
