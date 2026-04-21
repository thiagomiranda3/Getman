import 'package:flutter/material.dart';
import 'theme_ids.dart';
import 'themes/brutalist/brutalist_theme.dart';
import 'themes/editorial/editorial_theme.dart';
import 'themes/rpg/rpg_theme.dart';

typedef AppThemeBuilder = ThemeData Function(Brightness brightness, {bool isCompact});

const String defaultThemeId = kBrutalistThemeId;

const Map<String, AppThemeBuilder> appThemes = {
  kBrutalistThemeId: brutalistTheme,
  kEditorialThemeId: editorialTheme,
  kRpgThemeId: rpgTheme,
};

AppThemeBuilder resolveTheme(String? themeId) =>
    appThemes[themeId] ?? appThemes[defaultThemeId]!;
