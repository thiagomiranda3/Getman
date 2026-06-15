import 'package:flutter/material.dart';

class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.base,
    required this.codeFontFamily,
    required this.displayWeight,
    required this.titleWeight,
    required this.bodyWeight,
  });
  final TextTheme base;
  final String codeFontFamily;
  final FontWeight displayWeight;
  final FontWeight titleWeight;
  final FontWeight bodyWeight;

  @override
  AppTypography copyWith({
    TextTheme? base,
    String? codeFontFamily,
    FontWeight? displayWeight,
    FontWeight? titleWeight,
    FontWeight? bodyWeight,
  }) {
    return AppTypography(
      base: base ?? this.base,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
      displayWeight: displayWeight ?? this.displayWeight,
      titleWeight: titleWeight ?? this.titleWeight,
      bodyWeight: bodyWeight ?? this.bodyWeight,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      base: TextTheme.lerp(base, other.base, t),
      codeFontFamily: other.codeFontFamily,
      displayWeight: other.displayWeight,
      titleWeight: other.titleWeight,
      bodyWeight: other.bodyWeight,
    );
  }
}
