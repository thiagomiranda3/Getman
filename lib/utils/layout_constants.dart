class LayoutConstants {
  final bool isCompact;

  LayoutConstants(this.isCompact);

  double get pagePadding => isCompact ? 12.0 : 24.0;
  double get sectionSpacing => isCompact ? 12.0 : 24.0;
  double get verticalDividerWidth => isCompact ? 24.0 : 48.0;
  double get iconSize => isCompact ? 18.0 : 24.0;
  double get smallIconSize => isCompact ? 14.0 : 16.0;
  double get badgePaddingHorizontal => isCompact ? 6.0 : 10.0;
  double get badgePaddingVertical => isCompact ? 1.0 : 2.0;
  double get fontSizeTitle => isCompact ? 12.0 : 14.0;
  double get fontSizeSmall => isCompact ? 9.0 : 10.0;
  double get fontSizeNormal => isCompact ? 11.0 : 12.0;
  double get buttonPaddingHorizontal => isCompact ? 16.0 : 24.0;
  double get buttonPaddingVertical => isCompact ? 12.0 : 16.0;
  double get inputPadding => isCompact ? 10.0 : 16.0;
  double get cardOffset => isCompact ? 3.0 : 6.0;
  double get sideMenuWidth => isCompact ? 240.0 : 300.0;
}
