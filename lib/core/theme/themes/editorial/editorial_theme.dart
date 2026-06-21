import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_switch_theme.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/editorial/editorial_components.dart';
import 'package:getman/core/theme/themes/editorial/editorial_decorations.dart';
import 'package:getman/core/theme/themes/editorial/editorial_fade.dart';
import 'package:getman/core/theme/themes/editorial/editorial_palette.dart';
import 'package:getman/core/theme/themes/shared/calm_motion.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData editorialTheme(
  Brightness brightness, {
  bool isCompact = false,
  bool reduceEffects = false,
}) {
  final isDark = brightness == Brightness.dark;
  final paper = isDark
      ? EditorialPalette.paperDark
      : EditorialPalette.paperLight;
  final ink = isDark ? EditorialPalette.inkDark : EditorialPalette.inkLight;
  final inkSoft = isDark
      ? EditorialPalette.inkSoftDark
      : EditorialPalette.inkSoftLight;
  const accent = EditorialPalette.accent;

  final layout = isCompact ? AppLayout.compact : AppLayout.normal;
  const shape = AppShape(
    panelRadius: 0,
    buttonRadius: 0,
    inputRadius: 0,
    dialogRadius: 0,
    sheetRadius: 0,
  );

  final fraunces = GoogleFonts.frauncesTextTheme();
  final inter = GoogleFonts.interTextTheme();
  final plexMonoFamily = GoogleFonts.ibmPlexMono().fontFamily!;

  final baseTextTheme = fraunces
      .apply(bodyColor: ink, displayColor: ink)
      .copyWith(
        bodyMedium: inter.bodyMedium?.copyWith(
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w400,
          color: ink,
        ),
        bodySmall: inter.bodySmall?.copyWith(
          fontSize: layout.fontSizeNormal,
          fontWeight: FontWeight.w400,
          color: ink,
        ),
        titleMedium: fraunces.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleLarge: fraunces.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: ink,
        ),
        labelSmall: TextStyle(
          fontFamily: plexMonoFamily,
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 2.8,
          color: inkSoft,
        ),
      );

  final typography = AppTypography(
    base: baseTextTheme,
    codeFontFamily: plexMonoFamily,
    displayWeight: FontWeight.w900,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
  );

  final palette = AppPalette(
    methodColors: EditorialPalette.methodColors,
    methodFallback: inkSoft,
    statusSuccess: EditorialPalette.statusSuccess,
    statusWarning: EditorialPalette.statusWarning,
    statusError: EditorialPalette.statusError,
    statusAccentSuccess: EditorialPalette.statusAccentSuccess,
    statusAccentWarning: EditorialPalette.statusAccentWarning,
    statusAccentError: EditorialPalette.statusAccentError,
    codeBackground: isDark
        ? EditorialPalette.codeBackgroundDark
        : EditorialPalette.codeBackgroundLight,
    variableResolved: EditorialPalette.statusAccentSuccess,
    variableUnresolved: EditorialPalette.statusAccentError,
    selectorActive: EditorialPalette.accent,
    diffAddedForeground: EditorialPalette.statusSuccess,
    diffAddedBackground: EditorialPalette.statusSuccess.withValues(alpha: 0.12),
    diffRemovedForeground: EditorialPalette.statusError,
    diffRemovedBackground: EditorialPalette.statusError.withValues(alpha: 0.12),
  );

  final decoration = AppDecoration(
    panelBox: editorialPanelBox,
    tabShape: editorialTabShape,
    wrapInteractive: ({required child, onTap, scaleDown}) =>
        EditorialFade(onTap: onTap, child: child),
    scaffoldBackground: editorialScaffoldBackground,
  );

  final plexUppercase = TextStyle(
    fontFamily: plexMonoFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 2.4,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: accent,
    switchTheme: accentSwitchTheme(thumbWhenOn: inkSoft, trackWhenOn: accent),
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
    cardColor: paper,
    dividerColor: ink,
    hoverColor: ink.withValues(alpha: 0.04),
    splashColor: ink.withValues(alpha: 0.08),
    colorScheme: isDark
        ? ColorScheme.dark(
            primary: accent,
            secondary: inkSoft,
            surface: paper,
            onPrimary: paper,
            onSecondary: paper,
            onSurface: ink,
            error: accent,
            onError: paper,
          )
        : ColorScheme.light(
            primary: accent,
            secondary: inkSoft,
            surface: paper,
            onPrimary: paper,
            onSecondary: paper,
            onSurface: ink,
            error: accent,
            onError: paper,
          ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: GoogleFonts.fraunces().fontFamily,
        fontSize: layout.fontSizeSubtitle,
        color: ink,
        fontWeight: FontWeight.w600,
      ),
      shape: Border(bottom: BorderSide(color: ink)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: ink,
      unselectedLabelColor: inkSoft,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ink, width: layout.borderThick),
        ),
      ),
      labelStyle: plexUppercase.copyWith(color: ink),
      unselectedLabelStyle: plexUppercase.copyWith(color: inkSoft),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ink, width: layout.borderThin),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: plexUppercase.copyWith(color: paper),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink, width: layout.borderThin),
        shape: const RoundedRectangleBorder(),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: plexUppercase.copyWith(color: ink),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        textStyle: plexUppercase.copyWith(color: ink),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: ink, width: layout.borderThin),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: ink, width: layout.borderThin),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: accent, width: layout.borderThin),
      ),
      labelStyle: plexUppercase.copyWith(color: inkSoft),
      hintStyle: TextStyle(
        fontFamily: GoogleFonts.fraunces().fontFamily,
        color: inkSoft.withValues(alpha: 0.6),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.inputPaddingVertical,
      ),
    ),
    cardTheme: CardThemeData(
      color: paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: ink, width: layout.borderThin),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: ink, width: layout.borderThin),
      ),
      titleTextStyle: TextStyle(
        fontFamily: GoogleFonts.fraunces().fontFamily,
        color: ink,
        fontSize: layout.fontSizeSubtitle,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        fontFamily: GoogleFonts.inter().fontFamily,
        color: ink,
        fontSize: layout.fontSizeTitle,
        fontWeight: FontWeight.w400,
      ),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: accent.withValues(alpha: 0.08),
      selectedColor: accent,
      titleTextStyle: TextStyle(
        fontFamily: GoogleFonts.fraunces().fontFamily,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: plexMonoFamily,
        fontSize: 11,
        letterSpacing: 2.4,
        color: inkSoft,
      ),
    ),
  );

  return base.copyWith(
    extensions: [
      layout,
      palette,
      shape,
      typography,
      decoration,
      calmMotion(reduceEffects: reduceEffects),
      const AppCopy(emptyResponse: 'Awaiting the first response'),
      editorialComponents(),
    ],
  );
}
