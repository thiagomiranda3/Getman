import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';

/// Renders its children as either an [AlertDialog] or a full-screen [Scaffold]
/// page based on [BuildContext.isDialogFullscreen].
///
/// Use inside widgets whose build previously returned an `AlertDialog` — just
/// swap `AlertDialog(...)` for `ResponsiveDialogScaffold(...)` with the same
/// arguments.
class ResponsiveDialogScaffold extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;

  const ResponsiveDialogScaffold({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    if (!context.isDialogFullscreen) {
      return AlertDialog(
        title: DefaultTextStyle.merge(child: title, style: const TextStyle()),
        content: content,
        contentPadding: contentPadding,
        actions: actions,
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
                padding: EdgeInsets.symmetric(horizontal: layout.pagePadding, vertical: layout.tabSpacing),
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
