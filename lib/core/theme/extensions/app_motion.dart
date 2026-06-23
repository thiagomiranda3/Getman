import 'package:flutter/material.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// Wraps the whole app: may Transform the child (e.g. screen shake) and Stack
/// transient effects above it. Subscribes to [controller] for reactions.
typedef ReactionOverlayBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required ThemeReactionController controller,
    });

/// VM-B2: wraps the active tab/panel content; plays a themed transition when
/// [transitionKey] changes (keyed on "$activePanelId/$activeTabId").
typedef ContentTransitionBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required String transitionKey,
    });

/// VM-B2: transition builder for tab-strip chips entering/leaving (used as an
/// AnimatedSwitcher/AnimatedList transitionBuilder; [animation] is 0→1 enter).
typedef TabChipTransitionBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required Animation<double> animation,
    });

/// VM-B3: themed widget shown under the cursor while dragging a tree node.
typedef TreeDragFeedbackBuilder =
    Widget Function(BuildContext context, {required Widget child});

/// VM-B3: wraps a folder drop target; [active] is true while a draggable hovers
/// over it (themed highlight + an absorb cue on accept).
typedef TreeDropHighlightBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required bool active,
    });

/// VM-B3: a brief flourish wrapped around a node's expand/collapse toggle;
/// [expanded] is the post-toggle state. NOT a height animation (the TreeView
/// row extent is fixed) — an icon/glow flourish or short overlay only.
typedef TreeExpandFlourishBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required bool expanded,
    });

Widget _identityReactionOverlay(
  BuildContext context, {
  required Widget child,
  required ThemeReactionController controller,
}) => child;

Widget _identityContentTransition(
  BuildContext context, {
  required Widget child,
  required String transitionKey,
}) => child;

Widget _identityTabChipTransition(
  BuildContext context, {
  required Widget child,
  required Animation<double> animation,
}) => child;

Widget _identityTreeDragFeedback(
  BuildContext context, {
  required Widget child,
}) => child;

Widget _identityTreeDropHighlight(
  BuildContext context, {
  required Widget child,
  required bool active,
}) => child;

Widget _identityTreeExpandFlourish(
  BuildContext context, {
  required Widget child,
  required bool expanded,
}) => child;

/// Event-driven motion hooks for a theme. All default to identity, so a theme
/// that supplies no motion is completely unaffected (mirrors
/// AppDecoration.frost). Closures don't lerp — copyWith/lerp follow the
/// AppDecoration pattern.
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    this.reactionOverlay = _identityReactionOverlay,
    this.contentTransition = _identityContentTransition,
    this.tabChipTransition = _identityTabChipTransition,
    this.treeDragFeedback = _identityTreeDragFeedback,
    this.treeDropHighlight = _identityTreeDropHighlight,
    this.treeExpandFlourish = _identityTreeExpandFlourish,
  });

  final ReactionOverlayBuilder reactionOverlay;
  final ContentTransitionBuilder contentTransition;
  final TabChipTransitionBuilder tabChipTransition;
  final TreeDragFeedbackBuilder treeDragFeedback;
  final TreeDropHighlightBuilder treeDropHighlight;
  final TreeExpandFlourishBuilder treeExpandFlourish;

  @override
  AppMotion copyWith({
    ReactionOverlayBuilder? reactionOverlay,
    ContentTransitionBuilder? contentTransition,
    TabChipTransitionBuilder? tabChipTransition,
    TreeDragFeedbackBuilder? treeDragFeedback,
    TreeDropHighlightBuilder? treeDropHighlight,
    TreeExpandFlourishBuilder? treeExpandFlourish,
  }) => AppMotion(
    reactionOverlay: reactionOverlay ?? this.reactionOverlay,
    contentTransition: contentTransition ?? this.contentTransition,
    tabChipTransition: tabChipTransition ?? this.tabChipTransition,
    treeDragFeedback: treeDragFeedback ?? this.treeDragFeedback,
    treeDropHighlight: treeDropHighlight ?? this.treeDropHighlight,
    treeExpandFlourish: treeExpandFlourish ?? this.treeExpandFlourish,
  );

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) => this;
}
