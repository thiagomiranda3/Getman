// `BuildContext` accessors for all 8 theme extensions (appLayout, appPalette,
// appShape, appTypography, appDecoration, appCopy, appMotion, appComponents).
// Widgets read sizing/colors/shapes/weights/decorations/components through
// these instead of hardcoding — see docs/architecture/theming.md.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_copy.dart';
import 'package:getman/core/theme/extensions/app_decoration.dart';
import 'package:getman/core/theme/extensions/app_layout.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/extensions/app_palette.dart';
import 'package:getman/core/theme/extensions/app_shape.dart';
import 'package:getman/core/theme/extensions/app_typography.dart';

extension AppThemeAccess on BuildContext {
  AppLayout get appLayout => Theme.of(this).extension<AppLayout>()!;
  AppPalette get appPalette => Theme.of(this).extension<AppPalette>()!;
  AppShape get appShape => Theme.of(this).extension<AppShape>()!;
  AppTypography get appTypography => Theme.of(this).extension<AppTypography>()!;
  AppDecoration get appDecoration => Theme.of(this).extension<AppDecoration>()!;
  AppCopy get appCopy => Theme.of(this).extension<AppCopy>()!;
  AppMotion get appMotion => Theme.of(this).extension<AppMotion>()!;
  AppComponents get appComponents => Theme.of(this).extension<AppComponents>()!;
}
