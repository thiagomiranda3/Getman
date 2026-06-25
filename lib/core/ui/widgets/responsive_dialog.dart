import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';

/// Renders its children as either an [AlertDialog] or a full-screen [Scaffold]
/// page based on `BuildContext.isDialogFullscreen`.
///
/// Use inside widgets whose build previously returned an `AlertDialog` — just
/// swap `AlertDialog(...)` for `ResponsiveDialogScaffold(...)` with the same
/// arguments.
class ResponsiveDialogScaffold extends StatelessWidget {
  const ResponsiveDialogScaffold({
    required this.title,
    required this.content,
    super.key,
    this.actions,
    this.contentPadding,
  });
  final Widget title;
  final Widget content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    if (!context.isDialogFullscreen) {
      final surface = context.appDecoration.dialogSurface;
      if (surface == null) {
        return AlertDialog(
          title: DefaultTextStyle.merge(child: title, style: const TextStyle()),
          content: content,
          contentPadding: contentPadding,
          actions: actions,
        );
      }
      // Frosted-card path (glass, full effects). Reuse the base Dialog for the
      // same centering / insetPadding / min-width as AlertDialog, but transparent
      // so the frosted surface is the only visible card.
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: surface(
          context,
          borderRadius: BorderRadius.circular(context.appShape.dialogRadius),
          child: _DialogBody(
            title: title,
            content: content,
            actions: actions,
            contentPadding: contentPadding,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final layout = context.appLayout;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'BACK',
        ),
        title: DefaultTextStyle.merge(
          child: title,
          style: TextStyle(
            fontSize: layout.fontSizeSubtitle,
            fontWeight: context.appTypography.displayWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: contentPadding ?? EdgeInsets.all(layout.pagePadding),
          child: content,
        ),
      ),
      bottomNavigationBar: (actions == null || actions!.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: layout.pagePadding,
                  vertical: layout.tabSpacing,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (int i = 0; i < actions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions![i],
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

// Material AlertDialog default paddings + button gap, reproduced so the
// frosted-card dialog matches the standard dialog layout exactly.
const EdgeInsets _kDialogTitlePadding = EdgeInsets.fromLTRB(24, 24, 24, 0);
const EdgeInsets _kDialogContentPadding = EdgeInsets.fromLTRB(24, 20, 24, 24);
const EdgeInsets _kDialogActionsPadding = EdgeInsets.fromLTRB(8, 0, 8, 8);
const double _kDialogButtonSpacing = 8;

/// The inner column of a frosted-card dialog: title, scrollable content, and
/// an actions bar — mirroring `AlertDialog`'s structure so content does not
/// reflow.
class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.title,
    required this.content,
    this.actions,
    this.contentPadding,
  });

  final Widget title;
  final Widget content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final dialogTheme = Theme.of(context).dialogTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _kDialogTitlePadding,
          child: DefaultTextStyle.merge(
            style: dialogTheme.titleTextStyle ?? const TextStyle(),
            child: title,
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: contentPadding ?? _kDialogContentPadding,
            child: DefaultTextStyle.merge(
              style: dialogTheme.contentTextStyle ?? const TextStyle(),
              child: content,
            ),
          ),
        ),
        if (actions != null && actions!.isNotEmpty)
          Padding(
            padding: _kDialogActionsPadding,
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: _kDialogButtonSpacing,
              overflowAlignment: OverflowBarAlignment.end,
              children: actions!,
            ),
          ),
      ],
    );
  }
}

/// Opens [builder] as either a centered [AlertDialog]-style modal or a full-
/// screen [MaterialPageRoute] based on the viewport width.
///
/// The builder should typically return a [ResponsiveDialogScaffold] so the
/// chrome adapts automatically.
Future<T?> showResponsiveDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  if (context.isDialogFullscreen) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: builder,
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}
