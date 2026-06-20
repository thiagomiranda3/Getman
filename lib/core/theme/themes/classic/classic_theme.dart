import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_switch_theme.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/classic/classic_decorations.dart';
import 'package:getman/core/theme/themes/classic/classic_palette.dart';
import 'package:getman/core/theme/themes/classic/classic_press.dart';
import 'package:getman/core/theme/themes/shared/calm_motion.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData classicTheme(
  Brightness brightness, {
  bool isCompact = false,
  bool reduceEffects = false,
}) {
  final isDark = brightness == Brightness.dark;
  final scaffold = isDark
      ? ClassicPalette.scaffoldDark
      : ClassicPalette.scaffoldLight;
  final surface = isDark
      ? ClassicPalette.surfaceDark
      : ClassicPalette.surfaceLight;
  final ink = isDark ? ClassicPalette.inkDark : ClassicPalette.inkLight;
  final inkSoft = isDark
      ? ClassicPalette.inkSoftDark
      : ClassicPalette.inkSoftLight;
  final border = isDark
      ? ClassicPalette.borderDark
      : ClassicPalette.borderLight;
  final accent = isDark
      ? ClassicPalette.accentDark
      : ClassicPalette.accentLight;
  final code = isDark
      ? ClassicPalette.codeBackgroundDark
      : ClassicPalette.codeBackgroundLight;

  // Density: start from the shared layout and dial padding/borders down so the
  // theme reads calm and tight (no "huge paddings", no thick borders).
  final layoutBase = isCompact ? AppLayout.compact : AppLayout.normal;
  final layout = layoutBase.copyWith(
    pagePadding: isCompact ? 10 : 16,
    sectionSpacing: isCompact ? 10 : 16,
    buttonPaddingHorizontal: isCompact ? 14 : 16,
    buttonPaddingVertical: isCompact ? 8 : 10,
    inputPadding: isCompact ? 10 : 12,
    headerPaddingVertical: isCompact ? 10 : 12,
    headerFontSize: isCompact ? 17 : 18,
    tabBarHeight: isCompact ? 38 : 44,
    cardOffset: 0,
    borderThin: 1,
    borderThick: 1.5,
    borderHeavy: 2,
  );

  const shape = AppShape(
    panelRadius: 6,
    buttonRadius: 6,
    inputRadius: 6,
    dialogRadius: 10,
    sheetRadius: 12,
  );

  final interText = GoogleFonts.interTextTheme();
  final interFamily = GoogleFonts.inter().fontFamily;
  final monoFamily = GoogleFonts.jetBrainsMono().fontFamily!;
  final baseTextTheme = interText.apply(bodyColor: ink, displayColor: ink);

  final typography = AppTypography(
    base: baseTextTheme,
    codeFontFamily: monoFamily,
    displayWeight: FontWeight.w600,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
  );

  final palette = AppPalette(
    methodColors: ClassicPalette.methodColors,
    methodFallback: inkSoft,
    statusSuccess: ClassicPalette.statusSuccess,
    statusWarning: ClassicPalette.statusWarning,
    statusError: ClassicPalette.statusError,
    statusAccentSuccess: ClassicPalette.statusAccentSuccess,
    statusAccentWarning: ClassicPalette.statusAccentWarning,
    statusAccentError: ClassicPalette.statusAccentError,
    codeBackground: code,
    variableResolved: ClassicPalette.statusAccentSuccess,
    variableUnresolved: ClassicPalette.statusAccentError,
    selectorActive: accent,
    diffAddedForeground: ClassicPalette.statusSuccess,
    diffAddedBackground: ClassicPalette.statusSuccess.withValues(alpha: 0.12),
    diffRemovedForeground: ClassicPalette.statusError,
    diffRemovedBackground: ClassicPalette.statusError.withValues(alpha: 0.12),
  );

  // Legible text/icon color on the accent and on the error color.
  final onAccent = palette.onColor(accent);
  final onError = palette.onColor(ClassicPalette.statusError);

  final decoration = AppDecoration(
    panelBox: classicPanelBox,
    tabShape: classicTabShape,
    wrapInteractive: ({required child, onTap, scaleDown}) => ClassicPress(
      onTap: onTap,
      scaleDown: scaleDown,
      animate: !reduceEffects,
      child: child,
    ),
    scaffoldBackground: classicScaffoldBackground,
  );

  final labelStyle = TextStyle(
    fontFamily: interFamily,
    fontSize: layout.fontSizeNormal,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: accent,
    switchTheme: accentSwitchTheme(thumbWhenOn: surface, trackWhenOn: accent),
    scaffoldBackgroundColor: scaffold,
    canvasColor: scaffold,
    cardColor: surface,
    dividerColor: border,
    hoverColor: ink.withValues(alpha: isDark ? 0.06 : 0.04),
    splashColor: ink.withValues(alpha: 0.08),
    colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
          primary: accent,
          onPrimary: onAccent,
          secondary: inkSoft,
          onSecondary: surface,
          surface: surface,
          onSurface: ink,
          error: ClassicPalette.statusError,
          onError: onError,
        ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: baseTextTheme.titleMedium?.copyWith(
        fontSize: layout.fontSizeSubtitle,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      shape: Border(
        bottom: BorderSide(color: border, width: layout.borderThin),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: accent,
      unselectedLabelColor: inkSoft,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: accent, width: layout.borderThick),
        ),
      ),
      labelStyle: labelStyle.copyWith(color: accent),
      unselectedLabelStyle: labelStyle.copyWith(color: inkSoft),
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
        textStyle: labelStyle.copyWith(color: onAccent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: border, width: layout.borderThin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: labelStyle.copyWith(color: ink),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: labelStyle.copyWith(color: accent),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(shape.inputRadius),
        borderSide: BorderSide(color: border, width: layout.borderThin),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(shape.inputRadius),
        borderSide: BorderSide(color: border, width: layout.borderThin),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(shape.inputRadius),
        borderSide: BorderSide(color: accent, width: layout.borderThick),
      ),
      labelStyle: TextStyle(color: inkSoft),
      hintStyle: TextStyle(color: inkSoft.withValues(alpha: 0.6)),
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
        side: BorderSide(color: border, width: layout.borderThin),
      ),
      titleTextStyle: baseTextTheme.titleLarge?.copyWith(
        fontSize: layout.fontSizeSubtitle,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      contentTextStyle: baseTextTheme.bodyMedium?.copyWith(color: ink),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: accent.withValues(alpha: 0.10),
      selectedColor: accent,
      // Pin the ListTile text styles (inherit:true, like the other themes).
      // Without these, ListTile falls back to the geometry-localized
      // `textTheme` styles, which are inherit:false — and a ListTile mounted
      // during a theme switch then lerps the previous theme's inherit:true
      // style against this one, crashing AnimatedDefaultTextStyle with
      // "Failed to interpolate TextStyles with different inherit values".
      titleTextStyle: TextStyle(
        fontFamily: interFamily,
        fontWeight: typography.titleWeight,
        color: ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: interFamily,
        color: inkSoft,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThin),
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
      const AppCopy(emptyResponse: 'No response yet.'),
    ],
  );
}
