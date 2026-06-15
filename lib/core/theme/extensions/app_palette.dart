import 'package:flutter/material.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.methodColors,
    required this.methodFallback,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
    required this.statusAccentSuccess,
    required this.statusAccentWarning,
    required this.statusAccentError,
    required this.codeBackground,
    required this.variableResolved,
    required this.variableUnresolved,
    required this.selectorActive,
  });
  final Map<String, Color> methodColors;
  final Color methodFallback;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusError;
  final Color statusAccentSuccess;
  final Color statusAccentWarning;
  final Color statusAccentError;
  final Color codeBackground;
  final Color variableResolved;
  final Color variableUnresolved;

  /// Background for the active segment of a selector/toggle (body-type chips,
  /// response Pretty/Raw toggle). Each theme maps it to its signature accent.
  /// Pair with [Color]-derived contrast text via
  /// `ThemeData.estimateBrightnessForColor`.
  final Color selectorActive;

  Color methodColor(String method) =>
      methodColors[method.toUpperCase()] ?? methodFallback;

  Color statusColor(int code) {
    if (code >= 200 && code < 300) return statusSuccess;
    if (code >= 400) return statusError;
    return statusWarning;
  }

  Color statusAccent(int code) {
    if (code >= 200 && code < 300) return statusAccentSuccess;
    if (code >= 400) return statusAccentError;
    return statusAccentWarning;
  }

  /// Black or white — whichever yields the higher WCAG contrast on
  /// [background].
  /// (Flutter's estimateBrightnessForColor is threshold-based and picks the
  /// wrong one for some mid-tone colors; this direct comparison is optimal and
  /// guarantees >= ~4.58:1 for any background.) For text/icons on method- and
  /// status-colored chips instead of hardcoding white. (a11y)
  Color onColor(Color background) {
    final lum = background.computeLuminance();
    final contrastWithWhite = 1.05 / (lum + 0.05);
    final contrastWithBlack = (lum + 0.05) / 0.05;
    return contrastWithWhite >= contrastWithBlack ? Colors.white : Colors.black;
  }

  Color methodOn(String method) => onColor(methodColor(method));
  Color statusOn(int code) => onColor(statusColor(code));

  @override
  AppPalette copyWith({
    Map<String, Color>? methodColors,
    Color? methodFallback,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusError,
    Color? statusAccentSuccess,
    Color? statusAccentWarning,
    Color? statusAccentError,
    Color? codeBackground,
    Color? variableResolved,
    Color? variableUnresolved,
    Color? selectorActive,
  }) {
    return AppPalette(
      methodColors: methodColors ?? this.methodColors,
      methodFallback: methodFallback ?? this.methodFallback,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      statusError: statusError ?? this.statusError,
      statusAccentSuccess: statusAccentSuccess ?? this.statusAccentSuccess,
      statusAccentWarning: statusAccentWarning ?? this.statusAccentWarning,
      statusAccentError: statusAccentError ?? this.statusAccentError,
      codeBackground: codeBackground ?? this.codeBackground,
      variableResolved: variableResolved ?? this.variableResolved,
      variableUnresolved: variableUnresolved ?? this.variableUnresolved,
      selectorActive: selectorActive ?? this.selectorActive,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      methodColors: other.methodColors,
      methodFallback: Color.lerp(methodFallback, other.methodFallback, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      statusAccentSuccess: Color.lerp(
        statusAccentSuccess,
        other.statusAccentSuccess,
        t,
      )!,
      statusAccentWarning: Color.lerp(
        statusAccentWarning,
        other.statusAccentWarning,
        t,
      )!,
      statusAccentError: Color.lerp(
        statusAccentError,
        other.statusAccentError,
        t,
      )!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      variableResolved: Color.lerp(
        variableResolved,
        other.variableResolved,
        t,
      )!,
      variableUnresolved: Color.lerp(
        variableUnresolved,
        other.variableUnresolved,
        t,
      )!,
      selectorActive: Color.lerp(selectorActive, other.selectorActive, t)!,
    );
  }
}
