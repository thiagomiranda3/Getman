import 'package:flutter/material.dart';

/// Mirrors realtime frame directions (the log view's only consumer).
enum AppLogLineKind { outgoing, incoming, open, close, error }

@immutable
class AppLogLine {
  const AppLogLine({required this.text, required this.kind});
  final String text;
  final AppLogLineKind kind;
}

@immutable
class AppSelectItem {
  const AppSelectItem({required this.label, this.leading});
  final String label;
  final Widget? leading;
}

@immutable
class AppSelectSpec {
  const AppSelectSpec({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.placeholder,
  });
  final List<AppSelectItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? placeholder;
}

enum AppBannerState { info, success, warning, error }

typedef SurfaceBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      String? title,
      String? code,
      bool accent,
    });
typedef MethodBadgeBuilder =
    Widget Function(
      BuildContext context, {
      required String method,
      bool small,
    });
typedef StatusBadgeBuilder =
    Widget Function(
      BuildContext context, {
      required int statusCode,
    });
typedef MetricBuilder =
    Widget Function(
      BuildContext context, {
      required String label,
      required String value,
      String? unit,
      String? delta,
    });
typedef ToggleBuilder =
    Widget Function(
      BuildContext context, {
      required bool value,
      required ValueChanged<bool> onChanged,
      String? label,
    });
typedef LogViewBuilder =
    Widget Function(
      BuildContext context, {
      required List<AppLogLine> lines,
      String? title,
      ScrollController? controller,
    });
typedef DataRowBuilder =
    Widget Function(
      BuildContext context, {
      required String label,
      required String value,
      bool highlight,
    });
typedef SelectBuilder =
    Widget Function(
      BuildContext context,
      AppSelectSpec spec,
    );
typedef PendingIndicatorBuilder =
    Widget Function(
      BuildContext context, {
      String? label,
    });
typedef StatusBannerBuilder =
    Widget Function(
      BuildContext context, {
      required AppBannerState state,
      required String message,
    });

class AppComponents extends ThemeExtension<AppComponents> {
  const AppComponents({
    required this.surface,
    required this.methodBadge,
    required this.statusBadge,
    required this.metric,
    required this.toggle,
    required this.logView,
    required this.dataRow,
    required this.select,
    required this.pendingIndicator,
    required this.statusBanner,
  });

  final SurfaceBuilder surface;
  final MethodBadgeBuilder methodBadge;
  final StatusBadgeBuilder statusBadge;
  final MetricBuilder metric;
  final ToggleBuilder toggle;
  final LogViewBuilder logView;
  final DataRowBuilder dataRow;
  final SelectBuilder select;
  final PendingIndicatorBuilder pendingIndicator;
  final StatusBannerBuilder statusBanner;

  @override
  AppComponents copyWith({
    SurfaceBuilder? surface,
    MethodBadgeBuilder? methodBadge,
    StatusBadgeBuilder? statusBadge,
    MetricBuilder? metric,
    ToggleBuilder? toggle,
    LogViewBuilder? logView,
    DataRowBuilder? dataRow,
    SelectBuilder? select,
    PendingIndicatorBuilder? pendingIndicator,
    StatusBannerBuilder? statusBanner,
  }) {
    return AppComponents(
      surface: surface ?? this.surface,
      methodBadge: methodBadge ?? this.methodBadge,
      statusBadge: statusBadge ?? this.statusBadge,
      metric: metric ?? this.metric,
      toggle: toggle ?? this.toggle,
      logView: logView ?? this.logView,
      dataRow: dataRow ?? this.dataRow,
      select: select ?? this.select,
      pendingIndicator: pendingIndicator ?? this.pendingIndicator,
      statusBanner: statusBanner ?? this.statusBanner,
    );
  }

  @override
  AppComponents lerp(ThemeExtension<AppComponents>? other, double t) => this;
}
