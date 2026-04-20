import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'brutalist_bounce.dart';
import 'brutalist_decorations.dart';
import 'brutalist_palette.dart';

ThemeData brutalistTheme(Brightness brightness, {bool isCompact = false}) {
  final bool isDark = brightness == Brightness.dark;
  final Color background = isDark ? BrutalistPalette.backgroundDark : BrutalistPalette.backgroundLight;
  final Color surface = isDark ? BrutalistPalette.surfaceDark : BrutalistPalette.surfaceLight;
  final Color text = isDark ? BrutalistPalette.textDark : BrutalistPalette.textLight;
  final Color border = isDark ? BrutalistPalette.borderDark : BrutalistPalette.borderLight;
  final Color currentPrimary = isDark ? BrutalistPalette.primaryDark : BrutalistPalette.primary;
  final Color currentSecondary = isDark ? BrutalistPalette.secondaryDark : BrutalistPalette.secondary;

  final AppLayout layout = isCompact ? AppLayout.compact : AppLayout.normal;
  const AppShape shape = AppShape(panelRadius: 4, buttonRadius: 4, inputRadius: 4, dialogRadius: 8);

  final lexend = GoogleFonts.lexendTextTheme();
  final baseTextTheme = lexend.apply(bodyColor: text, displayColor: text).copyWith(
    bodyMedium: lexend.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: text),
    bodySmall: lexend.bodySmall?.copyWith(fontSize: 12, color: text),
    titleMedium: lexend.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: text),
    titleLarge: lexend.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: text),
  );

  final typography = AppTypography(
    base: baseTextTheme,
    codeFontFamily: GoogleFonts.jetBrainsMono().fontFamily!,
    displayWeight: FontWeight.w900,
    titleWeight: FontWeight.w700,
    bodyWeight: FontWeight.w500,
  );

  final palette = AppPalette(
    methodColors: BrutalistPalette.methodColors,
    methodFallback: BrutalistPalette.methodFallback,
    statusSuccess: Colors.green.shade700,
    statusWarning: Colors.orange.shade700,
    statusError: Colors.red.shade700,
    statusAccentSuccess: Colors.greenAccent,
    statusAccentWarning: Colors.orangeAccent,
    statusAccentError: Colors.redAccent,
    codeBackground: isDark ? BrutalistPalette.backgroundDark : Colors.white,
    mutedHover: Colors.black.withValues(alpha: 0.05),
  );

  final decoration = AppDecoration(
    panelBox: brutalistPanelBox,
    tabShape: brutalistTabShape,
    wrapInteractive: ({required child, onTap, scaleDown}) =>
        BrutalBounce(onTap: onTap, scaleDown: scaleDown ?? 0.95, child: child),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: currentPrimary,
    scaffoldBackgroundColor: background,
    canvasColor: surface,
    dividerColor: border,
    hoverColor: currentPrimary.withValues(alpha: 0.1),
    splashColor: currentPrimary.withValues(alpha: 0.2),
    colorScheme: isDark
        ? ColorScheme.dark(
            primary: currentPrimary,
            secondary: currentSecondary,
            surface: BrutalistPalette.surfaceDark,
            onPrimary: BrutalistPalette.textLight,
            onSecondary: Colors.white,
            onSurface: BrutalistPalette.textDark,
          )
        : ColorScheme.light(
            primary: currentPrimary,
            secondary: currentSecondary,
            surface: BrutalistPalette.surfaceLight,
            onPrimary: BrutalistPalette.textLight,
            onSecondary: Colors.white,
            onSurface: BrutalistPalette.textLight,
          ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      centerTitle: false,
      // Intentional change from reference's const 18: now responsive via AppLayout.fontSizeSubtitle (18/14).
      titleTextStyle: TextStyle(fontSize: layout.fontSizeSubtitle, color: text, fontWeight: FontWeight.w900),
      shape: Border(bottom: BorderSide(color: border, width: layout.borderThick)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: BrutalistPalette.textLight,
      unselectedLabelColor: text,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: currentPrimary,
        border: Border(
          top: BorderSide(color: border, width: layout.borderThick),
          left: BorderSide(color: border, width: layout.borderThick),
          right: BorderSide(color: border, width: layout.borderThick),
        ),
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: currentPrimary,
        foregroundColor: BrutalistPalette.textLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
          side: BorderSide(color: border, width: layout.borderThick),
        ),
        padding: EdgeInsets.symmetric(horizontal: layout.buttonPaddingHorizontal, vertical: layout.buttonPaddingVertical),
        textStyle: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900, color: BrutalistPalette.textLight),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered)) return Colors.white.withValues(alpha: 0.2);
          if (states.contains(WidgetState.pressed)) return Colors.black.withValues(alpha: 0.1);
          return null;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: border, width: layout.borderThick),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(shape.buttonRadius)),
        padding: EdgeInsets.symmetric(horizontal: layout.buttonPaddingHorizontal, vertical: layout.buttonPaddingVertical),
        textStyle: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: currentSecondary,
        textStyle: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThick),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThick),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: currentSecondary, width: layout.borderThick),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      labelStyle: TextStyle(color: text, fontWeight: FontWeight.bold),
      hintStyle: TextStyle(color: text.withValues(alpha: 0.5)),
      contentPadding: EdgeInsets.symmetric(horizontal: layout.inputPadding, vertical: layout.inputPadding),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThick),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.dialogRadius),
        side: BorderSide(color: border, width: layout.borderHeavy),
      ),
      titleTextStyle: TextStyle(color: text, fontSize: layout.fontSizeSubtitle, fontWeight: FontWeight.w900),
      contentTextStyle: TextStyle(color: text, fontSize: layout.fontSizeTitle),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: currentPrimary,
      selectedColor: BrutalistPalette.textLight,
      titleTextStyle: TextStyle(fontWeight: FontWeight.bold, color: text),
      subtitleTextStyle: TextStyle(color: text.withValues(alpha: 0.7)),
    ),
  );

  return base.copyWith(extensions: [layout, palette, shape, typography, decoration]);
}
