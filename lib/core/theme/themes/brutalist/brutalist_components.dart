// Brutalist component-slot overrides — "ink-press / risograph print shop".
// Hard borders, hard offset shadows, uppercase, mono accents. Built as
// defaultAppComponents().copyWith(...) so unlisted slots (select) inherit.
//
// Rules: no data/GetIt/BLoC imports; theme palette constants allowed
// (file is under lib/core/theme/, exempt from avoid_hardcoded_brand_colors).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';

AppComponents brutalistComponents({bool reduceEffects = false}) {
  return defaultAppComponents().copyWith(
    surface: _surface,
    methodBadge: (context, {required method, small = false}) => BrutalStamp(
      text: method,
      color: context.appPalette.methodColor(method),
    ),
    statusBadge: (context, {required statusCode}) => BrutalStamp(
      text: '$statusCode',
      color: context.appPalette.statusColor(statusCode),
      label: 'STATUS',
    ),
    metric: (context, {required label, required value, unit, delta}) =>
        BrutalTickerChip(
          label: label,
          value: [
            if (unit != null) '$value $unit' else value,
            ?delta,
          ].join('  '),
        ),
    toggle: (context, {required value, required onChanged, label}) =>
        BrutalSwitch(
          value: value,
          onChanged: onChanged,
          label: label,
          animate: !reduceEffects,
        ),
    logView: (context, {required lines, title, controller}) =>
        BrutalFanfoldLog(lines: lines, controller: controller),
    dataRow: (context, {required label, required value, highlight = false}) =>
        BrutalPrintedRow(label: label, value: value, highlight: highlight),
    pendingIndicator: (context, {label}) => BrutalPressIndicator(
      label: label ?? 'PRINTING…',
      animate: !reduceEffects,
    ),
    statusBanner: (context, {required state, required message}) =>
        BrutalStampBanner(state: state, message: message),
  );
}

Widget _surface(
  BuildContext context, {
  required Widget child,
  String? title,
  String? code,
  bool accent = false,
}) {
  return BrutalSlab(title: title, child: child);
}

// --- surface -------------------------------------------------------------
class BrutalSlab extends StatelessWidget {
  const BrutalSlab({required this.child, this.title, super.key});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    // Container (not DecoratedBox) so the panel border insets its child by the
    // border width (BoxDecoration.padding == border.dimensions). Without that
    // inset an opaque child — e.g. the code editor's surface fill — paints over
    // the border, leaving the editor unframed while the (transparent) toolbar
    // above still shows it. Matches how the default/classic surface behaves.
    final slab = Container(
      decoration: context.appDecoration.panelBox(context, offset: 0),
      child: child,
    );
    if (title == null) return slab;
    // Stuck-on header label: an offset, hard-shadowed tag over the slab.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StuckLabel(title!),
        Expanded(child: slab),
      ],
    );
  }
}

class _StuckLabel extends StatelessWidget {
  const _StuckLabel(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.primaryColor,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
        boxShadow: [
          BoxShadow(
            color: theme.dividerColor,
            offset: Offset(layout.borderHeavy, layout.borderHeavy),
          ),
        ],
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeSmall,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// --- ink stamp (method + status) ----------------------------------------
class BrutalStamp extends StatelessWidget {
  const BrutalStamp({
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
    final on = context.appPalette.onColor(color);
    return Container(
      margin: label != null
          ? EdgeInsets.only(right: layout.isCompact ? 8 : 12)
          : EdgeInsets.zero,
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: theme.dividerColor,
          width: layout.borderHeavy,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.dividerColor,
            offset: Offset(layout.borderHeavy, layout.borderHeavy),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Text(
              '$label: ',
              style: TextStyle(
                color: on,
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.titleWeight,
              ),
            ),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: on,
              fontSize: layout.fontSizeNormal,
              fontWeight: context.appTypography.displayWeight,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// --- metric (inline ticker chip, NO shadow → fits the Wrap) -------------
class BrutalTickerChip extends StatelessWidget {
  const BrutalTickerChip({required this.label, required this.value, super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${label.toUpperCase()}: ',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.titleWeight,
              color: theme.colorScheme.onSurface,
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

// --- chunky snap switch -------------------------------------------------
class BrutalSwitch extends StatelessWidget {
  const BrutalSwitch({
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
    final track = GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 56,
        height: 28,
        decoration: BoxDecoration(
          color: value ? theme.primaryColor : theme.cardColor,
          border: Border.all(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
        child: AnimatedAlign(
          duration: animate ? const Duration(milliseconds: 90) : Duration.zero,
          curve: Curves.easeOutBack,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              border: Border.all(
                color: theme.dividerColor,
                width: layout.borderThin,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.dividerColor,
                  offset: const Offset(2, 2),
                ),
              ],
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

// --- fanfold line-printer log -------------------------------------------
class BrutalFanfoldLog extends StatelessWidget {
  const BrutalFanfoldLog({required this.lines, this.controller, super.key});
  final List<AppLogLine> lines;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      itemCount: lines.length,
      itemBuilder: (context, i) => _FanfoldRow(line: lines[i], even: i.isEven),
    );
  }
}

class _FanfoldRow extends StatelessWidget {
  const _FanfoldRow({required this.line, required this.even});
  final AppLogLine line;
  final bool even;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final glyph = switch (line.kind) {
      AppLogLineKind.outgoing => '▲',
      AppLogLineKind.incoming => '▼',
      AppLogLineKind.open => '⊕',
      AppLogLineKind.close => '⊗',
      AppLogLineKind.error => '✕',
    };
    return ColoredBox(
      color: even
          ? theme.cardColor
          : theme.dividerColor.withValues(alpha: 0.08),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tractor-feed hole margin.
            Container(
              width: 18,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: theme.dividerColor,
                    width: layout.borderThin,
                  ),
                ),
              ),
              child: Center(
                child: Text(
                  '•',
                  style: TextStyle(color: theme.dividerColor),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                glyph,
                style: TextStyle(
                  fontFamily: context.appTypography.codeFontFamily,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SelectableText(
                  line.text,
                  style: TextStyle(
                    fontFamily: context.appTypography.codeFontFamily,
                    fontSize: layout.fontSizeCode,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- printed data row ----------------------------------------------------
class BrutalPrintedRow extends StatelessWidget {
  const BrutalPrintedRow({
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.primaryColor,
              border: Border.all(
                color: theme.dividerColor,
                width: layout.borderThin,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: context.appTypography.titleWeight,
                fontSize: layout.fontSizeSmall,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                fontSize: layout.fontSizeNormal,
                fontWeight: highlight
                    ? context.appTypography.titleWeight
                    : null,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- pending: hard block-shimmer ("press run") --------------------------
class BrutalPressIndicator extends StatefulWidget {
  const BrutalPressIndicator({
    required this.label,
    this.animate = true,
    super.key,
  });
  final String label;
  final bool animate;
  @override
  State<BrutalPressIndicator> createState() => _BrutalPressIndicatorState();
}

class _BrutalPressIndicatorState extends State<BrutalPressIndicator>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      );
      unawaited(_c!.repeat());
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final labelText = Text(
      widget.label,
      style: TextStyle(
        fontFamily: context.appTypography.codeFontFamily,
        fontWeight: context.appTypography.displayWeight,
        color: theme.colorScheme.onSurface,
      ),
    );
    final block = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        height: 18,
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
      ),
    );
    final blocks = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          labelText,
          const SizedBox(height: 12),
          block,
          block,
          block,
          block,
          block,
          block,
        ],
      ),
    );
    final inner = _c == null
        ? SingleChildScrollView(child: blocks)
        : SingleChildScrollView(
            child: AnimatedBuilder(
              animation: _c!,
              child: blocks,
              builder: (context, child) => Opacity(
                opacity: 0.6 + 0.4 * (1 - (_c!.value - 0.5).abs() * 2),
                child: child,
              ),
            ),
          );
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: inner,
    );
  }
}

// --- stamped status banner ----------------------------------------------
class BrutalStampBanner extends StatelessWidget {
  const BrutalStampBanner({
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
    final color = switch (state) {
      AppBannerState.success => palette.statusSuccess,
      AppBannerState.error => palette.statusError,
      AppBannerState.warning => palette.statusWarning,
      AppBannerState.info => theme.colorScheme.secondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: theme.dividerColor,
          width: layout.borderHeavy,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.dividerColor,
            offset: Offset(layout.borderHeavy, layout.borderHeavy),
          ),
        ],
      ),
      child: Text(
        message.toUpperCase(),
        style: TextStyle(
          color: palette.onColor(color),
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeNormal,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
