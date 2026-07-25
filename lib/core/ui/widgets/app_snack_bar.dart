// Theme-consistent floating snackbar helpers: showAppSnackBar (from a live
// BuildContext) and showAppSnackBarVia (from a captured
// ScaffoldMessengerState, for callers firing after an await/dialog
// dismissal where the original context may be deactivated). Both take an
// optional actionLabel + onAction pair that renders a themed SnackBarAction
// (used by the undo-on-delete flows). Always use these instead of
// constructing a SnackBar inline.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Theme-consistent floating snackbar. Use this instead of constructing
/// `SnackBar`s inline so every feature gets the same chrome (panel border,
/// radius, display-weight text). Pass BOTH [actionLabel] and [onAction] to
/// render an action button (e.g. UNDO); pressing it fires [onAction] and
/// dismisses the snackbar.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 2),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _showVia(
    ScaffoldMessenger.of(context),
    context,
    message,
    backgroundColor: backgroundColor,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
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
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _showVia(
    messenger,
    messenger.context,
    message,
    backgroundColor: backgroundColor,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

void _showVia(
  ScaffoldMessengerState messenger,
  BuildContext themeContext,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 2),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final theme = Theme.of(themeContext);
  final layout = themeContext.appLayout;
  // FIX I1: ScaffoldMessenger queues by default, so a burst of action
  // snackbars (e.g. rapid deletes) would otherwise stay live serially for
  // their full duration — the spec (and undo-on-delete UX generally) says
  // only the LATEST snackbar is undoable; earlier ones are accepted loss.
  // Remove (not hide) any current snackbar first so the new one replaces it
  // instantly rather than queuing behind an exit animation. Scoped to
  // action-carrying snackbars — plain toasts have no undo state to protect
  // and are left to the default queueing behavior.
  if (actionLabel != null && onAction != null) {
    messenger.removeCurrentSnackBar();
  }
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
      // The action slot is typed SnackBarAction. Colors come from the theme
      // (label color mirrors the content's onPrimary); the label's font
      // rides the theme's button typography, so nothing is hardcoded.
      action: actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: theme.colorScheme.onPrimary,
              onPressed: onAction,
            )
          : null,
      duration: duration,
    ),
  );
}
