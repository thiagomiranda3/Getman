import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import 'rpg_decorations.dart';
import 'rpg_palette.dart';
import 'rpg_sparkle.dart';

/// Arcane Quest — an RPG-flavoured theme with sparkle-on-tap, animated
/// starfield background, glowing gold panels, and carved-stone typography.
ThemeData rpgTheme(Brightness brightness, {bool isCompact = false}) {
  final bool isDark = brightness == Brightness.dark;
  final Color background = isDark ? RpgPalette.backgroundDark : RpgPalette.backgroundLight;
  final Color surface = isDark ? RpgPalette.surfaceDark : RpgPalette.surfaceLight;
  final Color surfaceRaised = isDark ? RpgPalette.surfaceRaisedDark : RpgPalette.surfaceRaisedLight;
  final Color text = isDark ? RpgPalette.textDark : RpgPalette.textLight;
  final Color textSoft = isDark ? RpgPalette.textSoftDark : RpgPalette.textSoftLight;
  final Color border = isDark ? RpgPalette.borderDark : RpgPalette.borderLight;
  const Color gold = RpgPalette.gold;
  const Color emerald = RpgPalette.emerald;

  final AppLayout layout = isCompact ? AppLayout.compact : AppLayout.normal;
  const AppShape shape = AppShape(
    panelRadius: 6,
    buttonRadius: 6,
    inputRadius: 4,
    dialogRadius: 10,
  );

  // Fonts: Cinzel Decorative for display, Spectral for body, Fira Code for code.
  final cinzelDecorative = GoogleFonts.cinzelDecorative().fontFamily!;
  final cinzel = GoogleFonts.cinzel().fontFamily!;
  final spectral = GoogleFonts.spectralTextTheme();
  final codeFamily = GoogleFonts.firaCode().fontFamily!;

  final baseTextTheme = spectral.apply(bodyColor: text, displayColor: text).copyWith(
    displayLarge: TextStyle(
      fontFamily: cinzelDecorative,
      fontSize: 32,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
      color: text,
    ),
    displayMedium: TextStyle(
      fontFamily: cinzelDecorative,
      fontSize: 24,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.0,
      color: text,
    ),
    titleLarge: TextStyle(
      fontFamily: cinzel,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: text,
    ),
    titleMedium: TextStyle(
      fontFamily: cinzel,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: text,
    ),
    bodyMedium: spectral.bodyMedium?.copyWith(
      fontSize: layout.fontSizeTitle,
      fontWeight: FontWeight.w500,
      color: text,
    ),
    bodySmall: spectral.bodySmall?.copyWith(
      fontSize: layout.fontSizeNormal,
      fontWeight: FontWeight.w500,
      color: text,
    ),
    labelSmall: TextStyle(
      fontFamily: cinzel,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.8,
      color: textSoft,
    ),
  );

  final typography = AppTypography(
    base: baseTextTheme,
    codeFontFamily: codeFamily,
    displayWeight: FontWeight.w900,
    titleWeight: FontWeight.w700,
    bodyWeight: FontWeight.w500,
  );

  final palette = AppPalette(
    methodColors: RpgPalette.methodColors,
    methodFallback: RpgPalette.methodFallback,
    statusSuccess: RpgPalette.statusSuccess,
    statusWarning: RpgPalette.statusWarning,
    statusError: RpgPalette.statusError,
    statusAccentSuccess: RpgPalette.statusAccentSuccess,
    statusAccentWarning: RpgPalette.statusAccentWarning,
    statusAccentError: RpgPalette.statusAccentError,
    codeBackground: isDark ? RpgPalette.codeBackgroundDark : RpgPalette.codeBackgroundLight,
  );

  final decoration = AppDecoration(
    panelBox: rpgPanelBox,
    tabShape: rpgTabShape,
    wrapInteractive: ({required child, onTap, scaleDown}) =>
        RpgSparkle(onTap: onTap, scaleDown: scaleDown ?? 0.96, child: child),
    scaffoldBackground: rpgScaffoldBackground,
    doubleRule: rpgDoubleRule,
  );

  final cinzelUppercase = TextStyle(
    fontFamily: cinzel,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: gold,
    scaffoldBackgroundColor: background,
    canvasColor: surface,
    cardColor: surface,
    dividerColor: border,
    hoverColor: gold.withValues(alpha: 0.08),
    splashColor: gold.withValues(alpha: 0.18),
    colorScheme: isDark
        ? ColorScheme.dark(
            primary: gold,
            secondary: emerald,
            surface: surface,
            surfaceContainerHighest: surfaceRaised,
            onPrimary: RpgPalette.backgroundDark,
            onSecondary: RpgPalette.backgroundDark,
            onSurface: text,
            error: RpgPalette.ruby,
            onError: Colors.white,
          )
        : ColorScheme.light(
            primary: gold,
            secondary: RpgPalette.emeraldDeep,
            surface: surface,
            surfaceContainerHighest: surfaceRaised,
            onPrimary: RpgPalette.backgroundDark,
            onSecondary: Colors.white,
            onSurface: text,
            error: RpgPalette.ruby,
            onError: Colors.white,
          ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: cinzelDecorative,
        fontSize: layout.fontSizeSubtitle,
        color: text,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      ),
      shape: Border(bottom: BorderSide(color: border, width: layout.borderThin)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: text,
      unselectedLabelColor: textSoft,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: gold.withValues(alpha: 0.2),
        border: Border(
          top: BorderSide(color: gold, width: layout.borderThick),
          left: BorderSide(color: border, width: layout.borderThin),
          right: BorderSide(color: border, width: layout.borderThin),
        ),
      ),
      labelStyle: cinzelUppercase.copyWith(color: text),
      unselectedLabelStyle: cinzelUppercase.copyWith(color: textSoft),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: RpgPalette.backgroundDark,
        elevation: 0,
        shadowColor: gold.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
          side: BorderSide(color: RpgPalette.goldDeep, width: layout.borderThin),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: TextStyle(
          fontFamily: cinzel,
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: RpgPalette.backgroundDark,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withValues(alpha: 0.18);
          }
          if (states.contains(WidgetState.pressed)) {
            return Colors.black.withValues(alpha: 0.12);
          }
          return null;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: gold,
        side: BorderSide(color: gold, width: layout.borderThin),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(shape.buttonRadius)),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: TextStyle(
          fontFamily: cinzel,
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: gold,
        textStyle: TextStyle(
          fontFamily: cinzel,
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThin),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThin),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: gold, width: layout.borderThin + 0.5),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      labelStyle: TextStyle(color: textSoft, fontWeight: FontWeight.w700, fontFamily: cinzel, letterSpacing: 1.0),
      hintStyle: TextStyle(color: textSoft.withValues(alpha: 0.6), fontFamily: spectral.bodyMedium?.fontFamily),
      contentPadding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.inputPaddingVertical,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.dialogRadius),
        side: BorderSide(color: gold, width: layout.borderThin),
      ),
      titleTextStyle: TextStyle(
        fontFamily: cinzelDecorative,
        color: text,
        fontSize: layout.fontSizeSubtitle,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      ),
      contentTextStyle: TextStyle(
        fontFamily: spectral.bodyMedium?.fontFamily,
        color: text,
        fontSize: layout.fontSizeTitle,
        fontWeight: FontWeight.w500,
      ),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: gold.withValues(alpha: 0.15),
      selectedColor: gold,
      titleTextStyle: TextStyle(
        fontFamily: cinzel,
        fontWeight: FontWeight.w700,
        color: text,
        letterSpacing: 0.6,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: codeFamily,
        fontSize: 11,
        color: textSoft,
        letterSpacing: 0.4,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: gold, width: layout.borderThin),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(gold.withValues(alpha: 0.5)),
    ),
  );

  return base.copyWith(extensions: [layout, palette, shape, typography, decoration]);
}
