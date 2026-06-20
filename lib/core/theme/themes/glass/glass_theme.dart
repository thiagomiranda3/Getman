import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_decorations.dart';
import 'package:getman/core/theme/themes/glass/glass_motion.dart';
import 'package:getman/core/theme/themes/glass/glass_palette.dart';
import 'package:getman/core/theme/themes/glass/glass_press.dart';
import 'package:google_fonts/google_fonts.dart';

/// Apple "Liquid Glass" theme. Translucent frosted panels (real backdrop blur),
/// generous rounding, hairline highlight edges, Apple-blue accent. Light =
/// "Clear", dark = "Smoked". The Scaffold is transparent so [GlassWallpaper]
/// (installed via scaffoldBackground) is the visible background.
///
/// When [reduceEffects] is true: no backdrop blur (frost stays identity), a
/// static wallpaper, and instant (non-animated) presses.
ThemeData glassTheme(
  Brightness brightness, {
  bool isCompact = false,
  bool reduceEffects = false,
}) {
  final isDark = brightness == Brightness.dark;
  final accent = isDark ? GlassPalette.accentDark : GlassPalette.accentLight;
  final panel = isDark ? GlassPalette.panelDark : GlassPalette.panelLight;
  final border = isDark ? GlassPalette.borderDark : GlassPalette.borderLight;
  final text = isDark ? GlassPalette.textDark : GlassPalette.textLight;
  final textSoft = isDark
      ? GlassPalette.textSoftDark
      : GlassPalette.textSoftLight;
  final codeBackground = isDark
      ? GlassPalette.codeBackgroundDark
      : GlassPalette.codeBackgroundLight;
  const onAccent = Colors.white;

  final layout = isCompact ? AppLayout.compact : AppLayout.normal;
  const shape = AppShape(
    panelRadius: 20,
    buttonRadius: 14,
    inputRadius: 14,
    dialogRadius: 24,
    sheetRadius: 28,
  );

  final inter = GoogleFonts.interTextTheme();
  final baseTextTheme = inter
      .apply(bodyColor: text, displayColor: text)
      .copyWith(
        bodyMedium: inter.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: text,
        ),
        bodySmall: inter.bodySmall?.copyWith(fontSize: 12, color: text),
        titleMedium: inter.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleLarge: inter.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: text,
        ),
      );

  final typography = AppTypography(
    base: baseTextTheme,
    codeFontFamily: GoogleFonts.jetBrainsMono().fontFamily!,
    displayWeight: FontWeight.w700,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
  );

  final palette = AppPalette(
    methodColors: GlassPalette.methodColors,
    methodFallback: GlassPalette.methodFallback,
    statusSuccess: GlassPalette.statusSuccess,
    statusWarning: GlassPalette.statusWarning,
    statusError: GlassPalette.statusError,
    statusAccentSuccess: GlassPalette.statusSuccess,
    statusAccentWarning: GlassPalette.statusWarning,
    statusAccentError: GlassPalette.statusError,
    codeBackground: codeBackground,
    variableResolved: GlassPalette.variableResolved,
    variableUnresolved: GlassPalette.variableUnresolved,
    selectorActive: accent,
    diffAddedForeground: GlassPalette.statusSuccess,
    diffAddedBackground: GlassPalette.statusSuccess.withValues(alpha: 0.16),
    diffRemovedForeground: GlassPalette.statusError,
    diffRemovedBackground: GlassPalette.statusError.withValues(alpha: 0.16),
  );

  // Full effects add real frost + an animated wallpaper + animated press;
  // reduced effects keep the identity frost (default), a static wallpaper, and
  // an instant press. Build the shared decoration once, then layer frost on.
  final decoration = AppDecoration(
    panelBox: glassPanelBox,
    tabShape: glassTabShape,
    brandedTabIndicator: glassBrandedTabIndicator,
    wrapInteractive: ({required child, onTap, scaleDown}) => GlassPress(
      animate: !reduceEffects,
      onTap: onTap,
      scaleDown: scaleDown ?? 0.98,
      child: child,
    ),
    scaffoldBackground: reduceEffects
        ? glassStaticScaffoldBackground
        : glassScaffoldBackground,
  );
  final effectiveDecoration = reduceEffects
      ? decoration
      : decoration.copyWith(frost: glassFrost);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: accent,
    // Transparent so GlassWallpaper (scaffoldBackground) is the visible base
    // and panels frost over it.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: panel,
    cardColor: panel,
    dividerColor: border,
    hoverColor: accent.withValues(alpha: 0.1),
    splashColor: accent.withValues(alpha: 0.2),
    colorScheme:
        (isDark
                ? ColorScheme.dark(primary: accent, secondary: accent)
                : ColorScheme.light(primary: accent, secondary: accent))
            .copyWith(
              onPrimary: onAccent,
              onSecondary: onAccent,
              surface: panel,
              onSurface: text,
            ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: layout.fontSizeSubtitle,
        color: text,
        fontWeight: FontWeight.w700,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: onAccent,
      unselectedLabelColor: textSoft,
      indicatorSize: TabBarIndicatorSize.tab,
      // Specular gradient lozenge (matches BrandedTabBar's glass indicator) so
      // any bare TabBar stays consistent with the panel tab strips. Top-rounded
      // only — the indicator sits flush on the tab content below it.
      indicator: BoxDecoration(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(shape.buttonRadius),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: 0.32), accent),
            accent.withValues(alpha: 0.94),
            Color.alphaBlend(Colors.black.withValues(alpha: 0.10), accent),
          ],
          stops: const [0, 0.5, 1],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.30 : 0.55),
          width: layout.borderThin,
        ),
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
    ),
    // Explicit switch styling: an always-visible white thumb, an accent track
    // when on and a translucent hairline-outlined track when off. Without this
    // the M3 default produced a near-invisible thumb on the glass surface.
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(onAccent),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return isDark
            ? Colors.white.withValues(alpha: 0.20)
            : Colors.black.withValues(alpha: 0.20);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return border;
      }),
      trackOutlineWidth: WidgetStatePropertyAll(layout.borderThin),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: TextStyle(
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: border, width: layout.borderThin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: TextStyle(
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: TextStyle(
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThin),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThin),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: accent, width: layout.borderThin),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      labelStyle: TextStyle(color: textSoft, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: textSoft.withValues(alpha: 0.7)),
      contentPadding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.inputPadding,
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.dialogRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
      titleTextStyle: TextStyle(
        color: text,
        fontSize: layout.fontSizeSubtitle,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(color: text, fontSize: layout.fontSizeTitle),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: accent,
      selectedColor: onAccent,
      titleTextStyle: TextStyle(fontWeight: FontWeight.w600, color: text),
      subtitleTextStyle: TextStyle(color: textSoft),
    ),
  );

  return base.copyWith(
    extensions: [
      layout,
      palette,
      shape,
      typography,
      effectiveDecoration,
      glassMotion(reduceEffects: reduceEffects),
      const AppCopy(emptyResponse: 'SEND A REQUEST TO SEE THE RESPONSE'),
    ],
  );
}
