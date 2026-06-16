import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_palette.dart';

/// Gaussian blur radius for frosted panels. Single tunable so the whole theme's
/// blur intensity moves together.
const double kGlassBlurSigma = 18;

/// Translucent frosted panel: a glassy fill, a hairline "specular" border, and
/// a soft ambient shadow. The fill is translucent so the wallpaper (and, with
/// [glassFrost], the blurred backdrop) read through it. [offset] is accepted
/// for API parity but ignored — glass uses a soft, near-centered shadow.
BoxDecoration glassPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final shape = context.appShape;
  final isDark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: color ?? theme.cardColor,
    borderRadius: borderRadius ?? BorderRadius.circular(shape.panelRadius),
    border: Border.all(
      color: theme.dividerColor,
      width: borderWidth ?? layout.borderThin,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

/// Wraps [child] in real frosted-glass blur, clipped to rounded corners.
/// `RepaintBoundary` isolates the always-visible blur from sibling repaints.
Widget glassFrost(
  BuildContext context, {
  required Widget child,
  BorderRadius? borderRadius,
}) {
  final radius =
      borderRadius ?? BorderRadius.circular(context.appShape.panelRadius);
  return RepaintBoundary(
    child: ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: kGlassBlurSigma,
          sigmaY: kGlassBlurSigma,
        ),
        child: child,
      ),
    ),
  );
}

/// Rounded translucent tab pill. Active = accent fill; hover = faint accent
/// tint; inactive = transparent (the wallpaper shows behind it).
BoxDecoration glassTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  // isFirst is unused: pill tabs have no left-edge rule (kept for API parity).
  final theme = Theme.of(context);
  final shape = context.appShape;
  final accent = theme.primaryColor;
  final Color background;
  if (active) {
    background = accent;
  } else if (hovered) {
    background = accent.withValues(alpha: 0.14);
  } else {
    background = Colors.transparent;
  }
  return BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(shape.buttonRadius),
  );
}

/// Full-effects wallpaper: animated drifting mesh gradient.
Widget glassScaffoldBackground(BuildContext context, {required Widget child}) =>
    GlassWallpaper(animate: true, child: child);

/// Reduced-effects wallpaper: the same mesh gradient, static (no controller).
Widget glassStaticScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) => GlassWallpaper(animate: false, child: child);

/// Soft mesh-gradient wallpaper behind the whole app. The Scaffold above it is
/// transparent, so this is the visible background and panels frost over it.
/// When [animate] is true a slow 40s controller drifts the blobs; when false it
/// renders one static frame (no per-frame cost).
class GlassWallpaper extends StatefulWidget {
  const GlassWallpaper({required this.child, required this.animate, super.key});
  final Widget child;
  final bool animate;

  @override
  State<GlassWallpaper> createState() => _GlassWallpaperState();
}

class _GlassWallpaperState extends State<GlassWallpaper>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      WidgetsBinding.instance.addObserver(this);
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 40),
      );
      unawaited(_controller!.repeat());
    }
  }

  @override
  void didUpdateWidget(GlassWallpaper old) {
    super.didUpdateWidget(old);
    if (old.animate == widget.animate) return;
    if (widget.animate) {
      WidgetsBinding.instance.addObserver(this);
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 40),
      );
      unawaited(_controller!.repeat());
    } else {
      WidgetsBinding.instance.removeObserver(this);
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.resumed) {
      if (!c.isAnimating) unawaited(c.repeat());
    } else {
      c.stop();
    }
  }

  @override
  void dispose() {
    if (widget.animate) WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? GlassPalette.wallpaperBaseDark
        : GlassPalette.wallpaperBaseLight;
    final blobs = isDark
        ? GlassPalette.wallpaperBlobsDark
        : GlassPalette.wallpaperBlobsLight;
    // A stopped animation for the static case never notifies, so the painter
    // paints exactly once; the live controller drives repaints when animated.
    final t = _controller ?? const AlwaysStoppedAnimation<double>(0);
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GlassMeshPainter(t: t, base: base, blobs: blobs),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Paints the glass mesh wallpaper: a base fill plus three drifting
/// radial-gradient blobs. Mirrors `rpg_decorations.dart`'s `_StarfieldPainter`
/// — a reused `Paint`, repaint driven by the animation, and zero per-frame
/// widget allocation (the previous widget-tree approach rebuilt three
/// `DecoratedBox`es every frame).
class _GlassMeshPainter extends CustomPainter {
  _GlassMeshPainter({required this.t, required this.base, required this.blobs})
    : super(repaint: t);
  final Animation<double> t;
  final Color base;
  final List<Color> blobs;

  // Reused across blobs/frames — only `.shader` changes per blob.
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final rect = Offset.zero & size;
    // Base fill (clear any shader left from the previous frame's last blob).
    canvas.drawRect(
      rect,
      _paint
        ..shader = null
        ..color = base,
    );
    final centers = <Alignment>[
      Alignment(-0.8 + 0.2 * _wave(v), -0.9 + 0.15 * _wave(v + 0.33)),
      Alignment(0.9 - 0.2 * _wave(v + 0.5), -0.8 + 0.15 * _wave(v)),
      Alignment(0.4 * _wave(v + 0.66), 0.95 - 0.1 * _wave(v + 0.2)),
    ];
    for (var i = 0; i < blobs.length; i++) {
      final blobRect = Rect.fromCircle(
        center: centers[i].alongSize(size),
        radius: size.shortestSide * 1.1,
      );
      _paint.shader = RadialGradient(
        colors: [blobs[i].withValues(alpha: 0.55), Colors.transparent],
      ).createShader(blobRect);
      canvas.drawRect(rect, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlassMeshPainter old) =>
      old.base != base || old.blobs != blobs;
}

// C0-continuous oscillation in -1..1 (no dart:math import in the hot path).
double _wave(double t) {
  final x = (t % 1.0) * 2 - 1; // sawtooth in [-1, 1)
  return 1 - (2 * x * x); // parabola, range -1..1
}
