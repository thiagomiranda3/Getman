import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/extensions/app_palette.dart';
import 'package:getman/core/theme/motion/latency_weight.dart';
import 'package:getman/core/theme/motion/photosensitivity.dart';
import 'package:getman/core/theme/motion/reaction_stage.dart';
import 'package:getman/core/theme/motion/status_reaction_flavor.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';

/// The per-flavor spec for the calm pulse bar: which color to use and how many
/// blinks to show across the sweep.
class CalmSpec {
  const CalmSpec({required this.color, this.blinks = 1});
  final Color color;
  final int blinks; // 304 = 2 (déjà-vu), 429 = 3 (throttle)
}

/// Pure mapping from a [StatusReactionFlavor] to a [CalmSpec].
/// [base] is the status color for the current code; [error] is the theme error
/// color. Exhaustive — no unhandled cases.
CalmSpec calmSpecFor(StatusReactionFlavor f, Color base, Color error) {
  switch (f) {
    case StatusReactionFlavor.notModified:
      return CalmSpec(color: base, blinks: 2);
    case StatusReactionFlavor.rateLimited:
      return CalmSpec(color: error, blinks: 3);
    case StatusReactionFlavor.unauthorized:
    case StatusReactionFlavor.forbidden:
    case StatusReactionFlavor.notFound:
    case StatusReactionFlavor.clientError:
    case StatusReactionFlavor.timeout:
      return CalmSpec(color: error);
    case StatusReactionFlavor.serverCrash:
    case StatusReactionFlavor.serviceUnavailable:
    case StatusReactionFlavor.serverError:
    case StatusReactionFlavor.networkError:
      return CalmSpec(color: error);
    case StatusReactionFlavor.badCertificate:
      return CalmSpec(color: error, blinks: 2);
    case StatusReactionFlavor.created:
    case StatusReactionFlavor.noContent:
    case StatusReactionFlavor.ok:
    case StatusReactionFlavor.cancelled:
      return CalmSpec(color: base);
  }
}

/// Restrained reactive motion for the calm themes: a thin status-colored pulse
/// bar that sweeps the top edge on each outcome. No background motion, no
/// shake. Identity when [reduceEffects].
AppMotion calmMotion({required bool reduceEffects}) {
  if (reduceEffects) return const AppMotion();
  return AppMotion(
    reactionOverlay: (context, {required child, required controller}) =>
        _CalmReactionOverlay(controller: controller, child: child),
    // Calm send: keep the existing interactive press; no extra ritual.
  );
}

class _CalmReactionOverlay extends StatefulWidget {
  const _CalmReactionOverlay({required this.controller, required this.child});
  final ThemeReactionController controller;
  final Widget child;

  @override
  State<_CalmReactionOverlay> createState() => _CalmReactionOverlayState();
}

class _CalmReactionOverlayState extends State<_CalmReactionOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _kSweepDuration = Duration(milliseconds: 700);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _kSweepDuration,
  );
  Color? _color;
  int _blinks = 1;
  double _weight = 0;

  void _onReaction(ThemeReaction r) {
    if (r.kind == ThemeReactionKind.sendStarted) return;
    final palette = Theme.of(context).extension<AppPalette>();
    final base =
        palette?.statusColor(r.statusCode ?? 200) ??
        Theme.of(context).colorScheme.primary;
    final error = Theme.of(context).colorScheme.error;
    final spec = calmSpecFor(flavorFor(r), base, error);
    _color = spec.color;
    _blinks = safeFlashCount(_kSweepDuration, spec.blinks);
    _weight = latencyWeight(r.durationMs);
    unawaited(_c.forward(from: 0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReactionStage(
      controller: widget.controller,
      onReaction: _onReaction,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, child) {
                  final color = _color;
                  if (color == null || _c.value == 0 || _c.value == 1) {
                    return const SizedBox.shrink();
                  }
                  // Blink N times across the sweep, fading in/out each blink.
                  // Scale opacity by latency weight so slow responses land
                  // heavier.
                  final t = _c.value;
                  final phase = (t * _blinks) % 1.0;
                  final envelope = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
                  final a = (envelope * (0.5 + 0.5 * _weight)).clamp(0.0, 1.0);
                  return Container(
                    height: 3,
                    color: color.withValues(alpha: a),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
