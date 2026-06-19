import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
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

/// The selected-tab "glass lozenge": a vertical specular gradient (a bright
/// near-white highlight at the top fading into the accent), a hairline
/// highlight border, and a soft accent glow. This is what makes a selected tab
/// read as a raised piece of glass rather than a flat accent billboard. White
/// labels stay legible because the gradient body is the near-opaque accent.
BoxDecoration glassSelectedTabBox(
  BuildContext context, {
  required BorderRadius borderRadius,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final accent = theme.primaryColor;
  return BoxDecoration(
    borderRadius: borderRadius,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        // Specular highlight: accent lightened toward white at the top edge.
        Color.alphaBlend(Colors.white.withValues(alpha: 0.32), accent),
        accent.withValues(alpha: 0.94),
        // Slight darken at the foot gives the lozenge volume.
        Color.alphaBlend(Colors.black.withValues(alpha: 0.10), accent),
      ],
      stops: const [0, 0.5, 1],
    ),
    border: Border.all(
      color: Colors.white.withValues(alpha: isDark ? 0.30 : 0.55),
      width: context.appLayout.borderThin,
    ),
    boxShadow: [
      BoxShadow(
        color: accent.withValues(alpha: isDark ? 0.45 : 0.35),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Rounded glass tab for the open-request tab strip. Active = the glass
/// lozenge; hover = a faint frosted-white tint with a hairline edge; inactive =
/// transparent (the wallpaper shows behind it). Only the TOP corners round:
/// the tab sits flush on the panel below it, so a rounded bottom would read as
/// a floating chip rather than a tab.
BoxDecoration glassTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  // isFirst is unused: pill tabs have no left-edge rule (kept for API parity).
  final shape = context.appShape;
  final radius = BorderRadius.vertical(
    top: Radius.circular(shape.buttonRadius),
  );
  if (active) return glassSelectedTabBox(context, borderRadius: radius);
  if (hovered) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: radius,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.18),
        width: context.appLayout.borderThin,
      ),
    );
  }
  return BoxDecoration(borderRadius: radius);
}

/// BrandedTabBar selected-tab indicator for glass — the same glass lozenge,
/// top-rounded only so the active PARAMS/HEADERS/BODY segment lifts off the
/// translucent panel as a tab (flush bottom) instead of a floating blue bar.
Decoration glassBrandedTabIndicator(BuildContext context) =>
    glassSelectedTabBox(
      context,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(context.appShape.buttonRadius),
      ),
    );

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
  // Created once in initState for the State's lifetime (a SingleTickerProvider
  // permits one ticker ever — disposing + recreating on an animate toggle threw
  // "multiple tickers"). Built in initState, not lazily, so dispose() never
  // first-initializes it via an unsafe ancestor lookup on a deactivated
  // element. We start/stop it instead of recreating. Stopped, it never
  // notifies, so the painter paints exactly one static frame at zero cost.
  late final AnimationController _controller;

  // Normalized (0..1) pointer position for the specular sheen.
  // Only wired to a MouseRegion when animate is true; static mode skips it
  // entirely so reduced-effects stays zero per-frame cost.
  final ValueNotifier<Offset> _pointer = ValueNotifier<Offset>(
    const Offset(0.5, 0.35),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    );
    if (widget.animate) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(_controller.repeat());
    }
  }

  @override
  void didUpdateWidget(GlassWallpaper old) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? GlassPalette.wallpaperBaseDark
        : GlassPalette.wallpaperBaseLight;
    final blobs = isDark
        ? GlassPalette.wallpaperBlobsDark
        : GlassPalette.wallpaperBlobsLight;
    // Stopped (reduced mode) the controller never notifies -> one static frame;
    // running it drives the drift. Either way it's a valid repaint listenable.
    final t = _controller;
    final stack = Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GlassMeshPainter(
                t: t,
                base: base,
                blobs: blobs,
                // Pass pointer only in animated mode: reduced-effects gets null
                // so the painter doesn't subscribe and stays zero-cost.
                pointer: widget.animate ? _pointer : null,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
    // MouseRegion is only attached in animated mode.  The static (reduced-
    // effects) path returns the Stack unwrapped so pointer moves never trigger
    // a repaint there.
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

/// Paints the glass mesh wallpaper: a base fill plus three drifting
/// radial-gradient blobs, and (in animated mode only) a soft specular sheen
/// that follows the cursor. Mirrors `rpg_decorations.dart`'s
/// `_StarfieldPainter` — a reused `Paint`, repaint driven by the animation,
/// and zero per-frame widget allocation (the previous widget-tree approach
/// rebuilt three `DecoratedBox`es every frame).
///
/// [pointer] is null in reduced-effects mode: the repaint listenable only
/// includes `t` then, so pointer moves never cause a repaint in static mode.
class _GlassMeshPainter extends CustomPainter {
  _GlassMeshPainter({
    required this.t,
    required this.base,
    required this.blobs,
    this.pointer,
  }) : super(
         repaint: pointer == null ? t : Listenable.merge([t, pointer]),
       );

  final Animation<double> t;
  final Color base;
  final List<Color> blobs;

  /// Non-null only in animated mode; drives the specular sheen position.
  final ValueListenable<Offset>? pointer;

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

    // Specular sheen: only in animated mode (pointer != null).
    // A soft radial near-white highlight that follows the cursor, blended with
    // BlendMode.plus so it brightens the mesh rather than covering it.
    // Colors.white is allowed here — lib/core/theme is exempt from the
    // avoid_hardcoded_brand_colors lint.
    final ptr = pointer;
    if (ptr != null) {
      final p = ptr.value;
      final center = Offset(p.dx * size.width, p.dy * size.height);
      final sheen = Paint()
        ..blendMode = BlendMode.plus
        ..shader =
            RadialGradient(
              colors: [
                // theme-internal near-white highlight; Colors.white is allowed
                // under lib/core/theme (exempt from avoid_hardcoded_brand_colors).
                Colors.white.withValues(alpha: 0.06),
                const Color(0x00000000),
              ],
            ).createShader(
              Rect.fromCircle(center: center, radius: size.shortestSide * 0.6),
            );
      canvas.drawRect(rect, sheen);
    }
  }

  @override
  bool shouldRepaint(covariant _GlassMeshPainter old) =>
      old.base != base || old.blobs != blobs || old.pointer != pointer;
}

// C0-continuous oscillation in -1..1 (no dart:math import in the hot path).
double _wave(double t) {
  final x = (t % 1.0) * 2 - 1; // sawtooth in [-1, 1)
  return 1 - (2 * x * x); // parabola, range -1..1
}
