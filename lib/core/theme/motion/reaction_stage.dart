import 'package:flutter/widgets.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// Subscribes to a [ThemeReactionController] and invokes [onReaction] exactly
/// once per `seq` change. Pure passthrough when [enabled] is false (reduced
/// effects). Themes wrap their overlay painters in this so they don't each
/// re-implement subscription + dedupe.
class ReactionStage extends StatefulWidget {
  const ReactionStage({
    required this.child,
    required this.controller,
    required this.onReaction,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final ThemeReactionController controller;
  final void Function(ThemeReaction reaction) onReaction;
  final bool enabled;

  @override
  State<ReactionStage> createState() => _ReactionStageState();
}

class _ReactionStageState extends State<ReactionStage> {
  int _lastSeq = 0;

  @override
  void initState() {
    super.initState();
    _lastSeq = widget.controller.seq;
    if (widget.enabled) widget.controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(ReactionStage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.enabled != widget.enabled) {
      if (old.enabled) old.controller.removeListener(_onTick);
      _lastSeq = widget.controller.seq;
      if (widget.enabled) widget.controller.addListener(_onTick);
    }
  }

  void _onTick() {
    final c = widget.controller;
    if (c.seq == _lastSeq) return;
    _lastSeq = c.seq;
    final r = c.latest;
    if (r != null) widget.onReaction(r);
  }

  @override
  void dispose() {
    if (widget.enabled) widget.controller.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
