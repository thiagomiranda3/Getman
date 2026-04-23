import 'package:flutter/material.dart';
import 'theme_ids.dart';
import 'themes/brutalist/brutalist_theme.dart';
import 'themes/editorial/editorial_theme.dart';
import 'themes/rpg/rpg_theme.dart';

typedef AppThemeBuilder = ThemeData Function(Brightness brightness, {bool isCompact});

/// Everything a theme registration needs: identity (persisted in settings),
/// a display name for the UI picker, and the actual builder.
class ThemeDescriptor {
  final String id;
  final String displayName;
  final AppThemeBuilder builder;

  const ThemeDescriptor({
    required this.id,
    required this.displayName,
    required this.builder,
  });
}

const String defaultThemeId = kBrutalistThemeId;

const Map<String, ThemeDescriptor> appThemes = {
  kBrutalistThemeId: ThemeDescriptor(
    id: kBrutalistThemeId,
    displayName: 'BRUTALIST',
    builder: brutalistTheme,
  ),
  kEditorialThemeId: ThemeDescriptor(
    id: kEditorialThemeId,
    displayName: 'EDITORIAL',
    builder: editorialTheme,
  ),
  kRpgThemeId: ThemeDescriptor(
    id: kRpgThemeId,
    displayName: 'ARCANE QUEST',
    builder: rpgTheme,
  ),
};

ThemeDescriptor resolveThemeDescriptor(String? themeId) =>
    appThemes[themeId] ?? appThemes[defaultThemeId]!;

AppThemeBuilder resolveTheme(String? themeId) => resolveThemeDescriptor(themeId).builder;
