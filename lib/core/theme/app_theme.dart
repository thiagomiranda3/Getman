import 'package:flutter/material.dart';

class AppLayout extends ThemeExtension<AppLayout> {
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
  final double fontSizeCode;
  final double fontSizeSubtitle;
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

  const AppLayout({
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
    required this.fontSizeCode,
    required this.fontSizeSubtitle,
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
  AppLayout copyWith({
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
    double? fontSizeCode,
    double? fontSizeSubtitle,
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
    return AppLayout(
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
      fontSizeCode: fontSizeCode ?? this.fontSizeCode,
      fontSizeSubtitle: fontSizeSubtitle ?? this.fontSizeSubtitle,
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
  AppLayout lerp(ThemeExtension<AppLayout>? other, double t) {
    if (other is! AppLayout) return this;
    double l(double a, double b) => (b - a) * t + a;
    return AppLayout(
      isCompact: other.isCompact,
      pagePadding: l(pagePadding, other.pagePadding),
      sectionSpacing: l(sectionSpacing, other.sectionSpacing),
      verticalDividerWidth: l(verticalDividerWidth, other.verticalDividerWidth),
      iconSize: l(iconSize, other.iconSize),
      smallIconSize: l(smallIconSize, other.smallIconSize),
      badgePaddingHorizontal: l(badgePaddingHorizontal, other.badgePaddingHorizontal),
      badgePaddingVertical: l(badgePaddingVertical, other.badgePaddingVertical),
      fontSizeTitle: l(fontSizeTitle, other.fontSizeTitle),
      fontSizeSmall: l(fontSizeSmall, other.fontSizeSmall),
      fontSizeNormal: l(fontSizeNormal, other.fontSizeNormal),
      fontSizeCode: l(fontSizeCode, other.fontSizeCode),
      fontSizeSubtitle: l(fontSizeSubtitle, other.fontSizeSubtitle),
      buttonPaddingHorizontal: l(buttonPaddingHorizontal, other.buttonPaddingHorizontal),
      buttonPaddingVertical: l(buttonPaddingVertical, other.buttonPaddingVertical),
      inputPadding: l(inputPadding, other.inputPadding),
      inputPaddingVertical: l(inputPaddingVertical, other.inputPaddingVertical),
      cardOffset: l(cardOffset, other.cardOffset),
      headerPaddingVertical: l(headerPaddingVertical, other.headerPaddingVertical),
      headerFontSize: l(headerFontSize, other.headerFontSize),
      tabBarHeight: l(tabBarHeight, other.tabBarHeight),
      tabCloseIconSize: l(tabCloseIconSize, other.tabCloseIconSize),
      tabPaddingHorizontal: l(tabPaddingHorizontal, other.tabPaddingHorizontal),
      tabFontSize: l(tabFontSize, other.tabFontSize),
      tabTitleMaxLength: other.tabTitleMaxLength,
      tabSpacing: l(tabSpacing, other.tabSpacing),
      addIconSize: l(addIconSize, other.addIconSize),
      dirtyStarSize: l(dirtyStarSize, other.dirtyStarSize),
      depthPaddingMultiplier: l(depthPaddingMultiplier, other.depthPaddingMultiplier),
      sideMenuWidth: l(sideMenuWidth, other.sideMenuWidth),
      borderThin: l(borderThin, other.borderThin),
      borderThick: l(borderThick, other.borderThick),
      borderHeavy: l(borderHeavy, other.borderHeavy),
      dialogWidth: l(dialogWidth, other.dialogWidth),
      splitterGrabSize: l(splitterGrabSize, other.splitterGrabSize),
      splitterLineSize: l(splitterLineSize, other.splitterLineSize),
    );
  }

  static const normal = AppLayout(
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
    fontSizeCode: 13.0,
    fontSizeSubtitle: 18.0,
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

  static const compact = AppLayout(
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
    fontSizeCode: 12.0,
    fontSizeSubtitle: 14.0,
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

class AppPalette extends ThemeExtension<AppPalette> {
  final Map<String, Color> methodColors;
  final Color methodFallback;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusError;
  final Color statusAccentSuccess;
  final Color statusAccentWarning;
  final Color statusAccentError;
  final Color codeBackground;
  final Color mutedHover;

  const AppPalette({
    required this.methodColors,
    required this.methodFallback,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
    required this.statusAccentSuccess,
    required this.statusAccentWarning,
    required this.statusAccentError,
    required this.codeBackground,
    required this.mutedHover,
  });

  Color methodColor(String method) =>
      methodColors[method.toUpperCase()] ?? methodFallback;

  Color statusColor(int code) {
    if (code >= 200 && code < 300) return statusSuccess;
    if (code >= 400) return statusError;
    return statusWarning;
  }

  Color statusAccent(int code) {
    if (code >= 200 && code < 300) return statusAccentSuccess;
    if (code >= 400) return statusAccentError;
    return statusAccentWarning;
  }

  @override
  AppPalette copyWith({
    Map<String, Color>? methodColors,
    Color? methodFallback,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusError,
    Color? statusAccentSuccess,
    Color? statusAccentWarning,
    Color? statusAccentError,
    Color? codeBackground,
    Color? mutedHover,
  }) {
    return AppPalette(
      methodColors: methodColors ?? this.methodColors,
      methodFallback: methodFallback ?? this.methodFallback,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      statusError: statusError ?? this.statusError,
      statusAccentSuccess: statusAccentSuccess ?? this.statusAccentSuccess,
      statusAccentWarning: statusAccentWarning ?? this.statusAccentWarning,
      statusAccentError: statusAccentError ?? this.statusAccentError,
      codeBackground: codeBackground ?? this.codeBackground,
      mutedHover: mutedHover ?? this.mutedHover,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      methodColors: other.methodColors,
      methodFallback: Color.lerp(methodFallback, other.methodFallback, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      statusAccentSuccess: Color.lerp(statusAccentSuccess, other.statusAccentSuccess, t)!,
      statusAccentWarning: Color.lerp(statusAccentWarning, other.statusAccentWarning, t)!,
      statusAccentError: Color.lerp(statusAccentError, other.statusAccentError, t)!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      mutedHover: Color.lerp(mutedHover, other.mutedHover, t)!,
    );
  }
}

class AppShape extends ThemeExtension<AppShape> {
  final double panelRadius;
  final double buttonRadius;
  final double inputRadius;
  final double dialogRadius;

  const AppShape({
    required this.panelRadius,
    required this.buttonRadius,
    required this.inputRadius,
    required this.dialogRadius,
  });

  @override
  AppShape copyWith({
    double? panelRadius,
    double? buttonRadius,
    double? inputRadius,
    double? dialogRadius,
  }) {
    return AppShape(
      panelRadius: panelRadius ?? this.panelRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      inputRadius: inputRadius ?? this.inputRadius,
      dialogRadius: dialogRadius ?? this.dialogRadius,
    );
  }

  @override
  AppShape lerp(ThemeExtension<AppShape>? other, double t) {
    if (other is! AppShape) return this;
    double l(double a, double b) => (b - a) * t + a;
    return AppShape(
      panelRadius: l(panelRadius, other.panelRadius),
      buttonRadius: l(buttonRadius, other.buttonRadius),
      inputRadius: l(inputRadius, other.inputRadius),
      dialogRadius: l(dialogRadius, other.dialogRadius),
    );
  }
}

class AppTypography extends ThemeExtension<AppTypography> {
  final TextTheme base;
  final String codeFontFamily;
  final FontWeight displayWeight;
  final FontWeight titleWeight;
  final FontWeight bodyWeight;

  const AppTypography({
    required this.base,
    required this.codeFontFamily,
    required this.displayWeight,
    required this.titleWeight,
    required this.bodyWeight,
  });

  @override
  AppTypography copyWith({
    TextTheme? base,
    String? codeFontFamily,
    FontWeight? displayWeight,
    FontWeight? titleWeight,
    FontWeight? bodyWeight,
  }) {
    return AppTypography(
      base: base ?? this.base,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
      displayWeight: displayWeight ?? this.displayWeight,
      titleWeight: titleWeight ?? this.titleWeight,
      bodyWeight: bodyWeight ?? this.bodyWeight,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      base: TextTheme.lerp(base, other.base, t),
      codeFontFamily: other.codeFontFamily,
      displayWeight: other.displayWeight,
      titleWeight: other.titleWeight,
      bodyWeight: other.bodyWeight,
    );
  }
}

typedef PanelBoxBuilder = BoxDecoration Function(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
});

typedef TabShapeBuilder = BoxDecoration Function(
  BuildContext context, {
  required bool active,
});

typedef InteractiveWrapper = Widget Function({
  required Widget child,
  VoidCallback? onTap,
  double? scaleDown,
});

class AppDecoration extends ThemeExtension<AppDecoration> {
  final PanelBoxBuilder panelBox;
  final TabShapeBuilder tabShape;
  final InteractiveWrapper wrapInteractive;

  const AppDecoration({
    required this.panelBox,
    required this.tabShape,
    required this.wrapInteractive,
  });

  @override
  AppDecoration copyWith({
    PanelBoxBuilder? panelBox,
    TabShapeBuilder? tabShape,
    InteractiveWrapper? wrapInteractive,
  }) {
    return AppDecoration(
      panelBox: panelBox ?? this.panelBox,
      tabShape: tabShape ?? this.tabShape,
      wrapInteractive: wrapInteractive ?? this.wrapInteractive,
    );
  }

  @override
  AppDecoration lerp(ThemeExtension<AppDecoration>? other, double t) => this;
}

extension AppThemeAccess on BuildContext {
  AppLayout get appLayout => Theme.of(this).extension<AppLayout>()!;
  AppPalette get appPalette => Theme.of(this).extension<AppPalette>()!;
  AppShape get appShape => Theme.of(this).extension<AppShape>()!;
  AppTypography get appTypography => Theme.of(this).extension<AppTypography>()!;
  AppDecoration get appDecoration => Theme.of(this).extension<AppDecoration>()!;
}
