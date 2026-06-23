import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/motion/latency_weight.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// How a flavor renders as a brutalist stamp. Pure data → unit-testable.
class StampSpec {
  const StampSpec({
    this.thuds = 1,
    this.doubled = false,
    this.sag = false,
    this.flicker = false,
    this.scatter = false,
    this.barrier = false,
    this.quiet = false,
  });
  final int thuds; // re-slam count (429 throttle)
  final bool doubled; // ghosted echo (304)
  final bool sag; // droops downward (408)
  final bool flicker; // brown-out (503)
  final bool scatter; // shatters apart (404)
  final bool barrier; // bar slammed across (401/403)
  final bool quiet; // smaller, no shake (204)
}

StampSpec stampSpecFor(StatusReactionFlavor f) => switch (f) {
  StatusReactionFlavor.noContent => const StampSpec(quiet: true),
  StatusReactionFlavor.notModified => const StampSpec(doubled: true),
  StatusReactionFlavor.timeout => const StampSpec(sag: true),
  StatusReactionFlavor.serviceUnavailable => const StampSpec(flicker: true),
  StatusReactionFlavor.notFound => const StampSpec(scatter: true),
  StatusReactionFlavor.unauthorized ||
  StatusReactionFlavor.forbidden => const StampSpec(barrier: true),
  StatusReactionFlavor.rateLimited => const StampSpec(thuds: 3),
  StatusReactionFlavor.badCertificate => const StampSpec(barrier: true),
  _ => const StampSpec(),
};

/// Brutalist motion: a giant status-code ink-stamp thuds onto the screen, a
/// glitch-shake on errors, and a hard "STAMP" slam on the SEND button. Identity
/// when [reduceEffects].
AppMotion brutalistMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _BrutalReactionOverlay(controller: controller, child: child),
    contentTransition: (context, {required child, required transitionKey}) =>
        _BrutalistContentTransition(transitionKey: transitionKey, child: child),
    tabChipTransition: (context, {required child, required animation}) =>
        _brutalistChipEntrance(animation, child),
    treeDragFeedback: (context, {required child}) =>
        _BrutalistTreeDragFeedback(child: child),
    treeDropHighlight: (context, {required child, required active}) =>
        _BrutalistTreeDropHighlight(active: active, child: child),
    treeExpandFlourish: (context, {required child, required expanded}) =>
        _BrutalistTreeExpandFlourish(expanded: expanded, child: child),
  );
}

/// Brutalist chip entrance: hard slam-in — overshoot scale (1.18→1.0) + fade.
/// The overshoot gives the characteristic brutalist "thud" feel.
Widget _brutalistChipEntrance(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutBack, // natural overshoot
  );
  // Scale overshoots slightly above 1.0 then snaps back — brutalist "slam".
  final scale = Tween<double>(begin: 0, end: 1).animate(curved);
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
    child: ScaleTransition(scale: scale, child: child),
  );
}

/// Slam-in content transition: a thick ink bar slams in from the left edge and
/// retracts (printing-press platen), revealing the new content (~380 ms).
class _BrutalistContentTransition extends StatefulWidget {
  const _BrutalistContentTransition({
    required this.transitionKey,
    required this.child,
  });

  final String transitionKey;
  final Widget child;

  @override
  State<_BrutalistContentTransition> createState() =>
      _BrutalistContentTransitionState();
}

class _BrutalistContentTransitionState
    extends State<_BrutalistContentTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(_BrutalistContentTransition old) {
    super.didUpdateWidget(old);
    if (old.transitionKey != widget.transitionKey) {
      unawaited(_c.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use AppPalette when available (normal runtime); fall back to colorScheme
    // for test environments that don't supply the full brutalist ThemeData.
    final palette = Theme.of(context).extension<AppPalette>();
    final accent =
        palette?.statusSuccess ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child, // hoisted — entire tab content NOT rebuilt per frame
      builder: (ctx, child) {
        if (_c.value == 0 || _c.value == 1) return child!;
        return Stack(
          children: [
            child!,
            Positioned.fill(
              key: const ValueKey<String>('content_transition_overlay'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BrutalistSlamPainter(t: _c.value, color: accent),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Ink-bar slam: sweeps in from the left (0→0.45), holds a beat, then snaps
/// out to the right (0.45→1). The bar is solid, thick, and hard-edged —
/// quintessentially brutalist. Reuses Paint; no per-frame allocation.
class _BrutalistSlamPainter extends CustomPainter {
  _BrutalistSlamPainter({required this.t, required this.color});
  final double t;
  final Color color;

  // Hoisted Paint — reused across frames.
  final Paint _fillPaint = Paint();
  final Paint _edgePaint = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Phase 0→0.45: bar slams in from left, covering full width at 0.45.
    // Phase 0.45→1: bar snaps out to the right.
    double coverFrac;
    double alpha;

    if (t < 0.45) {
      coverFrac = Curves.easeOut.transform(t / 0.45);
      alpha = 0.82;
    } else {
      coverFrac = 1.0 - Curves.easeIn.transform((t - 0.45) / 0.55);
      alpha = 0.82 * (1.0 - Curves.easeIn.transform((t - 0.45) / 0.55));
    }

    if (coverFrac <= 0) return;

    final barW = size.width * coverFrac;

    _fillPaint.color = color.withValues(alpha: alpha * 0.9);
    canvas.drawRect(Rect.fromLTWH(0, 0, barW, size.height), _fillPaint);

    // Hard right edge line.
    _edgePaint
      ..strokeWidth = 4
      ..color = color.withValues(alpha: alpha);
    canvas.drawLine(Offset(barW, 0), Offset(barW, size.height), _edgePaint);
  }

  @override
  bool shouldRepaint(covariant _BrutalistSlamPainter old) =>
      old.t != t || old.color != color;
}

class _BrutalReactionOverlay extends StatefulWidget {
  const _BrutalReactionOverlay({required this.controller, required this.child});
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_BrutalReactionOverlay> createState() => _BrutalReactionOverlayState();
}

class _BrutalReactionOverlayState extends State<_BrutalReactionOverlay>
    with TickerProviderStateMixin {
  AnimationController? _stamp;
  String _label = '';
  bool _isError = false;
  double _weight = 0;
  StampSpec _spec = const StampSpec();

  void _onReaction(ThemeReaction r) {
    if (r.kind == ThemeReactionKind.sendStarted) return;
    _weight = latencyWeight(r.durationMs);
    _spec = stampSpecFor(flavorFor(r));
    final label = switch (r.kind) {
      ThemeReactionKind.cancelled => 'CANCELLED',
      ThemeReactionKind.networkError => 'FAILED',
      _ => '${r.statusCode ?? 0}',
    };
    final isError = r.isError;
    _stamp?.dispose();
    // Declare first so the closure can close over the variable reference.
    late final AnimationController c;
    c =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: 900 + (600 * _weight).round()),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed && mounted) {
            if (_stamp == c) {
              setState(() => _stamp = null);
              c.dispose();
            }
          }
        });
    setState(() {
      _label = label;
      _isError = isError;
      _stamp = c;
    });
    unawaited(c.forward());
  }

  @override
  void dispose() {
    _stamp?.dispose();
    super.dispose();
  }

  double _shakeDx(double t) {
    if (!_isError) return 0;
    final decay = (1 - (t / 0.4)).clamp(0.0, 1.0);
    return math.sin(t * math.pi * 16) * (8 * (0.6 + 0.7 * _weight)) * decay;
  }

  @override
  Widget build(BuildContext context) {
    final stamp = _stamp;
    final palette = context.appPalette;
    final color = _isError ? palette.statusError : palette.statusSuccess;
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      child: stamp == null
          ? widget.child
          : AnimatedBuilder(
              animation: stamp,
              child: widget.child, // hoisted — not rebuilt per frame
              builder: (_, child) {
                final t = stamp.value;
                // Stamp: scale from big->1 in 0..0.18 (the "thud"), hold,
                // fade out.
                final inT = (t / 0.18).clamp(0.0, 1.0);
                final scale =
                    (2.4 + 0.8 * _weight) -
                    (1.4 + 0.8 * _weight) * Curves.easeOutBack.transform(inT);
                final alpha = t < 0.6
                    ? 1.0
                    : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
                final reps = _spec.thuds;
                final pulse = reps <= 1
                    ? inT
                    : Curves.easeOutBack.transform(
                        ((t * reps) % 1.0).clamp(0.0, 1.0),
                      );
                final baseScale = _spec.thuds > 1
                    ? (2.4 + 0.8 * _weight) - 1.2 * pulse
                    : scale;
                final flickerA = _spec.flicker
                    ? (0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * math.pi * 14)))
                    : 1.0;
                final sagDy = _spec.sag ? Curves.easeIn.transform(t) * 60 : 0.0;
                final scatterK = _spec.scatter
                    ? Curves.easeOut.transform(t)
                    : 0.0;
                final stampWidget = IgnorePointer(
                  child: Opacity(
                    opacity: (alpha * flickerA).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, sagDy),
                      child: Transform.scale(
                        scale: baseScale * (1 + scatterK * 0.6),
                        child: Transform.rotate(
                          angle: -0.12,
                          child: _spec.barrier
                              ? _BarrierStamp(label: _label, color: color)
                              : _StampLabel(label: _label, color: color),
                        ),
                      ),
                    ),
                  ),
                );
                final ghost = _spec.doubled
                    ? IgnorePointer(
                        child: Opacity(
                          opacity: (alpha * 0.35).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: const Offset(10, 8),
                            child: Transform.scale(
                              scale: baseScale,
                              child: Transform.rotate(
                                angle: -0.12,
                                child: _StampLabel(label: _label, color: color),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
                return Transform.translate(
                  offset: Offset(_spec.quiet ? 0 : _shakeDx(t), 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [child!, ghost, stampWidget],
                  ),
                );
              },
            ),
    );
  }
}

class _StampLabel extends StatelessWidget {
  const _StampLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: color, width: 6)),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 72,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
    );
  }
}

/// The status code with a thick bar slammed across it — "blocked".
class _BarrierStamp extends StatelessWidget {
  const _BarrierStamp({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _StampLabel(label: label, color: color),
        Transform.rotate(
          angle: 0.18,
          child: Container(width: 220, height: 18, color: color),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// VM-B3: Tree drag/drop/expand juice — Brutalist
// ---------------------------------------------------------------------------

/// Ink-stamp slab chip shown under cursor while dragging a tree node.
/// Hard edges, thick border — quintessentially brutalist.
class _BrutalistTreeDragFeedback extends StatelessWidget {
  const _BrutalistTreeDragFeedback({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Use AppPalette when available; fall back to colorScheme.primary.
    final palette = Theme.of(context).extension<AppPalette>();
    final color =
        palette?.statusSuccess ?? Theme.of(context).colorScheme.primary;
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color, width: 3),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      ),
    );
  }
}

/// Slam outline: hard thick border flashes around a drop target while [active].
class _BrutalistTreeDropHighlight extends StatefulWidget {
  const _BrutalistTreeDropHighlight({
    required this.active,
    required this.child,
  });
  final bool active;
  final Widget child;

  @override
  State<_BrutalistTreeDropHighlight> createState() =>
      _BrutalistTreeDropHighlightState();
}

class _BrutalistTreeDropHighlightState
    extends State<_BrutalistTreeDropHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200), // brutalist = fast snap
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.value = 1.0;
  }

  @override
  void didUpdateWidget(_BrutalistTreeDropHighlight old) {
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
    final palette = Theme.of(context).extension<AppPalette>();
    final color =
        palette?.statusSuccess ?? Theme.of(context).colorScheme.primary;
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
                    // No border-radius — brutalist is sharp
                    border: Border.all(
                      color: color.withValues(alpha: _c.value),
                      width: 4,
                    ),
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

/// Overshoot-bounce scale flourish on the expand icon.
///
/// Uses a [ValueKey] on [expanded] to restart the tween each toggle.
/// [Transform.scale] does not affect layout — row height stays fixed.
class _BrutalistTreeExpandFlourish extends StatelessWidget {
  const _BrutalistTreeExpandFlourish({
    required this.expanded,
    required this.child,
  });
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Animate: slam in at 1.2, then ease back to 1.0 with overshoot.
    return TweenAnimationBuilder<double>(
      key: ValueKey(expanded),
      tween: Tween(begin: 1.2, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      builder: (ctx, v, ch) => Transform.scale(scale: v, child: ch),
      child: child,
    );
  }
}
