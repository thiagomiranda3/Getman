// Dracula component-slot overrides — "neon dev-console / REPL terminal".
// Softly-glowing panels, neon pill badges, mono key-value rows, blinking
// cursor, [OK]/[ERR]/[!]/[i] status lines.  Built as
// defaultAppComponents().copyWith(...) so the unlisted `select` slot inherits.
//
// Rules: no data/GetIt/BLoC imports; DraculaPalette constants are allowed
// (file is under lib/core/theme/, exempt from avoid_hardcoded_brand_colors).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_components_defaults.dart';
import 'package:getman/core/theme/themes/dracula/dracula_palette.dart';

AppComponents draculaComponents({bool reduceEffects = false}) {
  return defaultAppComponents().copyWith(
    surface: _surface,
    methodBadge: (context, {required method, small = false}) => NeonCapsule(
      text: method,
      color: context.appPalette.methodColor(method),
    ),
    statusBadge: (context, {required statusCode}) => NeonCapsule(
      text: '$statusCode',
      color: context.appPalette.statusColor(statusCode),
    ),
    metric: (context, {required label, required value, unit, delta}) =>
        TerminalMetric(
          label: label,
          value: [
            if (unit != null) '$value $unit' else value,
            ?delta,
          ].join('  '),
        ),
    toggle: (context, {required value, required onChanged, label}) =>
        ConsoleToggle(
          value: value,
          onChanged: onChanged,
          label: label,
          animate: !reduceEffects,
        ),
    logView: (context, {required lines, title, controller}) =>
        DevConsoleLog(lines: lines, controller: controller),
    dataRow: (context, {required label, required value, highlight = false}) =>
        ConsoleKvRow(label: label, value: value, highlight: highlight),
    pendingIndicator: (context, {label}) => BlinkingCursor(
      label: label ?? 'awaiting response…',
      animate: !reduceEffects,
    ),
    statusBanner: (context, {required state, required message}) =>
        ConsoleStatusLine(state: state, message: message),
  );
}

Widget _surface(
  BuildContext context, {
  required Widget child,
  String? title,
  String? code,
  bool accent = false,
}) {
  return ConsolePanel(title: title, child: child);
}

// ---------------------------------------------------------------------------
// ConsolePanel — surface
// ---------------------------------------------------------------------------

/// Softly rounded dark panel with a static subtle purple edge-glow.
/// If [title] is given, renders a `// title` comment-style header above the
/// child inside an [Expanded] (the panel must live in a flex context).
/// Without a title the child fills the available space directly.
class ConsolePanel extends StatelessWidget {
  const ConsolePanel({required this.child, this.title, super.key});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? DraculaPalette.surfaceDark
        : DraculaPalette.surfaceLight;
    final glowColor = isDark
        ? DraculaPalette.primaryDark
        : DraculaPalette.primaryLight;
    final shape = context.appShape;

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(shape.panelRadius),
        border: Border.all(
          color: theme.dividerColor,
          width: context.appLayout.borderThin,
        ),
        boxShadow: [
          // Static purple edge-glow — no animation ever.
          BoxShadow(
            color: glowColor.withValues(alpha: 0.18),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );

    if (title == null) return panel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommentHeader(title: title!),
        const SizedBox(height: 4),
        Expanded(child: panel),
      ],
    );
  }
}

class _CommentHeader extends StatelessWidget {
  const _CommentHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final commentColor = isDark
        ? DraculaPalette.textSoftDark
        : DraculaPalette.textSoftLight;
    return Text(
      '// $title',
      style: TextStyle(
        fontFamily: context.appTypography.codeFontFamily,
        fontSize: context.appLayout.fontSizeSmall,
        color: commentColor,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NeonCapsule — method badge + status badge
// ---------------------------------------------------------------------------

/// Rounded pill badge (radius 999) with the given accent color and a subtle
/// static glow.  Shared by method and status slots.
class NeonCapsule extends StatelessWidget {
  const NeonCapsule({required this.text, required this.color, super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final on = context.appPalette.onColor(color);
    return Container(
      margin: EdgeInsets.only(right: layout.isCompact ? 6 : 10),
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal + 4,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: layout.borderThin),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.30),
            blurRadius: 6,
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          color: on,
          fontFamily: context.appTypography.codeFontFamily,
          fontSize: layout.fontSizeNormal,
          fontWeight: context.appTypography.titleWeight,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TerminalMetric — inline chip (metric)
// ---------------------------------------------------------------------------

/// `label: value` inline chip in `codeFontFamily` with an accent-colored key.
/// Compact — safe inside a [Wrap].
class TerminalMetric extends StatelessWidget {
  const TerminalMetric({required this.label, required this.value, super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final isDark = theme.brightness == Brightness.dark;
    final keyColor = isDark
        ? DraculaPalette.primaryDark
        : DraculaPalette.primaryLight;
    return Container(
      margin: EdgeInsets.only(right: layout.isCompact ? 6 : 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.dividerColor,
          width: layout.borderThin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              fontSize: layout.fontSizeSmall,
              color: keyColor,
              fontWeight: context.appTypography.titleWeight,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              fontSize: layout.fontSizeSmall,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ConsoleToggle — toggle
// ---------------------------------------------------------------------------

/// Rounded track toggle with accent fill + subtle glow when on.
/// [AnimatedAlign] thumb slide; tap flips.
class ConsoleToggle extends StatelessWidget {
  const ConsoleToggle({
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
    final accent = isDark
        ? DraculaPalette.primaryDark
        : DraculaPalette.primaryLight;
    final trackColor = value ? accent.withValues(alpha: 0.85) : theme.cardColor;

    final track = GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: animate ? const Duration(milliseconds: 160) : Duration.zero,
        width: 52,
        height: 26,
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: value ? accent : theme.dividerColor,
            width: layout.borderThin,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: animate ? const Duration(milliseconds: 160) : Duration.zero,
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              shape: BoxShape.circle,
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

// ---------------------------------------------------------------------------
// DevConsoleLog — logView (REPL style, bounded ListView)
// ---------------------------------------------------------------------------

/// REPL-style log view with colored prefix glyphs:
/// `→` outgoing / `←` incoming / `⊕` open / `⊗` close / `✗` error.
/// Uses [ListView.builder] — safe inside a bounded container.
class DevConsoleLog extends StatelessWidget {
  const DevConsoleLog({required this.lines, this.controller, super.key});
  final List<AppLogLine> lines;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      itemCount: lines.length,
      itemBuilder: (context, i) => _ConsoleRow(line: lines[i]),
    );
  }
}

class _ConsoleRow extends StatelessWidget {
  const _ConsoleRow({required this.line});
  final AppLogLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final layout = context.appLayout;

    // Dracula accent colors per direction
    final (glyph, color) = switch (line.kind) {
      AppLogLineKind.outgoing => (
        '→',
        isDark
            ? DraculaPalette.methodColorsDark['POST']!
            : DraculaPalette.methodColorsLight['POST']!,
      ),
      AppLogLineKind.incoming => (
        '←',
        isDark ? DraculaPalette.primaryDark : DraculaPalette.primaryLight,
      ),
      AppLogLineKind.open => (
        '⊕',
        isDark
            ? DraculaPalette.statusSuccessDark
            : DraculaPalette.statusSuccessLight,
      ),
      AppLogLineKind.close => (
        '⊗',
        isDark ? DraculaPalette.textSoftDark : DraculaPalette.textSoftLight,
      ),
      AppLogLineKind.error => (
        '✗',
        isDark
            ? DraculaPalette.statusErrorDark
            : DraculaPalette.statusErrorLight,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              glyph,
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                fontSize: layout.fontSizeCode,
                color: color,
                fontWeight: context.appTypography.titleWeight,
              ),
            ),
          ),
          const SizedBox(width: 6),
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

// ---------------------------------------------------------------------------
// ConsoleKvRow — dataRow
// ---------------------------------------------------------------------------

/// `key:` in accent color + mono value, separated by a thin divider.
class ConsoleKvRow extends StatelessWidget {
  const ConsoleKvRow({
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
    final isDark = theme.brightness == Brightness.dark;
    final layout = context.appLayout;
    final keyColor = isDark
        ? DraculaPalette.primaryDark
        : DraculaPalette.primaryLight;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              fontSize: layout.fontSizeNormal,
              color: keyColor,
              fontWeight: context.appTypography.titleWeight,
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
                    : context.appTypography.bodyWeight,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BlinkingCursor — pendingIndicator
// ---------------------------------------------------------------------------

/// "awaiting response…" line with a block cursor `▋` blinking via a single
/// [AnimationController].  Period is **700ms (≈1.43 Hz)**, well under the 3 Hz
/// WCAG 2.3.1 flash cap.  Under [animate]=false the cursor is rendered steady
/// (no controller created).
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({required this.label, this.animate = true, super.key});
  final String label;
  final bool animate;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  // Null when animate is false — the _c == null path renders a steady cursor.
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // 700ms period ≈ 1.43 Hz  ≤ 1.5 Hz hard cap.
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
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
    final isDark = theme.brightness == Brightness.dark;
    final layout = context.appLayout;
    final accent = isDark
        ? DraculaPalette.primaryDark
        : DraculaPalette.primaryLight;

    final labelWidget = Text(
      widget.label,
      style: TextStyle(
        fontFamily: context.appTypography.codeFontFamily,
        fontSize: layout.fontSizeNormal,
        color: theme.colorScheme.onSurface,
      ),
    );

    final cursorText = Text(
      '▋',
      style: TextStyle(
        fontFamily: context.appTypography.codeFontFamily,
        fontSize: layout.fontSizeNormal,
        color: accent,
      ),
    );
    final cursorBlock = _c == null
        ? cursorText
        : AnimatedBuilder(
            animation: _c!,
            child: cursorText,
            builder: (context, child) {
              // Toggle opacity 1↔0 once per period.
              final opacity = _c!.value < 0.5 ? 1.0 : 0.0;
              return Opacity(opacity: opacity, child: child);
            },
          );

    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [labelWidget, cursorBlock],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ConsoleStatusLine — statusBanner
// ---------------------------------------------------------------------------

/// Terminal-style `[OK]`/`[ERR]`/`[!]`/`[i]`-prefixed status line.
/// Color drives the bracket tag; message follows in mono.
class ConsoleStatusLine extends StatelessWidget {
  const ConsoleStatusLine({
    required this.state,
    required this.message,
    super.key,
  });
  final AppBannerState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final layout = context.appLayout;
    final palette = context.appPalette;

    final color = switch (state) {
      AppBannerState.success =>
        isDark
            ? DraculaPalette.statusSuccessDark
            : DraculaPalette.statusSuccessLight,
      AppBannerState.error =>
        isDark
            ? DraculaPalette.statusErrorDark
            : DraculaPalette.statusErrorLight,
      AppBannerState.warning =>
        isDark
            ? DraculaPalette.statusWarningDark
            : DraculaPalette.statusWarningLight,
      AppBannerState.info => palette.selectorActive,
    };

    final tag = switch (state) {
      AppBannerState.success => '[OK]',
      AppBannerState.error => '[ERR]',
      AppBannerState.warning => '[!]',
      AppBannerState.info => '[i]',
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: layout.isCompact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
          width: layout.borderThin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag,
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              fontSize: layout.fontSizeNormal,
              color: color,
              fontWeight: context.appTypography.displayWeight,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                fontSize: layout.fontSizeNormal,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
