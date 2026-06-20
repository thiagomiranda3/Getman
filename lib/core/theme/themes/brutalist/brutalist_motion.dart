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
    sendAffordance: (context, {required child, required isSending}) =>
        _BrutalStampSend(isSending: isSending, child: child),
  );
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

/// SEND "STAMP": a hard downward slam on press + a marching fill bar along the
/// bottom edge while [isSending] (tension builds the longer the wait runs).
class _BrutalStampSend extends StatefulWidget {
  const _BrutalStampSend({required this.isSending, required this.child});
  final bool isSending;
  final Widget child;

  @override
  State<_BrutalStampSend> createState() => _BrutalStampSendState();
}

class _BrutalStampSendState extends State<_BrutalStampSend>
    with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  // 0→1 over kTensionFullMs, then holds at 1 while still sending.
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
  void didUpdateWidget(_BrutalStampSend old) {
    super.didUpdateWidget(old);
    if (widget.isSending && !old.isSending) {
      unawaited(_build.forward(from: 0));
    } else if (!widget.isSending && old.isSending) {
      _build
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _build.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.appPalette.statusSuccess;
    return Listener(
      onPointerDown: (_) => unawaited(_press.forward(from: 0)),
      onPointerUp: (_) => unawaited(_press.reverse()),
      child: AnimatedBuilder(
        animation: Listenable.merge([_press, _build]),
        child: widget.child,
        builder: (_, child) => Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(_press.value * 3, _press.value * 3),
              child: child,
            ),
            if (widget.isSending)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MarchingBarPainter(
                      tension: inFlightTension(
                        (_build.value * kTensionFullMs).round(),
                      ),
                      color: accent,
                      phase: _build.value,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A hard fill bar along the bottom edge: width grows with tension; a marching
/// dash pattern conveys "working".
class _MarchingBarPainter extends CustomPainter {
  _MarchingBarPainter({
    required this.tension,
    required this.color,
    required this.phase,
  });
  final double tension;
  final Color color;

  /// Drives the march: 0→1 as the build controller advances.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 4.0;
    const dash = 10.0;
    const dashPitch = dash * 2; // gap == dash width
    final y = size.height - h;
    final w = size.width * (0.15 + 0.85 * tension);
    final paint = Paint()..color = color;

    // Clip so dashes never paint outside the bar bounds.
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, y, w, h));

    // Phase offset in [0, dashPitch) so the pattern wraps smoothly.
    final offset = (phase * dashPitch) % dashPitch;
    // Start one pitch before 0 so a partial dash can march in from the left.
    for (var x = -dashPitch + offset; x < w; x += dashPitch) {
      canvas.drawRect(Rect.fromLTWH(x, y, dash, h), paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarchingBarPainter old) =>
      old.tension != tension || old.color != color || old.phase != phase;
}
