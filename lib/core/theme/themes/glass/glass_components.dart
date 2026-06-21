// Liquid Glass component-slot overrides — "frosted HUD / Apple control center".
// Translucent frosted panels, glossy pill lozenges with a specular top
// highlight, a liquid switch that squishes its thumb, and a soft looping
// frosted ripple while pending. Built as defaultAppComponents().copyWith(...)
// so unlisted slots (select) inherit.
//
// Rules: no data/GetIt/BLoC imports; colors come from the theme accessors
// (context.appPalette / Theme.of). Colors.white / Colors.black specular
// highlights are allowed (this file is under lib/core/theme/, exempt from
// avoid_hardcoded_brand_colors).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';

AppComponents glassComponents({bool reduceEffects = false}) {
  return defaultAppComponents().copyWith(
    surface: _surface,
    methodBadge: (context, {required method, small = false}) => GlassLozenge(
      text: method.toUpperCase(),
      color: context.appPalette.methodColor(method),
    ),
    statusBadge: (context, {required statusCode}) => GlassLozenge(
      text: '$statusCode',
      color: context.appPalette.statusColor(statusCode),
      label: 'STATUS',
    ),
    metric: (context, {required label, required value, unit, delta}) =>
        FrostedLozengeMetric(
          label: label,
          value: [
            if (unit != null) '$value $unit' else value,
            ?delta,
          ].join('  '),
        ),
    toggle: (context, {required value, required onChanged, label}) =>
        LiquidSwitch(
          value: value,
          onChanged: onChanged,
          label: label,
          animate: !reduceEffects,
        ),
    logView: (context, {required lines, title, controller}) =>
        BlurredTerminalLog(lines: lines, controller: controller),
    dataRow: (context, {required label, required value, highlight = false}) =>
        GlassDataRow(label: label, value: value, highlight: highlight),
    pendingIndicator: (context, {label}) => FrostedRipple(
      label: label ?? 'SENDING…',
      animate: !reduceEffects,
    ),
    statusBanner: (context, {required state, required message}) =>
        FrostedCapsuleBanner(state: state, message: message),
  );
}

Widget _surface(
  BuildContext context, {
  required Widget child,
  String? title,
  String? code,
  bool accent = false,
}) {
  return FrostedTile(title: title, child: child);
}

// --- surface: frosted tile -------------------------------------------------
// Fills its slot. The frost (context.appDecoration.frost) is identity under
// reduceEffects, so blur auto-degrades without threading the flag here.

class FrostedTile extends StatelessWidget {
  const FrostedTile({required this.child, this.title, super.key});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(context.appShape.panelRadius);
    // The frosted box forwards constraints (DecoratedBox sizes to its child;
    // the child receives the full slot via the outer Expanded in the titled
    // path, or directly here for the no-title path).
    final frosted = context.appDecoration.frost(
      context,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: context.appDecoration.panelBox(
          context,
          borderRadius: radius,
        ),
        child: child,
      ),
    );

    if (title == null) return frosted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FloatingTitleChip(title: title!),
        const SizedBox(height: 6),
        Expanded(child: frosted),
      ],
    );
  }
}

class _FloatingTitleChip extends StatelessWidget {
  const _FloatingTitleChip({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: context.appTypography.titleWeight,
          fontSize: layout.fontSizeSmall,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// --- glass lozenge (method + status) ---------------------------------------
// A glossy pill: a low-alpha color fill, a hairline specular border, and a
// white→transparent top-highlight gradient that reads as a curved glass face.

class GlassLozenge extends StatelessWidget {
  const GlassLozenge({
    required this.text,
    required this.color,
    this.label,
    super.key,
  });
  final String text;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    // Legible label color against the low-alpha tint: the full-strength method
    // / status color on the glass, which keeps its semantic hue.
    final textColor = color;
    return Container(
      margin: label != null
          ? EdgeInsets.only(right: layout.isCompact ? 8 : 12)
          : EdgeInsets.zero,
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal + 4,
        // The labeled (status) lozenge sits inline beside the taller TIME /
        // SIZE FrostedLozengeMetric chips (vertical padding 4); match their
        // height so it doesn't read as undersized next to them. The bare method
        // badge keeps the tighter default padding.
        vertical: label != null
            ? layout.badgePaddingVertical + 2
            : layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.55),
          width: layout.borderThin,
        ),
        // Specular top highlight blended over the color tint so both survive.
        // Flutter ignores `color` when `gradient` is set — encode tint here.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: isDark ? 0.18 : 0.45),
              color.withValues(alpha: isDark ? 0.22 : 0.16),
            ),
            color.withValues(alpha: isDark ? 0.22 : 0.16),
          ],
          stops: const [0, 0.6],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Text(
              '$label: ',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.titleWeight,
              ),
            ),
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: layout.fontSizeNormal,
              fontWeight: context.appTypography.displayWeight,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// --- metric: frosted lozenge chip (inline-safe, sits in a Wrap) ------------

class FrostedLozengeMetric extends StatelessWidget {
  const FrostedLozengeMetric({
    required this.label,
    required this.value,
    super.key,
  });
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.30),
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.titleWeight,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              fontSize: layout.fontSizeNormal,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// --- toggle: liquid switch -------------------------------------------------
// A frosted track + a glossy thumb that slides and (when animating) squishes
// on its way across. reduceEffects → plain glossy thumb, instant slide.

class LiquidSwitch extends StatefulWidget {
  const LiquidSwitch({
    required this.value,
    required this.onChanged,
    this.label,
    this.animate = true,
    super.key,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final bool animate;

  @override
  State<LiquidSwitch> createState() => _LiquidSwitchState();
}

class _LiquidSwitchState extends State<LiquidSwitch> {
  // Squish factor: 1.0 at rest; briefly widens during a slide. State-only
  // (no controller) — AnimatedScale interpolates it.
  double _squish = 1;

  void _flip() {
    widget.onChanged(!widget.value);
    if (!widget.animate) return;
    setState(() => _squish = 1.18);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _squish = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.primaryColor;
    final on = widget.value;

    final thumb = Transform.scale(
      scaleX: widget.animate ? _squish : 1.0,
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white.withValues(alpha: 0.85),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );

    final track = GestureDetector(
      onTap: _flip,
      child: Container(
        width: 56,
        height: 28,
        decoration: BoxDecoration(
          color: on
              ? accent.withValues(alpha: 0.9)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? Colors.transparent : theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
        child: AnimatedAlign(
          duration: widget.animate
              ? const Duration(milliseconds: 180)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: thumb,
        ),
      ),
    );

    if (widget.label == null) return track;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label!,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: context.appTypography.bodyWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        track,
      ],
    );
  }
}

// --- logView: blurred terminal log -----------------------------------------
// A scrolling list of frosted rows: a translucent direction pill + mono
// payload. Fills its bounded Expanded.

class BlurredTerminalLog extends StatelessWidget {
  const BlurredTerminalLog({required this.lines, this.controller, super.key});
  final List<AppLogLine> lines;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
      itemCount: lines.length,
      itemBuilder: (context, i) => _TerminalRow(line: lines[i]),
    );
  }
}

class _TerminalRow extends StatelessWidget {
  const _TerminalRow({required this.line});
  final AppLogLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final palette = context.appPalette;

    final (label, color) = switch (line.kind) {
      AppLogLineKind.outgoing => ('OUT', theme.colorScheme.secondary),
      AppLogLineKind.incoming => ('IN', theme.colorScheme.onSurface),
      AppLogLineKind.open => ('OPEN', palette.statusSuccess),
      AppLogLineKind.close => ('CLOSE', theme.colorScheme.onSurface),
      AppLogLineKind.error => ('ERROR', palette.statusError),
    };

    return Padding(
      padding: EdgeInsets.only(bottom: layout.tabSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: layout.borderThin,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.displayWeight,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              line.text,
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                fontSize: layout.fontSizeCode,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- dataRow: translucent glass row ----------------------------------------

class GlassDataRow extends StatelessWidget {
  const GlassDataRow({
    required this.label,
    required this.value,
    this.highlight = false,
    super.key,
  });
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.primaryColor,
              fontWeight: context.appTypography.titleWeight,
              fontSize: layout.fontSizeNormal,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                fontSize: layout.fontSizeNormal,
                fontWeight: highlight
                    ? context.appTypography.titleWeight
                    : null,
                color: highlight
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- pendingIndicator: frosted ripple --------------------------------------
// A soft looping ripple of expanding rings while pending. A single controller
// drives a CustomPainter (built once, repaint via super(repaint:)); reduced
// effects render a static frosted placeholder with no controller at all.

class FrostedRipple extends StatefulWidget {
  const FrostedRipple({
    required this.label,
    this.animate = true,
    super.key,
  });
  final String label;
  final bool animate;

  @override
  State<FrostedRipple> createState() => _FrostedRippleState();
}

class _FrostedRippleState extends State<FrostedRipple>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      );
      unawaited(_c!.repeat());
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  // Painter built once per build (not per frame). When animating it reads
  // progress from the controller inside paint() and uses _c as its repaint
  // notifier; static mode passes a null animation (no controller, no repaint).
  late _RipplePainter _painter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _painter = _RipplePainter(
      animation: _c,
      color: Theme.of(context).primaryColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: context.appTypography.displayWeight,
                  fontSize: layout.fontSizeNormal,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 16),
              RepaintBoundary(
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: CustomPaint(painter: _painter),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Allocation-free frosted ripple painter.
///
/// - One reusable [Paint] is built at construction, not per frame.
/// - When [animation] is non-null the controller drives repaint directly (via
///   `super(repaint: animation)`); the ring radii/alpha are read from
///   `animation.value` inside [paint]. No [AnimatedBuilder] wrapper needed.
/// - When [animation] is null (static / reduceEffects mode) it paints a single
///   static frosted ring.
class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.color, this.animation})
    : _paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
      super(repaint: animation);

  final Color color;
  final AnimationController? animation;
  final Paint _paint;

  static const _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2 - 2;
    final t = animation?.value ?? 0.0;

    if (animation == null) {
      // Static frosted placeholder: a single mid ring.
      _paint
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = 2;
      canvas.drawCircle(center, maxRadius * 0.6, _paint);
      return;
    }

    for (var i = 0; i < _rings; i++) {
      // Each ring offset in phase so they cascade outward.
      final phase = (t + i / _rings) % 1.0;
      final radius = maxRadius * phase;
      final alpha = (1 - phase) * 0.5;
      _paint
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, _paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.animation != animation || old.color != color;
}

// --- statusBanner: frosted capsule banner ----------------------------------

class FrostedCapsuleBanner extends StatelessWidget {
  const FrostedCapsuleBanner({
    required this.state,
    required this.message,
    super.key,
  });
  final AppBannerState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final palette = context.appPalette;
    final isDark = theme.brightness == Brightness.dark;

    final color = switch (state) {
      AppBannerState.success => palette.statusSuccess,
      AppBannerState.error => palette.statusError,
      AppBannerState.warning => palette.statusWarning,
      AppBannerState.info => theme.colorScheme.secondary,
    };

    final icon = switch (state) {
      AppBannerState.success => Icons.link,
      AppBannerState.error => Icons.link_off,
      AppBannerState.warning => Icons.warning_amber_outlined,
      AppBannerState.info => Icons.info_outline,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: layout.isCompact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: isDark ? 0.24 : 0.18),
        border: Border.all(
          color: color.withValues(alpha: 0.55),
          width: layout.borderThin,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: layout.smallIconSize),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: context.appTypography.displayWeight,
                fontSize: layout.fontSizeNormal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
