// Arcane Quest (RPG) collections-tree drag/drop/expand motion (AppMotion.
// treeDragFeedback / treeDropHighlight / treeExpandFlourish): a gold rune-glow
// chip under the drag cursor, an animated gold glow-pull border on a drop
// target, and a gold glow flourish on expand/collapse. `rpgMotion` returns
// identity (const AppMotion()) when reduceEffects is true, per
// THEME_AUTHORING's mandatory degradation rule.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/themes/rpg/rpg_palette.dart';

/// Arcane Quest motion: tree drag/drop/expand juice only. Identity when
/// [reduceEffects].
AppMotion rpgMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    treeDragFeedback: (context, {required child}) =>
        _RpgTreeDragFeedback(child: child),
    treeDropHighlight: (context, {required child, required active}) =>
        _RpgTreeDropHighlight(active: active, child: child),
    treeExpandFlourish: (context, {required child, required expanded}) =>
        _RpgTreeExpandFlourish(expanded: expanded, child: child),
  );
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
