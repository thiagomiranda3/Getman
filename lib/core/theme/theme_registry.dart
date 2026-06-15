import 'package:flutter/material.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/theme/themes/editorial/editorial_theme.dart';
import 'package:getman/core/theme/themes/rpg/rpg_theme.dart';

typedef AppThemeBuilder =
    ThemeData Function(Brightness brightness, {bool isCompact});

/// Everything a theme registration needs: identity (persisted in settings),
/// a display name for the UI picker, and the actual builder.
class ThemeDescriptor {
  const ThemeDescriptor({
    required this.id,
    required this.displayName,
    required this.builder,
  });
  final String id;
  final String displayName;
  final AppThemeBuilder builder;
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

AppThemeBuilder resolveTheme(String? themeId) =>
    resolveThemeDescriptor(themeId).builder;

// Cache keyed by (resolved theme id, brightness, isCompact).
// ThemeData is immutable and theme builders are pure functions of these three
// inputs, so entries are safe to share indefinitely.
// Bounded: themes × brightness × compact ≤ ~12 entries total.
final Map<(String, Brightness, bool), ThemeData> _themeDataCache = {};

/// Resolve and build the [ThemeData] for [themeId], caching by
/// (resolved theme id, brightness, isCompact) so repeated calls during
/// BLoC rebuilds never re-run the expensive theme builder.
ThemeData resolveThemeData(
  String? themeId,
  Brightness brightness, {
  required bool isCompact,
}) {
  // Resolve the id first so an unknown id shares a cache entry with the
  // fallback theme rather than creating a separate (never-reused) entry.
  final resolvedId = resolveThemeDescriptor(themeId).id;
  final key = (resolvedId, brightness, isCompact);
  return _themeDataCache.putIfAbsent(
    key,
    () => resolveTheme(resolvedId)(brightness, isCompact: isCompact),
  );
}
