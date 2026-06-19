import 'dart:async';

import 'package:flutter/material.dart';

/// Plays a brief one-shot sweep/dissolve overlay whenever [themeId] changes, so
/// switching themes feels intentional rather than an instant cut. Instant (no
/// overlay) when [reduceEffects] — matching main.dart's themeAnimationDuration:
/// Duration.zero decision.
class ThemeSwitchTransition extends StatefulWidget {
  const ThemeSwitchTransition({
    required this.themeId,
    required this.reduceEffects,
    required this.child,
    super.key,
  });

  final String themeId;
  final bool reduceEffects;
  final Widget child;

  @override
  State<ThemeSwitchTransition> createState() => _ThemeSwitchTransitionState();
}

class _ThemeSwitchTransitionState extends State<ThemeSwitchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void didUpdateWidget(ThemeSwitchTransition old) {
    super.didUpdateWidget(old);
    if (old.themeId != widget.themeId && !widget.reduceEffects) {
      unawaited(_c.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).primaryColor;
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            if (_c.value == 0 || _c.value == 1) return const SizedBox.shrink();
            return Positioned.fill(
              key: const ValueKey('theme_switch_overlay'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SweepPainter(t: _c.value, color: accent),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A horizontal accent sweep that wipes left→right (0..0.5) then reveals
/// (0.5..1).
class _SweepPainter extends CustomPainter {
  _SweepPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Cover then uncover: a wide band travels left->right; opacity peaks mid.
    final x =
        Curves.easeInOut.transform(t) * (size.width * 1.6) - size.width * 0.3;
    final alpha = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0) * 0.85;
    final paint = Paint()
      ..shader =
          LinearGradient(
            colors: [
              const Color(0x00000000),
              color.withValues(alpha: alpha),
              const Color(0x00000000),
            ],
          ).createShader(
            Rect.fromLTWH(
              x - size.width * 0.4,
              0,
              size.width * 0.8,
              size.height,
            ),
          );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) =>
      old.t != t || old.color != color;
}
