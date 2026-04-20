import 'package:flutter/material.dart';
import 'theme_ids.dart';
import 'themes/brutalist/brutalist_theme.dart';

typedef AppThemeBuilder = ThemeData Function(Brightness brightness, {bool isCompact});

const String defaultThemeId = kBrutalistThemeId;

const Map<String, AppThemeBuilder> appThemes = {
  kBrutalistThemeId: brutalistTheme,
};

AppThemeBuilder resolveTheme(String? themeId) =>
    appThemes[themeId] ?? appThemes[defaultThemeId]!;
