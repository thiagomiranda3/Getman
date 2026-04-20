import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LayoutExtension extends ThemeExtension<LayoutExtension> {
  final double pagePadding;
  final double sectionSpacing;
  final double verticalDividerWidth;
  final double iconSize;
  final double smallIconSize;
  final double badgePaddingHorizontal;
  final double badgePaddingVertical;
  final double fontSizeTitle;
  final double fontSizeSmall;
  final double fontSizeNormal;
  final double buttonPaddingHorizontal;
  final double buttonPaddingVertical;
  final double inputPadding;
  final double inputPaddingVertical;
  final double cardOffset;
  final double headerPaddingVertical;
  final double headerFontSize;
  final double tabBarHeight;
  final double tabCloseIconSize;
  final double tabPaddingHorizontal;
  final double tabFontSize;
  final int tabTitleMaxLength;
  final double tabSpacing;
  final double addIconSize;
  final double dirtyStarSize;
  final bool isCompact;
  final double depthPaddingMultiplier;
  final double sideMenuWidth;
  final double borderThin;
  final double borderThick;
  final double borderHeavy;
  final double dialogWidth;
  final double splitterGrabSize;
  final double splitterLineSize;

  const LayoutExtension({
    required this.isCompact,
    required this.pagePadding,
    required this.sectionSpacing,
    required this.verticalDividerWidth,
    required this.iconSize,
    required this.smallIconSize,
    required this.badgePaddingHorizontal,
    required this.badgePaddingVertical,
    required this.fontSizeTitle,
    required this.fontSizeSmall,
    required this.fontSizeNormal,
    required this.buttonPaddingHorizontal,
    required this.buttonPaddingVertical,
    required this.inputPadding,
    required this.inputPaddingVertical,
    required this.cardOffset,
    required this.headerPaddingVertical,
    required this.headerFontSize,
    required this.tabBarHeight,
    required this.tabCloseIconSize,
    required this.tabPaddingHorizontal,
    required this.tabFontSize,
    required this.tabTitleMaxLength,
    required this.tabSpacing,
    required this.addIconSize,
    required this.dirtyStarSize,
    required this.depthPaddingMultiplier,
    required this.sideMenuWidth,
    required this.borderThin,
    required this.borderThick,
    required this.borderHeavy,
    required this.dialogWidth,
    required this.splitterGrabSize,
    required this.splitterLineSize,
  });

  @override
  ThemeExtension<LayoutExtension> copyWith({
    bool? isCompact,
    double? pagePadding,
    double? sectionSpacing,
    double? verticalDividerWidth,
    double? iconSize,
    double? smallIconSize,
    double? badgePaddingHorizontal,
    double? badgePaddingVertical,
    double? fontSizeTitle,
    double? fontSizeSmall,
    double? fontSizeNormal,
    double? buttonPaddingHorizontal,
    double? buttonPaddingVertical,
    double? inputPadding,
    double? inputPaddingVertical,
    double? cardOffset,
    double? headerPaddingVertical,
    double? headerFontSize,
    double? tabBarHeight,
    double? tabCloseIconSize,
    double? tabPaddingHorizontal,
    double? tabFontSize,
    int? tabTitleMaxLength,
    double? tabSpacing,
    double? addIconSize,
    double? dirtyStarSize,
    double? depthPaddingMultiplier,
    double? sideMenuWidth,
    double? borderThin,
    double? borderThick,
    double? borderHeavy,
    double? dialogWidth,
    double? splitterGrabSize,
    double? splitterLineSize,
  }) {
    return LayoutExtension(
      isCompact: isCompact ?? this.isCompact,
      pagePadding: pagePadding ?? this.pagePadding,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      verticalDividerWidth: verticalDividerWidth ?? this.verticalDividerWidth,
      iconSize: iconSize ?? this.iconSize,
      smallIconSize: smallIconSize ?? this.smallIconSize,
      badgePaddingHorizontal: badgePaddingHorizontal ?? this.badgePaddingHorizontal,
      badgePaddingVertical: badgePaddingVertical ?? this.badgePaddingVertical,
      fontSizeTitle: fontSizeTitle ?? this.fontSizeTitle,
      fontSizeSmall: fontSizeSmall ?? this.fontSizeSmall,
      fontSizeNormal: fontSizeNormal ?? this.fontSizeNormal,
      buttonPaddingHorizontal: buttonPaddingHorizontal ?? this.buttonPaddingHorizontal,
      buttonPaddingVertical: buttonPaddingVertical ?? this.buttonPaddingVertical,
      inputPadding: inputPadding ?? this.inputPadding,
      inputPaddingVertical: inputPaddingVertical ?? this.inputPaddingVertical,
      cardOffset: cardOffset ?? this.cardOffset,
      headerPaddingVertical: headerPaddingVertical ?? this.headerPaddingVertical,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      tabBarHeight: tabBarHeight ?? this.tabBarHeight,
      tabCloseIconSize: tabCloseIconSize ?? this.tabCloseIconSize,
      tabPaddingHorizontal: tabPaddingHorizontal ?? this.tabPaddingHorizontal,
      tabFontSize: tabFontSize ?? this.tabFontSize,
      tabTitleMaxLength: tabTitleMaxLength ?? this.tabTitleMaxLength,
      tabSpacing: tabSpacing ?? this.tabSpacing,
      addIconSize: addIconSize ?? this.addIconSize,
      dirtyStarSize: dirtyStarSize ?? this.dirtyStarSize,
      depthPaddingMultiplier: depthPaddingMultiplier ?? this.depthPaddingMultiplier,
      sideMenuWidth: sideMenuWidth ?? this.sideMenuWidth,
      borderThin: borderThin ?? this.borderThin,
      borderThick: borderThick ?? this.borderThick,
      borderHeavy: borderHeavy ?? this.borderHeavy,
      dialogWidth: dialogWidth ?? this.dialogWidth,
      splitterGrabSize: splitterGrabSize ?? this.splitterGrabSize,
      splitterLineSize: splitterLineSize ?? this.splitterLineSize,
    );
  }

  @override
  ThemeExtension<LayoutExtension> lerp(ThemeExtension<LayoutExtension>? other, double t) {
    if (other is! LayoutExtension) return this;
    return LayoutExtension(
      isCompact: other.isCompact,
      pagePadding: (other.pagePadding - pagePadding) * t + pagePadding,
      sectionSpacing: (other.sectionSpacing - sectionSpacing) * t + sectionSpacing,
      verticalDividerWidth: (other.verticalDividerWidth - verticalDividerWidth) * t + verticalDividerWidth,
      iconSize: (other.iconSize - iconSize) * t + iconSize,
      smallIconSize: (other.smallIconSize - smallIconSize) * t + smallIconSize,
      badgePaddingHorizontal: (other.badgePaddingHorizontal - badgePaddingHorizontal) * t + badgePaddingHorizontal,
      badgePaddingVertical: (other.badgePaddingVertical - badgePaddingVertical) * t + badgePaddingVertical,
      fontSizeTitle: (other.fontSizeTitle - fontSizeTitle) * t + fontSizeTitle,
      fontSizeSmall: (other.fontSizeSmall - fontSizeSmall) * t + fontSizeSmall,
      fontSizeNormal: (other.fontSizeNormal - fontSizeNormal) * t + fontSizeNormal,
      buttonPaddingHorizontal: (other.buttonPaddingHorizontal - buttonPaddingHorizontal) * t + buttonPaddingHorizontal,
      buttonPaddingVertical: (other.buttonPaddingVertical - buttonPaddingVertical) * t + buttonPaddingVertical,
      inputPadding: (other.inputPadding - inputPadding) * t + inputPadding,
      inputPaddingVertical: (other.inputPaddingVertical - inputPaddingVertical) * t + inputPaddingVertical,
      cardOffset: (other.cardOffset - cardOffset) * t + cardOffset,
      headerPaddingVertical: (other.headerPaddingVertical - headerPaddingVertical) * t + headerPaddingVertical,
      headerFontSize: (other.headerFontSize - headerFontSize) * t + headerFontSize,
      tabBarHeight: (other.tabBarHeight - tabBarHeight) * t + tabBarHeight,
      tabCloseIconSize: (other.tabCloseIconSize - tabCloseIconSize) * t + tabCloseIconSize,
      tabPaddingHorizontal: (other.tabPaddingHorizontal - tabPaddingHorizontal) * t + tabPaddingHorizontal,
      tabFontSize: (other.tabFontSize - tabFontSize) * t + tabFontSize,
      tabTitleMaxLength: other.tabTitleMaxLength,
      tabSpacing: (other.tabSpacing - tabSpacing) * t + tabSpacing,
      addIconSize: (other.addIconSize - addIconSize) * t + addIconSize,
      dirtyStarSize: (other.dirtyStarSize - dirtyStarSize) * t + dirtyStarSize,
      depthPaddingMultiplier: (other.depthPaddingMultiplier - depthPaddingMultiplier) * t + depthPaddingMultiplier,
      sideMenuWidth: (other.sideMenuWidth - sideMenuWidth) * t + sideMenuWidth,
      borderThin: (other.borderThin - borderThin) * t + borderThin,
      borderThick: (other.borderThick - borderThick) * t + borderThick,
      borderHeavy: (other.borderHeavy - borderHeavy) * t + borderHeavy,
      dialogWidth: (other.dialogWidth - dialogWidth) * t + dialogWidth,
      splitterGrabSize: (other.splitterGrabSize - splitterGrabSize) * t + splitterGrabSize,
      splitterLineSize: (other.splitterLineSize - splitterLineSize) * t + splitterLineSize,
    );
  }

  static const normal = LayoutExtension(
    isCompact: false,
    pagePadding: 24.0,
    sectionSpacing: 24.0,
    verticalDividerWidth: 48.0,
    iconSize: 24.0,
    smallIconSize: 16.0,
    badgePaddingHorizontal: 10.0,
    badgePaddingVertical: 2.0,
    fontSizeTitle: 14.0,
    fontSizeSmall: 10.0,
    fontSizeNormal: 12.0,
    buttonPaddingHorizontal: 24.0,
    buttonPaddingVertical: 16.0,
    inputPadding: 16.0,
    inputPaddingVertical: 8.0,
    cardOffset: 6.0,
    headerPaddingVertical: 20.0,
    headerFontSize: 24.0,
    tabBarHeight: 60.0,
    tabCloseIconSize: 16.0,
    tabPaddingHorizontal: 16.0,
    tabFontSize: 11.0,
    tabTitleMaxLength: 25,
    tabSpacing: 8.0,
    addIconSize: 24.0,
    dirtyStarSize: 16.0,
    depthPaddingMultiplier: 20.0,
    sideMenuWidth: 300.0,
    borderThin: 2.0,
    borderThick: 3.0,
    borderHeavy: 4.0,
    dialogWidth: 400.0,
    splitterGrabSize: 40.0,
    splitterLineSize: 3.0,
  );

  static const compact = LayoutExtension(
    isCompact: true,
    pagePadding: 12.0,
    sectionSpacing: 12.0,
    verticalDividerWidth: 24.0,
    iconSize: 18.0,
    smallIconSize: 14.0,
    badgePaddingHorizontal: 6.0,
    badgePaddingVertical: 1.0,
    fontSizeTitle: 12.0,
    fontSizeSmall: 9.0,
    fontSizeNormal: 11.0,
    buttonPaddingHorizontal: 16.0,
    buttonPaddingVertical: 12.0,
    inputPadding: 10.0,
    inputPaddingVertical: 6.0,
    cardOffset: 3.0,
    headerPaddingVertical: 12.0,
    headerFontSize: 18.0,
    tabBarHeight: 40.0,
    tabCloseIconSize: 12.0,
    tabPaddingHorizontal: 8.0,
    tabFontSize: 9.0,
    tabTitleMaxLength: 15,
    tabSpacing: 4.0,
    addIconSize: 18.0,
    dirtyStarSize: 12.0,
    depthPaddingMultiplier: 12.0,
    sideMenuWidth: 240.0,
    borderThin: 2.0,
    borderThick: 3.0,
    borderHeavy: 4.0,
    dialogWidth: 320.0,
    splitterGrabSize: 28.0,
    splitterLineSize: 2.0,
  );
}

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
    final LayoutExtension layout = isCompact ? LayoutExtension.compact : LayoutExtension.normal;

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
    final layout = theme.extension<LayoutExtension>()!;
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
    final layout = theme.extension<LayoutExtension>()!;
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


