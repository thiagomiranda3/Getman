// The AppCopy theme extension: per-theme user-facing strings so copy such as
// empty-state text can vary by theme's voice without hardcoding it in
// widgets.
import 'package:flutter/material.dart';

/// Per-theme user-facing copy (strings), so empty states read in each theme's
/// voice without hardcoding text in widgets.
class AppCopy extends ThemeExtension<AppCopy> {
  const AppCopy({required this.emptyResponse});
  final String emptyResponse;

  @override
  AppCopy copyWith({String? emptyResponse}) =>
      AppCopy(emptyResponse: emptyResponse ?? this.emptyResponse);

  // Strings don't interpolate — snap to the target.
  @override
  AppCopy lerp(ThemeExtension<AppCopy>? other, double t) =>
      other is AppCopy ? other : this;
}
