import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

class NeoBrutalistTheme {
  // Neo-Brutalist Colors
  static const Color backgroundLight = Color(0xFFF3F4F6); // Refined Off-White
  static const Color surfaceLight = Color(0xFFFFFFFF); // White
  static const Color textLight = Color(0xFF000000); // Black
  static const Color borderLight = Color(0xFF000000); // Black

  static const Color backgroundDark = Color(0xFF1A1A1A); // Softer Black
  static const Color surfaceDark = Color(0xFF242424); // Dark Gray
  static const Color textDark = Color(0xFFE0E0E0); // Off-White
  static const Color borderDark = Color(0xFF404040); // Muted Border

  static const Color primary = Color(0xFFFFD700); // Refined Golden Yellow
  static const Color primaryDark = Color(0xFFFFD700); // Keep it vibrant for Dark mode pop
  
  static const Color secondary = Color(0xFF6D28D9); // Refined Deep Violet
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

  static ThemeData theme(Brightness brightness, {bool isCompact = false}) => _createTheme(brightness, isCompact: isCompact);

  static ThemeData _createTheme(Brightness brightness, {bool isCompact = false}) {
    final bool isDark = brightness == Brightness.dark;
    final Color background = isDark ? backgroundDark : backgroundLight;
    final Color surface = isDark ? surfaceDark : surfaceLight;
    final Color text = isDark ? textDark : textLight;
    final Color border = isDark ? borderDark : borderLight;
    final Color currentPrimary = isDark ? primaryDark : primary;
    final Color currentSecondary = isDark ? secondaryDark : secondary;
    final AppLayout layout = isCompact ? AppLayout.compact : AppLayout.normal;

    final baseTextTheme = GoogleFonts.lexendTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [layout],
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
            onPrimary: textLight, // Black text on Yellow
            onSecondary: Colors.white,
            onSurface: textDark,
          )
        : ColorScheme.light(
            primary: currentPrimary,
            secondary: currentSecondary,
            surface: surfaceLight,
            onPrimary: textLight, // Black text on Yellow
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
        shape: Border(bottom: BorderSide(color: border, width: layout.borderThick)),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: textLight, // Black on Yellow active indicator
        unselectedLabelColor: text, // White/Gray on Dark background
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
          foregroundColor: textLight, // Black text on Yellow
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: border, width: layout.borderThick),
          ),
          padding: EdgeInsets.symmetric(horizontal: layout.buttonPaddingHorizontal, vertical: layout.buttonPaddingVertical),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textLight),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: EdgeInsets.symmetric(horizontal: layout.buttonPaddingHorizontal, vertical: layout.buttonPaddingVertical),
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
          borderSide: BorderSide(color: border, width: layout.borderThick),
          borderRadius: BorderRadius.circular(4),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: border, width: layout.borderThick),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: currentSecondary, width: layout.borderThick),
          borderRadius: BorderRadius.circular(4),
        ),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.bold),
        hintStyle: TextStyle(color: text.withValues(alpha: 0.5)),
        contentPadding: EdgeInsets.symmetric(horizontal: layout.inputPadding, vertical: layout.inputPadding),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: border, width: layout.borderThick),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border, width: layout.borderHeavy),
        ),
        titleTextStyle: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900),
        contentTextStyle: TextStyle(color: text, fontSize: 14),
      ),
      listTileTheme: ListTileThemeData(
        selectedTileColor: currentPrimary,
        selectedColor: textLight, // Black text on Yellow selected tile
        titleTextStyle: TextStyle(fontWeight: FontWeight.bold, color: text),
        subtitleTextStyle: TextStyle(color: text.withValues(alpha: 0.7)),
      ),
    );
  }

  static BoxDecoration brutalBox(
    BuildContext context, {
    Color? color,
    double? borderWidth,
    double? offset,
    BorderRadius? borderRadius,
  }) {
    final theme = Theme.of(context);
    final layout = theme.extension<AppLayout>()!;
    final border = theme.dividerColor;
    return BoxDecoration(
      color: color ?? theme.cardColor,
      borderRadius: borderRadius ?? BorderRadius.circular(4),
      border: Border.all(color: border, width: borderWidth ?? layout.borderThick),
      boxShadow: [
        BoxShadow(
          color: border,
          offset: Offset(offset ?? layout.borderHeavy, offset ?? layout.borderHeavy),
          blurRadius: 0,
        ),
      ],
    );
  }

  static BoxDecoration brutalTab(BuildContext context, {bool active = false}) {
    final theme = Theme.of(context);
    final layout = theme.extension<AppLayout>()!;
    final border = theme.dividerColor;
    return BoxDecoration(
      color: active ? theme.primaryColor : theme.cardColor,
      border: Border(
        right: BorderSide(color: border, width: layout.borderThin),
        bottom: active ? BorderSide.none : BorderSide(color: border, width: layout.borderThin),
        top: active ? BorderSide(color: border, width: layout.borderHeavy) : BorderSide.none,
      ),
    );
  }
}

class BrutalBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  const BrutalBounce({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.95,
  });

  @override
  State<BrutalBounce> createState() => _BrutalBounceState();
}

class _BrutalBounceState extends State<BrutalBounce> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}


