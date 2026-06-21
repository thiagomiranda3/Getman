// Editorial component-slot overrides — "print magazine / typographic spread".
// Hairline rules, serif section headings, small-caps mono labels, generous
// air. Deliberately CALM: no glow, no looping motion, no repainting painters,
// no controllers. The only movement is the OutlinedSwitch thumb's AnimatedAlign
// slide (motion-light). Built as defaultAppComponents().copyWith(...) so
// unlisted slots (select) inherit.
//
// Rules: no data/GetIt/BLoC imports; theme palette constants allowed
// (file is under lib/core/theme/, exempt from avoid_hardcoded_brand_colors).

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';

AppComponents editorialComponents() {
  return defaultAppComponents().copyWith(
    surface: _surface,
    methodBadge: (context, {required method, small = false}) => TypographicTag(
      text: method.toUpperCase(),
      color: context.appPalette.methodColor(method),
      small: small,
    ),
    statusBadge: (context, {required statusCode}) => TypographicTag(
      text: '$statusCode',
      color: context.appPalette.statusColor(statusCode),
      label: 'STATUS',
    ),
    metric: (context, {required label, required value, unit, delta}) =>
        FootnoteMetric(
          label: label,
          value: [
            if (unit != null) '$value $unit' else value,
            ?delta,
          ].join('  '),
        ),
    toggle: (context, {required value, required onChanged, label}) =>
        OutlinedSwitch(value: value, onChanged: onChanged, label: label),
    logView: (context, {required lines, title, controller}) =>
        DispatchLog(lines: lines, controller: controller),
    dataRow: (context, {required label, required value, highlight = false}) =>
        ReferenceRow(label: label, value: value, highlight: highlight),
    pendingIndicator: (context, {label}) =>
        GalleyProof(label: label ?? 'SETTING TYPE…'),
    statusBanner: (context, {required state, required message}) =>
        EditorialNoteBar(state: state, message: message),
  );
}

Widget _surface(
  BuildContext context, {
  required Widget child,
  String? title,
  String? code,
  bool accent = false,
}) {
  return ArticlePanel(title: title, child: child);
}

// --- surface: article panel ------------------------------------------------
// A thin hairline-rule frame with generous internal air. Titled → a serif
// section heading + an underline rule above the child, which fills the rest.
// No-title → the framed child fills the whole slot.

class ArticlePanel extends StatelessWidget {
  const ArticlePanel({required this.child, this.title, super.key});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final decoration = BoxDecoration(
      color: theme.cardColor,
      border: Border.all(color: theme.dividerColor, width: layout.borderThin),
    );

    // Container (not DecoratedBox) so the hairline frame insets its child by
    // the border width (BoxDecoration.padding == border.dimensions). Otherwise
    // an opaque child — e.g. the code editor's surface fill — paints over the
    // border, leaving the editor unframed below the (transparent) toolbar.
    if (title == null) {
      return Container(decoration: decoration, child: child);
    }

    return Container(
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(title: title!),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
      ),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: context.appTypography.titleWeight,
        ),
      ),
    );
  }
}

// --- typographic tag (method + status) -------------------------------------
// A quiet hairline box with small-caps colored text. No shadow, no fill (or a
// whisper-low tint), letting the type carry the meaning.

class TypographicTag extends StatelessWidget {
  const TypographicTag({
    required this.text,
    required this.color,
    this.label,
    this.small = false,
    super.key,
  });
  final String text;
  final Color color;
  final String? label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      margin: label != null
          ? EdgeInsets.only(right: layout.isCompact ? 8 : 12)
          : EdgeInsets.zero,
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color, width: layout.borderThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Text(
              '$label  ',
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                color: theme.colorScheme.secondary,
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.bodyWeight,
                letterSpacing: 2,
              ),
            ),
          Text(
            text,
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              color: color,
              fontSize: small ? layout.fontSizeSmall : layout.fontSizeNormal,
              fontWeight: context.appTypography.titleWeight,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// --- metric: footnote chip (inline-safe, sits in a Wrap) -------------------
// A compact inline chip: small-caps label + value, separated by a thin
// vertical rule. No box fill — reads like a typeset footnote entry.

class FootnoteMetric extends StatelessWidget {
  const FootnoteMetric({
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
    return Container(
      margin: EdgeInsets.only(right: layout.isCompact ? 10 : 16),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.bodyWeight,
              letterSpacing: 2,
              color: theme.colorScheme.secondary,
            ),
          ),
          Container(
            width: layout.borderThin,
            height: layout.fontSizeNormal,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: theme.dividerColor,
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              fontSize: layout.fontSizeNormal,
              fontWeight: context.appTypography.titleWeight,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// --- toggle: outlined switch -----------------------------------------------
// A thin-outlined minimal track + small thumb. The thumb slides via
// AnimatedAlign — the one piece of allowed motion (motion-light, no glow).

class OutlinedSwitch extends StatelessWidget {
  const OutlinedSwitch({
    required this.value,
    required this.onChanged,
    this.label,
    super.key,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final accent = theme.primaryColor;
    final track = GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 52,
        height: 26,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(
            color: value ? accent : theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            color: value ? accent : theme.colorScheme.secondary,
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

// --- logView: dispatch log -------------------------------------------------
// A bounded scrolling list of typeset entries: a small-caps source label
// (OUT/IN/OPEN/CLOSE/ERROR) + mono payload, a hairline divider, airy leading.
// Fills its bounded Expanded.

class DispatchLog extends StatelessWidget {
  const DispatchLog({required this.lines, this.controller, super.key});
  final List<AppLogLine> lines;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
      itemCount: lines.length,
      itemBuilder: (context, i) => _DispatchRow(line: lines[i]),
    );
  }
}

class _DispatchRow extends StatelessWidget {
  const _DispatchRow({required this.line});
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
      AppLogLineKind.close => ('CLOSE', theme.colorScheme.secondary),
      AppLogLineKind.error => ('ERROR', palette.statusError),
    };

    return Container(
      margin: EdgeInsets.only(bottom: layout.tabSpacing),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.3),
            width: layout.borderThin,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.titleWeight,
                letterSpacing: 1.5,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
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

// --- dataRow: reference row ------------------------------------------------
// A small-caps key + readable value, with a hairline rule between rows.

class ReferenceRow extends StatelessWidget {
  const ReferenceRow({
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
            color: theme.dividerColor.withValues(alpha: 0.3),
            width: layout.borderThin,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              color: theme.colorScheme.secondary,
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.bodyWeight,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 12),
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
                    ? theme.primaryColor
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- pendingIndicator: galley proof ----------------------------------------
// A purely static "proof sheet": a quiet label over a column of thin static
// type-rules (no animation, no controller). Reads as an unset galley awaiting
// the press.

class GalleyProof extends StatelessWidget {
  const GalleyProof({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    // Descending widths give the impression of typeset paragraphs.
    const widths = <double>[1, 0.92, 0.96, 0.72, 0.88, 0.6];

    return Semantics(
      label: label,
      liveRegion: true,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: context.appTypography.codeFontFamily,
                  fontSize: layout.fontSizeSmall,
                  fontWeight: context.appTypography.bodyWeight,
                  letterSpacing: 2,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 16),
              for (final w in widths)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: w,
                    child: Container(
                      height: layout.borderThin,
                      color: theme.dividerColor.withValues(alpha: 0.4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- statusBanner: editorial note bar --------------------------------------
// A quiet ruled bar with a small-caps label, tinted by state. No shadow, no
// glow — a left accent rule carries the state color.

class EditorialNoteBar extends StatelessWidget {
  const EditorialNoteBar({
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
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: layout.isCompact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border(
          left: BorderSide(color: color, width: layout.borderThick),
          top: BorderSide(color: theme.dividerColor, width: layout.borderThin),
          right: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
          bottom: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                color: color,
                fontWeight: context.appTypography.titleWeight,
                fontSize: layout.fontSizeNormal,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
