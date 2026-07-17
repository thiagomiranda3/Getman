// Brutalist collections-tree drag/drop/expand motion (AppMotion.
// treeDragFeedback / treeDropHighlight / treeExpandFlourish): a hard-bordered
// ink-stamp chip under the drag cursor, a fast thick-border "slam" outline on
// a drop target, and an overshoot-bounce scale flourish on expand/collapse.
// `brutalistMotion` returns identity (const AppMotion()) when reduceEffects is
// true, per THEME_AUTHORING's mandatory degradation rule.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Brutalist motion: tree drag/drop/expand juice only. Identity when
/// [reduceEffects].
AppMotion brutalistMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    treeDragFeedback: (context, {required child}) =>
        _BrutalistTreeDragFeedback(child: child),
    treeDropHighlight: (context, {required child, required active}) =>
        _BrutalistTreeDropHighlight(active: active, child: child),
    treeExpandFlourish: (context, {required child, required expanded}) =>
        _BrutalistTreeExpandFlourish(expanded: expanded, child: child),
  );
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
