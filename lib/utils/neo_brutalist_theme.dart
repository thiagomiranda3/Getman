import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NeoBrutalistTheme {
  // Neo-Brutalist Colors
  static const Color backgroundLight = Color(0xFFF8F7F2); // Off-White
  static const Color surfaceLight = Color(0xFFFFFFFF); // White
  static const Color textLight = Color(0xFF000000); // Black
  static const Color borderLight = Color(0xFF000000); // Black

  static const Color backgroundDark = Color(0xFF1A1A1A); // Softer Black
  static const Color surfaceDark = Color(0xFF242424); // Dark Gray
  static const Color textDark = Color(0xFFE0E0E0); // Off-White
  static const Color borderDark = Color(0xFF404040); // Muted Border

  static const Color primary = Color(0xFFFDE047); // Vibrant Yellow
  static const Color primaryDark = Color(0xFFD4B92E); // Muted Yellow for Dark mode
  
  static const Color secondary = Color(0xFF7C3AED); // Violet
  static const Color secondaryDark = Color(0xFF6330BD); // Muted Violet for Dark mode
  
  static const Color lightGray = Color(0xFFE5E7EB);

  static Color getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET': return const Color(0xFF4ADE80); // Green
      case 'POST': return const Color(0xFF60A5FA); // Blue
      case 'PUT': return const Color(0xFFFB923C); // Orange
      case 'DELETE': return const Color(0xFFF87171); // Red
      case 'PATCH': return const Color(0xFFA78BFA); // Purple
      default: return Colors.grey;
    }
  }

  static ThemeData get lightTheme => _createTheme(Brightness.light);
  static ThemeData get darkTheme => _createTheme(Brightness.dark);

  static ThemeData _createTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color background = isDark ? backgroundDark : backgroundLight;
    final Color surface = isDark ? surfaceDark : surfaceLight;
    final Color text = isDark ? textDark : textLight;
    final Color border = isDark ? borderDark : borderLight;
    final Color currentPrimary = isDark ? primaryDark : primary;
    final Color currentSecondary = isDark ? secondaryDark : secondary;
    
    final baseTextTheme = GoogleFonts.lexendTextTheme();
    
    return ThemeData(
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
            surface: surfaceDark,
            onPrimary: textLight,
            onSecondary: Colors.white,
            onSurface: textDark,
          )
        : ColorScheme.light(
            primary: currentPrimary,
            secondary: currentSecondary,
            surface: surfaceLight,
            onPrimary: textLight,
            onSecondary: Colors.white,
            onSurface: textLight,
          ),
      textTheme: baseTextTheme.apply(
        bodyColor: text,
        displayColor: text,
      ).copyWith(
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: text),
        bodySmall: baseTextTheme.bodySmall?.copyWith(fontSize: 12, color: text),
        titleMedium: baseTextTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: text),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: text),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 18, color: text, fontWeight: FontWeight.w900),
        shape: Border(bottom: BorderSide(color: border, width: 3)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: text.withValues(alpha: 0.7),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: currentPrimary,
          border: Border(
            top: BorderSide(color: border, width: 3),
            left: BorderSide(color: border, width: 3),
            right: BorderSide(color: border, width: 3),
          ),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: currentPrimary,
          foregroundColor: textLight,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: border, width: 3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
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
          side: BorderSide(color: border, width: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: currentSecondary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: border, width: 3),
          borderRadius: BorderRadius.circular(4),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: border, width: 3),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: currentSecondary, width: 3),
          borderRadius: BorderRadius.circular(4),
        ),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.bold),
        hintStyle: TextStyle(color: text.withValues(alpha: 0.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: border, width: 3),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border, width: 4),
        ),
        titleTextStyle: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900),
        contentTextStyle: TextStyle(color: text, fontSize: 14),
      ),
      listTileTheme: ListTileThemeData(
        selectedTileColor: currentPrimary,
        selectedColor: textLight,
        titleTextStyle: TextStyle(fontWeight: FontWeight.bold, color: text),
        subtitleTextStyle: TextStyle(color: text.withValues(alpha: 0.7)),
      ),
    );
  }

  static BoxDecoration brutalBox(
    BuildContext context, {
    Color? color, 
    double borderWidth = 3, 
    double offset = 4,
    BorderRadius? borderRadius,
  }) {
    final theme = Theme.of(context);
    final border = theme.dividerColor;
    return BoxDecoration(
      color: color ?? theme.cardColor,
      borderRadius: borderRadius ?? BorderRadius.circular(4),
      border: Border.all(color: border, width: borderWidth),
      boxShadow: [
        BoxShadow(
          color: border,
          offset: Offset(offset, offset),
          blurRadius: 0,
        ),
      ],
    );
  }

  static BoxDecoration brutalTab(BuildContext context, {bool active = false}) {
    final theme = Theme.of(context);
    final border = theme.dividerColor;
    return BoxDecoration(
      color: active ? theme.primaryColor : theme.cardColor,
      border: Border(
        right: BorderSide(color: border, width: 2),
        bottom: active ? BorderSide.none : BorderSide(color: border, width: 2),
        top: active ? BorderSide(color: border, width: 4) : BorderSide.none,
      ),
    );
  }
}
