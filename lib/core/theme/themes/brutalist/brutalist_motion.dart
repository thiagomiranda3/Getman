import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// Brutalist motion: a giant status-code ink-stamp thuds onto the screen, a
/// glitch-shake on errors, and a hard "STAMP" slam on the SEND button. Identity
/// when [reduceEffects].
AppMotion brutalistMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _BrutalReactionOverlay(controller: controller, child: child),
    sendAffordance: (context, {required child, required isSending}) =>
        _BrutalStampSend(child: child),
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

  void _onReaction(ThemeReaction r) {
    if (r.kind == ThemeReactionKind.sendStarted) return;
    _label = switch (r.kind) {
      ThemeReactionKind.cancelled => 'CANCELLED',
      ThemeReactionKind.networkError => 'FAILED',
      _ => '${r.statusCode ?? 0}',
    };
    _isError = r.isError;
    _stamp?.dispose();
    final c =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed && mounted) {
            setState(() {});
          }
        });
    setState(() => _stamp = c);
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
    return math.sin(t * math.pi * 16) * 8 * decay;
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
              builder: (_, child) {
                final t = stamp.value;
                // Stamp: scale from big->1 in 0..0.18 (the "thud"), hold,
                // fade out.
                final inT = (t / 0.18).clamp(0.0, 1.0);
                final scale = 2.4 - 1.4 * Curves.easeOutBack.transform(inT);
                final alpha = t < 0.6
                    ? 1.0
                    : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
                return Transform.translate(
                  offset: Offset(_shakeDx(t), 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      widget.child,
                      IgnorePointer(
                        child: Opacity(
                          opacity: alpha,
                          child: Transform.scale(
                            scale: scale,
                            child: Transform.rotate(
                              angle: -0.12,
                              child: _StampLabel(
                                label: _label,
                                color: color,
                              ),
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

/// SEND "STAMP": a hard downward slam onto its shadow on press.
class _BrutalStampSend extends StatefulWidget {
  const _BrutalStampSend({required this.child});
  final Widget child;

  @override
  State<_BrutalStampSend> createState() => _BrutalStampSendState();
}

class _BrutalStampSendState extends State<_BrutalStampSend>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => unawaited(_c.forward(from: 0)),
      onPointerUp: (_) => unawaited(_c.reverse()),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(_c.value * 3, _c.value * 3),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
