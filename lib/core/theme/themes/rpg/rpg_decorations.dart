import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/motion/ambient_signals.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/core/theme/themes/rpg/rpg_palette.dart';
import 'package:provider/provider.dart';

BoxDecoration rpgPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final shape = context.appShape;
  final border = theme.dividerColor;
  final radius = borderRadius ?? BorderRadius.circular(shape.panelRadius);
  final panelColor = color ?? theme.cardColor;
  return BoxDecoration(
    color: panelColor,
    borderRadius: radius,
    border: Border.all(color: border, width: borderWidth ?? layout.borderThin),
    boxShadow: [
      // Outer gold glow — the arcane aura.
      BoxShadow(
        color: RpgPalette.gold.withValues(alpha: 0.22),
        blurRadius: 14,
      ),
      // Inner deep shadow for depth.
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35),
        offset: const Offset(0, 3),
        blurRadius: 8,
      ),
    ],
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        panelColor,
        Color.lerp(panelColor, RpgPalette.goldDeep, 0.08) ?? panelColor,
      ],
    ),
  );
}

BoxDecoration rpgTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final border = theme.dividerColor;
  const gold = RpgPalette.gold;
  final Color background;
  if (active) {
    background = Color.lerp(theme.cardColor, gold, 0.18) ?? theme.cardColor;
  } else if (hovered) {
    background = Color.lerp(theme.cardColor, gold, 0.08) ?? theme.cardColor;
  } else {
    background = theme.scaffoldBackgroundColor;
  }

  final rule = BorderSide(color: border);
  final goldTop = BorderSide(color: gold, width: layout.borderThick);
  final softTop = BorderSide(color: gold.withValues(alpha: 0.4));

  return BoxDecoration(
    color: background,
    border: Border(
      left: isFirst ? rule : BorderSide.none,
      right: rule,
      bottom: active ? BorderSide.none : rule,
      top: active ? goldTop : (hovered ? softTop : BorderSide.none),
    ),
    boxShadow: active
        ? [
            BoxShadow(
              color: gold.withValues(alpha: 0.4),
              blurRadius: 10,
              spreadRadius: -2,
            ),
          ]
        : null,
  );
}

/// @visibleForTesting C2 sentinel — last idle value read by the painter's
/// paint() on the most recent frame. 0.0 when no pulse is plumbed.
@visibleForTesting
double debugRpgLastIdleFactor = 0;

Widget rpgScaffoldBackground(BuildContext context, {required Widget child}) {
  return _RpgAnimatedBackground(child: child);
}

/// Reduced-effects RPG background: the radial vignette only, no animated
/// starfield (no controller, no per-frame paint).
Widget rpgStaticScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return Stack(
    children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.2,
              colors: [
                theme.scaffoldBackgroundColor,
                if (isDark)
                  Colors.black.withValues(alpha: 0.6)
                else
                  RpgPalette.goldDeep.withValues(alpha: 0.08),
              ],
            ),
          ),
        ),
      ),
      RepaintBoundary(child: child),
    ],
  );
}

/// Slowly drifting starfield + radial vignette behind the app.
///
/// Uses a single long-looping controller to keep cost near zero — particle
/// positions are derived from `t` so there's no per-frame state churn.
class _RpgAnimatedBackground extends StatefulWidget {
  const _RpgAnimatedBackground({required this.child});
  final Widget child;

  @override
  State<_RpgAnimatedBackground> createState() => _RpgAnimatedBackgroundState();
}

class _RpgAnimatedBackgroundState extends State<_RpgAnimatedBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final List<_Mote> _motes;
  late final ValueNotifier<double> _frameNotifier;

  // Parallax pointer: convention is -1..1 from centre (existing starfield).
  final ValueNotifier<Offset> _pointer = ValueNotifier<Offset>(Offset.zero);

  // Resolved from the provider once dependencies are available; null when no
  // provider is registered (e.g. standalone tests).
  WorkspacePulseController? _pulse;

  // Inert stand-in when no provider is registered. Built lazily, disposed
  // here (never by the provider layer).
  WorkspacePulseController? _ownedIdlePulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _frameNotifier = ValueNotifier<double>(0);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    unawaited(_controller.repeat());
    _controller.addListener(() {
      // Quantize to 30 steps per second (60s loop × 30 steps/s = 1800 steps total).
      final q = (_controller.value * (60 * 30)).floorToDouble() / (60 * 30);
      if (q != _frameNotifier.value) _frameNotifier.value = q;
    });
    final rng = math.Random(42);
    _motes = List.generate(45, (_) {
      return _Mote(
        seedX: rng.nextDouble(),
        seedY: rng.nextDouble(),
        speed: 0.15 + rng.nextDouble() * 0.55,
        size: 0.6 + rng.nextDouble() * 1.8,
        twinkleOffset: rng.nextDouble(),
        hue: rng.nextDouble(),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve pulse unconditionally (the Task 11 pulse-resolution lesson):
    // didChangeDependencies does NOT re-fire on prop changes, so gating on an
    // animate flag would miss a re-enable round-trip.
    try {
      _pulse = Provider.of<WorkspacePulseController>(context, listen: false);
    } on ProviderNotFoundException {
      _pulse = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't burn CPU/battery animating the starfield while the app is hidden.
    if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) unawaited(_controller.repeat());
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _frameNotifier.dispose();
    _pointer.dispose();
    _ownedIdlePulse?.dispose();
    super.dispose();
  }

  /// The pulse to bundle into [AmbientSignals]: the real provider controller
  /// when present, otherwise an inert idle stand-in we own. Built once.
  WorkspacePulseController get _effectivePulse =>
      _pulse ?? (_ownedIdlePulse ??= WorkspacePulseController());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final signals = AmbientSignals(
      pointer: _pointer,
      pulse: _effectivePulse,
      isDark: isDark,
    );

    final stack = Stack(
      children: [
        // Radial vignette under everything.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.2,
                colors: [
                  theme.scaffoldBackgroundColor,
                  if (isDark)
                    Colors.black.withValues(alpha: 0.6)
                  else
                    RpgPalette.goldDeep.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
        ),
        RepaintBoundary(child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _StarfieldPainter(
                  tListenable: _frameNotifier,
                  motes: _motes,
                  isDark: isDark,
                  signals: signals,
                  hasPulse: _pulse != null,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Listener(
      onPointerDown: (e) {
        // Keep the pulse awake on pointer-down (touch() is activity).
        if (e.kind != PointerDeviceKind.mouse &&
            e.kind != PointerDeviceKind.stylus) {
          return;
        }
        _pulse?.touch();
      },
      child: MouseRegion(
        onHover: (e) {
          final size = context.size;
          if (size == null) return;
          // Normalized -1..1 from center; parallax keeps each mote shift small.
          _pointer.value = Offset(
            (e.localPosition.dx / size.width) * 2 - 1,
            (e.localPosition.dy / size.height) * 2 - 1,
          );
        },
        child: stack,
      ),
    );
  }
}

class _Mote {
  _Mote({
    required this.seedX,
    required this.seedY,
    required this.speed,
    required this.size,
    required this.twinkleOffset,
    required this.hue,
  });
  final double seedX;
  final double seedY;
  final double speed;
  final double size;
  final double twinkleOffset;
  final double hue;
}

/// Geometry for the traveling shooting star at [fraction] (0..1) of its visible
/// window. The comet `head` advances `travel * fraction` from [origin] along
/// [angle]; `tailStart` trails [bodyLength] behind it (clamped to never run
/// behind the origin). The drawn streak is the short `tailStart → head` body —
/// it *moves*, rather than the whole path being painted as a static line.
@visibleForTesting
({Offset head, Offset tailStart}) rpgShootingStarSegment({
  required Offset origin,
  required double angle,
  required double travel,
  required double bodyLength,
  required double fraction,
}) {
  final f = fraction.clamp(0.0, 1.0);
  final dx = math.cos(angle);
  final dy = math.sin(angle);
  final headDist = travel * f;
  final tailDist = math.max<double>(0, headDist - bodyLength);
  return (
    head: Offset(origin.dx + dx * headDist, origin.dy + dy * headDist),
    tailStart: Offset(origin.dx + dx * tailDist, origin.dy + dy * tailDist),
  );
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.tListenable,
    required this.motes,
    required this.isDark,
    required this.signals,
    required this.hasPulse,
  }) : super(repaint: _repaintFor(tListenable, signals, hasPulse));

  final ValueListenable<double> tListenable;
  final List<_Mote> motes;
  final bool isDark;

  /// Non-null (always passed from animated state).
  final AmbientSignals? signals;
  final bool hasPulse;

  // Reused across motes/frames — only `.color` changes per draw (the immutable
  // blur MaskFilter is set once). Allocating per mote per frame was the hot
  // spot.
  final Paint _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final Paint _corePaint = Paint();
  final Paint _constellationPaint = Paint()..strokeWidth = 0.5;
  final Paint _shootPaint = Paint()..strokeCap = StrokeCap.round;

  static Listenable _repaintFor(
    ValueListenable<double> t,
    AmbientSignals? signals,
    bool hasPulse,
  ) {
    if (signals == null) return t;
    return Listenable.merge([
      t,
      signals.pointer,
      if (hasPulse) signals.pulse,
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = tListenable.value;

    // C2 session rhythm: read idle factor defensively (null-safe).
    // idleFactor (0..1) → dimmer, slower starfield when idle.
    final idleFactor = signals?.pulse.idleFactor ?? 0.0;
    // Write sentinel for tests.
    debugRpgLastIdleFactor = idleFactor;

    // Pointer is -1..1 from centre (parallax convention).
    final par = signals?.pointer.value ?? Offset.zero;
    // Cursor force: convert pointer to pixel coords for distance check.
    // Pointer is -1..1 from centre → pixel centre + (par * halfSize).
    final ptrPxX = size.width * 0.5 + par.dx * size.width * 0.5;
    final ptrPxY = size.height * 0.5 + par.dy * size.height * 0.5;

    // --- Build mote screen positions (parallax + cursor force applied) ---
    final positions = List<Offset>.unmodifiable(
      motes.map((m) {
        final dy = ((m.seedY + t * m.speed) % 1.0) * size.height;
        final dx =
            ((m.seedX +
                    math.sin(
                          (t + m.twinkleOffset) * math.pi * 2,
                        ) *
                        0.01) %
                1.0) *
            size.width;
        // Bigger motes shift more → depth illusion.
        var px = dx + par.dx * (m.size * 4);
        var py = dy + par.dy * (m.size * 4);

        // C1 cursor force: motes repel from pointer position.
        final ddx = px - ptrPxX;
        final ddy = py - ptrPxY;
        final dist = math.sqrt(ddx * ddx + ddy * ddy);
        const forceRadius = 90.0;
        if (dist < forceRadius && dist > 0) {
          final push = (1 - dist / forceRadius) * 24.0;
          px += ddx / dist * push;
          py += ddy / dist * push;
        }

        return Offset(px, py);
      }),
    );

    // C2: compute a single alpha multiplier for all motes (cheap arithmetic).
    // Idle dims the starfield (-40%).
    final alphaMult = 1.0 - 0.4 * idleFactor;

    // --- Draw motes ---
    for (var i = 0; i < motes.length; i++) {
      final m = motes[i];
      final pos = positions[i];

      // Twinkle alpha — pulse each mote on a different phase.
      final twinkle =
          0.3 +
          0.7 *
              (0.5 +
                  0.5 *
                      math.sin(
                        (t * math.pi * 2 + m.twinkleOffset * math.pi * 2) * 1.4,
                      ));
      // C2: apply idle multiplier to the base alpha.
      final alphaBase = (isDark ? 0.55 : 0.18) * alphaMult;
      final color = _colorFor(
        m.hue,
      ).withValues(alpha: (alphaBase * twinkle).clamp(0.0, 1.0));

      _glowPaint.color = color.withValues(alpha: color.a * 0.6);
      canvas.drawCircle(pos, m.size * 2, _glowPaint);

      _corePaint.color = color;
      canvas.drawCircle(pos, m.size, _corePaint);
    }

    // --- Constellation lines ---
    // Compare each mote only to the next ~6 to bound O(n²) cost.
    const maxNeighbours = 6;
    const proximityThreshold = 90.0;
    for (var i = 0; i < positions.length; i++) {
      final a = positions[i];
      final end = math.min(i + maxNeighbours + 1, positions.length);
      for (var j = i + 1; j < end; j++) {
        final b = positions[j];
        final dist = (b - a).distance;
        if (dist < proximityThreshold) {
          // proximity 1 at dist=0, 0 at dist=proximityThreshold.
          final proximity = 1.0 - dist / proximityThreshold;
          _constellationPaint.color = RpgPalette.gold.withValues(
            alpha: 0.06 * proximity,
          );
          canvas.drawLine(a, b, _constellationPaint);
        }
      }
    }

    // --- Shooting star ---
    // A short comet that *travels* the sky once per ~20 s cycle. Everything is
    // derived from `t` (no extra state): as `progress` sweeps the visible
    // window the comet head advances along a seeded diagonal, trailing a
    // tapered tail behind it. (It previously drew the whole path as a static
    // line that only faded in/out — a "fixed yellow line".)
    final shoot = (t * 3) % 1.0;
    if (shoot < 0.12) {
      // Stable diagonal path seeded by the integer cycle index.
      final seed = (t * 3).floor();
      final rng = math.Random(seed);
      // Launch point: somewhere across the upper band of the viewport.
      final origin = Offset(
        rng.nextDouble() * size.width * 0.7,
        rng.nextDouble() * size.height * 0.4,
      );
      final diag = math.sqrt(
        size.width * size.width + size.height * size.height,
      );
      // Travel far enough that the motion reads; the visible body stays short.
      final travel = diag * 0.55;
      final bodyLength = diag * 0.12;
      // Angle between 20°–40° from horizontal for a natural downward streak.
      final angle = math.pi / 9 + rng.nextDouble() * math.pi / 9;

      final progress = shoot / 0.12; // 0..1 across the visible window
      final seg = rpgShootingStarSegment(
        origin: origin,
        angle: angle,
        travel: travel,
        bodyLength: bodyLength,
        fraction: progress,
      );

      // Fade in at launch / out as it leaves frame so it never pops.
      final fade = math
          .min(progress / 0.18, (1.0 - progress) / 0.3)
          .clamp(0.0, 1.0);

      final body = seg.head - seg.tailStart;
      if (body.distanceSquared > 0.5 && fade > 0) {
        // Tapered tail: transparent at the back → bright gold at the head. The
        // streak always points down-right (angle 20–40°), so the gradient runs
        // topLeft (tail) → bottomRight (head) across its bounding box.
        _shootPaint
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              RpgPalette.gold.withValues(alpha: 0),
              RpgPalette.gold.withValues(alpha: 0.8 * fade),
            ],
          ).createShader(Rect.fromPoints(seg.tailStart, seg.head))
          ..strokeWidth = 2.5;
        canvas.drawLine(seg.tailStart, seg.head, _shootPaint);
        _shootPaint.shader = null;

        // Bright spark at the comet head.
        _corePaint.color = RpgPalette.gold.withValues(alpha: 0.9 * fade);
        canvas.drawCircle(seg.head, 1.8, _corePaint);
      }
    }
  }

  Color _colorFor(double h) {
    // Most motes gold, a few cool-colored for variety.
    if (h < 0.7) return RpgPalette.gold;
    if (h < 0.85) return RpgPalette.arcane;
    return RpgPalette.azure;
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.motes != motes ||
      old.isDark != isDark ||
      old.signals != signals ||
      old.hasPulse != hasPulse;
}
