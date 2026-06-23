// lib/core/theme/themes/glass/glass_motion.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';

/// Liquid Glass motion: tree drag/drop/expand juice only. Identity when
/// [reduceEffects].
AppMotion glassMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    treeDragFeedback: (context, {required child}) =>
        _GlassTreeDragFeedback(child: child),
    treeDropHighlight: (context, {required child, required active}) =>
        _GlassTreeDropHighlight(active: active, child: child),
    treeExpandFlourish: (context, {required child, required expanded}) =>
        _GlassTreeExpandFlourish(expanded: expanded, child: child),
  );
}

// ---------------------------------------------------------------------------
// VM-B3: Tree drag/drop/expand juice — Glass
// ---------------------------------------------------------------------------

/// Frosted chip shown under the cursor while dragging a tree node.
class _GlassTreeDragFeedback extends StatelessWidget {
  const _GlassTreeDragFeedback({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).primaryColor;
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      ),
    );
  }
}

/// Animated glow border around drop targets while [active].
class _GlassTreeDropHighlight extends StatefulWidget {
  const _GlassTreeDropHighlight({
    required this.active,
    required this.child,
  });
  final bool active;
  final Widget child;

  @override
  State<_GlassTreeDropHighlight> createState() =>
      _GlassTreeDropHighlightState();
}

class _GlassTreeDropHighlightState extends State<_GlassTreeDropHighlight>
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
  void didUpdateWidget(_GlassTreeDropHighlight old) {
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
    final accent = Theme.of(context).primaryColor;
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
                      color: accent.withValues(alpha: 0.7 * _c.value),
                      width: 2,
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

/// A brief circular glow around the expand icon on expand/collapse.
class _GlassTreeExpandFlourish extends StatelessWidget {
  const _GlassTreeExpandFlourish({
    required this.expanded,
    required this.child,
  });
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).primaryColor;
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
                        color: accent.withValues(alpha: 0.6 * v),
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
