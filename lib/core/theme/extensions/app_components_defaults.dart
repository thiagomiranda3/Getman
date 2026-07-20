// Default component-slot implementations that reproduce the app's CURRENT
// rendering for each surface. Themes that do not override a slot inherit these
// closures, so existing themes look identical after the slot system lands.
//
// Rules:
//  • Pull all sizes/colors/weights from context.app* — never hardcode.
//  • Each private widget stays under ~40 lines.
//  • No imports from `data/`, no GetIt, no BLoC.

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:shimmer/shimmer.dart';

/// Returns an [AppComponents] whose every slot reproduces today's rendering.
/// Call this in theme builders that have no custom overrides.
AppComponents defaultAppComponents() {
  return const AppComponents(
    surface: _defaultSurface,
    methodBadge: _defaultMethodBadge,
    statusBadge: _defaultStatusBadge,
    metric: _defaultMetric,
    toggle: _defaultToggle,
    logView: _defaultLogView,
    dataRow: _defaultDataRow,
    select: _defaultSelect,
    pendingIndicator: _defaultPendingIndicator,
    statusBanner: _defaultStatusBanner,
  );
}

// ---------------------------------------------------------------------------
// surface
// ---------------------------------------------------------------------------

Widget _defaultSurface(
  BuildContext context, {
  required Widget child,
  String? title,
  String? code,
  bool accent = false,
}) {
  return Container(
    decoration: context.appDecoration.panelBox(context, offset: 0),
    child: child,
  );
}

// ---------------------------------------------------------------------------
// methodBadge  — mirrors MethodBadge in lib/core/ui/widgets/method_badge.dart
// ---------------------------------------------------------------------------

Widget _defaultMethodBadge(
  BuildContext context, {
  required String method,
  bool small = false,
}) {
  return _DefaultMethodBadge(method: method, small: small);
}

class _DefaultMethodBadge extends StatelessWidget {
  const _DefaultMethodBadge({required this.method, required this.small});
  final String method;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final color = context.appPalette.methodColor(method);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
      ),
      child: Text(
        method,
        style: TextStyle(
          color: context.appPalette.methodOn(method),
          fontWeight: context.appTypography.displayWeight,
          fontSize: small ? layout.fontSizeSmall : layout.fontSizeNormal,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// statusBadge  — byte-faithful reproduction of the STATUS chip in
// ResponseMetadataItem: 600ms color-fade keyed by statusCode, label 'STATUS',
// border, panelRadius, and the same white-in-dark text logic.
// ---------------------------------------------------------------------------

Widget _defaultStatusBadge(
  BuildContext context, {
  required int statusCode,
}) {
  return _DefaultStatusBadge(statusCode: statusCode);
}

class _DefaultStatusBadge extends StatelessWidget {
  const _DefaultStatusBadge({required this.statusCode});
  final int statusCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final baseColor = context.appPalette.statusAccent(statusCode);
    final isDark = theme.brightness == Brightness.dark;
    final lightOn = context.appPalette.onColor(baseColor);
    // Deliberate contrast on a variable-colored status badge
    // (docs/architecture/theming.md exception): STATUS text is always white
    // in dark mode; light mode keeps the higher-contrast on-color.
    // ignore: avoid_hardcoded_brand_colors
    final textColor = isDark ? Colors.white : lightOn;

    return TweenAnimationBuilder<Color?>(
      key: ValueKey(statusCode),
      duration: const Duration(milliseconds: 600),
      tween: ColorTween(
        begin: baseColor.withValues(alpha: 1),
        end: baseColor.withValues(alpha: 0.2),
      ),
      builder: (context, animColor, child) {
        return Container(
          margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: layout.isCompact ? 4 : 8,
          ),
          decoration: BoxDecoration(
            color: animColor,
            border: Border.all(
              color: theme.dividerColor,
              width: layout.borderThin,
            ),
            borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'STATUS: ',
            style: TextStyle(
              color: textColor,
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.titleWeight,
            ),
          ),
          Text(
            '$statusCode',
            style: TextStyle(
              color: textColor,
              fontWeight: context.appTypography.displayWeight,
              fontSize: layout.fontSizeNormal,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// metric  — byte-faithful reproduction of TIME/SIZE chips in
// ResponseMetadataItem: 600ms color-fade keyed by value, label text, border,
// panelRadius, and the same white-in-dark text logic. delta is ignored by the
// default (not rendered in the original ResponseMetadataItem).
// ---------------------------------------------------------------------------

Widget _defaultMetric(
  BuildContext context, {
  required String label,
  required String value,
  String? unit,
  String? delta,
}) {
  return _DefaultMetric(label: label, value: value, unit: unit, delta: delta);
}

class _DefaultMetric extends StatelessWidget {
  const _DefaultMetric({
    required this.label,
    required this.value,
    this.unit,
    this.delta,
  });
  final String label;
  final String value;
  final String? unit;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final baseColor = theme.colorScheme.secondary;
    final isDark = theme.brightness == Brightness.dark;
    final lightOn = context.appPalette.onColor(baseColor);
    // Deliberate contrast on a variable-colored metric chip
    // (docs/architecture/theming.md exception): TIME/SIZE text is always
    // white in dark mode; light mode keeps the higher-contrast on-color.
    // ignore: avoid_hardcoded_brand_colors
    final textColor = isDark ? Colors.white : lightOn;
    final displayValue = unit != null ? '$value $unit' : value;

    return TweenAnimationBuilder<Color?>(
      key: ValueKey(displayValue),
      duration: const Duration(milliseconds: 600),
      tween: ColorTween(
        begin: baseColor.withValues(alpha: 1),
        end: baseColor.withValues(alpha: 0.2),
      ),
      builder: (context, animColor, child) {
        return Container(
          margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: layout.isCompact ? 4 : 8,
          ),
          decoration: BoxDecoration(
            color: animColor,
            border: Border.all(
              color: theme.dividerColor,
              width: layout.borderThin,
            ),
            borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: textColor,
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.titleWeight,
            ),
          ),
          Text(
            displayValue,
            style: TextStyle(
              color: textColor,
              fontWeight: context.appTypography.displayWeight,
              fontSize: layout.fontSizeNormal,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// toggle
// ---------------------------------------------------------------------------

Widget _defaultToggle(
  BuildContext context, {
  required bool value,
  required ValueChanged<bool> onChanged,
  String? label,
}) {
  return _DefaultToggle(value: value, onChanged: onChanged, label: label);
}

class _DefaultToggle extends StatelessWidget {
  const _DefaultToggle({
    required this.value,
    required this.onChanged,
    this.label,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: layout.fontSizeNormal,
              fontWeight: context.appTypography.bodyWeight,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// logView  — mirrors _FrameRow rows in realtime_panel.dart
// ---------------------------------------------------------------------------

Widget _defaultLogView(
  BuildContext context, {
  required List<AppLogLine> lines,
  String? title,
  ScrollController? controller,
}) {
  return _DefaultLogView(lines: lines, controller: controller);
}

class _DefaultLogView extends StatelessWidget {
  const _DefaultLogView({required this.lines, this.controller});
  final List<AppLogLine> lines;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
      itemCount: lines.length,
      itemBuilder: (context, i) => _LogLineRow(line: lines[i]),
    );
  }
}

class _LogLineRow extends StatelessWidget {
  const _LogLineRow({required this.line});
  final AppLogLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final palette = context.appPalette;

    final (icon, label, color) = switch (line.kind) {
      AppLogLineKind.outgoing => (
        Icons.arrow_upward,
        'OUT',
        theme.colorScheme.secondary,
      ),
      AppLogLineKind.incoming => (
        Icons.arrow_downward,
        'IN',
        theme.colorScheme.onSurface,
      ),
      AppLogLineKind.open => (
        Icons.link,
        'OPEN',
        palette.statusSuccess,
      ),
      AppLogLineKind.close => (
        Icons.link_off,
        'CLOSE',
        theme.colorScheme.onSurface,
      ),
      AppLogLineKind.error => (
        Icons.error_outline,
        'ERROR',
        palette.statusError,
      ),
    };

    return Padding(
      padding: EdgeInsets.only(bottom: layout.tabSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: layout.smallIconSize, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.displayWeight,
                color: color,
              ),
            ),
          ),
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
// dataRow  — mirrors response header/cookie row (ListTile pattern)
// ---------------------------------------------------------------------------

Widget _defaultDataRow(
  BuildContext context, {
  required String label,
  required String value,
  bool highlight = false,
}) {
  return _DefaultDataRow(label: label, value: value, highlight: highlight);
}

class _DefaultDataRow extends StatelessWidget {
  const _DefaultDataRow({
    required this.label,
    required this.value,
    required this.highlight,
  });
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    // A transparency Material gives the row its own ink/background surface.
    // The views render these rows inside a themed panel (a colored DecoratedBox
    // via panelBox); Flutter 3.44 asserts when a ListTile's nearest background
    // ancestor is that colored box rather than a Material. Transparency paints
    // nothing, so the panel behind it still shows through.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        title: Text(
          label,
          style: TextStyle(
            fontWeight: context.appTypography.titleWeight,
            fontSize: layout.fontSizeNormal,
            // Both highlight states use primaryColor — the views always show
            // the key in primaryColor regardless of highlight state.
            color: theme.primaryColor,
          ),
        ),
        subtitle: Text(
          value,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: highlight ? context.appTypography.titleWeight : null,
            color: highlight
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// select  — a PopupMenuButton reflecting spec.selectedIndex
// ---------------------------------------------------------------------------

Widget _defaultSelect(BuildContext context, AppSelectSpec spec) {
  return _DefaultSelect(spec: spec);
}

class _DefaultSelect extends StatelessWidget {
  const _DefaultSelect({required this.spec});
  final AppSelectSpec spec;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    final selected =
        spec.selectedIndex >= 0 && spec.selectedIndex < spec.items.length
        ? spec.items[spec.selectedIndex]
        : null;
    final label = selected?.label ?? spec.placeholder ?? '';

    return PopupMenuButton<int>(
      onSelected: spec.onSelected,
      itemBuilder: (context) => [
        for (var i = 0; i < spec.items.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                if (spec.items[i].leading != null) ...[
                  spec.items[i].leading!,
                  const SizedBox(width: 8),
                ],
                Text(
                  spec.items[i].label,
                  style: TextStyle(
                    fontSize: layout.fontSizeNormal,
                    fontWeight: i == spec.selectedIndex
                        ? context.appTypography.titleWeight
                        : context.appTypography.bodyWeight,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: layout.fontSizeNormal,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down,
            size: layout.iconSize,
            color: theme.colorScheme.onSurface,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// pendingIndicator  — mirrors the Shimmer skeleton in response_section.dart
// ---------------------------------------------------------------------------

Widget _defaultPendingIndicator(
  BuildContext context, {
  String? label,
}) {
  return _DefaultPendingIndicator(label: label);
}

class _DefaultPendingIndicator extends StatelessWidget {
  const _DefaultPendingIndicator({this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final shimmerFill = theme.colorScheme.onSurface.withValues(alpha: 0.08);

    return Semantics(
      key: const ValueKey('response_pending_indicator'),
      label: label ?? 'Loading response',
      liveRegion: true,
      child: Shimmer.fromColors(
        baseColor: theme.dividerColor.withValues(alpha: 0.1),
        highlightColor: theme.dividerColor.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 100,
                  height: 32,
                  decoration: BoxDecoration(
                    color: shimmerFill,
                    border: Border.all(
                      color: theme.dividerColor,
                      width: layout.borderThin,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 100,
                  height: 32,
                  decoration: BoxDecoration(
                    color: shimmerFill,
                    border: Border.all(
                      color: theme.dividerColor,
                      width: layout.borderThin,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: 15,
                itemBuilder: (context, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Container(
                    width: double.infinity,
                    height: 20,
                    color: shimmerFill,
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

// ---------------------------------------------------------------------------
// statusBanner  — mirrors _StatusBanner in realtime_panel.dart
// ---------------------------------------------------------------------------

Widget _defaultStatusBanner(
  BuildContext context, {
  required AppBannerState state,
  required String message,
}) {
  return _DefaultStatusBanner(state: state, message: message);
}

class _DefaultStatusBanner extends StatelessWidget {
  const _DefaultStatusBanner({required this.state, required this.message});
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
    final on = palette.onColor(color);

    final icon = switch (state) {
      AppBannerState.success => Icons.link,
      AppBannerState.error => Icons.link_off,
      AppBannerState.warning => Icons.warning_amber_outlined,
      AppBannerState.info => Icons.info_outline,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: layout.isCompact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: theme.dividerColor,
          width: layout.borderThin,
        ),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: on, size: layout.smallIconSize),
          const SizedBox(width: 6),
          Text(
            message,
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
