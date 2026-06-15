import 'package:flutter/material.dart';

class AppLayout extends ThemeExtension<AppLayout> {
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
    required this.treeRowExtent,
    required this.sideMenuWidth,
    required this.borderThin,
    required this.borderThick,
    required this.borderHeavy,
    required this.dialogWidth,
    required this.splitterGrabSize,
    required this.splitterLineSize,
  });
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
  final double treeRowExtent;
  final double sideMenuWidth;
  final double borderThin;
  final double borderThick;
  final double borderHeavy;
  final double dialogWidth;
  final double splitterGrabSize;
  final double splitterLineSize;

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
    double? treeRowExtent,
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
      badgePaddingHorizontal:
          badgePaddingHorizontal ?? this.badgePaddingHorizontal,
      badgePaddingVertical: badgePaddingVertical ?? this.badgePaddingVertical,
      fontSizeTitle: fontSizeTitle ?? this.fontSizeTitle,
      fontSizeSmall: fontSizeSmall ?? this.fontSizeSmall,
      fontSizeNormal: fontSizeNormal ?? this.fontSizeNormal,
      fontSizeCode: fontSizeCode ?? this.fontSizeCode,
      fontSizeSubtitle: fontSizeSubtitle ?? this.fontSizeSubtitle,
      buttonPaddingHorizontal:
          buttonPaddingHorizontal ?? this.buttonPaddingHorizontal,
      buttonPaddingVertical:
          buttonPaddingVertical ?? this.buttonPaddingVertical,
      inputPadding: inputPadding ?? this.inputPadding,
      inputPaddingVertical: inputPaddingVertical ?? this.inputPaddingVertical,
      cardOffset: cardOffset ?? this.cardOffset,
      headerPaddingVertical:
          headerPaddingVertical ?? this.headerPaddingVertical,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      tabBarHeight: tabBarHeight ?? this.tabBarHeight,
      tabCloseIconSize: tabCloseIconSize ?? this.tabCloseIconSize,
      tabPaddingHorizontal: tabPaddingHorizontal ?? this.tabPaddingHorizontal,
      tabFontSize: tabFontSize ?? this.tabFontSize,
      tabTitleMaxLength: tabTitleMaxLength ?? this.tabTitleMaxLength,
      tabSpacing: tabSpacing ?? this.tabSpacing,
      addIconSize: addIconSize ?? this.addIconSize,
      dirtyStarSize: dirtyStarSize ?? this.dirtyStarSize,
      depthPaddingMultiplier:
          depthPaddingMultiplier ?? this.depthPaddingMultiplier,
      treeRowExtent: treeRowExtent ?? this.treeRowExtent,
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
      badgePaddingHorizontal: l(
        badgePaddingHorizontal,
        other.badgePaddingHorizontal,
      ),
      badgePaddingVertical: l(badgePaddingVertical, other.badgePaddingVertical),
      fontSizeTitle: l(fontSizeTitle, other.fontSizeTitle),
      fontSizeSmall: l(fontSizeSmall, other.fontSizeSmall),
      fontSizeNormal: l(fontSizeNormal, other.fontSizeNormal),
      fontSizeCode: l(fontSizeCode, other.fontSizeCode),
      fontSizeSubtitle: l(fontSizeSubtitle, other.fontSizeSubtitle),
      buttonPaddingHorizontal: l(
        buttonPaddingHorizontal,
        other.buttonPaddingHorizontal,
      ),
      buttonPaddingVertical: l(
        buttonPaddingVertical,
        other.buttonPaddingVertical,
      ),
      inputPadding: l(inputPadding, other.inputPadding),
      inputPaddingVertical: l(inputPaddingVertical, other.inputPaddingVertical),
      cardOffset: l(cardOffset, other.cardOffset),
      headerPaddingVertical: l(
        headerPaddingVertical,
        other.headerPaddingVertical,
      ),
      headerFontSize: l(headerFontSize, other.headerFontSize),
      tabBarHeight: l(tabBarHeight, other.tabBarHeight),
      tabCloseIconSize: l(tabCloseIconSize, other.tabCloseIconSize),
      tabPaddingHorizontal: l(tabPaddingHorizontal, other.tabPaddingHorizontal),
      tabFontSize: l(tabFontSize, other.tabFontSize),
      tabTitleMaxLength: other.tabTitleMaxLength,
      tabSpacing: l(tabSpacing, other.tabSpacing),
      addIconSize: l(addIconSize, other.addIconSize),
      dirtyStarSize: l(dirtyStarSize, other.dirtyStarSize),
      depthPaddingMultiplier: l(
        depthPaddingMultiplier,
        other.depthPaddingMultiplier,
      ),
      treeRowExtent: l(treeRowExtent, other.treeRowExtent),
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
    pagePadding: 24,
    sectionSpacing: 24,
    verticalDividerWidth: 48,
    iconSize: 24,
    smallIconSize: 16,
    badgePaddingHorizontal: 10,
    badgePaddingVertical: 2,
    fontSizeTitle: 14,
    fontSizeSmall: 10,
    fontSizeNormal: 12,
    fontSizeCode: 13,
    fontSizeSubtitle: 18,
    buttonPaddingHorizontal: 24,
    buttonPaddingVertical: 16,
    inputPadding: 16,
    inputPaddingVertical: 8,
    cardOffset: 6,
    headerPaddingVertical: 20,
    headerFontSize: 24,
    tabBarHeight: 60,
    tabCloseIconSize: 16,
    tabPaddingHorizontal: 16,
    tabFontSize: 11,
    tabTitleMaxLength: 25,
    tabSpacing: 8,
    addIconSize: 24,
    dirtyStarSize: 16,
    depthPaddingMultiplier: 20,
    treeRowExtent: 40,
    sideMenuWidth: 300,
    borderThin: 2,
    borderThick: 3,
    borderHeavy: 4,
    dialogWidth: 400,
    splitterGrabSize: 40,
    splitterLineSize: 3,
  );

  static const compact = AppLayout(
    isCompact: true,
    pagePadding: 12,
    sectionSpacing: 12,
    verticalDividerWidth: 24,
    iconSize: 18,
    smallIconSize: 14,
    badgePaddingHorizontal: 6,
    badgePaddingVertical: 1,
    fontSizeTitle: 12,
    fontSizeSmall: 9,
    fontSizeNormal: 11,
    fontSizeCode: 12,
    fontSizeSubtitle: 14,
    buttonPaddingHorizontal: 16,
    buttonPaddingVertical: 12,
    inputPadding: 10,
    inputPaddingVertical: 6,
    cardOffset: 3,
    headerPaddingVertical: 12,
    headerFontSize: 18,
    tabBarHeight: 40,
    tabCloseIconSize: 12,
    tabPaddingHorizontal: 8,
    tabFontSize: 9,
    tabTitleMaxLength: 15,
    tabSpacing: 4,
    addIconSize: 18,
    dirtyStarSize: 12,
    depthPaddingMultiplier: 12,
    treeRowExtent: 32,
    sideMenuWidth: 240,
    borderThin: 2,
    borderThick: 3,
    borderHeavy: 4,
    dialogWidth: 320,
    splitterGrabSize: 28,
    splitterLineSize: 2,
  );
}
