import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NeoBrutalistTheme {
  // Neo-Brutalist Colors
  static const Color background = Color(0xFFF8F7F2); // Off-White
  static const Color surface = Color(0xFFFFFFFF); // White
  static const Color editorBackground = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFFFDE047); // Vibrant Yellow
  static const Color secondary = Color(0xFF7C3AED); // Violet
  static const Color accent = Color(0xFF000000); // Black
  static const Color border = Color(0xFF000000); // Black
  static const Color text = Color(0xFF000000); // Black
  static const Color shadow = Color(0xFF000000); // Black
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

  static ThemeData get theme {
    final baseTextTheme = GoogleFonts.lexendTextTheme();
    
    return ThemeData(
      useMaterial3: true, 
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      dividerColor: border,
      hoverColor: primary.withValues(alpha: 0.1),
      splashColor: primary.withValues(alpha: 0.2),
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
        onPrimary: text,
        onSecondary: Colors.white,
        onSurface: text,
      ),
      textTheme: baseTextTheme.apply(
        bodyColor: text,
        displayColor: text,
      ).copyWith(
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
        bodySmall: baseTextTheme.bodySmall?.copyWith(fontSize: 12),
        titleMedium: baseTextTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5),
      ),
      appBarTheme: const AppBarTheme(
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
        indicator: const BoxDecoration(
          color: primary,
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
          backgroundColor: primary,
          foregroundColor: text,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: border, width: 3),
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
          side: const BorderSide(color: border, width: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: secondary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: border, width: 3),
          borderRadius: BorderRadius.circular(4),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: border, width: 3),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: secondary, width: 3),
          borderRadius: BorderRadius.circular(4),
        ),
        labelStyle: const TextStyle(color: text, fontWeight: FontWeight.bold),
        hintStyle: TextStyle(color: text.withValues(alpha: 0.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: border, width: 3),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border, width: 4),
        ),
        titleTextStyle: const TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900),
        contentTextStyle: const TextStyle(color: text, fontSize: 14),
      ),
      listTileTheme: ListTileThemeData(
        selectedTileColor: primary,
        selectedColor: text,
        titleTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: text),
        subtitleTextStyle: TextStyle(color: text.withValues(alpha: 0.7)),
      ),
    );
  }

  static BoxDecoration brutalBox({
    Color color = surface, 
    double borderWidth = 3, 
    double offset = 4,
    BorderRadius? borderRadius,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: borderRadius ?? BorderRadius.circular(4),
      border: Border.all(color: border, width: borderWidth),
      boxShadow: [
        BoxShadow(
          color: shadow,
          offset: Offset(offset, offset),
          blurRadius: 0,
        ),
      ],
    );
  }

  static BoxDecoration brutalTab({bool active = false}) {
    return BoxDecoration(
      color: active ? primary : surface,
      border: Border(
        right: const BorderSide(color: border, width: 2),
        bottom: active ? BorderSide.none : const BorderSide(color: border, width: 2),
        top: active ? const BorderSide(color: border, width: 4) : BorderSide.none,
      ),
    );
  }
}
