// AURIS scaffold-background ambient: a scanning sci-fi HUD grid with a slow
// radar sweep arc and drifting telemetry ticks, painted by a single
// RepaintBoundary'd CustomPainter. `aurisScaffoldBackgroundAnimated` (full
// effects) plumbs AmbientSignals (pointer + WorkspacePulseController session
// pulse) so parallax + idle-dimming stay live; `aurisStaticScaffoldBackground`
// (reduceEffects) renders one still frame with no controller/pointer/signals.
// Wired into `auris_theme.dart`'s AppDecoration.scaffoldBackground.
//
// Gotchas: the AnimationController is created once in initState and
// start/stopped (never disposed+recreated) because SingleTickerProviderState
// permits only one ticker ever. Pulse is resolved unconditionally in
// didChangeDependencies (not gated on animate) so a false->true toggle picks
// up the real provider. The HUD palette falls back to neutral Theme colours
// (never a hardcoded AURIS gold) when AurisScheme is absent from the theme.

import 'dart:async';
import 'dart:math' as math;

import 'package:auris/auris.dart' show AurisScheme;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/motion/ambient_signals.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:provider/provider.dart';

/// @visibleForTesting C2 sentinel — last idle value read by the painter's
/// paint() on the most recent frame. 0.0 when no pulse is plumbed.
@visibleForTesting
double debugAurisLastIdleFactor = 0;

/// Full-effects AURIS wallpaper: a scanning sci-fi HUD grid (faint gridlines)
/// with a slow radar sweep arc and drifting telemetry ticks. [AmbientSignals]
/// (pointer + session pulse) is plumbed through the painter so parallax and
/// rhythm-dimming remain live.
Widget aurisScaffoldBackgroundAnimated(
  BuildContext context, {
  required Widget child,
}) => _AurisAmbient(animate: true, child: child);

/// Reduced-effects AURIS wallpaper: a single still HUD grid frame (no radar
/// sweep motion). No controller, no pointer/MouseRegion, no signals — zero
/// per-frame cost.
Widget aurisStaticScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) => _AurisAmbient(animate: false, child: child);

/// Scanning HUD-grid wallpaper behind the whole AURIS app. When [animate] is
/// true a slow 30 s controller drives a radar sweep arc and a gentle gridline
/// drift; the widget owns the [AmbientSignals] (normalized 0..1 pointer and a
/// null-safe [WorkspacePulseController]) and threads them into
/// [_AurisHudPainter] ONCE. When [animate] is false it renders one static grid
/// frame (no controller, no pointer, no signals).
class _AurisAmbient extends StatefulWidget {
  const _AurisAmbient({required this.child, required this.animate});
  final Widget child;
  final bool animate;

  @override
  State<_AurisAmbient> createState() => _AurisAmbientState();
}

class _AurisAmbientState extends State<_AurisAmbient>
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

  // Resolved from the provider once dependencies are available; null when no
  // provider is registered (e.g. standalone tests / web without DI).
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
      duration: const Duration(seconds: 30),
    );
    if (widget.animate) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(_controller.repeat());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve pulse UNCONDITIONALLY so a false→true animate flip (via
    // didUpdateWidget) picks up the real provider. didChangeDependencies does
    // NOT re-fire on prop changes — gating on widget.animate would silently
    // miss the re-enable round-trip (the Task 11 pulse-resolution lesson).
    //
    // Null-safe: Provider.of throws when no provider is present; swallow and
    // leave _pulse null. Standalone tests (no provider) MUST NOT throw. The
    // static path (!widget.animate) never reads _pulse, so unconditional
    // caching is harmless.
    try {
      _pulse = Provider.of<WorkspacePulseController>(context, listen: false);
    } on ProviderNotFoundException {
      _pulse = null;
    }
  }

  @override
  void didUpdateWidget(_AurisAmbient old) {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Read HUD colours from AurisScheme. When absent (a smoke test pumped
    // without the AURIS theme, or a transitional theme switch) the painter
    // degrades to a neutral pass using Theme colours rather than a wrong
    // hardcoded brand colour (the Task 5/7 lesson). We resolve the scheme here
    // and pass a fully-resolved palette down; never hardcode an AURIS gold.
    final scheme = theme.extension<AurisScheme>();

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
              painter: _AurisHudPainter(
                t: _controller,
                palette: _AurisHudPalette.resolve(scheme, theme),
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

/// The resolved HUD colour set the painter draws with. Resolving from
/// [AurisScheme] happens ONCE per build (cheap), so the painter holds plain
/// [Color]s and never touches `Theme.of`. When the scheme is absent we fall
/// back to neutral [ThemeData] colours — never a hardcoded AURIS gold.
@immutable
class _AurisHudPalette {
  const _AurisHudPalette({
    required this.base,
    required this.grid,
    required this.sweep,
    required this.tick,
    required this.hasScheme,
  });

  factory _AurisHudPalette.resolve(AurisScheme? scheme, ThemeData theme) {
    if (scheme == null) {
      // Neutral fallback: no AurisScheme means we render a plain, faint grid
      // using the active theme's own colours (Task 5/7 lesson — never a wrong
      // hardcoded brand colour). The base is transparent so we don't fight the
      // scaffold fill underneath.
      final neutral = theme.dividerColor;
      return _AurisHudPalette(
        base: const Color(0x00000000),
        grid: neutral,
        sweep: theme.colorScheme.primary,
        tick: neutral,
        hasScheme: false,
      );
    }
    return _AurisHudPalette(
      base: scheme.surfacePage,
      // Gridlines: the resting outline — a faint structural lattice.
      grid: scheme.borderResting,
      // Radar sweep: the active primary (amber/gold), the HUD's live colour.
      sweep: scheme.primaryActive,
      // Telemetry ticks: the cool secondary so they read as separate data.
      tick: scheme.secondary,
      hasScheme: true,
    );
  }

  /// Page fill behind the grid.
  final Color base;

  /// Faint gridline colour.
  final Color grid;

  /// Radar-sweep arc colour (the bright leading edge + trail).
  final Color sweep;

  /// Drifting telemetry-tick colour.
  final Color tick;

  /// Whether an AurisScheme was present (drives the equality used by
  /// shouldRepaint so a scheme appearing/disappearing forces a repaint).
  final bool hasScheme;

  @override
  bool operator ==(Object other) =>
      other is _AurisHudPalette &&
      other.base == base &&
      other.grid == grid &&
      other.sweep == sweep &&
      other.tick == tick &&
      other.hasScheme == hasScheme;

  @override
  int get hashCode => Object.hash(base, grid, sweep, tick, hasScheme);
}

/// Paints the AURIS scanning-HUD wallpaper: a base fill, a faint scanning grid
/// (cached as a [Path] keyed by size — never rebuilt per frame), a slow radar
/// sweep arc emanating from the centre, and a handful of drifting telemetry
/// ticks along the grid.
///
/// Performance: reused [Paint] objects (mutate `.color`/`.shader`); the
/// gridline [Path] is built once and cached, invalidated only when [Size]
/// changes; no `Paint()`/`Path()`/`Random()` allocation inside `paint()` beyond
/// the per-frame sweep shader (a single gradient, unavoidable for a moving
/// sweep). The grid loop is bounded by [_kMaxLines] each axis.
class _AurisHudPainter extends CustomPainter {
  _AurisHudPainter({
    required this.t,
    required this.palette,
    required this.hasPulse,
    required this.signals,
  }) : super(repaint: _repaintFor(t, signals, hasPulse));

  final Animation<double> t;
  final _AurisHudPalette palette;
  final bool hasPulse;

  /// Non-null only in animated mode (C1/C2 inputs).
  final AmbientSignals? signals;

  // Reused across frames — `.color`/`.shader`/`.strokeWidth` mutate per draw.
  final Paint _fillPaint = Paint();
  final Paint _gridPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _sweepPaint = Paint();
  final Paint _tickPaint = Paint();
  // Dedicated paint for the bright leading radar spoke — owns its own
  // strokeWidth so the grid paint is never mutated-and-restored between frames
  // (a future paint pass inserted between would bleed the wrong strokeWidth).
  final Paint _spokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  // Gridline Path cache — built once, reused across frames; rebuilt only when
  // Size changes. NEVER rebuilt per frame (the drift is applied via a canvas
  // translate, not by regenerating the Path).
  Size? _gridSize;
  final Path _gridPath = Path();

  static const double _kCell = 44; // px between gridlines
  static const int _kMaxLines = 80; // bound per axis (huge-window guard)

  // Telemetry-tick seeds: (normalized-x, normalized-y, phase). Deterministic so
  // there is no Random() in the hot path; they drift sinusoidally with `t`.
  static const List<(double, double, double)> _kTickSeeds = [
    (0.12, 0.22, 0.0),
    (0.78, 0.16, 0.4),
    (0.55, 0.84, 0.8),
    (0.90, 0.60, 0.2),
    (0.22, 0.72, 0.6),
    (0.40, 0.34, 0.9),
  ];

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

  void _rebuildGrid(Size size) {
    _gridPath.reset();
    // One extra cell each way so the drift never reveals an unpainted edge.
    final cols = math.min(_kMaxLines, (size.width / _kCell).ceil() + 2);
    final rows = math.min(_kMaxLines, (size.height / _kCell).ceil() + 2);
    for (var c = 0; c <= cols; c++) {
      final x = c * _kCell;
      _gridPath
        ..moveTo(x, -_kCell)
        ..lineTo(x, size.height + _kCell);
    }
    for (var r = 0; r <= rows; r++) {
      final y = r * _kCell;
      _gridPath
        ..moveTo(-_kCell, y)
        ..lineTo(size.width + _kCell, y);
    }
    _gridSize = size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final v = t.value; // 0..1 over the 30 s loop
    final rect = Offset.zero & size;

    // C2 session rhythm: read idle factor defensively (null-safe).
    // idleFactor (0..1) → dimmer, calmer HUD when idle.
    final idleFactor = signals?.pulse.idleFactor ?? 0.0;
    // Write sentinel for tests.
    debugAurisLastIdleFactor = idleFactor;

    // C2 multiplier: idle dims HUD elements (down to -30%).
    // Grid gets a subtler effect (always faint).
    final hudMult = 1.0 - 0.3 * idleFactor;
    final gridMult = 1.0 - 0.2 * idleFactor;

    // Slightly stronger when the AurisScheme is present (the scheme-coloured
    // HUD); fainter for the neutral fallback so it never shouts.
    final has = palette.hasScheme;
    final gridAlpha = ((has ? 0.07 : 0.05) * gridMult).clamp(0.0, 1.0);
    final sweepAlpha = ((has ? 0.10 : 0.06) * hudMult).clamp(0.0, 1.0);
    final spokeAlpha = ((has ? 0.16 : 0.10) * hudMult).clamp(0.0, 1.0);
    final tickBaseAlpha = ((has ? 0.22 : 0.14) * hudMult).clamp(0.0, 1.0);

    // Base fill (clear any shader left from a previous frame).
    if (palette.base.a > 0) {
      canvas.drawRect(
        rect,
        _fillPaint
          ..shader = null
          ..blendMode = BlendMode.srcOver
          ..color = palette.base,
      );
    }

    // Build/refresh the cached grid Path only on a size change.
    if (size != _gridSize) _rebuildGrid(size);

    // Scanning grid: a gentle one-cell drift over the loop so the lattice
    // breathes rather than sits dead. Applied via a canvas translate so the
    // Path itself is never regenerated. _wave is C0-continuous in -1..1.
    final driftX = _wave(v) * _kCell * 0.5;
    final driftY = _wave(v + 0.27) * _kCell * 0.5;
    _gridPaint.color = palette.grid.withValues(alpha: gridAlpha);
    canvas
      ..save()
      ..translate(driftX, driftY)
      ..drawPath(_gridPath, _gridPaint)
      ..restore();

    // Radar sweep: a soft angular gradient that rotates once per loop, plus a
    // bright leading spoke. Continuous rotation — NOT a flash (WCAG 2.3.1 is
    // about flashes; a smooth sweep is fine).
    final center = size.center(Offset.zero);
    final radius = size.longestSide * 0.75;
    final angle = v * math.pi * 2;
    _sweepPaint
      ..blendMode = BlendMode.plus
      ..shader = SweepGradient(
        transform: GradientRotation(angle),
        colors: [
          palette.sweep.withValues(alpha: 0),
          palette.sweep.withValues(alpha: 0),
          palette.sweep.withValues(alpha: sweepAlpha),
          palette.sweep.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.72, 0.97, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawRect(rect, _sweepPaint);

    // Bright leading spoke of the sweep — uses its own _spokePaint so
    // _gridPaint.strokeWidth is never mutated (a future paint pass inserted
    // between would bleed the wrong strokeWidth).
    final spokeEnd = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawLine(
      center,
      spokeEnd,
      _spokePaint..color = palette.sweep.withValues(alpha: spokeAlpha),
    );

    // Drifting telemetry ticks: small crosshair marks that bob slowly and fade
    // in/out so the HUD feels alive without strobing.
    for (final seed in _kTickSeeds) {
      final phase = v + seed.$3;
      final bob = _wave(phase) * 0.02;
      // C1 cursor force: ticks lean slightly toward pointer (adds HUD-tracking
      // feel without jarring displacement).
      final ptr = signals?.pointer.value;
      var cx = (seed.$1 + bob) * size.width;
      var cy = (seed.$2 - bob) * size.height;
      if (ptr != null) {
        final targetX = ptr.dx * size.width;
        final targetY = ptr.dy * size.height;
        cx += (targetX - cx) * 0.04;
        cy += (targetY - cy) * 0.04;
      }
      // Slow fade cycle (0..1..0) — no hard on/off, so not a flash.
      final fade = 0.35 + 0.35 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
      _tickPaint
        ..color = palette.tick.withValues(alpha: tickBaseAlpha * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      const arm = 4.0;
      canvas
        ..drawLine(Offset(cx - arm, cy), Offset(cx + arm, cy), _tickPaint)
        ..drawLine(Offset(cx, cy - arm), Offset(cx, cy + arm), _tickPaint);
    }

    // C1 cursor reticle: a small targeting crosshair at the pointer position
    // so the HUD visually "tracks" the cursor. Only in animated mode.
    final ptr = signals?.pointer.value;
    if (ptr != null) {
      final cx = ptr.dx * size.width;
      final cy = ptr.dy * size.height;
      _tickPaint
        ..color = palette.sweep.withValues(alpha: spokeAlpha * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      const reticleArm = 6.0;
      const reticleGap = 3.0;
      // Broken crosshair (gap in centre) — classic HUD targeting reticle.
      canvas
        ..drawLine(
          Offset(cx - reticleArm, cy),
          Offset(cx - reticleGap, cy),
          _tickPaint,
        )
        ..drawLine(
          Offset(cx + reticleGap, cy),
          Offset(cx + reticleArm, cy),
          _tickPaint,
        )
        ..drawLine(
          Offset(cx, cy - reticleArm),
          Offset(cx, cy - reticleGap),
          _tickPaint,
        )
        ..drawLine(
          Offset(cx, cy + reticleGap),
          Offset(cx, cy + reticleArm),
          _tickPaint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _AurisHudPainter old) =>
      old.palette != palette ||
      old.hasPulse != hasPulse ||
      old.signals != signals;
}

// C0-continuous oscillation in -1..1 (cheap; no trig for the drift).
double _wave(double t) {
  final x = (t % 1.0) * 2 - 1; // sawtooth in [-1, 1)
  return 1 - (2 * x * x); // parabola, range -1..1
}
