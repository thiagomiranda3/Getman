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
  _showVia(
    ScaffoldMessenger.of(context),
    context,
    message,
    backgroundColor: backgroundColor,
    duration: duration,
  );
}

/// Like [showAppSnackBar] but takes a captured [ScaffoldMessengerState], for
/// callers that fire after an `await` / dialog dismissal where the original
/// `BuildContext` may be deactivated. Capture `ScaffoldMessenger.of(context)`
/// before the gap and pass it here.
void showAppSnackBarVia(
  ScaffoldMessengerState messenger,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 2),
}) {
  _showVia(
    messenger,
    messenger.context,
    message,
    backgroundColor: backgroundColor,
    duration: duration,
  );
}

void _showVia(
  ScaffoldMessengerState messenger,
  BuildContext themeContext,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 2),
}) {
  final theme = Theme.of(themeContext);
  final layout = themeContext.appLayout;
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: backgroundColor ?? theme.primaryColor,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(themeContext.appShape.panelRadius),
        side: BorderSide(color: theme.dividerColor, width: layout.borderThick),
      ),
      content: Text(
        message,
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: layout.fontSizeNormal,
          fontWeight: themeContext.appTypography.displayWeight,
        ),
      ),
      duration: duration,
    ),
  );
}
