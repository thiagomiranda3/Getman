import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_switch_theme.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/dracula/dracula_decorations.dart';
import 'package:getman/core/theme/themes/dracula/dracula_palette.dart';
import 'package:getman/core/theme/themes/dracula/dracula_press.dart';
import 'package:getman/core/theme/themes/shared/calm_motion.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dracula theme — the popular VS Code palette. Dark uses "Dracula Classic";
/// light uses the project's official "Alucard" light companion. Visual
/// personality is clean & flat (soft rounded corners, thin purple-tinted
/// borders, gentle shadows — no hard offsets, no animated background).
ThemeData draculaTheme(
  Brightness brightness, {
  bool isCompact = false,
  bool reduceEffects = false,
}) {
  final isDark = brightness == Brightness.dark;
  final background = isDark
      ? DraculaPalette.backgroundDark
      : DraculaPalette.backgroundLight;
  final surface = isDark
      ? DraculaPalette.surfaceDark
      : DraculaPalette.surfaceLight;
  final text = isDark ? DraculaPalette.textDark : DraculaPalette.textLight;
  final textSoft = isDark
      ? DraculaPalette.textSoftDark
      : DraculaPalette.textSoftLight;
  final border = isDark
      ? DraculaPalette.borderDark
      : DraculaPalette.borderLight;
  final currentPrimary = isDark
      ? DraculaPalette.primaryDark
      : DraculaPalette.primaryLight;
  final currentSecondary = isDark
      ? DraculaPalette.secondaryDark
      : DraculaPalette.secondaryLight;
  // The dark-mode purple is light enough to need dark text on top; the
  // light-mode (Alucard) purple is deep and needs white.
  final onPrimary = isDark ? DraculaPalette.backgroundDark : Colors.white;
  final onSecondary = isDark ? DraculaPalette.backgroundDark : Colors.white;
  // Request-tab (TabWidget) label color. The active tab sits on the surface
  // (not the purple indicator), so onPrimary would be unreadable there — dark
  // text on the dark surface / white text on the white Alucard surface. Use a
  // single high-contrast color for both active and inactive in each mode
  // (active/inactive stay distinct via background, font weight, and the purple
  // top accent line): white on dark, black on light.
  final tabLabelColor = isDark ? Colors.white : Colors.black;

  final layout = isCompact ? AppLayout.compact : AppLayout.normal;
  const shape = AppShape(
    panelRadius: 8,
    buttonRadius: 6,
    inputRadius: 6,
    dialogRadius: 12,
    sheetRadius: 16,
  );

  final lexend = GoogleFonts.lexendTextTheme();
  final baseTextTheme = lexend
      .apply(bodyColor: text, displayColor: text)
      .copyWith(
        bodyMedium: lexend.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: text,
        ),
        bodySmall: lexend.bodySmall?.copyWith(fontSize: 12, color: text),
        titleMedium: lexend.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleLarge: lexend.titleLarge?.copyWith(
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
    methodColors: isDark
        ? DraculaPalette.methodColorsDark
        : DraculaPalette.methodColorsLight,
    methodFallback: DraculaPalette.methodFallback,
    statusSuccess: isDark
        ? DraculaPalette.statusSuccessDark
        : DraculaPalette.statusSuccessLight,
    statusWarning: isDark
        ? DraculaPalette.statusWarningDark
        : DraculaPalette.statusWarningLight,
    statusError: isDark
        ? DraculaPalette.statusErrorDark
        : DraculaPalette.statusErrorLight,
    statusAccentSuccess: isDark
        ? DraculaPalette.statusSuccessDark
        : DraculaPalette.statusSuccessLight,
    statusAccentWarning: isDark
        ? DraculaPalette.statusWarningDark
        : DraculaPalette.statusWarningLight,
    statusAccentError: isDark
        ? DraculaPalette.statusErrorDark
        : DraculaPalette.statusErrorLight,
    codeBackground: isDark
        ? DraculaPalette.codeBackgroundDark
        : DraculaPalette.codeBackgroundLight,
    variableResolved: isDark
        ? DraculaPalette.variableResolvedDark
        : DraculaPalette.variableResolvedLight,
    variableUnresolved: isDark
        ? DraculaPalette.variableUnresolvedDark
        : DraculaPalette.variableUnresolvedLight,
    selectorActive: currentPrimary,
    diffAddedForeground: isDark
        ? DraculaPalette.statusSuccessDark
        : DraculaPalette.statusSuccessLight,
    diffAddedBackground:
        (isDark
                ? DraculaPalette.statusSuccessDark
                : DraculaPalette.statusSuccessLight)
            .withValues(alpha: 0.16),
    diffRemovedForeground: isDark
        ? DraculaPalette.statusErrorDark
        : DraculaPalette.statusErrorLight,
    diffRemovedBackground:
        (isDark
                ? DraculaPalette.statusErrorDark
                : DraculaPalette.statusErrorLight)
            .withValues(alpha: 0.16),
  );

  final decoration = AppDecoration(
    panelBox: draculaPanelBox,
    tabShape: draculaTabShape,
    wrapInteractive: ({required child, onTap, scaleDown}) =>
        DraculaPress(onTap: onTap, scaleDown: scaleDown ?? 0.98, child: child),
    scaffoldBackground: draculaScaffoldBackground,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: currentPrimary,
    switchTheme: accentSwitchTheme(
      thumbWhenOn: currentSecondary,
      trackWhenOn: currentPrimary,
    ),
    scaffoldBackgroundColor: background,
    canvasColor: surface,
    dividerColor: border,
    hoverColor: currentPrimary.withValues(alpha: 0.1),
    splashColor: currentPrimary.withValues(alpha: 0.2),
    colorScheme: isDark
        ? ColorScheme.dark(
            primary: currentPrimary,
            onPrimary: onPrimary,
            secondary: currentSecondary,
            onSecondary: onSecondary,
            surface: surface,
            onSurface: text,
          )
        : ColorScheme.light(
            primary: currentPrimary,
            onPrimary: onPrimary,
            secondary: currentSecondary,
            onSecondary: onSecondary,
            surface: surface,
            onSurface: text,
          ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: layout.fontSizeSubtitle,
        color: text,
        fontWeight: FontWeight.w700,
      ),
      shape: Border(
        bottom: BorderSide(color: border, width: layout.borderThin),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: tabLabelColor,
      unselectedLabelColor: tabLabelColor,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: currentPrimary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(shape.buttonRadius),
        ),
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: currentPrimary,
        foregroundColor: onPrimary,
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
          color: onPrimary,
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
        foregroundColor: currentSecondary,
        textStyle: TextStyle(
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w600,
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
        borderSide: BorderSide(color: currentPrimary, width: layout.borderThin),
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
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
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
      selectedTileColor: currentPrimary,
      selectedColor: onPrimary,
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
      decoration,
      calmMotion(reduceEffects: reduceEffects),
      const AppCopy(emptyResponse: 'SEND A REQUEST TO SEE THE RESPONSE'),
    ],
  );
}
