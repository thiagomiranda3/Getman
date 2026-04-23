import 'package:flutter/widgets.dart';

/// Progressive layout modes derived from viewport width.
///
/// These are orthogonal to [AppLayout]'s density (driven by the user's
/// `isCompactMode` setting). `LayoutMode` drives navigation and panel-layout
/// branches; [AppLayout] drives paddings and font sizes.
enum LayoutMode {
  compactPhone,
  phone,
  tablet,
  desktop,
}

/// Width thresholds (inclusive upper bounds). The largest tier has no upper bound.
const double kCompactPhoneMax = 500;
const double kPhoneMax = 700;
const double kTabletMax = 900;

LayoutMode layoutModeForWidth(double width) {
  if (width <= kCompactPhoneMax) return LayoutMode.compactPhone;
  if (width <= kPhoneMax) return LayoutMode.phone;
  if (width <= kTabletMax) return LayoutMode.tablet;
  return LayoutMode.desktop;
}

extension ResponsiveBuildContext on BuildContext {
  /// Resolved [LayoutMode] for the current viewport width.
  LayoutMode get layoutMode => layoutModeForWidth(MediaQuery.sizeOf(this).width);

  /// True for compact-phone or phone tiers (viewport ≤ 700 px).
  bool get isPhone => layoutMode.index <= LayoutMode.phone.index;

  /// True when the side menu should render as a [Drawer] (viewport ≤ 900 px).
  bool get useDrawerNav => layoutMode.index <= LayoutMode.tablet.index;

  /// True when request/response should collapse to a single 4-tab strip
  /// (viewport ≤ 700 px).
  bool get useUnifiedRequestTabs => layoutMode.index <= LayoutMode.phone.index;

  /// True when the request tab bar should collapse to a chip + switcher sheet
  /// (viewport ≤ 500 px).
  bool get useTabSwitcher => layoutMode == LayoutMode.compactPhone;

  /// Minimum recommended touch-target size for the current layout mode.
  /// 44 on phone/compact-phone (iOS/Android HIG), 28 otherwise.
  double get touchTargetMin => isPhone ? 44.0 : 28.0;

  /// True when dialogs should render as full-screen pages rather than
  /// centered modals (viewport ≤ 700 px).
  bool get isDialogFullscreen => isPhone;
}
