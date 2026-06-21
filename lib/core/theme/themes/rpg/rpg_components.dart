// Arcane Quest RPG component-slot overrides — "grimoire / heraldic scroll".
// Runic panels, gem badges, summoning rings, enchanted levers, parchment rows.
// Built as defaultAppComponents().copyWith(...) so unlisted slots (select)
// inherit.
//
// Rules: no data/GetIt/BLoC imports; RpgPalette constants are allowed
// (file is under lib/core/theme/, exempt from avoid_hardcoded_brand_colors).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';
import 'package:getman/core/theme/themes/rpg/rpg_palette.dart';

AppComponents rpgComponents({bool reduceEffects = false}) {
  return defaultAppComponents().copyWith(
    surface: _surface,
    methodBadge: (context, {required method, small = false}) =>
        RunePlateBadge(method: method),
    statusBadge: (context, {required statusCode}) =>
        GemBadge(statusCode: statusCode),
    metric: (context, {required label, required value, unit, delta}) =>
        RunestoneChip(
          label: label,
          value: [
            if (unit != null) '$value $unit' else value,
            ?delta,
          ].join('  '),
        ),
    toggle: (context, {required value, required onChanged, label}) =>
        EnchantedLever(
          value: value,
          onChanged: onChanged,
          label: label,
          animate: !reduceEffects,
        ),
    logView: (context, {required lines, title, controller}) =>
        GrimoireLog(lines: lines, controller: controller),
    dataRow: (context, {required label, required value, highlight = false}) =>
        QuestLedgerRow(label: label, value: value, highlight: highlight),
    pendingIndicator: (context, {label}) => SummoningRing(
      label: label ?? 'SUMMONING…',
      animate: !reduceEffects,
    ),
    statusBanner: (context, {required state, required message}) =>
        HeraldicBanner(state: state, message: message),
  );
}

Widget _surface(
  BuildContext context, {
  required Widget child,
  String? title,
  String? code,
  bool accent = false,
}) {
  return RunicPanel(title: title, child: child);
}

// --- surface: runic parchment panel ----------------------------------------

class RunicPanel extends StatelessWidget {
  const RunicPanel({required this.child, this.title, super.key});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? RpgPalette.surfaceDark : RpgPalette.surfaceLight;
    final borderColor = isDark ? RpgPalette.borderDark : RpgPalette.borderLight;

    final panel = CustomPaint(
      painter: _RunicBorderPainter(borderColor: borderColor),
      child: ColoredBox(
        color: bg,
        child: child,
      ),
    );

    if (title == null) return panel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EngravedHeader(title: title!, isDark: isDark),
        SizedBox(height: layout.borderThin),
        Expanded(child: panel),
      ],
    );
  }
}

class _RunicBorderPainter extends CustomPainter {
  _RunicBorderPainter({required this.borderColor})
    : _paint = Paint()
        ..color = borderColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

  final Color borderColor;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    // Mutate the hoisted Paint's color (borderColor may differ between
    // instances; a single painter is constructed per build, not per frame).
    _paint.color = borderColor;

    const r = 6.0;
    const flourish = 8.0;

    // Main rect.
    final rect = RRect.fromLTRBR(
      0,
      0,
      size.width,
      size.height,
      const Radius.circular(r),
    );
    canvas.drawRRect(rect, _paint);

    // Corner flourishes — small cross marks at each corner.
    // Inline instead of allocating a List<Offset> per call.
    void drawCorner(double cx, double cy) {
      final dx = cx == 0 ? flourish : -flourish;
      final dy = cy == 0 ? flourish : -flourish;
      canvas
        ..drawLine(
          Offset(cx + dx / 2, cy),
          Offset(cx + dx, cy),
          _paint,
        )
        ..drawLine(
          Offset(cx, cy + dy / 2),
          Offset(cx, cy + dy),
          _paint,
        );
    }

    drawCorner(0, 0);
    drawCorner(size.width, 0);
    drawCorner(0, size.height);
    drawCorner(size.width, size.height);
  }

  @override
  bool shouldRepaint(_RunicBorderPainter old) => old.borderColor != borderColor;
}

class _EngravedHeader extends StatelessWidget {
  const _EngravedHeader({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final bg = isDark
        ? RpgPalette.surfaceRaisedDark
        : RpgPalette.surfaceRaisedLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(
          color: isDark ? RpgPalette.borderDark : RpgPalette.borderLight,
          width: layout.borderThin,
        ),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius / 2),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: RpgPalette.gold,
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeSmall,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// --- method badge: heraldic rune plate -------------------------------------

class RunePlateBadge extends StatelessWidget {
  const RunePlateBadge({required this.method, super.key});
  final String method;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final color = context.appPalette.methodColor(method);
    final on = context.appPalette.onColor(color);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? RpgPalette.borderDark : RpgPalette.borderLight;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        border: Border.all(color: borderColor, width: layout.borderThin + 0.5),
      ),
      child: Text(
        method.toUpperCase(),
        style: TextStyle(
          color: on,
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeNormal,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// --- status badge: faceted gem ---------------------------------------------

class GemBadge extends StatelessWidget {
  const GemBadge({required this.statusCode, super.key});
  final int statusCode;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final color = context.appPalette.statusColor(statusCode);
    // Deliberate contrast on a variable-colored gem badge (CLAUDE.md §4.8
    // exception): status text is always white for legibility on jewel tones.
    // ignore: avoid_hardcoded_brand_colors
    const on = Colors.white;
    return Container(
      height: 36,
      margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: ShapeDecoration(
        color: color,
        shape: _GemShape(borderColor: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'STATUS: ',
            style: TextStyle(
              color: on,
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.titleWeight,
            ),
          ),
          Text(
            '$statusCode',
            style: TextStyle(
              color: on,
              fontWeight: context.appTypography.displayWeight,
              fontSize: layout.fontSizeNormal,
            ),
          ),
        ],
      ),
    );
  }
}

class _GemShape extends ShapeBorder {
  const _GemShape({required this.borderColor});
  final Color borderColor;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final cut = rect.height * 0.18;
    return Path()
      ..moveTo(rect.left + cut, rect.top)
      ..lineTo(rect.right - cut, rect.top)
      ..lineTo(rect.right, rect.top + cut)
      ..lineTo(rect.right, rect.bottom - cut)
      ..lineTo(rect.right - cut, rect.bottom)
      ..lineTo(rect.left + cut, rect.bottom)
      ..lineTo(rect.left, rect.bottom - cut)
      ..lineTo(rect.left, rect.top + cut)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // Build the stroke path directly to avoid the extra allocation that
    // delegating to getOuterPath() would cause (getOuterPath allocates a new
    // Path each call).  _GemShape.paint is not a hot path (it runs once per
    // layout, not per frame), but the discipline is kept.
    final cut = rect.height * 0.18;
    final path = Path()
      ..moveTo(rect.left + cut, rect.top)
      ..lineTo(rect.right - cut, rect.top)
      ..lineTo(rect.right, rect.top + cut)
      ..lineTo(rect.right, rect.bottom - cut)
      ..lineTo(rect.right - cut, rect.bottom)
      ..lineTo(rect.left + cut, rect.bottom)
      ..lineTo(rect.left, rect.bottom - cut)
      ..lineTo(rect.left, rect.top + cut)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  ShapeBorder scale(double t) => this;
}

// --- metric: runestone chip (inline-safe, no offset shadow) ----------------

class RunestoneChip extends StatelessWidget {
  const RunestoneChip({required this.label, required this.value, super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? RpgPalette.borderDark : RpgPalette.borderLight;
    return Container(
      margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? RpgPalette.surfaceRaisedDark
            : RpgPalette.surfaceRaisedLight,
        border: Border.all(color: borderColor, width: layout.borderThin),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${label.toUpperCase()}: ',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.titleWeight,
              color: RpgPalette.gold,
              letterSpacing: 0.8,
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

// --- toggle: enchanted lever -----------------------------------------------

class EnchantedLever extends StatelessWidget {
  const EnchantedLever({
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? RpgPalette.borderDark : RpgPalette.borderLight;

    final track = GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 56,
        height: 28,
        decoration: BoxDecoration(
          color: value
              ? RpgPalette.gold.withValues(alpha: 0.2)
              : (isDark ? RpgPalette.surfaceDark : RpgPalette.surfaceLight),
          border: Border.all(color: borderColor, width: layout.borderThin),
          borderRadius: BorderRadius.circular(14),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: RpgPalette.gold.withValues(
                      alpha: animate ? 0.4 : 0.25,
                    ),
                    blurRadius: animate ? 6 : 3,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value ? RpgPalette.gold : borderColor,
              shape: BoxShape.circle,
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: RpgPalette.gold.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
            child: const Center(
              child: Text(
                '᛭',
                style: TextStyle(
                  fontSize: 10,
                  color: RpgPalette.backgroundDark,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (label == null) return track;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
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

// --- logView: grimoire scroll log ------------------------------------------

class GrimoireLog extends StatelessWidget {
  const GrimoireLog({required this.lines, this.controller, super.key});
  final List<AppLogLine> lines;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      itemCount: lines.length,
      itemBuilder: (context, i) => _GrimoireRow(line: lines[i]),
    );
  }
}

class _GrimoireRow extends StatelessWidget {
  const _GrimoireRow({required this.line});
  final AppLogLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    final parchment = isDark ? RpgPalette.surfaceDark : RpgPalette.surfaceLight;

    final (rune, color) = switch (line.kind) {
      AppLogLineKind.outgoing => ('᛫', RpgPalette.azure),
      AppLogLineKind.incoming => ('᛬', RpgPalette.emerald),
      AppLogLineKind.open => ('᚛', RpgPalette.gold),
      AppLogLineKind.close => ('᚜', theme.colorScheme.onSurface),
      AppLogLineKind.error => ('᛭', RpgPalette.ruby),
    };

    return Container(
      color: parchment,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rune,
            style: TextStyle(
              fontSize: layout.fontSizeNormal + 2,
              color: color,
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

// --- dataRow: quest ledger row ---------------------------------------------

class QuestLedgerRow extends StatelessWidget {
  const QuestLedgerRow({
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
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? RpgPalette.borderDark : RpgPalette.borderLight;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor, width: layout.borderThin),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '᛫',
            style: TextStyle(
              color: RpgPalette.gold,
              fontSize: layout.fontSizeNormal,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: RpgPalette.gold,
              fontWeight: context.appTypography.titleWeight,
              fontSize: layout.fontSizeSmall,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
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
                    ? RpgPalette.gold
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- pendingIndicator: summoning ring --------------------------------------

class SummoningRing extends StatefulWidget {
  const SummoningRing({
    required this.label,
    this.animate = true,
    super.key,
  });
  final String label;
  final bool animate;

  @override
  State<SummoningRing> createState() => _SummoningRingState();
}

class _SummoningRingState extends State<SummoningRing>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      );
      unawaited(_c!.repeat());
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  // Painter is constructed once per build (not per frame). When animating,
  // it reads angle from the controller directly inside paint() and uses _c as
  // its repaint notifier — no AnimatedBuilder rebuild needed.
  late _SummoningRingPainter _painter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuild the painter when dependencies (e.g. theme brightness) change;
    // at 60fps the animation itself does NOT trigger a build — only repaint.
    _painter = _SummoningRingPainter(animation: _c);
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
                  color: RpgPalette.gold,
                  fontWeight: context.appTypography.displayWeight,
                  fontSize: layout.fontSizeNormal,
                  letterSpacing: 1.2,
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
              const SizedBox(height: 12),
              Text(
                'CASTING SPELL…',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: layout.fontSizeSmall,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Allocation-free summoning ring painter.
///
/// - 2 [Paint] objects are built once at construction, not per frame.
/// - 8 [TextPainter]s (one per rune glyph) are laid out once at construction.
/// - When [animation] is non-null the controller drives repaint directly
///   (via `super(repaint: animation)`); the angle is read from
///   `animation.value` inside [paint]. No [AnimatedBuilder] wrapper needed.
/// - When [animation] is null (static / reduceEffects mode) angle stays 0.
class _SummoningRingPainter extends CustomPainter {
  _SummoningRingPainter({this.animation})
    : _arcPaint = Paint()
        ..color = RpgPalette.gold
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
      _innerPaint = Paint()
        ..color = RpgPalette.goldDeep.withValues(alpha: 0.4)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
      _runePainters = _buildRunePainters(),
      super(repaint: animation);

  final AnimationController? animation;
  final Paint _arcPaint;
  final Paint _innerPaint;
  // One pre-laid-out TextPainter per rune glyph — never reallocated in paint.
  final List<TextPainter> _runePainters;

  static const _runes = ['ᚠ', 'ᚢ', 'ᚦ', 'ᚨ', 'ᚱ', 'ᚲ', 'ᚷ', 'ᚹ'];

  static List<TextPainter> _buildRunePainters() {
    const style = TextStyle(color: RpgPalette.gold, fontSize: 10);
    return [
      for (final r in _runes)
        TextPainter(
          text: TextSpan(text: r, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final angle = animation != null ? animation!.value * 2 * math.pi : 0.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Outer rotating border arc + inner static ring.
    canvas
      ..drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        math.pi * 1.6,
        false,
        _arcPaint,
      )
      ..drawCircle(center, radius * 0.65, _innerPaint);

    // Rune glyphs arranged in a circle — reuse pre-built painters.
    final runeRadius = radius * 0.82;
    for (var i = 0; i < _runePainters.length; i++) {
      final theta = (i / _runePainters.length) * 2 * math.pi + angle * 0.4;
      final x = center.dx + runeRadius * math.cos(theta);
      final y = center.dy + runeRadius * math.sin(theta);
      final tp = _runePainters[i];
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_SummoningRingPainter old) => old.animation != animation;
}

// --- statusBanner: heraldic ribbon banner ----------------------------------

class HeraldicBanner extends StatelessWidget {
  const HeraldicBanner({
    required this.state,
    required this.message,
    super.key,
  });
  final AppBannerState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final theme = Theme.of(context);

    final color = switch (state) {
      AppBannerState.success => palette.statusSuccess,
      AppBannerState.error => palette.statusError,
      AppBannerState.warning => palette.statusWarning,
      AppBannerState.info => theme.colorScheme.secondary,
    };

    final sigil = switch (state) {
      AppBannerState.success => '⚔',
      AppBannerState.error => '☠',
      AppBannerState.warning => '⚠',
      AppBannerState.info => '᛭',
    };

    // Use luminance to pick text color: light ribbon backgrounds (parchment
    // tones) get the deep RPG background text; dark jewel tones get the warm
    // parchment text. Both avoid literal black/white on themed surfaces.
    final on = color.computeLuminance() > 0.3
        ? RpgPalette.backgroundDark
        : RpgPalette.textDark;

    return CustomPaint(
      painter: _RibbonPainter(color: color),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: layout.isCompact ? 4 : 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sigil,
              style: TextStyle(
                color: on,
                fontSize: layout.fontSizeNormal + 2,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message.toUpperCase(),
                style: TextStyle(
                  color: on,
                  fontWeight: context.appTypography.displayWeight,
                  fontSize: layout.fontSizeNormal,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              sigil,
              style: TextStyle(
                color: on,
                fontSize: layout.fontSizeNormal + 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  const _RibbonPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const notch = 10.0;
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - notch, size.height / 2)
      ..lineTo(size.width, 0)
      ..moveTo(0, 0)
      ..lineTo(notch, size.height / 2)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - notch, size.height / 2)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);

    // Border.
    final borderPaint = Paint()
      ..color = RpgPalette.goldDeep
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.color != color;
}
