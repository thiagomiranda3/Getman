// lib/core/theme/themes/auris/auris_motion.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:auris/auris_widgets.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/motion/latency_weight.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Loud sci-fi HUD motion for the AURIS theme.
///
/// When [reduceEffects] is true, returns [const AppMotion()] (identity —
/// mandatory degradation per THEME_AUTHORING §5).
AppMotion aurisMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _AurisReactionOverlay(controller: controller, child: child),
    treeDragFeedback: (context, {required child}) =>
        _AurisTreeDragFeedback(child: child),
    treeDropHighlight: (context, {required child, required active}) =>
        _AurisTreeDropHighlight(active: active, child: child),
    treeExpandFlourish: (context, {required child, required expanded}) =>
        _AurisTreeExpandFlourish(expanded: expanded, child: child),
  );
}

// ---------------------------------------------------------------------------
// Effect kind enum
// ---------------------------------------------------------------------------

/// Visual effect style used by the AURIS HUD reaction overlay.
enum _AurisFx {
  scanSweep, // success: teal/gold scanline sweeps down
  amberFlash, // clientError: amber edge bracket flash
  redAlarm, // serverError/generic networkError: red edge + shake + glitch
  redPulse, // timeout: slow red pulse
  lockGlyph, // badCertificate: lock-glyph frame flash
  fizzle, // cancelled: dim reverse retract
}

/// Parameters that drive a single AURIS effect instance.
class _AurisSpec {
  const _AurisSpec(this.fx, {this.weight = 0.0});
  final _AurisFx fx;

  /// 0..1 latency weight (used to scale scanSweep intensity/duration).
  final double weight;
}

/// Selects the [_AurisSpec] for a given [StatusReactionFlavor].
_AurisSpec _aurisSpecFor(StatusReactionFlavor f, double w) => switch (f) {
  // Success family → scanline sweep
  StatusReactionFlavor.ok ||
  StatusReactionFlavor.created ||
  StatusReactionFlavor.noContent ||
  StatusReactionFlavor.notModified => _AurisSpec(_AurisFx.scanSweep, weight: w),

  // Client-error family → amber bracket flash
  StatusReactionFlavor.unauthorized ||
  StatusReactionFlavor.forbidden ||
  StatusReactionFlavor.notFound ||
  StatusReactionFlavor.rateLimited ||
  StatusReactionFlavor.clientError => const _AurisSpec(_AurisFx.amberFlash),

  // Transport failures
  StatusReactionFlavor.timeout => const _AurisSpec(_AurisFx.redPulse),
  StatusReactionFlavor.badCertificate => const _AurisSpec(_AurisFx.lockGlyph),

  // Server / generic network → red HUD alarm
  StatusReactionFlavor.serverCrash ||
  StatusReactionFlavor.serverError ||
  StatusReactionFlavor.serviceUnavailable ||
  StatusReactionFlavor.networkError => const _AurisSpec(_AurisFx.redAlarm),

  // Cancelled → quick fizzle
  StatusReactionFlavor.cancelled => const _AurisSpec(_AurisFx.fizzle),
};

// ---------------------------------------------------------------------------
// _AurisEffect — a live in-progress effect + its controller
// ---------------------------------------------------------------------------

class _AurisEffect {
  _AurisEffect({
    required this.controller,
    required this.spec,
    required this.color,
    required this.shakeController,
  });
  final AnimationController controller;
  final AnimationController shakeController;
  final _AurisSpec spec;
  final Color color;
}

// ---------------------------------------------------------------------------
// _AurisReactionOverlay
// ---------------------------------------------------------------------------

class _AurisReactionOverlay extends StatefulWidget {
  const _AurisReactionOverlay({
    required this.controller,
    required this.child,
  });
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_AurisReactionOverlay> createState() => _AurisReactionOverlayState();
}

class _AurisReactionOverlayState extends State<_AurisReactionOverlay>
    with TickerProviderStateMixin {
  final List<_AurisEffect> _effects = [];

  // How long the main effect animation runs per fx type:
  static Duration _durationFor(_AurisFx fx, double w) => switch (fx) {
    _AurisFx.scanSweep => Duration(
      milliseconds: 700 + (500 * w).round(),
    ), // faster→heavier
    _AurisFx.amberFlash => const Duration(milliseconds: 500),
    _AurisFx.redAlarm => const Duration(milliseconds: 800),
    _AurisFx.redPulse => const Duration(milliseconds: 1200),
    _AurisFx.lockGlyph => const Duration(milliseconds: 700),
    _AurisFx.fizzle => const Duration(milliseconds: 350),
  };

  void _onReaction(ThemeReaction r) {
    if (r.kind == ThemeReactionKind.sendStarted) return;

    final scheme = Theme.of(context).extension<AurisScheme>();

    // Photosensitivity: all effects are single-shot (one forward() per
    // reaction event). No repeating loops → WCAG 2.3.1 3 Hz cap not
    // triggered. If a repeating blink is ever added, import
    // photosensitivity.dart and clamp via safeFlashCount(sweep, desired).
    final w = latencyWeight(r.durationMs);
    final flavor = flavorFor(r);
    final spec = _aurisSpecFor(flavor, w);

    final color = switch (spec.fx) {
      _AurisFx.scanSweep => scheme?.successBright ?? Colors.tealAccent,
      _AurisFx.amberFlash => scheme?.primaryActive ?? Colors.amber,
      _AurisFx.redAlarm ||
      _AurisFx.redPulse ||
      _AurisFx.lockGlyph => scheme?.dangerBright ?? const Color(0xFFE84838),
      _AurisFx.fizzle => scheme?.primaryDim ?? Colors.amber,
    };

    final duration = _durationFor(spec.fx, w);

    final ctrl = AnimationController(vsync: this, duration: duration);

    // redAlarm gets a brief screen-shake AnimationController (≤4px, brief)
    final shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    final effect = _AurisEffect(
      controller: ctrl,
      spec: spec,
      color: color,
      shakeController: shakeCtrl,
    );

    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _effects.remove(effect));
        ctrl.dispose();
        shakeCtrl.dispose();
      }
    });

    if (spec.fx == _AurisFx.redAlarm) {
      unawaited(shakeCtrl.forward());
    }

    setState(() => _effects.add(effect));
    unawaited(ctrl.forward());
  }

  @override
  void dispose() {
    for (final e in _effects) {
      e.controller.dispose();
      e.shakeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      // Hoist child out of per-frame rebuilds via AnimatedBuilder's child param
      child: AnimatedBuilder(
        animation: _effects.isEmpty
            ? const AlwaysStoppedAnimation(0)
            : Listenable.merge(
                _effects.map((e) => e.controller).toList(),
              ),
        child: widget.child, // hoisted — not rebuilt per frame
        builder: (context, child) {
          Widget result = Stack(
            children: [
              child!, // hoisted app subtree
              for (final e in _effects)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: e.controller,
                        builder: (_, child) => CustomPaint(
                          painter: _aurisPainterFor(e),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );

          // Apply shake offset for redAlarm effects (≤4px, brief 200ms —
          // allowed in non-reduced path per THEME_AUTHORING §5).
          for (final e in _effects) {
            if (e.spec.fx == _AurisFx.redAlarm) {
              final shakeT = e.shakeController.value;
              final offset = shakeT < 1.0
                  ? math.sin(shakeT * math.pi * 4) * 3.0
                  : 0.0;
              result = Transform.translate(
                offset: Offset(offset, 0),
                child: result,
              );
              break; // only first redAlarm shakes
            }
          }
          return result;
        },
      ),
    );
  }
}

CustomPainter _aurisPainterFor(_AurisEffect e) => switch (e.spec.fx) {
  _AurisFx.scanSweep => _AurisScanSweepPainter(
    t: e.controller.value,
    color: e.color,
    weight: e.spec.weight,
  ),
  _AurisFx.amberFlash => _AurisEdgeFlashPainter(
    t: e.controller.value,
    color: e.color,
  ),
  _AurisFx.redAlarm => _AurisRedAlarmPainter(
    t: e.controller.value,
    color: e.color,
  ),
  _AurisFx.redPulse => _AurisRedPulsePainter(
    t: e.controller.value,
    color: e.color,
  ),
  _AurisFx.lockGlyph => _AurisLockGlyphPainter(
    t: e.controller.value,
    color: e.color,
  ),
  _AurisFx.fizzle => _AurisFizzlePainter(
    t: e.controller.value,
    color: e.color,
  ),
};

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// Teal/gold scanline sweep: a horizontal line that sweeps from top to bottom.
/// Intensity (thickness + glow alpha) is scaled by [weight].
class _AurisScanSweepPainter extends CustomPainter {
  _AurisScanSweepPainter({
    required this.t,
    required this.color,
    required this.weight,
  });
  final double t;
  final Color color;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    final y = Curves.easeInOut.transform(t) * size.height;
    final fade = (1.0 - t).clamp(0.0, 1.0);

    // Trailing glow band (wider, dimmer)
    final trailHeight = 8.0 + weight * 12.0;
    final trailRect = Rect.fromLTWH(
      0,
      y - trailHeight,
      size.width,
      trailHeight,
    );
    final trailPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(
            alpha: 0.18 * fade * (0.5 + 0.5 * weight),
          ),
          color.withValues(alpha: 0),
        ],
      ).createShader(trailRect);
    canvas.drawRect(trailRect, trailPaint);

    // Sharp leading scanline
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 + weight
      ..color = color.withValues(alpha: 0.7 * fade);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant _AurisScanSweepPainter old) =>
      old.t != t || old.color != color || old.weight != weight;
}

/// Amber edge/bracket flash for 4xx client errors.
/// Draws four corner brackets that flash in and fade out.
class _AurisEdgeFlashPainter extends CustomPainter {
  _AurisEdgeFlashPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Single flash — no repeat loop needed; t drives the full cycle.
    final flash = t < 0.3
        ? Curves.easeOut.transform(t / 0.3)
        : (1.0 - Curves.easeIn.transform((t - 0.3) / 0.7)).clamp(0.0, 1.0);

    if (flash <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color.withValues(alpha: 0.8 * flash);

    const leg = 24.0;
    final corners = [
      // top-left
      [
        const Offset(0, leg),
        Offset.zero,
        const Offset(leg, 0),
      ],
      // top-right
      [
        Offset(size.width - leg, 0),
        Offset(size.width, 0),
        Offset(size.width, leg),
      ],
      // bottom-right
      [
        Offset(size.width, size.height - leg),
        Offset(size.width, size.height),
        Offset(size.width - leg, size.height),
      ],
      // bottom-left
      [
        Offset(leg, size.height),
        Offset(0, size.height),
        Offset(0, size.height - leg),
      ],
    ];

    for (final pts in corners) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AurisEdgeFlashPainter old) =>
      old.t != t || old.color != color;
}

/// Red HUD alarm: red edge flash + a diagonal glitch line.
/// Combined with a small screen shake in the overlay (via shakeController).
class _AurisRedAlarmPainter extends CustomPainter {
  _AurisRedAlarmPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = (1.0 - t).clamp(0.0, 1.0);

    // Red edge border
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: 0.7 * fade);
    canvas.drawRect(
      Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3),
      edgePaint,
    );

    // Glitch line (appears in 0.1..0.7, then fades)
    if (t > 0.1 && t < 0.7) {
      final glitchFade = t < 0.3
          ? (t - 0.1) / 0.2
          : (1.0 - (t - 0.3) / 0.4).clamp(0.0, 1.0);
      final rng = math.Random(42);
      final y = size.height * (0.3 + rng.nextDouble() * 0.4);
      final xStart = size.width * rng.nextDouble() * 0.3;
      final xEnd = size.width * (0.6 + rng.nextDouble() * 0.4);
      final glitchPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.6 * glitchFade);
      canvas.drawLine(Offset(xStart, y), Offset(xEnd, y + 4), glitchPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AurisRedAlarmPainter old) =>
      old.t != t || old.color != color;
}

/// Slow red pulse for timeout transport failure.
/// A single centered pulsing ring — WCAG 3Hz compliant (single pulse, no loop).
class _AurisRedPulsePainter extends CustomPainter {
  _AurisRedPulsePainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final fade = (1.0 - t).clamp(0.0, 1.0);
    // Single expanding ring — no repeat, no strobe risk.
    final maxR = size.longestSide * 0.6;
    final r = Curves.easeOut.transform(t) * maxR;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.6 * fade);
    canvas.drawCircle(center, r, paint);

    // Soft central bloom
    final bloom = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.12 * fade),
          const Color(0x00000000),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxR * 0.4));
    canvas.drawCircle(center, maxR * 0.4, bloom);
  }

  @override
  bool shouldRepaint(covariant _AurisRedPulsePainter old) =>
      old.t != t || old.color != color;
}

/// Lock-glyph flash for badCertificate — a padlock outline in the center.
class _AurisLockGlyphPainter extends CustomPainter {
  _AurisLockGlyphPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final flash = t < 0.25
        ? Curves.easeOut.transform(t / 0.25)
        : (1.0 - Curves.easeIn.transform((t - 0.25) / 0.75)).clamp(0.0, 1.0);

    if (flash <= 0) return;

    final center = size.center(Offset.zero);
    const bodyW = 32.0;
    const bodyH = 24.0;
    const archR = 12.0;
    const archH = 18.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.8 * flash);

    // Lock body (rounded rect)
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center + const Offset(0, archH / 2),
        width: bodyW,
        height: bodyH,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(bodyRect, paint);

    // Arch (shackle)
    final archPath = Path()
      ..moveTo(center.dx - archR, center.dy + archH / 2)
      ..lineTo(center.dx - archR, center.dy - archH / 2)
      ..arcToPoint(
        Offset(center.dx + archR, center.dy - archH / 2),
        radius: const Radius.circular(archR),
        clockwise: false,
      )
      ..lineTo(center.dx + archR, center.dy + archH / 2);
    canvas.drawPath(archPath, paint);
  }

  @override
  bool shouldRepaint(covariant _AurisLockGlyphPainter old) =>
      old.t != t || old.color != color;
}

/// Cancelled fizzle — a dim, retracting ring that quickly vanishes.
class _AurisFizzlePainter extends CustomPainter {
  _AurisFizzlePainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Ring starts at max radius and collapses inward (retract)
    final maxR = size.longestSide * 0.3;
    final r = (1.0 - Curves.easeIn.transform(t)) * maxR;
    final alpha = (1.0 - t).clamp(0.0, 1.0) * 0.4;
    if (r <= 0 || alpha <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: alpha);
    canvas.drawCircle(center, r, paint);
  }

  @override
  bool shouldRepaint(covariant _AurisFizzlePainter old) =>
      old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// VM-B3: Tree drag/drop/expand juice — AURIS HUD
// ---------------------------------------------------------------------------

/// HUD chip shown under cursor while dragging a tree node.
/// Bails to identity when [AurisScheme] is absent.
class _AurisTreeDragFeedback extends StatelessWidget {
  const _AurisTreeDragFeedback({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).extension<AurisScheme>();
    if (scheme == null) return child;
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryActive.withValues(alpha: 0.15),
          border: Border.all(
            color: scheme.borderActive,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      ),
    );
  }
}

/// HUD lock-on: corner bracket border animates in/out while [active].
/// Bails to identity when [AurisScheme] is absent.
class _AurisTreeDropHighlight extends StatefulWidget {
  const _AurisTreeDropHighlight({
    required this.active,
    required this.child,
  });
  final bool active;
  final Widget child;

  @override
  State<_AurisTreeDropHighlight> createState() =>
      _AurisTreeDropHighlightState();
}

class _AurisTreeDropHighlightState extends State<_AurisTreeDropHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.value = 1.0;
  }

  @override
  void didUpdateWidget(_AurisTreeDropHighlight old) {
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
    final scheme = Theme.of(context).extension<AurisScheme>();
    if (scheme == null) return widget.child;
    if (!widget.active && _c.value == 0) return widget.child;
    final color = scheme.primaryActive;
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
                child: CustomPaint(
                  painter: _AurisHudBracketPainter(
                    t: _c.value,
                    color: color,
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

/// Draws four HUD corner brackets (lock-on style) with opacity = [t].
/// Reuses Paint in constructor — no per-frame alloc.
class _AurisHudBracketPainter extends CustomPainter {
  _AurisHudBracketPainter({required this.t, required this.color});
  final double t;
  final Color color;

  // Hoisted Paint — reused across frames.
  final Paint _paint = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    _paint
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: t);

    const leg = 8.0; // length of each bracket arm

    canvas
      // top-left
      ..drawLine(Offset.zero, const Offset(leg, 0), _paint)
      ..drawLine(Offset.zero, const Offset(0, leg), _paint)
      // top-right
      ..drawLine(Offset(size.width, 0), Offset(size.width - leg, 0), _paint)
      ..drawLine(Offset(size.width, 0), Offset(size.width, leg), _paint)
      // bottom-right
      ..drawLine(
        Offset(size.width, size.height),
        Offset(size.width - leg, size.height),
        _paint,
      )
      ..drawLine(
        Offset(size.width, size.height),
        Offset(size.width, size.height - leg),
        _paint,
      )
      // bottom-left
      ..drawLine(
        Offset(0, size.height),
        Offset(leg, size.height),
        _paint,
      )
      ..drawLine(
        Offset(0, size.height),
        Offset(0, size.height - leg),
        _paint,
      );
  }

  @override
  bool shouldRepaint(covariant _AurisHudBracketPainter old) =>
      old.t != t || old.color != color;
}

/// Teal glow flourish around the expand icon on expand/collapse.
/// Bails to identity when [AurisScheme] is absent.
class _AurisTreeExpandFlourish extends StatelessWidget {
  const _AurisTreeExpandFlourish({
    required this.expanded,
    required this.child,
  });
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).extension<AurisScheme>();
    if (scheme == null) return child;
    final color = scheme.primaryActive;
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
                        color: color.withValues(alpha: 0.6 * v),
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
