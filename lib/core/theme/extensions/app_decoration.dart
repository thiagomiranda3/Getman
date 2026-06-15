import 'package:flutter/material.dart';

typedef PanelBoxBuilder =
    BoxDecoration Function(
      BuildContext context, {
      Color? color,
      double? borderWidth,
      double? offset,
      BorderRadius? borderRadius,
    });

typedef TabShapeBuilder =
    BoxDecoration Function(
      BuildContext context, {
      required bool active,
      required bool hovered,
      required bool isFirst,
    });

typedef InteractiveWrapper =
    Widget Function({
      required Widget child,
      VoidCallback? onTap,
      double? scaleDown,
    });

typedef ScaffoldBackgroundWrapper =
    Widget Function(
      BuildContext context, {
      required Widget child,
    });

class AppDecoration extends ThemeExtension<AppDecoration> {
  const AppDecoration({
    required this.panelBox,
    required this.tabShape,
    required this.wrapInteractive,
    required this.scaffoldBackground,
  });
  final PanelBoxBuilder panelBox;
  final TabShapeBuilder tabShape;
  final InteractiveWrapper wrapInteractive;
  final ScaffoldBackgroundWrapper scaffoldBackground;

  @override
  AppDecoration copyWith({
    PanelBoxBuilder? panelBox,
    TabShapeBuilder? tabShape,
    InteractiveWrapper? wrapInteractive,
    ScaffoldBackgroundWrapper? scaffoldBackground,
  }) {
    return AppDecoration(
      panelBox: panelBox ?? this.panelBox,
      tabShape: tabShape ?? this.tabShape,
      wrapInteractive: wrapInteractive ?? this.wrapInteractive,
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
    );
  }

  @override
  AppDecoration lerp(ThemeExtension<AppDecoration>? other, double t) => this;
}
