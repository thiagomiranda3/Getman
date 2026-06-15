import 'dart:async';

import 'package:flutter/material.dart';

class BrutalBounce extends StatefulWidget {
  const BrutalBounce({
    required this.child,
    super.key,
    this.onTap,
    this.scaleDown = 0.95,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  @override
  State<BrutalBounce> createState() => _BrutalBounceState();
}

class _BrutalBounceState extends State<BrutalBounce>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1, end: widget.scaleDown).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant BrutalBounce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scaleDown != widget.scaleDown) {
      _scaleAnimation = Tween<double>(begin: 1, end: widget.scaleDown).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        unawaited(_controller.reverse());
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
