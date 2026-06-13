import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Theme-consistent floating snackbar. Use this instead of constructing
/// `SnackBar`s inline so every feature gets the same chrome (panel border,
/// radius, display-weight text).
void showAppSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 2),
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: backgroundColor ?? theme.primaryColor,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        side: BorderSide(color: theme.dividerColor, width: layout.borderThick),
      ),
      content: Text(
        message,
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: layout.fontSizeNormal,
          fontWeight: context.appTypography.displayWeight,
        ),
      ),
      duration: duration,
    ),
  );
}
