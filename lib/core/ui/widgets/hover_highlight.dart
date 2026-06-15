import 'package:flutter/material.dart';

/// Wraps [child] in a hover-aware [AnimatedContainer] whose decoration is
/// produced by [decoration]. The child is built by the caller and held stable
/// across hover changes, so entering/leaving rebuilds only this wrapper's
/// container — never the (potentially large) child subtree. Replaces the
/// per-widget `bool _isHovered + setState` boilerplate that rebuilt whole rows
/// on every mouse enter/exit.
class HoverHighlight extends StatefulWidget {
  const HoverHighlight({
    required this.child,
    required this.decoration,
    super.key,
    this.duration = const Duration(milliseconds: 200),
  });
  final Widget child;

  /// Callback signature: the positional `hovered` flag is the natural shape for
  /// this decoration builder and its closures live in out-of-scope feature
  /// widgets; converting to a named param would change their call sites.
  // ignore: avoid_positional_boolean_parameters
  final BoxDecoration Function(bool hovered) decoration;
  final Duration duration;

  @override
  State<HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<HoverHighlight> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: widget.duration,
        decoration: widget.decoration(_hovered),
        child: widget.child,
      ),
    );
  }
}
