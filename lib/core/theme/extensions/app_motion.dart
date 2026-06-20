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

/// Wraps the SEND control: plays the theme's send ritual and renders its
/// "charging" state while [isSending].
typedef SendAffordanceBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required bool isSending,
    });

Widget _identityReactionOverlay(
  BuildContext context, {
  required Widget child,
  required ThemeReactionController controller,
}) => child;

Widget _identitySendAffordance(
  BuildContext context, {
  required Widget child,
  required bool isSending,
}) => child;

/// Event-driven motion hooks for a theme. Both default to identity, so a theme
/// that supplies no motion is completely unaffected (mirrors
/// AppDecoration.frost). Closures don't lerp — copyWith/lerp follow the
/// AppDecoration pattern.
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    this.reactionOverlay = _identityReactionOverlay,
    this.sendAffordance = _identitySendAffordance,
  });

  final ReactionOverlayBuilder reactionOverlay;
  final SendAffordanceBuilder sendAffordance;

  @override
  AppMotion copyWith({
    ReactionOverlayBuilder? reactionOverlay,
    SendAffordanceBuilder? sendAffordance,
  }) => AppMotion(
    reactionOverlay: reactionOverlay ?? this.reactionOverlay,
    sendAffordance: sendAffordance ?? this.sendAffordance,
  );

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) => this;
}
