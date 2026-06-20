import 'dart:async';
import 'dart:math' as math;

import 'package:auris/auris_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Plain panel box: [AurisScheme.surfacePanel] fill +
/// [AurisScheme.borderResting] hairline + theme panel radius.
/// The `offset` parameter is ignored — auris has no hard brutalist shadow.
BoxDecoration aurisPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final radius =
      borderRadius ?? BorderRadius.circular(context.appShape.panelRadius);
  // Transitional theme guard: AppDecoration.lerp returns `this`, so this auris
  // closure can run while AurisScheme has been dropped (see _hasAurisScheme in
  // auris_components.dart). Fall back to a plain themed box, not a throw.
  final scheme = theme.extension<AurisScheme>();
  if (scheme == null) {
    return BoxDecoration(
      color: color ?? theme.cardColor,
      border: Border.all(
        color: theme.dividerColor,
        width: borderWidth ?? layout.borderThin,
      ),
      borderRadius: radius,
    );
  }
  return BoxDecoration(
    color: color ?? scheme.surfacePanel,
    border: Border.all(
      color: scheme.borderResting,
      width: borderWidth ?? layout.borderThin,
    ),
    borderRadius: radius,
  );
}

/// Browser-style tab: active = [AurisScheme.surfacePanel] + gold bottom
/// indicator; hovered = [AurisScheme.surfaceInset]; inactive = transparent.
BoxDecoration aurisTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  // Transitional theme guard (see aurisPanelBox): degrade to a plain themed tab
  // when AurisScheme is absent rather than throwing on every frame.
  final scheme = theme.extension<AurisScheme>();
  if (scheme == null) {
    return BoxDecoration(
      color: active
          ? theme.cardColor
          : (hovered ? theme.hoverColor : Colors.transparent),
      border: Border(
        bottom: BorderSide(
          color: active ? theme.primaryColor : Colors.transparent,
          width: layout.borderThick,
        ),
      ),
    );
  }

  final Color bg;
  if (active) {
    bg = scheme.surfacePanel;
  } else if (hovered) {
    bg = scheme.surfaceInset;
  } else {
    bg = Colors.transparent;
  }

  return BoxDecoration(
    color: bg,
    border: Border(
      bottom: BorderSide(
        color: active ? scheme.primaryActive : Colors.transparent,
        width: layout.borderThick,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Scaffold background — animated ambient + static variant
// ---------------------------------------------------------------------------

/// Full-effects wallpaper: animated drifting scanlines + hex ornaments.
Widget aurisScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) => AurisWallpaper(animate: true, child: child);

/// Reduced-effects wallpaper: the same visuals at a fixed phase,
/// no controller, no per-frame paint.
Widget aurisStaticScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) => AurisWallpaper(animate: false, child: child);

/// Ambient wallpaper behind the whole AURIS app: slowly drifting scanlines
/// and faint hex ornaments placed in front of the page background.
///
/// When `animate` is true a 35 s controller drifts the lines; when false it
/// renders one static frame (no per-frame cost). A single
/// [AnimationController] is created in `initState` and kept for the State's
/// lifetime — **never** disposed + recreated when `animate` toggles
/// (a toggle-twice crash: SingleTickerProvider permits only one ticker ever).
/// Instead we `.repeat()`/`.stop()` it in `didUpdateWidget`.
class AurisWallpaper extends StatefulWidget {
  const AurisWallpaper({
    required this.child,
    required this.animate,
    super.key,
  });

  final Widget child;
  final bool animate;

  @override
  State<AurisWallpaper> createState() => _AurisWallpaperState();
}

class _AurisWallpaperState extends State<AurisWallpaper>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Created once in initState, kept for the State's lifetime.
  // We start/stop it via repeat()/stop() — no dispose+recreate.
  // Stopped, it never notifies, so the painter paints exactly one static
  // frame at zero cost (glass's proven pattern).
  late final AnimationController _controller;

  // Normalized (0..1) pointer position for a subtle sheen.
  // Wired to MouseRegion only in animated mode; static mode passes null
  // so the painter doesn't subscribe and stays zero-cost.
  final ValueNotifier<Offset> _pointer = ValueNotifier<Offset>(
    const Offset(0.5, 0.35),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 35),
    );
    if (widget.animate) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(_controller.repeat());
    }
  }

  @override
  void didUpdateWidget(AurisWallpaper old) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Transitional theme guard (see aurisPanelBox): this wraps the WHOLE app
    // via scaffoldBackground, so if AurisScheme is momentarily absent we render
    // the child plain (no ambient) rather than throwing across the entire tree.
    final scheme = Theme.of(context).extension<AurisScheme>();
    if (scheme == null) return widget.child;

    final stack = Stack(
      children: [
        // Ambient layer: scanlines + hex ornaments.
        // Stopped (static mode) the controller never notifies → one static
        // frame. Running it drives the drift.
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AurisScanlinePainter(
                t: _controller,
                scanlineColor: scheme.borderBright,
                // Pointer only in animated mode — reduced-effects stays
                // zero per-frame repaint cost.
                pointer: widget.animate ? _pointer : null,
              ),
            ),
          ),
        ),
        // Drifting hex ornaments — drawn above scanlines, below the app.
        // IgnorePointer so they never steal taps.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: _AurisHexLayer(
                t: _controller,
                scheme: scheme,
                animate: widget.animate,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );

    // MouseRegion only in animated mode — static path returns the Stack
    // unwrapped so pointer moves never trigger a repaint there.
    if (!widget.animate) return stack;
    return MouseRegion(
      onHover: (e) {
        final size = context.size;
        if (size == null) return;
        _pointer.value = Offset(
          e.localPosition.dx / size.width,
          e.localPosition.dy / size.height,
        );
      },
      child: stack,
    );
  }
}

// ---------------------------------------------------------------------------
// Scanline painter
// ---------------------------------------------------------------------------

/// Paints slowly drifting horizontal scanlines — a quintessential sci-fi/HUD
/// motif that suits the AURIS aesthetic.
///
/// The lines translate smoothly downward; because they tile continuously this
/// is perceived as ambient flow, not a strobe (WCAG 2.3.1 flash safety:
/// smooth translation is NOT a flash — no `safeFlashCount` needed here).
/// The optional [pointer] adds a soft sheen in animated mode only.
class _AurisScanlinePainter extends CustomPainter {
  _AurisScanlinePainter({
    required this.t,
    required this.scanlineColor,
    this.pointer,
  }) : super(repaint: pointer == null ? t : Listenable.merge([t, pointer]));

  final Animation<double> t;
  final Color scanlineColor;

  /// Non-null only in animated mode; drives a soft circular sheen.
  final ValueListenable<Offset>? pointer;

  // Reused across frames.
  final Paint _linePaint = Paint()..strokeWidth = 1;
  final Paint _sheenPaint = Paint()..blendMode = BlendMode.plus;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    // Spacing between scanlines (px). Larger = more airy, less oppressive.
    const spacing = 28.0;
    // Drift: lines move downward over the full controller period.
    // At v=0 offset=0; at v=1 offset=spacing (one full tile = seamless loop).
    final offset = v * spacing;

    // Draw lines from top to bottom, tiling with the drift offset.
    _linePaint.color = scanlineColor.withValues(alpha: 0.06);
    var y = offset % spacing - spacing; // start one tile above top edge
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _linePaint);
      y += spacing;
    }

    // Soft sheen in animated mode only.
    final ptr = pointer;
    if (ptr != null) {
      final p = ptr.value;
      final center = Offset(p.dx * size.width, p.dy * size.height);
      _sheenPaint.shader =
          RadialGradient(
            colors: [
              // Low-alpha gold glow at cursor; Colors.transparent for the rim.
              scanlineColor.withValues(alpha: 0.03),
              const Color(0x00000000),
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.shortestSide * 0.55),
          );
      canvas.drawRect(Offset.zero & size, _sheenPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AurisScanlinePainter old) =>
      old.scanlineColor != scanlineColor || old.pointer != pointer;
}

// ---------------------------------------------------------------------------
// Hex ornament layer
// ---------------------------------------------------------------------------

/// A handful of drifting [AurisHexOrnament]s positioned via static seeds so
/// their positions are deterministic and drift slowly with the controller.
///
/// We use a widget-tree approach (not a painter) because [AurisHexOrnament]
/// is a library widget that draws itself — we cannot replicate its paint.
/// The positions are seeded, so there is no per-frame widget allocation.
///
/// When [animate] is false the positions are frozen at the seed values
/// (the controller is stopped, so `t.value` never changes → one static frame).
class _AurisHexLayer extends StatelessWidget {
  const _AurisHexLayer({
    required this.t,
    required this.scheme,
    required this.animate,
  });

  final Animation<double> t;
  final AurisScheme scheme;
  final bool animate;

  // Hex ornament seed data: (normalised-x, normalised-y, size, driftAmplitude)
  static const List<(double, double, double, double)> _seeds = [
    (0.08, 0.12, 40, 0.04),
    (0.82, 0.08, 28, 0.05),
    (0.55, 0.88, 36, 0.03),
    (0.92, 0.62, 22, 0.06),
    (0.18, 0.75, 30, 0.04),
  ];

  @override
  Widget build(BuildContext context) {
    // In static mode just render at seed positions without rebuilding.
    if (!animate) {
      return Stack(
        children: _seeds.map((s) {
          return Positioned(
            left: s.$1 * 1000 - s.$3 / 2, // approximate; LayoutBuilder refines
            top: s.$2 * 700 - s.$3 / 2,
            width: s.$3,
            height: s.$3,
            child: AurisHexOrnament(
              color: scheme.borderBright,
              opacity: 0.18,
              hexRadius: s.$3 / 2,
            ),
          );
        }).toList(),
      );
    }

    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            // Guard against zero-size constraints in tests.
            if (w <= 0 || h <= 0) return const SizedBox.shrink();

            final v = t.value;
            return Stack(
              children: _seeds.map((s) {
                final size = s.$3;
                // Slow sinusoidal drift using the seed amplitude.
                final driftX = math.sin(v * math.pi * 2 + s.$1 * 3) * s.$4 * w;
                final driftY = math.cos(v * math.pi * 2 + s.$2 * 3) * s.$4 * h;
                final left = s.$1 * w + driftX - size / 2;
                final top = s.$2 * h + driftY - size / 2;
                return Positioned(
                  left: left.clamp(-size, w),
                  top: top.clamp(-size, h),
                  width: size,
                  height: size,
                  child: AurisHexOrnament(
                    color: scheme.borderBright,
                    opacity: 0.20,
                    hexRadius: size / 2,
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Press feedback
// ---------------------------------------------------------------------------

/// Auris-flavored press feedback: a quick scale-down on tap-down.
///
/// Like `GlassPress`, the [AnimationController] is created in `initState` and
/// kept for the State's lifetime — never disposed + recreated when `animate`
/// toggles (the SingleTickerProvider-one-ticker invariant). We merely
/// forward/reverse it; in reduced mode we just let it sit idle.
class AurisPress extends StatefulWidget {
  const AurisPress({
    required this.child,
    required this.animate,
    super.key,
    this.onTap,
    this.scaleDown,
  });

  final Widget child;
  final bool animate;
  final VoidCallback? onTap;
  final double? scaleDown;

  @override
  State<AurisPress> createState() => _AurisPressState();
}

class _AurisPressState extends State<AurisPress>
    with SingleTickerProviderStateMixin {
  // Built in initState — never recreated (see glass_press.dart for rationale).
  late final AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AurisTokens.durationFast, // 120 ms — crisp
    );
    _scale = _buildScale();
  }

  Animation<double> _buildScale() =>
      Tween<double>(
        begin: 1,
        end: widget.scaleDown ?? 0.97,
      ).animate(
        CurvedAnimation(parent: _controller, curve: AurisTokens.curveDefault),
      );

  @override
  void didUpdateWidget(AurisPress old) {
    super.didUpdateWidget(old);
    if (old.scaleDown != widget.scaleDown) _scale = _buildScale();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      // Reduced mode: plain tap target, no animation.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        unawaited(_controller.reverse());
        widget.onTap?.call();
      },
      onTapCancel: _controller.reverse,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
