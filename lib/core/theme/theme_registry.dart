import 'package:flutter/material.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/themes/auris/auris_theme.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/theme/themes/classic/classic_theme.dart';
import 'package:getman/core/theme/themes/dracula/dracula_theme.dart';
import 'package:getman/core/theme/themes/editorial/editorial_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_theme.dart';
import 'package:getman/core/theme/themes/rpg/rpg_theme.dart';

typedef AppThemeBuilder =
    ThemeData Function(
      Brightness brightness, {
      bool isCompact,
      bool reduceEffects,
    });

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

const String defaultThemeId = kClassicThemeId;

const Map<String, ThemeDescriptor> appThemes = {
  kClassicThemeId: ThemeDescriptor(
    id: kClassicThemeId,
    displayName: 'CLASSIC',
    builder: classicTheme,
  ),
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
  kDraculaThemeId: ThemeDescriptor(
    id: kDraculaThemeId,
    displayName: 'DRACULA',
    builder: draculaTheme,
  ),
  kGlassThemeId: ThemeDescriptor(
    id: kGlassThemeId,
    displayName: 'LIQUID GLASS',
    builder: glassTheme,
  ),
  kAurisThemeId: ThemeDescriptor(
    id: kAurisThemeId,
    displayName: 'AURIS',
    builder: aurisTheme,
  ),
};

ThemeDescriptor resolveThemeDescriptor(String? themeId) =>
    appThemes[themeId] ?? appThemes[defaultThemeId]!;

AppThemeBuilder resolveTheme(String? themeId) =>
    resolveThemeDescriptor(themeId).builder;

// Cache keyed by (resolved theme id, brightness, isCompact, reduceEffects).
// ThemeData is immutable and theme builders are pure functions of these inputs,
// so entries are safe to share indefinitely.
// Bounded: themes × brightness × compact × reduceEffects ≤ ~16 entries total.
final Map<(String, Brightness, bool, bool), ThemeData> _themeDataCache = {};

/// Resolve and build the [ThemeData] for [themeId], caching by
/// (resolved theme id, brightness, isCompact, reduceEffects) so repeated calls
/// during BLoC rebuilds never re-run the expensive theme builder.
ThemeData resolveThemeData(
  String? themeId,
  Brightness brightness, {
  required bool isCompact,
  bool reduceEffects = false,
}) {
  // Resolve the id first so an unknown id shares a cache entry with the
  // fallback theme rather than creating a separate (never-reused) entry.
  final resolvedId = resolveThemeDescriptor(themeId).id;
  final key = (resolvedId, brightness, isCompact, reduceEffects);
  return _themeDataCache.putIfAbsent(
    key,
    () => _materializeTextThemes(
      resolveTheme(resolvedId)(
        brightness,
        isCompact: isCompact,
        reduceEffects: reduceEffects,
      ),
    ),
  );
}

/// Normalizes a built theme's `textTheme`/`primaryTextTheme` so every text
/// style is `inherit: false` with a non-null `textBaseline` — the Material
/// convention. The app uses `themeAnimationDuration: Duration.zero`, so on a
/// theme switch a mounted `ListTile` (and similar) runs its OWN internal
/// `AnimatedDefaultTextStyle` lerp between the old and new resolved styles.
/// `TextStyle.lerp` throws if the two sides disagree on `inherit`, and ListTile
/// force-unwraps `textBaseline` — so a theme whose package text styles are
/// `inherit: true` / lack a baseline (AURIS) crashed every time it was switched
/// to/from with a ListTile mounted (e.g. the Settings dialog). Forcing every
/// theme to the same Material-conventional shape makes all cross-theme lerps
/// safe. Styles already specify font/size/color, so this does not change how
/// they render. Applied here (the single build+cache choke point) so it covers
/// every current and future theme uniformly. See auris_text_lerp_test.
ThemeData _materializeTextThemes(ThemeData theme) => theme.copyWith(
  textTheme: _materialTextTheme(theme.textTheme),
  primaryTextTheme: _materialTextTheme(theme.primaryTextTheme),
  // ListTile resolves its leading/trailing/title/subtitle styles from
  // listTileTheme too (e.g. AURIS sets a ShareTechMono inherit:true style
  // there), each wrapped in an AnimatedDefaultTextStyle — normalize them too.
  listTileTheme: theme.listTileTheme.copyWith(
    titleTextStyle: _materialStyle(theme.listTileTheme.titleTextStyle),
    subtitleTextStyle: _materialStyle(theme.listTileTheme.subtitleTextStyle),
    leadingAndTrailingTextStyle: _materialStyle(
      theme.listTileTheme.leadingAndTrailingTextStyle,
    ),
  ),
);

TextTheme _materialTextTheme(TextTheme t) => TextTheme(
  displayLarge: _materialStyle(t.displayLarge),
  displayMedium: _materialStyle(t.displayMedium),
  displaySmall: _materialStyle(t.displaySmall),
  headlineLarge: _materialStyle(t.headlineLarge),
  headlineMedium: _materialStyle(t.headlineMedium),
  headlineSmall: _materialStyle(t.headlineSmall),
  titleLarge: _materialStyle(t.titleLarge),
  titleMedium: _materialStyle(t.titleMedium),
  titleSmall: _materialStyle(t.titleSmall),
  bodyLarge: _materialStyle(t.bodyLarge),
  bodyMedium: _materialStyle(t.bodyMedium),
  bodySmall: _materialStyle(t.bodySmall),
  labelLarge: _materialStyle(t.labelLarge),
  labelMedium: _materialStyle(t.labelMedium),
  labelSmall: _materialStyle(t.labelSmall),
);

TextStyle? _materialStyle(TextStyle? s) => s?.copyWith(
  inherit: false,
  textBaseline: s.textBaseline ?? TextBaseline.alphabetic,
);
