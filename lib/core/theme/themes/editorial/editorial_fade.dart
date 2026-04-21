import 'package:flutter/material.dart';

class EditorialFade extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const EditorialFade({
    super.key,
    required this.child,
    this.onTap,
  });

  @override
  State<EditorialFade> createState() => _EditorialFadeState();
}

class _EditorialFadeState extends State<EditorialFade> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        opacity: _pressed ? 0.7 : 1.0,
        child: widget.child,
      ),
    );
  }
}
