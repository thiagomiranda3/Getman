// lib/core/theme/themes/auris/auris_motion.dart
import 'dart:async';
import 'package:auris/auris_widgets.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Sci-fi HUD motion for the AURIS theme: tree drag/drop/expand juice only.
///
/// When [reduceEffects] is true, returns [const AppMotion()] (identity —
/// mandatory degradation per THEME_AUTHORING §5).
AppMotion aurisMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    treeDragFeedback: (context, {required child}) =>
        _AurisTreeDragFeedback(child: child),
    treeDropHighlight: (context, {required child, required active}) =>
        _AurisTreeDropHighlight(active: active, child: child),
    treeExpandFlourish: (context, {required child, required expanded}) =>
        _AurisTreeExpandFlourish(expanded: expanded, child: child),
  );
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
