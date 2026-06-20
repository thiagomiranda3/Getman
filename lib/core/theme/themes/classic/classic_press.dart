import 'package:flutter/material.dart';

/// Subtle press feedback for CLASSIC: a quick opacity dim plus an optional tiny
/// scale on tap — no bounce. When [animate] is false (reduceEffects) it is a
/// plain tap target with no animation.
class ClassicPress extends StatefulWidget {
  const ClassicPress({
    required this.child,
    super.key,
    this.onTap,
    this.scaleDown,
    this.animate = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double? scaleDown;
  final bool animate;

  @override
  State<ClassicPress> createState() => _ClassicPressState();
}

class _ClassicPressState extends State<ClassicPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.child,
      );
    }
    final scale = _pressed ? (widget.scaleDown ?? 0.99) : 1.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          opacity: _pressed ? 0.85 : 1.0,
          child: widget.child,
        ),
      ),
    );
  }
}
