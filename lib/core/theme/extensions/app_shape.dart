import 'package:flutter/material.dart';

class AppShape extends ThemeExtension<AppShape> {
  final double panelRadius;
  final double buttonRadius;
  final double inputRadius;
  final double dialogRadius;

  /// Top-corner radius for modal bottom sheets (action sheets, tab switcher).
  final double sheetRadius;

  const AppShape({
    required this.panelRadius,
    required this.buttonRadius,
    required this.inputRadius,
    required this.dialogRadius,
    required this.sheetRadius,
  });

  @override
  AppShape copyWith({
    double? panelRadius,
    double? buttonRadius,
    double? inputRadius,
    double? dialogRadius,
    double? sheetRadius,
  }) {
    return AppShape(
      panelRadius: panelRadius ?? this.panelRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      inputRadius: inputRadius ?? this.inputRadius,
      dialogRadius: dialogRadius ?? this.dialogRadius,
      sheetRadius: sheetRadius ?? this.sheetRadius,
    );
  }

  @override
  AppShape lerp(ThemeExtension<AppShape>? other, double t) {
    if (other is! AppShape) return this;
    double l(double a, double b) => (b - a) * t + a;
    return AppShape(
      panelRadius: l(panelRadius, other.panelRadius),
      buttonRadius: l(buttonRadius, other.buttonRadius),
      inputRadius: l(inputRadius, other.inputRadius),
      dialogRadius: l(dialogRadius, other.dialogRadius),
      sheetRadius: l(sheetRadius, other.sheetRadius),
    );
  }
}
