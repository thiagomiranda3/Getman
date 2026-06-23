import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/motion/ambient_signals.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_palette.dart';
import 'package:provider/provider.dart';

/// @visibleForTesting C2 sentinels — last activity/idle values read by the
/// painter's paint() on the most recent frame. 0.0 when no pulse is plumbed.
@visibleForTesting
double debugBrutalistLastActivityLevel = 0;
@visibleForTesting
double debugBrutalistLastIdleFactor = 0;

/// Full-effects Brutalist wallpaper: a slowly drifting risograph/halftone dot
/// grid with a faint accent registration "ghost" offset. This is the C1/C2
/// foundation — [AmbientSignals] (pointer + session pulse) is plumbed through
/// the painter so parallax and rhythm-dimming remain live.
Widget brutalistScaffoldBackgroundAnimated(
  BuildContext context, {
  required Widget child,
}) => _BrutalistAmbient(animate: true, child: child);

/// Reduced-effects Brutalist wallpaper: a single static halftone-dot frame.
/// No controller, no pointer/MouseRegion, no signals — zero per-frame cost.
Widget brutalistStaticScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) => _BrutalistAmbient(animate: false, child: child);

/// Risograph halftone dot-grid wallpaper behind the whole app. When [animate]
/// is true a slow 48 s controller drifts the grid and a faint accent ghost; the
/// widget owns the [AmbientSignals] (normalized 0..1 pointer and a null-safe
/// [WorkspacePulseController]) and threads them into [_HalftonePainter] ONCE.
/// When [animate] is false it renders one static frame (no controller, no
/// pointer, no signals).
class _BrutalistAmbient extends StatefulWidget {
  const _BrutalistAmbient({required this.child, required this.animate});
  final Widget child;
  final bool animate;

  @override
  State<_BrutalistAmbient> createState() => _BrutalistAmbientState();
}

class _BrutalistAmbientState extends State<_BrutalistAmbient>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Created once in initState for the State's lifetime (a SingleTickerProvider
  // permits one ticker ever — disposing + recreating on an animate toggle would
  // throw "multiple tickers"). We start/stop instead of recreating. Stopped, it
  // never notifies, so the painter paints exactly one static frame.
  late final AnimationController _controller;

  // Normalized (0..1) pointer position. Convention: top-left = (0,0),
  // bottom-right = (1,1). Only wired to a MouseRegion in animated mode.
  final ValueNotifier<Offset> _pointer = ValueNotifier<Offset>(
    const Offset(0.5, 0.5),
  );

  // Null-safe in animated mode: read from the provider once dependencies are
  // available; null when no provider is registered (e.g. standalone tests).
  WorkspacePulseController? _pulse;

  // Inert stand-in for [AmbientSignals.pulse] (non-nullable) when no provider
  // is registered. We never add a listener to it, so its internal timer never
  // starts — it stays idle and we own it (disposed below). Built once, lazily.
  WorkspacePulseController? _ownedIdlePulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 48),
    );
    if (widget.animate) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(_controller.repeat());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve pulse unconditionally so a false→true animate flip (via
    // didUpdateWidget) picks up the real provider. didChangeDependencies does
    // NOT re-fire on prop changes — gating on widget.animate would silently
    // miss the re-enable round-trip (C2 regression fix).
    //
    // Null-safe: Provider.of throws when no provider is absent; swallow and
    // leave _pulse null. Standalone tests (no provider) MUST NOT throw.
    // The static path (!widget.animate) never reads _pulse, so unconditional
    // caching is harmless.
    try {
      _pulse = Provider.of<WorkspacePulseController>(context, listen: false);
    } on ProviderNotFoundException {
      _pulse = null;
    }
  }

  @override
  void didUpdateWidget(_BrutalistAmbient old) {
    super.didUpdateWidget(old);
    if (old.animate == widget.animate) return;
    if (widget.animate) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(_controller.repeat());
    } else {
      WidgetsBinding.instance.removeObserver(this);
      _controller.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.animate) return;
    if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) unawaited(_controller.repeat());
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    if (widget.animate) WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _pointer.dispose();
    // Only dispose the fallback we created; the provider's controller is owned
    // by the DI/provider layer, never by us.
    _ownedIdlePulse?.dispose();
    super.dispose();
  }

  /// The pulse to bundle into [AmbientSignals]: the real provider controller
  /// when present, otherwise an inert idle stand-in we own. Built once.
  WorkspacePulseController get _effectivePulse =>
      _pulse ?? (_ownedIdlePulse ??= WorkspacePulseController());

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Built only in animated mode; static passes null so nothing subscribes.
    final signals = widget.animate
        ? AmbientSignals(
            pointer: _pointer,
            // Non-nullable; falls back to an inert idle controller when no
            // provider is registered (see [_effectivePulse]).
            pulse: _effectivePulse,
            isDark: isDark,
          )
        : null;

    final stack = Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _HalftonePainter(
                t: _controller,
                isDark: isDark,
                // Pass the real pulse listenable into repaint: only when one is
                // registered (signals carries the idle fallback for type
                // safety, but we don't want to subscribe to a dead controller).
                hasPulse: _pulse != null,
                signals: signals,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );

    if (!widget.animate) return stack;
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
          if (size == null || size.isEmpty) return;
          _pointer.value = Offset(
            (e.localPosition.dx / size.width).clamp(0.0, 1.0),
            (e.localPosition.dy / size.height).clamp(0.0, 1.0),
          );
        },
        child: stack,
      ),
    );
  }
}

/// Paints the Brutalist risograph halftone wallpaper: a base fill plus a grid
/// of monochrome ink dots whose radius swells/shrinks on a slow drift, with a
/// faint accent "registration ghost" copy offset a pixel or two — the
/// misaligned two-colour riso print look.
///
/// Performance: one reused [Paint] (mutate `.color`), a `Path` reused per frame
/// for dots, no `Paint()`/`Path()`/`Random()` allocation inside `paint()`, and
/// the dot loop is bounded by [_kMaxCols] × [_kMaxRows].
class _HalftonePainter extends CustomPainter {
  _HalftonePainter({
    required this.t,
    required this.isDark,
    required this.hasPulse,
    required this.signals,
  }) : super(repaint: _repaintFor(t, signals, hasPulse));

  final Animation<double> t;
  final bool isDark;
  final bool hasPulse;

  /// Non-null only in animated mode (C1/C2 inputs).
  final AmbientSignals? signals;

  // Reused across dots/frames — only `.color` mutates per draw.
  final Paint _paint = Paint();

  // Built once and reused: a single accumulating Path for the ink dots and one
  // for the ghost copy, so a frame is two drawPath calls (cheap, no per-dot
  // overdraw of state).
  final Path _inkPath = Path();
  final Path _ghostPath = Path();

  static const int _kMaxCols = 40;
  static const int _kMaxRows = 28;
  static const double _kCell = 26; // px between dot centres
  static const double _kMaxRadius = 4.2;

  // Merge only the live listenables: the controller always; pointer when
  // present; the pulse only when a real controller is registered (the idle
  // fallback is never subscribed to, so it never ticks).
  static Listenable _repaintFor(
    Animation<double> t,
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
    final v = t.value; // 0..1 over the loop
    final rect = Offset.zero & size;

    // C2 session rhythm: read pulse values defensively (null-safe).
    // activityLevel (0..1) → more ink density / darker dots when busy.
    // idleFactor (0..1) → lighter, calmer halftone grid when idle.
    final activityLevel = signals?.pulse.activityLevel ?? 0.0;
    final idleFactor = signals?.pulse.idleFactor ?? 0.0;
    // Write sentinels for tests.
    debugBrutalistLastActivityLevel = activityLevel;
    debugBrutalistLastIdleFactor = idleFactor;

    // Base paper fill.
    final base = isDark
        ? BrutalistPalette.backgroundDark
        : BrutalistPalette.backgroundLight;
    canvas.drawRect(
      rect,
      _paint
        ..shader = null
        ..blendMode = BlendMode.srcOver
        ..color = base,
    );

    // Two slow phases (a slight x/y drift) so the grid breathes rather than
    // marching. _wave is C0-continuous in -1..1 (no dart:math in the hot path
    // beyond the cheap sin used for the radius swell below).
    final driftX = _wave(v) * _kCell * 0.5;
    final driftY = _wave(v + 0.27) * _kCell * 0.5;
    // Registration ghost offset: a couple of px of misalignment that itself
    // wobbles — the riso "two plates don't line up" tell.
    final ghostDx = 1.5 + _wave(v + 0.5) * 1.2;
    final ghostDy = 1.5 + _wave(v + 0.13) * 1.2;

    final cols = math.min(_kMaxCols, (size.width / _kCell).ceil() + 2);
    final rows = math.min(_kMaxRows, (size.height / _kCell).ceil() + 2);

    _inkPath.reset();
    _ghostPath.reset();

    // C1 cursor force: pointer 0..1 → pixel coords. Dots near the cursor are
    // pushed radially outward, creating a "parting" effect. Applied per-dot
    // before adding to the path (no allocation — just adjust cx/cy locals).
    final ptr = signals?.pointer.value;
    final ptrPx = ptr != null
        ? Offset(ptr.dx * size.width, ptr.dy * size.height)
        : null;

    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        var cx = c * _kCell + driftX;
        var cy = r * _kCell + driftY;

        // Cursor force: push the dot away from the pointer position.
        if (ptrPx != null) {
          final dx = cx - ptrPx.dx;
          final dy = cy - ptrPx.dy;
          final dist = math.sqrt(dx * dx + dy * dy);
          const forceRadius = 80.0;
          if (dist < forceRadius && dist > 0) {
            final push = (1 - dist / forceRadius) * 28.0;
            cx += dx / dist * push;
            cy += dy / dist * push;
          }
        }

        // Radius swells on a diagonal wave so dots pulse in soft bands.
        final phase = (c + r) * 0.45 + v * math.pi * 2;
        final swell = 0.5 + 0.5 * math.sin(phase);
        final radius = (_kMaxRadius * (0.35 + 0.65 * swell)).clamp(
          0.0,
          _kMaxRadius,
        );
        if (radius <= 0) continue;
        _inkPath.addOval(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        );
        _ghostPath.addOval(
          Rect.fromCircle(
            center: Offset(cx + ghostDx, cy + ghostDy),
            radius: radius,
          ),
        );
      }
    }

    // C2: compute alpha multiplier (cheap arithmetic, no alloc).
    // Activity densifies the ink (up to +50%); idle thins it (down to -35%).
    final alphaMult = (1.0 + 0.5 * activityLevel) * (1.0 - 0.35 * idleFactor);

    // Accent registration ghost first (under the ink), faint.
    canvas.drawPath(
      _ghostPath,
      _paint
        ..shader = null
        ..blendMode = BlendMode.srcOver
        ..color = BrutalistPalette.primary.withValues(
          alpha: ((isDark ? 0.10 : 0.14) * alphaMult).clamp(0.0, 1.0),
        ),
    );

    // Monochrome ink dots on top.
    final ink = isDark ? BrutalistPalette.textDark : BrutalistPalette.textLight;
    canvas.drawPath(
      _inkPath,
      _paint
        ..color = ink.withValues(
          alpha: ((isDark ? 0.06 : 0.05) * alphaMult).clamp(0.0, 1.0),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _HalftonePainter old) =>
      old.isDark != isDark ||
      old.hasPulse != hasPulse ||
      old.signals != signals;
}

// C0-continuous oscillation in -1..1 (cheap, no trig for the drift).
double _wave(double t) {
  final x = (t % 1.0) * 2 - 1; // sawtooth in [-1, 1)
  return 1 - (2 * x * x); // parabola, range -1..1
}
