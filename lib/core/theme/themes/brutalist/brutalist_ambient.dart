import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/motion/ambient_signals.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_palette.dart';
import 'package:provider/provider.dart';

/// How long a click impulse stays alive before the widget prunes it. C1 (the
/// ripple render) lands in Task 13; we age + drop entries now so the list never
/// grows unbounded and the painter (later) only ever sees live impulses.
const Duration _kImpulseLifetime = Duration(milliseconds: 1400);

/// Full-effects Brutalist wallpaper: a slowly drifting risograph/halftone dot
/// grid with a faint accent registration "ghost" offset. This is the C1/C2
/// foundation — [AmbientSignals] (pointer + click impulses + session pulse) is
/// plumbed through the painter now so Tasks 13/14 only touch `paint()` logic.
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
/// widget owns the [AmbientSignals] (normalized 0..1 pointer, click impulses,
/// and a null-safe [WorkspacePulseController]) and threads them into
/// [_HalftonePainter] ONCE. When [animate] is false it renders one static frame
/// (no controller, no pointer, no signals).
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

  // Active click ripple seeds (VM-C1). Appended on pointer-down, pruned by age.
  // Only populated in animated mode.
  final ValueNotifier<List<AmbientImpulse>> _impulses =
      ValueNotifier<List<AmbientImpulse>>(const []);

  // Widget-owned monotonic clock for impulse ageing (matches AmbientImpulse's
  // contract — a single source so born/now are comparable).
  final Stopwatch _clock = Stopwatch();

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
      _clock.start();
      WidgetsBinding.instance.addObserver(this);
      unawaited(_controller.repeat());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Null-safe pulse lookup: Provider.of throws when no provider is
    // registered, so swallow that and leave _pulse null. The standalone smoke
    // test pumps WITHOUT a WorkspacePulseController provider — MUST NOT throw.
    if (!widget.animate) {
      _pulse = null;
      return;
    }
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
      _clock.start();
      WidgetsBinding.instance.addObserver(this);
      unawaited(_controller.repeat());
    } else {
      _clock
        ..stop()
        ..reset();
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
    _impulses.dispose();
    // Only dispose the fallback we created; the provider's controller is owned
    // by the DI/provider layer, never by us.
    _ownedIdlePulse?.dispose();
    super.dispose();
  }

  /// The pulse to bundle into [AmbientSignals]: the real provider controller
  /// when present, otherwise an inert idle stand-in we own. Built once.
  WorkspacePulseController get _effectivePulse =>
      _pulse ?? (_ownedIdlePulse ??= WorkspacePulseController());

  void _addImpulse(Offset normalized) {
    final nowMs = _clock.elapsedMilliseconds;
    final cutoff = nowMs - _kImpulseLifetime.inMilliseconds;
    // Prune aged entries while appending the fresh one (bounded list).
    final next = <AmbientImpulse>[
      for (final imp in _impulses.value)
        if (imp.bornAtMs >= cutoff) imp,
      AmbientImpulse(position: normalized, bornAtMs: nowMs),
    ];
    _impulses.value = next;
    // Clicking is activity — keep the session pulse awake (no-op if null).
    _pulse?.touch();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Built only in animated mode; static passes null so nothing subscribes.
    final signals = widget.animate
        ? AmbientSignals(
            pointer: _pointer,
            impulses: _impulses,
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
        final size = context.size;
        if (size == null || size.isEmpty) return;
        _addImpulse(
          Offset(
            (e.localPosition.dx / size.width).clamp(0.0, 1.0),
            (e.localPosition.dy / size.height).clamp(0.0, 1.0),
          ),
        );
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
/// This task renders ONLY the base animated grid (drift + ghost). The cursor
/// force (C1), click ripple (C1), and rhythm-dimming (C2) land in Tasks 13/14;
/// [signals] is already plumbed so those tasks add `paint()` logic without
/// changing this constructor.
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

  /// Non-null only in animated mode (C1/C2 inputs). Read by Tasks 13/14.
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

  // Merge only the live listenables: the controller always; pointer + impulses
  // when present; the pulse only when a real controller is registered (the idle
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
      signals.impulses,
      if (hasPulse) signals.pulse,
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value; // 0..1 over the loop
    final rect = Offset.zero & size;

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

    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        final cx = c * _kCell + driftX;
        final cy = r * _kCell + driftY;
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

    // Accent registration ghost first (under the ink), faint.
    canvas.drawPath(
      _ghostPath,
      _paint
        ..shader = null
        ..blendMode = BlendMode.srcOver
        ..color = BrutalistPalette.primary.withValues(
          alpha: isDark ? 0.10 : 0.14,
        ),
    );

    // Monochrome ink dots on top.
    final ink = isDark ? BrutalistPalette.textDark : BrutalistPalette.textLight;
    canvas.drawPath(
      _inkPath,
      _paint..color = ink.withValues(alpha: isDark ? 0.06 : 0.05),
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
