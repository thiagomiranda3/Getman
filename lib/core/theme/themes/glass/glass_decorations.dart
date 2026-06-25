import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/motion/ambient_signals.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/core/theme/themes/glass/glass_palette.dart';
import 'package:provider/provider.dart';

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

/// The frosted **dialog** card: like [glassFrost] (clip + real backdrop blur)
/// but it also paints the translucent panel fill + hairline border, so the card
/// is a complete surface the dialog content sits in. Used via
/// `AppDecoration.dialogSurface` at full effects only.
Widget glassDialogSurface(
  BuildContext context, {
  required Widget child,
  required BorderRadius borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  return RepaintBoundary(
    child: ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: kGlassBlurSigma,
          sigmaY: kGlassBlurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.cardColor, // glass panel fill; the blur frosts it
            borderRadius: borderRadius,
            border: Border.all(
              color: theme.dividerColor,
              width: layout.borderThin,
            ),
          ),
          child: child,
        ),
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
// topBorder is accepted for API parity with the indicator hook but not used:
// the glass lozenge is a rounded, top-cornered pill (no flat top edge to drop),
// so it reads cleanly inside the Settings tab strip's dividers either way.
Decoration glassBrandedTabIndicator(
  BuildContext context, {
  bool topBorder = true,
}) => glassSelectedTabBox(
  context,
  borderRadius: BorderRadius.vertical(
    top: Radius.circular(context.appShape.buttonRadius),
  ),
);

/// @visibleForTesting C2 sentinel — last idle value read by the painter's
/// paint() on the most recent frame. 0.0 when no pulse is plumbed
/// (static / no-provider path). Read by rhythm tests to confirm C2 wiring.
@visibleForTesting
double debugGlassLastIdleFactor = 0;

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

  // Resolved from the provider once dependencies are available; null when no
  // provider is registered (e.g. standalone tests).
  WorkspacePulseController? _pulse;

  // Inert stand-in when no provider is registered. Built lazily, disposed
  // here (never by the provider layer).
  WorkspacePulseController? _ownedIdlePulse;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve pulse unconditionally (the Task 11 pulse-resolution lesson).
    try {
      _pulse = Provider.of<WorkspacePulseController>(context, listen: false);
    } on ProviderNotFoundException {
      _pulse = null;
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
    final base = isDark
        ? GlassPalette.wallpaperBaseDark
        : GlassPalette.wallpaperBaseLight;
    final blobs = isDark
        ? GlassPalette.wallpaperBlobsDark
        : GlassPalette.wallpaperBlobsLight;
    // Stopped (reduced mode) the controller never notifies -> one static frame;
    // running it drives the drift. Either way it's a valid repaint listenable.
    final t = _controller;

    // Built only in animated mode; static passes null so nothing subscribes.
    final signals = widget.animate
        ? AmbientSignals(
            pointer: _pointer,
            pulse: _effectivePulse,
            isDark: isDark,
          )
        : null;

    final stack = Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GlassMeshPainter(
                t: t,
                base: base,
                blobs: blobs,
                signals: signals,
                hasPulse: _pulse != null,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
    // Listener + MouseRegion are only attached in animated mode.  The static
    // (reduced-effects) path returns the Stack unwrapped so pointer moves and
    // clicks never trigger a repaint there.
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
          if (size == null) return;
          _pointer.value = Offset(
            e.localPosition.dx / size.width,
            e.localPosition.dy / size.height,
          );
        },
        child: stack,
      ),
    );
  }
}

/// Paints the glass mesh wallpaper: a base fill plus three drifting
/// radial-gradient blobs, and (in animated mode only) a soft specular sheen
/// that follows the cursor. Mirrors `rpg_decorations.dart`'s
/// `_StarfieldPainter` — reused [Paint] objects, repaint driven by the
/// animation, and zero per-frame allocation (the previous widget-tree approach
/// rebuilt three `DecoratedBox`es every frame; the earlier per-frame `sheen`
/// Paint allocation has been moved to a field).
///
/// [signals] is null in reduced-effects mode: the repaint listenable only
/// includes `t` then, so pointer moves and clicks never cause a repaint in
/// static mode.
class _GlassMeshPainter extends CustomPainter {
  _GlassMeshPainter({
    required this.t,
    required this.base,
    required this.blobs,
    this.signals,
    this.hasPulse = false,
  }) : super(repaint: _repaintFor(t, signals, hasPulse));

  final Animation<double> t;
  final Color base;
  final List<Color> blobs;

  /// Non-null only in animated mode; drives sheen + parallax.
  final AmbientSignals? signals;
  final bool hasPulse;

  // Reused across blobs/frames — only `.shader`/`.color` changes per draw.
  final Paint _paint = Paint();

  // Specular sheen paint — reused across frames (was incorrectly allocated
  // inside paint() before C1 work; moved to a field to eliminate per-frame
  // Paint construction).
  // Colors.white is allowed in lib/core/theme (exempt from
  // avoid_hardcoded_brand_colors).
  final Paint _sheenPaint = Paint()..blendMode = BlendMode.plus;

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
    final v = t.value;
    final rect = Offset.zero & size;

    // C2 session rhythm: read idle factor defensively (null-safe).
    // idleFactor (0..1) → dim and calm the mesh when idle.
    final idleFactor = signals?.pulse.idleFactor ?? 0.0;
    // Write sentinel for tests.
    debugGlassLastIdleFactor = idleFactor;

    // Base fill (clear any shader left from the previous frame's last blob).
    canvas.drawRect(
      rect,
      _paint
        ..shader = null
        ..color = base,
    );

    // C1 cursor force: blobs lean slightly toward the pointer. Each blob centre
    // is offset a fraction of the way toward the pointer, giving the mesh a
    // subtle magnetic "pull toward cursor" feel.
    final ptr = signals?.pointer.value;
    final ptrAlign = ptr != null
        ? Alignment((ptr.dx * 2 - 1) * 0.12, (ptr.dy * 2 - 1) * 0.12)
        : Alignment.center;

    final centers = <Alignment>[
      Alignment(
        -0.8 + 0.2 * _wave(v) + ptrAlign.x,
        -0.9 + 0.15 * _wave(v + 0.33) + ptrAlign.y,
      ),
      Alignment(
        0.9 - 0.2 * _wave(v + 0.5) + ptrAlign.x,
        -0.8 + 0.15 * _wave(v) + ptrAlign.y,
      ),
      Alignment(
        0.4 * _wave(v + 0.66) + ptrAlign.x,
        0.95 - 0.1 * _wave(v + 0.2) + ptrAlign.y,
      ),
    ];
    // C2: idle dims blob opacity.
    // Base blob alpha 0.55; down to 0.33 on full idle.
    // Multiplier is cheap arithmetic — no per-frame alloc.
    final blobAlpha = (0.55 * (1 - 0.4 * idleFactor)).clamp(
      0.0,
      1.0,
    );
    for (var i = 0; i < blobs.length; i++) {
      final blobRect = Rect.fromCircle(
        center: centers[i].alongSize(size),
        radius: size.shortestSide * 1.1,
      );
      _paint.shader = RadialGradient(
        colors: [
          blobs[i].withValues(alpha: blobAlpha),
          Colors.transparent,
        ],
      ).createShader(blobRect);
      canvas.drawRect(rect, _paint);
    }

    // Specular sheen: only in animated mode (signals != null).
    // A soft radial near-white highlight that follows the cursor, blended with
    // BlendMode.plus so it brightens the mesh rather than covering it.
    // C2: dim the sheen when idle; intensify slightly when active.
    if (ptr != null) {
      final center = Offset(ptr.dx * size.width, ptr.dy * size.height);
      // C2: sheen alpha dims on idle (0.06 → 0.03). Cheap multiplier — no
      // per-frame alloc.
      final sheenAlpha = (0.06 * (1 - 0.5 * idleFactor)).clamp(
        0.0,
        1.0,
      );
      _sheenPaint.shader =
          RadialGradient(
            colors: [
              // theme-internal near-white; Colors.white is allowed in
              // lib/core/theme (exempt from avoid_hardcoded_brand_colors).
              Colors.white.withValues(alpha: sheenAlpha),
              const Color(0x00000000),
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.shortestSide * 0.6),
          );
      canvas.drawRect(rect, _sheenPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlassMeshPainter old) =>
      old.base != base ||
      old.blobs != blobs ||
      old.signals != signals ||
      old.hasPulse != hasPulse;
}

// C0-continuous oscillation in -1..1 (no dart:math import in the hot path).
double _wave(double t) {
  final x = (t % 1.0) * 2 - 1; // sawtooth in [-1, 1)
  return 1 - (2 * x * x); // parabola, range -1..1
}
