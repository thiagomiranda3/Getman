// ThemeSwitchTransition plays a brief one-shot accent sweep/dissolve overlay
// over `child` whenever `themeId` changes, so switching themes feels
// intentional rather than an instant cut. Instant (no overlay) when
// reduceEffects, matching main.dart's `themeAnimationDuration:
// Duration.zero` decision. The sweep accent is `colorScheme.primary`
// (resolved via `themeSwitchSweepAccent`), never `ThemeData.primaryColor` —
// AURIS's kit leaves primaryColor at the framework default (near-black in
// dark mode, stock blue in light), the documented AURIS primaryColor gotcha.
import 'dart:async';

import 'package:flutter/material.dart';

/// Resolves the sweep's accent color for the current theme.
///
/// `colorScheme.primary`, never `ThemeData.primaryColor`: themes that compose
/// an external kit (AURIS) leave `primaryColor` at the framework default —
/// near-black in dark mode, stock blue in light — so a primaryColor sweep
/// reads as an off-brand flash there (the documented AURIS primaryColor
/// gotcha).
@visibleForTesting
Color themeSwitchSweepAccent(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

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

  // Built once per theme change (didChangeDependencies re-fires when Theme
  // changes), not per frame: the painter reads progress straight from the
  // controller and repaints via super(repaint:), so no per-frame painter or
  // Paint allocation (the build-painter-once pattern, see glass_components'
  // _RipplePainter).
  late _SweepPainter _painter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _painter = _SweepPainter(t: _c, color: themeSwitchSweepAccent(context));
  }

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
                child: CustomPaint(painter: _painter),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A horizontal accent sweep that wipes left→right (0..0.5) then reveals
/// (0.5..1). Built once; [t] drives repaint via `super(repaint:)`.
class _SweepPainter extends CustomPainter {
  _SweepPainter({required this.t, required this.color}) : super(repaint: t);
  final Animation<double> t;
  final Color color;

  // Reused across frames — only `.shader` mutates per draw (allocating a
  // Paint per frame was the hot spot).
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // Cover then uncover: a wide band travels left->right; opacity peaks mid.
    final v = t.value;
    final x =
        Curves.easeInOut.transform(v) * (size.width * 1.6) - size.width * 0.3;
    final alpha = (v < 0.5 ? v * 2 : (1 - v) * 2).clamp(0.0, 1.0) * 0.85;
    // Zero-alpha edges keep the ACCENT's RGB — not Color(0x00000000)
    // (transparent BLACK), whose fade drags the band through a muddy dark
    // mid-stop (the documented transparent-lerp gotcha).
    final edge = color.withValues(alpha: 0);
    _paint.shader =
        LinearGradient(
          colors: [
            edge,
            color.withValues(alpha: alpha),
            edge,
          ],
        ).createShader(
          Rect.fromLTWH(
            x - size.width * 0.4,
            0,
            size.width * 0.8,
            size.height,
          ),
        );
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) =>
      old.t != t || old.color != color;
}
